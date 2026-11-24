/**
 * Recarga incremental do Preview (Preview Protocol §3, `preview.reload` com `patch`) e a regra de
 * equivalência incremental do Build System §5.1: compilar entidade por entidade e aplicar os patches
 * sobre o bundle anterior dá o mesmo `bundle.json` que compilar tudo de novo.
 *
 * Um patch é uma lista de trocas `{ file, pointer, value? }` sobre a forma canônica: em `bundle.json`,
 * `/scenes/<uuid>`, `/chapters/<uuid>`, `/characters/<uuid>`, `/ui/<id>`, `/sets/<id>`, `/assets/<id>`
 * ou `/theme`; em `locales/<idioma>.json`, `/strings/<caminho>`; em `licenses.json`, `/entries`. Com
 * `value` a entidade é criada ou substituída, sem `value` é removida. Mudanças em `/project`,
 * `/variables`, `/aliases`, em `plugins.json` ou na lista de idiomas pedem a recarga completa.
 */
import {
  type CompileContext,
  type CompileOptions,
  type CompiledBundle,
  bundleContentHash,
  compileAliases,
  compileAssets,
  compileChapter,
  compileCharacters,
  compileLicenses,
  compileLocale,
  compilePlugins,
  compileProjectEntity,
  compileScene,
  compileSets,
  compileTheme,
  compileUi,
  compileVariables,
  createContext,
} from './compile.js';
import { type Json, type JsonObject, canonicalize } from './jcs.js';
import type { ProjectInput } from './input.js';

export interface PatchOp {
  file: string;
  pointer: string;
  value?: Json;
}

/** Coleções de `bundle.json` que aceitam troca por entidade. */
export const ENTITY_COLLECTIONS = ['scenes', 'chapters', 'characters', 'ui', 'sets', 'assets'] as const;
export type EntityCollection = (typeof ENTITY_COLLECTIONS)[number];

/** Partes de `bundle.json` que só mudam com a recarga completa. */
export const FULL_RELOAD_PARTS = ['project', 'variables', 'aliases', 'format_version', 'bundle_version'] as const;

