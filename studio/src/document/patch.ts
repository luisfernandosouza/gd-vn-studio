import { current, isDraft, produce } from 'immer';
import { VNError, type VNErrorCode } from './errors';
import { formatPointer, getValue, isObject, parsePointer, resolvePointer } from './pointer';

/** Operações JSON Patch (RFC 6902) sobre o documento lógico (Plugin SDK §10.4). */
export type Operation =
  | { op: 'add' | 'replace' | 'test'; path: string; value: unknown }
  | { op: 'remove'; path: string }
  | { op: 'move' | 'copy'; from: string; path: string };

export type EditSource = 'studio' | 'plugin';

export interface ApplyOptions {
  /** `plugin` ativa a lista de ponteiros proibidos (SDK §10.4.1). O Studio edita tudo. */
  source?: EditSource;
}

export interface PatchResult<D> {
  doc: D;
  /** O patch como foi aplicado: `@<id>` e `-` trocados por índice, valores copiados. */
  forward: Operation[];
  /** Desfaz `forward`: cada mudança vem precedida de um `test` do valor que ela espera encontrar. */
  inverse: Operation[];
}

/** Coleções do documento lógico em que cada entrada tem `id` igual à chave. */
export const ENTITY_COLLECTIONS = ['characters', 'chapters', 'scenes', 'ui', 'sets'] as const;

export function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b || a === null || b === null || typeof a !== 'object') return false;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((v, i) => deepEqual(v, b[i]));
  }
  const ka = Object.keys(a as object);
  const kb = Object.keys(b as object);
  if (ka.length !== kb.length) return false;
  return ka.every((k) => Object.hasOwn(b as object, k) && deepEqual((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]));
}

const plain = <T>(v: T): T => (isDraft(v) ? (current(v as never) as T) : v);
const clone = <T>(v: T): T => (v === undefined ? v : (structuredClone(plain(v)) as T));

function hasAccessKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(hasAccessKey);
  if (!isObject(value)) return false;
  return Object.hasOwn(value, 'access') || Object.values(value).some(hasAccessKey);
}

const FORBIDDEN_PROJECT_KEYS = new Set(['build', 'runtime', 'format_version', 'id']);

/**
 * Ponteiros que um plugin não pode tocar (SDK §10.4.1): `/plugins` e tudo abaixo, `/variables/**` até
 * `access`, `/project/build`, `/project/runtime`, `/project/format_version` e `/project/id`. "Tocar"
 * inclui escrever num ancestral que apague ou sobrescreva esses caminhos (`/project`, o documento
 * todo) e criar, trocar ou remover uma definição de variável que carregue `access`.
 */
export function isForbiddenForPlugin(doc: unknown, pointer: string, written?: unknown): boolean {
  const seg = parsePointer(pointer);
  const [head, second] = seg;
  if (seg.length === 0 || head === 'plugins') return true;
  if (head === 'project') return seg.length === 1 || FORBIDDEN_PROJECT_KEYS.has(second as string);
  if (head === 'variables') {
    if (seg.slice(1).includes('access')) return true;
    return hasAccessKey(written) || hasAccessKey(getValue(doc, pointer));
  }
  return false;
}

function fail(code: VNErrorCode, message: string): never {
  throw new VNError(code, message);
}

type Container = Record<string, unknown> | unknown[];

function readAt(parent: Container, key: string): unknown {
  if (Array.isArray(parent)) return parent[Number(key)];
  return Object.hasOwn(parent, key) ? parent[key] : undefined;
}

function existsAt(parent: Container, key: string): boolean {
  if (Array.isArray(parent)) return key !== '-' && Number(key) < parent.length;
  return Object.hasOwn(parent, key);
}

/** Insere `value` em `pointer` e devolve o ponteiro normalizado, mais o valor que ele substituiu (chave de objeto que já existia). */
function insertAt(draft: unknown, pointer: string, value: unknown): { path: string; replaced?: { value: unknown } } {
  const r = resolvePointer(draft, pointer);
  if (!r.parent || r.key === undefined) return fail('INVALID_PATCH', 'Não dá para escrever na raiz do documento.');
  if (Array.isArray(r.parent)) {
    const idx = r.key === '-' ? r.parent.length : Number(r.key);
    if (idx > r.parent.length) fail('INVALID_PATCH', `${pointer}: índice fora do array (tamanho ${r.parent.length}).`);
    r.parent.splice(idx, 0, value);
    return { path: formatPointer([...r.segments.slice(0, -1), idx]) };
  }
  const had = existsAt(r.parent, r.key);
  const old = had ? clone(r.parent[r.key]) : undefined;
  r.parent[r.key] = value;
  return { path: formatPointer(r.segments), replaced: had ? { value: old } : undefined };
}

