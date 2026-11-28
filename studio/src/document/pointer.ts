import { VNError } from './errors';

/**
 * Ponteiros JSON (RFC 6901) com o segmento estendido `@<id>` do Plugin SDK §10.4.1: num array de
 * entidades com id, `@<id>` aponta para o elemento cujo `id` (ou, nas definições de variável, cuja
 * `key`) é `<id>`. O Studio troca o segmento por índice no momento de aplicar.
 */

export function parsePointer(pointer: string): string[] {
  if (pointer === '') return [];
  if (!pointer.startsWith('/')) throw new VNError('INVALID_PATCH', `Ponteiro inválido: "${pointer}" (precisa começar com "/").`);
  return pointer
    .slice(1)
    .split('/')
    .map((s) => s.replace(/~1/g, '/').replace(/~0/g, '~'));
}

export function formatPointer(segments: readonly (string | number)[]): string {
  return segments.map((s) => `/${String(s).replace(/~/g, '~0').replace(/\//g, '~1')}`).join('');
}

export const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

/** Índice do elemento de `array` com `id` ou `key` igual a `ref`; -1 se não houver. `id` tem precedência. */
export function indexOfRef(array: readonly unknown[], ref: string): number {
  let byKey = -1;
  for (let i = 0; i < array.length; i++) {
    const item = array[i];
    if (!isObject(item)) continue;
    if (item.id === ref) return i;
    if (byKey < 0 && item.key === ref) byKey = i;
  }
  return byKey;
}

export interface ResolvedPointer {
  /** Segmentos com `@<id>` já trocados por índice. */
  segments: string[];
  /** Pai do alvo (objeto ou array). Ausente só para o ponteiro raiz. */
  parent?: Record<string, unknown> | unknown[];
  /** Último segmento (chave ou índice) dentro do pai; `-` em array vale "fim" e fica como está. */
  key?: string;
}

/**
 * Resolve os segmentos até o pai do alvo, trocando `@<id>` por índice. O próprio alvo não precisa
 * existir (um `add` cria); os intermediários, sim.
 */
export function resolvePointer(doc: unknown, pointer: string): ResolvedPointer {
  const raw = parsePointer(pointer);
  if (raw.length === 0) return { segments: [] };
  const segments: string[] = [];
  let node: unknown = doc;
  for (let i = 0; i < raw.length; i++) {
    const seg = raw[i] as string;
    const last = i === raw.length - 1;
    let resolved = seg;
    if (Array.isArray(node)) {
      if (seg.startsWith('@')) {
        const idx = indexOfRef(node, seg.slice(1));
        if (idx < 0) {
          // `add` antes de um elemento que não existe é erro, tanto quanto qualquer outro uso
          throw new VNError('NOT_FOUND', `${formatPointer(raw.slice(0, i))}: não há elemento com id "${seg.slice(1)}".`);
        }
        resolved = String(idx);
      } else if (!(seg === '-' && last) && !/^(0|[1-9]\d*)$/.test(seg)) {
        throw new VNError('INVALID_PATCH', `${formatPointer(raw.slice(0, i + 1))}: índice de array inválido.`);
      }
    }
    segments.push(resolved);
    if (last) return { segments, parent: node as Record<string, unknown> | unknown[], key: resolved };
    if (Array.isArray(node)) node = node[Number(resolved)];
    else if (isObject(node)) node = Object.hasOwn(node, resolved) ? node[resolved] : undefined;
    else node = undefined;
    if (node === undefined || node === null || typeof node !== 'object') {
      throw new VNError('NOT_FOUND', `${formatPointer(segments)}: caminho não existe.`);
    }
  }
  /* c8 ignore next */
  throw new VNError('INVALID_PATCH', 'Ponteiro inválido.');
}

/** Valor em `pointer`, ou `undefined` se não existir. `@<id>` é aceito. */
export function getValue(doc: unknown, pointer: string): unknown {
  let node: unknown = doc;
  for (const seg of parsePointer(pointer)) {
    if (Array.isArray(node)) {
      node = seg.startsWith('@') ? node[indexOfRef(node, seg.slice(1))] : node[Number(seg)];
    } else if (isObject(node)) {
      node = Object.hasOwn(node, seg) ? node[seg] : undefined;
    } else return undefined;
    if (node === undefined) return undefined;
  }
  return node;
}