/** RFC 6901: `~` vira `~0` e `/` vira `~1`. */
export function escapePointer(token: string): string {
  return token.replace(/~/g, '~0').replace(/\//g, '~1');
}

export function unescapePointer(token: string): string {
  return token.replace(/~1/g, '/').replace(/~0/g, '~');
}

/** Ids de uma coleção no contexto novo. */
function entityIds(ctx: CompileContext, coll: EntityCollection): string[] {
  switch (coll) {
    case 'scenes':
      return ctx.input.scenes.map((s) => String(s.id));
    case 'chapters':
      return ctx.input.chapters.map((c) => String(c.id));
    case 'characters':
      return ctx.input.characters.map((c) => String(c.id));
    case 'sets':
      return [...ctx.sets.keys()];
    case 'ui':
      return Object.keys(compileUi(ctx));
    case 'assets':
      return Object.keys(compileAssets(ctx));
  }
}

/**
 * Compila uma entidade só, como o Build System a gravaria (defaults resolvidos), ou `undefined` se
 * ela não existe no projeto. As telas e os assets dependem uns dos outros (tela `minigames` gerada,
 * substitutas da edição censurada), então saem da compilação da coleção.
 */
export function compileEntity(ctx: CompileContext, coll: EntityCollection | 'theme', id = ''): Json | undefined {
  switch (coll) {
    case 'theme':
      return compileTheme(ctx);
    case 'scenes': {
      const src = ctx.input.scenes.filter((s) => s.id === id).pop();
      return src && compileScene(ctx, src);
    }
    case 'chapters': {
      const src = ctx.input.chapters.filter((c) => c.id === id).pop();
      return src && compileChapter(ctx, src);
    }
    case 'characters':
      return compileCharacters(ctx)[id];
    case 'sets':
      return compileSets(ctx)[id];
    case 'ui':
      return compileUi(ctx)[id];
    case 'assets':
      return compileAssets(ctx)[id];
  }
}

const same = (a: unknown, b: unknown): boolean =>
  a === undefined || b === undefined ? a === b : canonicalize(a) === canonicalize(b);

export interface ReloadPlan {
  /** Trocas da recarga incremental, entidade por entidade. */
  patch: PatchOp[];
  /** O que pede a recarga completa (vazio = o patch basta). */
  fullReload: string[];
}

/**
 * Planeja a recarga a partir do bundle anterior e do projeto editado: recompila cada entidade
 * sozinha e troca só as que mudaram.
 */
export function planReload(prev: CompiledBundle, input: ProjectInput, options: CompileOptions = {}): ReloadPlan {
  const ctx = createContext(input, options);
  const prevBundle = prev.bundle as unknown as JsonObject;
  const patch: PatchOp[] = [];
  const fullReload: string[] = [];

  const variables = compileVariables(ctx);
  const top: Record<string, Json> = {
    project: compileProjectEntity(ctx),
    variables,
    aliases: compileAliases(ctx, variables),
    format_version: ctx.input.project.format_version ?? null,
    bundle_version: 1,
  };
  for (const part of FULL_RELOAD_PARTS) if (!same(prevBundle[part], top[part])) fullReload.push(`bundle.json /${part}`);

  for (const coll of ENTITY_COLLECTIONS) {
    const before = (prevBundle[coll] ?? {}) as JsonObject;
    const ids = new Set([...Object.keys(before), ...entityIds(ctx, coll)]);
    for (const id of ids) {
      const value = compileEntity(ctx, coll, id);
      if (same(before[id], value)) continue;
      const pointer = `/${coll}/${escapePointer(id)}`;
      patch.push(value === undefined ? { file: 'bundle.json', pointer } : { file: 'bundle.json', pointer, value });
    }
  }
  const theme = compileEntity(ctx, 'theme');
  if (!same(prevBundle.theme, theme)) patch.push({ file: 'bundle.json', pointer: '/theme', value: theme! });

  const prevLangs = Object.keys(prev.locales);
  if (canonicalize(prevLangs) !== canonicalize(ctx.locales)) fullReload.push('idiomas');
  for (const lang of ctx.locales) {
    if (!prev.locales[lang]) continue; // idioma novo: só na recarga completa
    const before = (prev.locales[lang]?.strings ?? {}) as JsonObject;
    const after = compileLocale(ctx, lang).strings as JsonObject;
    for (const k of new Set([...Object.keys(before), ...Object.keys(after)])) {
      if (same(before[k], after[k])) continue;
      const pointer = `/strings/${escapePointer(k)}`;
      const file = `locales/${lang}.json`;
      patch.push(k in after ? { file, pointer, value: after[k]! } : { file, pointer });
    }
  }

  const plugins = compilePlugins(ctx);
  if (!same(prev.plugins, plugins)) fullReload.push('plugins.json');
  const assets = (prevBundle.assets ?? {}) as JsonObject;
  const licenses = compileLicenses(ctx, plugins, patchedAssets(assets, patch));
  if (!same(prev.licenses.entries, licenses.entries))
    patch.push({ file: 'licenses.json', pointer: '/entries', value: licenses.entries as unknown as Json });
  return { patch, fullReload };
}

function patchedAssets(assets: JsonObject, patch: PatchOp[]): JsonObject {
  const out = { ...assets };
  for (const op of patch) {
    if (op.file !== 'bundle.json' || !op.pointer.startsWith('/assets/')) continue;
    const id = unescapePointer(op.pointer.slice('/assets/'.length));
    if (op.value === undefined) delete out[id];
    else out[id] = op.value;
  }
  return out;
}

/**
 * Aplica um patch à forma canônica, como o runtime faz na memória (sem recalcular o `content_hash`,
 * que fica o do bundle anterior). Recusa ponteiros fora das entidades, como o `BUNDLE_INVALID`.
 */
export function applyPatch(prev: CompiledBundle, patch: PatchOp[]): CompiledBundle {
  const next = structuredClone(prev);
  for (const op of patch) {
    let target: JsonObject;
    let key: string;
    const toks = op.pointer.split('/').slice(1).map(unescapePointer);
    if (op.file === 'bundle.json') {
      const bundle = next.bundle as unknown as JsonObject;
      if (toks.length === 1 && toks[0] === 'theme') {
        target = bundle;
        key = 'theme';
      } else if (toks.length === 2 && (ENTITY_COLLECTIONS as readonly string[]).includes(toks[0]!)) {
        target = (bundle[toks[0]!] ??= {}) as JsonObject;
        key = toks[1]!;
      } else throw new Error(`troca fora das entidades: ${op.pointer} (full_reload_required)`);
    } else if (op.file === 'licenses.json' && op.pointer === '/entries') {
      target = next.licenses as unknown as JsonObject;
      key = 'entries';
    } else if (op.file.startsWith('locales/') && toks.length === 2 && toks[0] === 'strings') {
      const lang = op.file.slice('locales/'.length, -'.json'.length);
      const doc = next.locales[lang];
      if (!doc) throw new Error(`idioma fora do bundle: ${lang} (full_reload_required)`);
      target = doc.strings as unknown as JsonObject;
      key = toks[1]!;
    } else throw new Error(`troca inválida: ${op.file} ${op.pointer}`);
    if (op.value === undefined) delete target[key];
    else target[key] = structuredClone(op.value);
  }
  return next;
}

/** `content_hash` que o bundle teria depois do patch (a recarga completa o recalcula). */
export function rehash(compiled: CompiledBundle): CompiledBundle {
  const bundle = compiled.bundle as unknown as JsonObject;
  return { ...compiled, bundle: { ...bundle, content_hash: bundleContentHash(bundle) } as unknown as CompiledBundle['bundle'] };
}