function removeAt(draft: unknown, pointer: string): { path: string; value: unknown } {
  const r = resolvePointer(draft, pointer);
  if (!r.parent || r.key === undefined) return fail('INVALID_PATCH', 'Não dá para remover a raiz do documento.');
  if (!existsAt(r.parent, r.key)) return fail('NOT_FOUND', `${pointer}: caminho não existe.`);
  const value = clone(readAt(r.parent, r.key));
  if (Array.isArray(r.parent)) r.parent.splice(Number(r.key), 1);
  else delete r.parent[r.key];
  return { path: formatPointer(r.segments), value };
}

function undoAdd(path: string, value: unknown, replaced?: { value: unknown }): Operation[] {
  return [{ op: 'test', path, value: clone(value) }, replaced ? { op: 'replace', path, value: replaced.value } : { op: 'remove', path }];
}

/**
 * Aplica um patch JSON ao documento lógico, sem alterar o original. Tudo ou nada: qualquer falha
 * lança `VNError` e o documento fica como estava.
 *
 * - `@<id>` vira índice; `add` em `…/@<id>` insere antes do elemento; `-` é o fim do array.
 * - `replace`, `remove` e `move` exigem um `test` anterior no mesmo caminho (no `from`, para `move`).
 *   `test` que não confere recusa o patch inteiro com `CONFLICT`.
 * - Com `source: 'plugin'`, tocar um ponteiro proibido recusa o patch com `FORBIDDEN_PATH`.
 * - O resultado traz o patch inverso, que é o que o undo aplica.
 */
export function applyPatch<D>(doc: D, ops: readonly Operation[], options: ApplyOptions = {}): PatchResult<D> {
  const forward: Operation[] = [];
  const inverseSteps: Operation[][] = [];
  const tested = new Set<string>();

  const forbid = (draft: unknown, pointer: string, written?: unknown) => {
    if (options.source === 'plugin' && isForbiddenForPlugin(draft, pointer, written)) {
      fail('FORBIDDEN_PATH', `${pointer || '/'}: plugins não podem editar este caminho.`);
    }
  };
  const requireTest = (pointer: string, normalized: string, what: string) => {
    if (!tested.has(pointer) && !tested.has(normalized)) {
      fail('INVALID_PATCH', `${pointer}: ${what} precisa de um "test" antes, com o valor esperado.`);
    }
  };

  const next = produce(doc, (draft) => {
    for (const operation of ops) {
      switch (operation.op) {
        case 'test': {
          forbid(draft, operation.path);
          let resolved;
          try {
            resolved = resolvePointer(draft, operation.path);
          } catch (e) {
            if (e instanceof VNError && e.code === 'NOT_FOUND') fail('CONFLICT', `${operation.path}: o valor mudou desde que foi lido.`);
            throw e;
          }
          const { parent, key, segments } = resolved;
          const actual = parent && key !== undefined && existsAt(parent, key) ? plain(readAt(parent, key)) : undefined;
          if (parent && !deepEqual(actual, operation.value)) fail('CONFLICT', `${operation.path}: o valor mudou desde que foi lido.`);
          const path = formatPointer(segments);
          tested.add(operation.path);
          tested.add(path);
          forward.push({ op: 'test', path, value: clone(operation.value) });
          break;
        }
        case 'add': {
          forbid(draft, operation.path, operation.value);
          const value = clone(operation.value);
          const { path, replaced } = insertAt(draft, operation.path, clone(value));
          forward.push({ op: 'add', path, value });
          inverseSteps.push(undoAdd(path, value, replaced));
          break;
        }
        case 'replace': {
          forbid(draft, operation.path, operation.value);
          const r = resolvePointer(draft, operation.path);
          if (!r.parent || r.key === undefined) fail('INVALID_PATCH', 'Não dá para substituir a raiz do documento.');
          if (!existsAt(r.parent, r.key)) fail('NOT_FOUND', `${operation.path}: caminho não existe.`);
          const path = formatPointer(r.segments);
          requireTest(operation.path, path, '"replace"');
          const old = clone(readAt(r.parent, r.key));
          const value = clone(operation.value);
          if (Array.isArray(r.parent)) r.parent[Number(r.key)] = clone(value);
          else r.parent[r.key] = clone(value);
          forward.push({ op: 'replace', path, value });
          inverseSteps.push([
            { op: 'test', path, value: clone(value) },
            { op: 'replace', path, value: old },
          ]);
          break;
        }
        case 'remove': {
          forbid(draft, operation.path);
          const pre = resolvePointer(draft, operation.path);
          requireTest(operation.path, formatPointer(pre.segments), '"remove"');
          const { path, value } = removeAt(draft, operation.path);
          forward.push({ op: 'remove', path });
          inverseSteps.push([{ op: 'add', path, value }]);
          break;
        }
        case 'move': {
          forbid(draft, operation.from);
          forbid(draft, operation.path, getValue(draft, operation.from));
          if (operation.path === operation.from) break;
          if (operation.path.startsWith(`${operation.from}/`)) fail('INVALID_PATCH', `${operation.from}: não dá para mover um valor para dentro dele mesmo.`);
          const pre = resolvePointer(draft, operation.from);
          requireTest(operation.from, formatPointer(pre.segments), '"move"');
          const removed = removeAt(draft, operation.from);
          const { path, replaced } = insertAt(draft, operation.path, clone(removed.value));
          forward.push({ op: 'move', from: removed.path, path });
          inverseSteps.push([
            { op: 'test', path, value: clone(removed.value) },
            { op: 'move', from: path, path: removed.path },
            ...(replaced ? [{ op: 'add', path, value: replaced.value } as Operation] : []),
          ]);
          break;
        }
        case 'copy': {
          forbid(draft, operation.from);
          const source = getValue(draft, operation.from);
          if (source === undefined) fail('NOT_FOUND', `${operation.from}: caminho não existe.`);
          forbid(draft, operation.path, source);
          const value = clone(source);
          const { path, replaced } = insertAt(draft, operation.path, clone(value));
          forward.push({ op: 'add', path, value });
          inverseSteps.push(undoAdd(path, value, replaced));
          break;
        }
        default:
          fail('INVALID_PATCH', `Operação desconhecida: "${String((operation as { op?: unknown }).op)}".`);
      }
    }
  });

  checkEntityIds(next, forward);
  return { doc: next, forward, inverse: inverseSteps.reverse().flat() };
}

/** Cada entidade nas coleções do §10.4.1 carrega o próprio id como chave (`/scenes/<uuid>` → `id: <uuid>`). */
function checkEntityIds(doc: unknown, applied: readonly Operation[]): void {
  if (!isObject(doc)) return;
  for (const op of applied) {
    if (op.op === 'test') continue;
    for (const pointer of op.op === 'move' ? [op.from, op.path] : [op.path]) {
      const [collection, key] = parsePointer(pointer);
      if (!collection || !key || !(ENTITY_COLLECTIONS as readonly string[]).includes(collection)) continue;
      const group = doc[collection];
      const entity = isObject(group) && Object.hasOwn(group, key) ? group[key] : undefined;
      if (entity === undefined) continue;
      if (!isObject(entity) || entity.id !== key) {
        fail('INVALID_PATCH', `/${collection}/${key}: a entidade precisa ser um objeto com "id": "${key}".`);
      }
    }
  }
}

/**
 * Monta um patch do Studio a partir de edições sem `test`: antes de cada `replace`, `remove` e `move`
 * insere o `test` com o valor atual (no estado já alterado pelas operações anteriores do mesmo
 * patch). É assim que os comandos do próprio Studio cumprem a regra do §10.4.1 sem repetir o valor.
 */
export function withTests(doc: unknown, ops: readonly Operation[]): Operation[] {
  const out: Operation[] = [];
  const tested = new Set<string>();
  let state = doc;
  for (const op of ops) {
    const step: Operation[] = [];
    if (op.op === 'test') tested.add(op.path);
    const target = op.op === 'move' ? op.from : op.op === 'replace' || op.op === 'remove' ? op.path : null;
    if (target !== null && !tested.has(target)) {
      const value = getValue(state, target);
      if (value !== undefined) step.push({ op: 'test', path: target, value: structuredClone(value) });
      tested.add(target);
    }
    step.push(op);
    state = applyPatch(state, step).doc;
    out.push(...step);
  }
  return out;
}
