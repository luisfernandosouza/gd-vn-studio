/**
 * Content Validator do Narrative Data Model v1 em TypeScript (tarefa M5-01).
 *
 * Porte fiel de `docs/specs/tools/validate.py`, a implementação de referência: os dois DEVEM dar o mesmo
 * resultado nos casos de `tools/test_validate.py` (Req §14). A ordem das regras e o texto técnico de cada
 * diagnóstico seguem o arquivo Python; cada diagnóstico também traz uma frase em linguagem simples (Req §6).
 *
 * Regras: Data Model §11 (S, R, T, P, W), UI Spec §11 (U) e spec 09 §5 (P021).
 */
import { readdirSync } from 'node:fs';
import path from 'node:path';
import { cmpPath, exists, globFiles, isDir, isFile, loadJson, rel, rglobFiles } from './files.js';
import { plainMessage, type Params } from './messages.js';
import { checkPluginCode } from './plugin-code.js';
import {
  get,
  has,
  isBool,
  isDict,
  isFloat,
  isInt,
  isList,
  isNum,
  isStr,
  items,
  keys,
  list,
  num,
  pyFloat,
  pyIn,
  pyRepr,
  pyStr,
  fnmatchcase,
  sorted,
  stem,
  suffix,
  truthy,
  values,
  type Dict,
  type J,
} from './py.js';
import { satisfies } from './semver.js';
import { Schemas, findSpecs } from './schemas.js';

export type Severity = 'error' | 'warning';

export interface Diagnostic {
  code: string;
  severity: Severity;
  /** Arquivo e, quando há, o id do item (`scenes/ch01/x.json#<uuid>`, `ui/title.json#btn_new`). */
  where: string;
  /** Texto técnico, igual ao do validador de referência ("Detalhes" no Studio). */
  detail: string;
  /** Frase em linguagem simples (Req §6). */
  message: string;
}

export interface ValidateOptions {
  /** `--export`: regras de exportação (R021, P013; W013 e U009 viram erro). */
  export?: boolean;
  /** Pasta com `schemas/` e `presets/`; o padrão é achar `docs/specs/` ou as cópias do pacote. */
  specsDir?: string;
}

export interface ValidationResult {
  errors: Diagnostic[];
  warnings: Diagnostic[];
}

/** Diagnóstico no formato de linha do validador de referência: `[R004] onde: detalhe`. */
export function formatDiagnostic(d: Diagnostic): string {
  return `[${d.code}] ${d.where}: ${d.detail}`;
}

// chave do tema/projeto → tipos de asset aceitos (R004 e W014)
const IMG = new Set(['image', 'background']);
const S = (...xs: string[]) => new Set(xs);
const ASSET_KEYS: Record<string, Set<string>> = {
  image: IMG, background: IMG, overlay: IMG, logo: IMG, icon: S('image'), splash: IMG,
  button: S('image'), button_hover: S('image'), button_disabled: S('image'), advance_indicator: S('image'),
  locked_image: IMG, music: S('audio_music'), click: S('audio_sfx'), hover: S('audio_sfx'),
  choice: S('audio_sfx'), dialogue: S('font'), name: S('font'), ui: S('font'),
  font: S('font'), cursor: IMG, locked_asset: IMG, asset: S('image', 'background', 'sprite', 'video'),
};
// subárvores do tema/telas em que toda string é asset de um tipo fixo
const ASSET_CTX: Record<string, Set<string>> = { sounds: S('audio_sfx'), fonts: S('font'), fallbacks: S('font') };
const CURSORS = S('default', 'look', 'talk', 'use', 'walk');
const AUDIO_TYPES: Record<string, Set<string>> = {
  music: S('audio_music'), ambient: S('audio_music', 'audio_sfx'), sfx: S('audio_sfx'), voice: S('audio_voice'),
};
const PAIRED = S('b', 'i', 'color', 'speed');
const SINGLE = S('pause');
const SYS_FIXED: Record<string, string> = {
  'sys.chapter.id': 'string', 'sys.scene.id': 'string', 'sys.selection_count': 'integer',
  'sys.locale': 'string', 'sys.save_modified': 'boolean',
  'sys.ui.has_save': 'boolean', 'sys.ui.in_game': 'boolean', 'sys.ui.platform': 'string', 'sys.ui.activity': 'boolean',
  'sys.ui.activity_skippable': 'boolean',
  'sys.ui.has_minigames': 'boolean', 'sys.ui.last_activity_outcome': 'string', 'sys.ui.last_record_rank': 'integer',
  'sys.ui.content_filter': 'boolean', 'sys.ui.content_filter_available': 'boolean',
  'sys.ui.has_gallery': 'boolean', 'sys.ui.gallery_endings': 'boolean', 'sys.ui.gallery_images': 'boolean',
  'sys.ui.gallery_music': 'boolean',
};
// Modo stream (Data Model §10.4): estado do filtro só nas telas (R022); censor só em passos de apresentação (R023)
const CONTENT_FILTER_VARS = S('sys.ui.content_filter', 'sys.ui.content_filter_available');
const CENSORABLE_NODES = S('line', 'background', 'show', 'audio', 'wait');
// UI Spec §4, §5.1, §8
const COSMETIC = S('set_state', 'toggle_state', 'play_animation', 'play_sfx', 'show', 'hide', 'toggle_visible');
const TITLE_ONLY = S('new_game', 'continue');
const GAME_ONLY = S('return_to_title', 'save', 'quick_save', 'toggle_auto', 'toggle_skip', 'hide_textbox', 'open_backlog', 'emit');
const FIXED_SCREENS = ['title', 'pause', 'save', 'load', 'settings', 'gallery', 'credits', 'hud'];
const PRESET_SCREENS = ['backlog', 'minigames'];
const PRODUCT_LOCALES = S('en', 'pt-BR', 'es', 'fr', 'it', 'de', 'ja', 'zh-Hans', 'zh-Hant'); // Req §9.1
const DEFAULT_STYLES = S('button', 'choice', 'slot', 'slider', 'toggle', 'select', 'hotspot', 'label');
const SETTING_TYPES: Record<string, string> = {
  'volume.master': 'number', 'volume.music': 'number', 'volume.ambient': 'number', 'volume.sfx': 'number',
  'volume.voice': 'number', display_mode: 'string', resolution: 'list', vsync: 'boolean',
  fps_limit_vn: 'integer', fps_limit_activity: 'integer', text_speed: 'number', auto_delay: 'number',
  skip_unread: 'boolean', locale: 'string', text_scale: 'number', reduce_motion: 'boolean',
  subtitles: 'boolean', high_contrast: 'boolean', show_hotspots: 'boolean', content_filter: 'boolean',
};
// tipos de resultado das funções (DM §6.1.1): [mín, máx, tipo dos argumentos]
const FN_ARITY: Record<string, [number, number, string]> = {
  add: [2, 2, 'num'], sub: [2, 2, 'num'], mul: [2, 2, 'num'], div: [2, 2, 'num'], mod: [2, 2, 'int'],
  min: [2, 8, 'num'], max: [2, 8, 'num'], clamp: [3, 3, 'num'], round: [1, 1, 'num'], floor: [1, 1, 'num'],
  ceil: [1, 1, 'num'], abs: [1, 1, 'num'], concat: [1, 8, 'any'], random_int: [2, 2, 'int'],
};

const MARKUP = /\[\[|\]\]|\[(\/?)([a-z]+)(=[^\]]*)?\]/g;
const INTERP = /\{\{|\}\}|\{([^{}]*)\}/g;

function walk(o: J, fn: (d: Dict) => void): void {
  if (isDict(o)) {
    fn(o);
    for (const v of Object.values(o)) walk(v, fn);
  } else if (isList(o)) {
    for (const v of o) walk(v, fn);
  }
}

function writtenVars(o: J): Set<string> {
  const out = new Set<string>();
  walk(o, (d) => {
    if (has(d, 'op') && isStr(d.variable)) out.add(d.variable);
  });
  walk(o, (d) => {
    if (isStr(get(d, 'record'))) out.add(d.record);
  });
  return out;
}

function readVars(o: J): Set<string> {
  const out = new Set<string>();
  walk(o, (d) => {
    if (has(d, 'operator') && isStr(get(d, 'variable'))) out.add(d.variable);
    if (isStr(get(d, 'var'))) out.add(d.var);
  });
  return out;
}

function walkConds(conds: J): Dict[] {
  const out: Dict[] = [];
  walk(conds, (o) => {
    if (has(o, 'variable') && has(o, 'operator')) out.push(o);
  });
  return out;
}

function markupParamOk(tag: string, p: string | null): boolean {
  if (tag === 'b' || tag === 'i') return p === null;
  if (tag === 'color') return p !== null && /^#[0-9a-fA-F]{6}$/.test(p);
  const v = p === null ? null : pyFloat(p);
  if (v === null) return false;
  return tag === 'pause' ? 0 <= v && v <= 10 : 0.1 <= v && v <= 10;
}

function interpRefs(text: J): string[] {
  const t = isStr(text) ? text : '';
  return [...t.matchAll(INTERP)].filter((m) => m[1] !== undefined).map((m) => m[1]!.trim());
}

/** `ui_elements`: todos os elementos de uma tela, inclusive dentro de containers. */
function uiElements(elements: J): Dict[] {
  const out: Dict[] = [];
  for (const e of list(elements)) {
    out.push(e);
    if (get(e, 'type') === 'container') out.push(...uiElements(get(e, 'children', [])));
  }
  return out;
}

/** `ui_actions`: todas as ações de uma lista, inclusive em else e then. */
function uiActions(lst: J): Dict[] {
  const out: Dict[] = [];
  for (const a of list(lst)) {
    out.push(a);
    out.push(...uiActions(get(a, 'else')));
    out.push(...uiActions(get(a, 'then')));
  }
  return out;
}

const union = <T>(...sets: Iterable<T>[]): Set<T> => {
  const out = new Set<T>();
  for (const s of sets) for (const x of s) out.add(x);
  return out;
};

/** Roda o validador num projeto (e nos plugins passados) e devolve erros e avisos. */
export function validateProject(root: string, pluginDirsIn: string[] = [], opts: ValidateOptions = {}): ValidationResult {
  const EXPORT = !!opts.export;
  const specs = findSpecs(opts.specsDir);
  const schemas = schemasFor(specs.schemas, () => new Schemas(specs));
  const PRESETS = specs.presets;
  const errors: Diagnostic[] = [];
  const warnings: Diagnostic[] = [];
  const mk = (code: string, severity: Severity, where: string, detail: string, params?: Params): Diagnostic => ({
    code, severity, where, detail, message: plainMessage(code, where, detail, params),
  });
  const err = (code: string, where: string, msg: string, params?: Params) => void errors.push(mk(code, 'error', where, msg, params));
  const warn = (code: string, where: string, msg: string, params?: Params) => void warnings.push(mk(code, 'warning', where, msg, params));
  const errOrWarn = (asError: boolean) => (asError ? err : warn);

  const checkSchema = (p: string, schema: string): J => {
    let data: J;
    try {
      data = loadJson(p);
    } catch (e) {
      const why = (e as NodeJS.ErrnoException).code === 'ENOENT' ? 'arquivo não encontrado' : `JSON inválido: ${(e as Error).message}`;
      err('S000', p, `<raiz>: ${why}`);
      return {};
    }
    for (const i of schemas.check(schema, data)) err('S000', p, `${i.path || '<raiz>'}: ${i.message}`, { detalhe: `${i.path || 'raiz'}: ${i.message}` });
    return data;
  };
  const safeLoad = (p: string): J => {
    try {
      return loadJson(p);
    } catch {
      return {};
    }
  };

  const checkMarkup = (text: J, where: string) => {
    if (!isStr(text)) return;
    const stack: string[] = [];
    for (const m of text.matchAll(MARKUP)) {
      if (m[0] === '[[' || m[0] === ']]') continue;
      const close = m[1]!;
      const tag = m[2]!;
      if (!PAIRED.has(tag) && !SINGLE.has(tag)) {
        err('R018', where, `marcação desconhecida [${close}${tag}]`);
        continue;
      }
      const param = m[3] ? m[3].slice(1) : null;
      if (!close && !markupParamOk(tag, param)) err('R018', where, `parâmetro inválido em [${tag}${param !== null ? '=' + param : ''}]`);
      if (SINGLE.has(tag)) continue;
      if (!close) stack.push(tag);
      else if (!stack.length || stack.pop() !== tag) err('R018', where, `[/${tag}] sem abertura correspondente`);
    }
    for (const tag of stack) err('R018', where, `[${tag}] sem fechamento`);
  };

  // ---------- carga dos arquivos ----------
  root = path.resolve(root);
  const J_ = (...p: string[]) => path.join(root, ...p);
  const project = checkSchema(J_('project.json'), 'project.schema.json');
  const variables = checkSchema(J_('variables.json'), 'variables.schema.json');
  const assets: Dict = get(checkSchema(J_('assets.json'), 'assets.schema.json'), 'assets', {});
  const chars: Dict = {};
  for (const p of globFiles(J_('characters'), '.json')) {
    const c = checkSchema(p, 'character.schema.json');
    chars[pyStr(get(c, 'id'))] = c;
  }
  const chapters: Dict = {};
  for (const p of globFiles(J_('chapters'), '.json')) {
    const c = checkSchema(p, 'chapter.schema.json');
    chapters[pyStr(get(c, 'id'))] = c;
  }
  const scenes: Dict = {};
  const scenePaths: Record<string, string> = {};
  for (const p of rglobFiles(J_('scenes'), (n) => n.endsWith('.json'))) {
    const s = checkSchema(p, 'scene.schema.json');
    const id = pyStr(get(s, 'id'));
    if (has(scenes, id)) err('R001', p, `id de cena duplicado ${id}`);
    scenes[id] = s;
    scenePaths[id] = p;
  }
  const localeFiles = rglobFiles(J_('locales'), (n) => n.endsWith('.json'));
  for (const p of localeFiles) checkSchema(p, 'locale.schema.json');
  const sets: Dict = {};
  const screens: Dict = {};
  for (const [folder, schema, table] of [['sets', 'set.schema.json', sets], ['ui', 'ui-screen.schema.json', screens]] as const) {
    for (const p of globFiles(J_(folder), '.json')) {
      const d = checkSchema(p, schema);
      const st = stem(p);
      if (get(d, 'id') !== st) err('U001', `${folder}/${path.basename(p)}`, `id ${pyStr(get(d, 'id'))} difere do nome do arquivo`, { alvo: st });
      table[st] = d;
    }
  }
  const pluginsCfg = exists(J_('plugins.json')) ? checkSchema(J_('plugins.json'), 'plugins.schema.json') : { plugins: {} };
  const cfgPlugins: Dict = get(pluginsCfg, 'plugins', {});
  if (exists(J_('plugin-lock.json'))) checkSchema(J_('plugin-lock.json'), 'plugin-lock.schema.json');
  const localLockFile = J_('.vnstudio', 'plugin-lock.local.json');
  if (exists(localLockFile)) checkSchema(localLockFile, 'plugin-lock.schema.json');
  const themeFile = path.join(root, pyStr(get(project, 'theme', 'theme.json')));
  const themeName = path.basename(themeFile);
  const theme: Dict = exists(themeFile) ? checkSchema(themeFile, 'theme.schema.json') : {};
  const lock = exists(J_('plugin-lock.json')) ? safeLoad(J_('plugin-lock.json')) : { plugins: {} };
  const localLock = exists(localLockFile) ? safeLoad(localLockFile) : { plugins: {} };
  const manifests: Dict = {};
  const pluginRoots: Record<string, string> = {};
  // fontes path: (spec 09 §3): pacote guardado ou plugin embutido, cujo manifesto é carregado sozinho
  const pluginDirs = pluginDirsIn.map((d) => path.resolve(d));
  for (const [pid, cfg] of items(cfgPlugins)) {
    const source = pyStr(get(cfg, 'source', ''));
    if (!source.startsWith('path:')) continue;
    const relSrc = source.slice(5);
    const target = path.resolve(root, relSrc);
    if (suffix(target) === '.vnplugin') {
      if (!isFile(target)) err('P021', `plugins.json/${pid}`, `pacote ${relSrc} não existe`);
      continue;
    }
    // sorted(target.glob("vn_plugins/*/plugin.json"))
    const found = isDir(target) ? listDirs(path.join(target, 'vn_plugins')).map((d) => path.join(d, 'plugin.json')).filter(isFile) : [];
    if (found.length !== 1) {
      err('P021', `plugins.json/${pid}`, `${relSrc}: esperado exatamente um vn_plugins/<namespace>/plugin.json, achei ${found.length}`);
    } else if (!pluginDirs.includes(path.resolve(path.dirname(found[0]!)))) {
      pluginDirs.push(path.dirname(found[0]!));
    }
  }
  for (const d of pluginDirs) {
    const m = checkSchema(path.join(d, 'plugin.json'), 'plugin.schema.json');
    const id = pyStr(get(m, 'id'));
    manifests[id] = m;
    pluginRoots[id] = d;
  }

  const endings = new Set(list(get(project, 'endings', [])).map((e: J) => get(e, 'id')));
  const storyEvents = new Set(list(get(project, 'events', [])).map((e: J) => get(e, 'name')));

  // --- R001: UUIDs únicos no projeto inteiro ---
  const seenIds = new Map<string, string>();
  const claim = (uid: J, where: string) => {
    const k = pyStr(uid);
    if (seenIds.has(k)) err('R001', where, `UUID ${k} já usado em ${seenIds.get(k)}`);
    else seenIds.set(k, where);
  };
  for (const cid of keys(chapters)) claim(cid, `chapters/${cid}`);
  for (const cid of keys(chars)) claim(cid, `characters/${cid}`);
  for (const [sid, s] of items(scenes)) {
    claim(sid, `scenes/${sid}`);
    for (const n of list(get(s, 'nodes', []))) {
      claim(get(n, 'id'), `scenes/${sid}#${pyStr(get(n, 'id'))}`);
      for (const o of [...list(get(n, 'options', [])), ...list(get(n, 'hotspots', []))]) claim(get(o, 'id'), `scenes/${sid}#${pyStr(get(o, 'id'))}`);
    }
  }

  const charKeys: Dict = {};
  for (const [cid, c] of items(chars)) {
    const k = pyStr(get(c, 'key'));
    if (has(charKeys, k)) err('R001', `characters/${cid}`, `key de personagem duplicada ${k}`);
    charKeys[k] = cid;
  }

  // --- tabela de variáveis (ID qualificado -> definição) ---
  const vars_: Dict = {};
  const define = (qid: string, d: J, where: string) => {
    if (has(vars_, qid)) err('R002', where, `variável duplicada ${qid}`);
    vars_[qid] = d;
  };
  for (const d of list(get(variables, 'global', []))) define(`global.${pyStr(get(d, 'key'))}`, d, 'variables.json');
  for (const d of list(get(variables, 'character', []))) {
    if (get(d, 'persistence') === 'profile') err('R017', 'variables.json', `character.*.${pyStr(get(d, 'key'))}: profile só em variáveis globais e de plugin`);
    for (const ck of has(d, 'characters') ? list(d.characters) : keys(charKeys)) {
      if (!has(charKeys, ck)) err('R010', 'variables.json', `personagem ${pyStr(ck)} não existe (characters usa a key do personagem)`);
      define(`character.${pyStr(ck)}.${pyStr(get(d, 'key'))}`, d, 'variables.json');
    }
  }
  const chapterVars: Record<string, Dict> = {};
  for (const [cid, c] of items(chapters)) {
    chapterVars[cid] = {};
    for (const d of list(get(c, 'variables', []))) chapterVars[cid][`chapter.${pyStr(get(d, 'key'))}`] = d;
  }
  for (const [cid, c] of items(chapters)) {
    for (const d of list(get(c, 'variables', []))) {
      if (get(d, 'persistence') === 'profile') err('R017', `chapters/${cid}`, `chapter.${pyStr(get(d, 'key'))}: profile só em variáveis globais e de plugin`);
    }
  }
  const namespaces: Dict = {};
  for (const [pid, m] of items(manifests)) {
    const ns = pyStr(get(m, 'namespace'));
    if (has(namespaces, ns)) err('P001', pid, `namespace ${ns} já usado por ${namespaces[ns]}`);
    namespaces[ns] = pid;
    for (const d of list(get(m, 'variables', []))) define(`plugin.${ns}.${pyStr(get(d, 'key'))}`, d, pid);
  }

  const resolve = (ref: J, chapterId: J, scene: J): Dict | null => {
    if (!isStr(ref)) return null;
    if (ref.startsWith('sys.')) {
      if (has(SYS_FIXED, ref)) return { type: SYS_FIXED[ref] };
      const parts = ref.split('.');
      if (parts.length === 4 && parts[1] === 'scenes' && (parts[3] === 'plays' || parts[3] === 'last_selection'))
        return has(scenes, parts[2]!) ? { type: 'integer' } : null;
      if (parts.length === 4 && parts[1] === 'chapters' && parts[3] === 'completed') return has(chapters, parts[2]!) ? { type: 'boolean' } : null;
      if (parts.length === 3 && parts[1] === 'endings') return endings.has(parts[2]) ? { type: 'boolean' } : null;
      return null;
    }
    if (ref.startsWith('chapter.')) {
      if (chapterId === null || chapterId === undefined) return null;
      return get(get(chapterVars, pyStr(chapterId), {}), ref);
    }
    if (ref.startsWith('scene.')) {
      const table: Dict = {};
      for (const d of list(get(scene ?? {}, 'variables', []))) table[`scene.${pyStr(get(d, 'key'))}`] = d;
      return get(table, ref);
    }
    return get(vars_, ref);
  };

  const literalTypeOk = (defn: J, value: J): boolean => {
    const t = get(defn, 'type');
    if (t === null || t === 'any' || isDict(value)) return true;
    if (isList(value)) return value.every((v) => literalTypeOk(defn, v));
    switch (t) {
      case 'boolean':
        return isBool(value);
      case 'integer':
        return isInt(value);
      case 'number':
        return isNum(value);
      case 'string':
        return isStr(value);
      case 'enum':
        return isStr(value) && pyIn(value, get(get(defn, 'constraints', {}), 'values', []));
      default:
        return true;
    }
  };
  const family = (t: J) => (t === 'integer' || t === 'number' ? 'number' : t === 'string' || t === 'enum' ? 'string' : t);

  // defaults e enums
  for (const [qid, d] of items(vars_)) {
    if (has(d, 'default') && !literalTypeOk(d, d.default))
      err('T001', qid, `default ${pyRepr(d.default)} incompatível com ${pyStr(get(d, 'type'))}`, { variavel: qid, tipo: pyStr(get(d, 'type')), valor: pyRepr(d.default) });
  }
  for (const [cid, c] of items(chars)) {
    for (const [k, v] of items(get(c, 'initial_values', {}))) {
      const d = get(vars_, `character.${pyStr(get(c, 'key'))}.${k}`);
      if (d === null) err('R003', `characters/${cid}`, `initial_values.${k} não é variável de personagem`);
      else if (!literalTypeOk(d, v)) err('T001', `characters/${cid}`, `initial_values.${k} tipo incompatível`, { variavel: k, tipo: pyStr(get(d, 'type')), valor: pyRepr(v) });
    }
    const de = get(c, 'default_expression');
    if (truthy(de) && !has(get(c, 'expressions', {}), de)) err('R011', `characters/${cid}`, `default_expression ${pyStr(de)} não existe`);
    const blip = get(get(c, 'voice', {}), 'blip');
    if (truthy(blip) && !has(assets, blip)) err('R004', `characters/${cid}`, `asset ${pyStr(blip)} não registrado (voice.blip)`, { asset: pyStr(blip) });
    for (const [e, a] of items(get(c, 'expressions', {}))) {
      if (!has(assets, a)) err('R004', `characters/${cid}`, `asset ${pyStr(a)} não registrado`, { asset: pyStr(a) });
      else if (assets[a].type !== 'sprite') warn('W014', `characters/${cid}`, `expressão ${e} usa asset ${a} do tipo ${pyStr(assets[a].type)} (esperado sprite)`);
    }
  }

  const activities = new Map<string, [Dict, Dict]>();
  for (const m of values(manifests)) for (const a of list(get(m, 'activities', []))) activities.set(`${pyStr(get(m, 'namespace'))}.${pyStr(get(a, 'id'))}`, [m, a]);
  const usedPluginNs = new Set(keys(cfgPlugins).filter((p) => has(manifests, p)).map((p) => manifests[p].namespace));

  const infer = (e: J, chapterId: J, scene: J, rschema: J = null, where = ''): string | null => {
    if (isBool(e)) return 'boolean';
    if (isInt(e)) return 'integer';
    if (isFloat(e)) return 'number';
    if (isStr(e)) return 'string';
    if (!isDict(e)) return null;
    if (has(e, 'var')) {
      const d = resolve(e.var, chapterId, scene);
      return d ? get(d, 'type') : null;
    }
    if (has(e, 'result')) {
      let node: J = truthy(rschema) ? rschema : {};
      for (const part of pyStr(e.result).split('.')) node = isDict(node) ? get(get(node, 'properties') ?? {}, part) : null;
      const t = isDict(node) ? get(node, 'type') : null;
      return ['boolean', 'integer', 'number', 'string'].includes(t) ? t : null;
    }
    if (has(e, 'if')) {
      const a = infer(get(e, 'then'), chapterId, scene, rschema, where);
      const b = infer(get(e, 'else'), chapterId, scene, rschema, where);
      if (a === b) return a;
      return (a === 'integer' && b === 'number') || (a === 'number' && b === 'integer') ? 'number' : null;
    }
    if (has(e, 'fn')) {
      const fn = pyStr(e.fn);
      const args = list(get(e, 'args', []));
      const ar = FN_ARITY[fn];
      if (!ar) return null;
      const [lo, hi, kind] = ar;
      const ts = args.map((a) => infer(a, chapterId, scene, rschema, where));
      if (!(lo <= args.length && args.length <= hi)) err('T007', where, `${fn} recebe de ${lo} a ${hi} argumentos, não ${args.length}`);
      for (const t of ts) {
        if (t === null) continue;
        if (kind === 'num' && t !== 'integer' && t !== 'number') err('T007', where, `${fn} exige números, recebeu ${t}`);
        if (kind === 'int' && t !== 'integer') err('T007', where, `${fn} exige inteiros, recebeu ${t}`);
      }
      if (fn === 'concat') return 'string';
      if (fn === 'div') return 'number';
      if (['round', 'floor', 'ceil', 'mod', 'random_int'].includes(fn)) return 'integer';
      if (fn === 'abs') return ts.length ? ts[0]! : null;
      if (ts.some((t) => t === null)) return null;
      return ts.every((t) => t === 'integer') ? 'integer' : 'number';
    }
    return null;
  };

  const checkValueType = (target: J, op: J, value: J, where: string, chapterId: J, scene: J, rschema: J = null) => {
    const d = resolve(target, chapterId, scene);
    if (d === null) return;
    const t = infer(value, chapterId, scene, rschema, where);
    if (t === null || ((isBool(value) || isNum(value) || isStr(value)) && op === 'set')) return; // literais: T001 já cobre
    const dt = get(d, 'type');
    const tgt = pyStr(target);
    if (op === 'add' || op === 'subtract' || op === 'multiply') {
      if (t !== 'integer' && t !== 'number') err('T006', where, `${op} em ${tgt} com valor do tipo ${t}`, { variavel: tgt, tipo: pyStr(dt) });
      else if (dt === 'integer' && t === 'number') warn('W017', where, `resultado number gravado em ${tgt} (integer) será truncado`, { variavel: tgt });
    } else if (op === 'set') {
      if (family(t) !== family(dt)) err('T006', where, `${tgt} (${pyStr(dt)}) recebe valor do tipo ${t}`, { variavel: tgt, tipo: pyStr(dt) });
      else if (dt === 'integer' && t === 'number') warn('W017', where, `resultado number gravado em ${tgt} (integer) será truncado`, { variavel: tgt });
    }
  };

  const schemaHasPath = (schema: J, p: string): boolean => {
    let node: J = schema;
    for (const part of p.split('.')) {
      node = isDict(node) ? get(get(node, 'properties') ?? {}, part) : null;
      if (node === null) return false;
    }
    return true;
  };

  const checkText = (text: J, where: string, chapterId: J, scene: J) => {
    for (const ref of interpRefs(text)) {
      if (resolve(ref, chapterId, scene) === null) err('R019', where, `interpolação {${ref}}: variável inexistente ou fora de escopo`, { variavel: ref });
      else if (CONTENT_FILTER_VARS.has(ref)) err('R022', where, `{${ref}}: o estado do modo stream só vale em telas`);
    }
  };

  /** resultFields: null = {result} proibido aqui (T005); dict = result_schema da atividade; true = qualquer campo. */
  const checkRefs = (obj: J, where: string, chapterId: J, scene: J, resultFields: J = null) => {
    walk(obj, (o) => {
      const n = Object.keys(o).length;
      if (has(o, 'result') && n <= 2 && isStr(o.result) && (has(o, 'default') || n === 1)) {
        if (resultFields === null) err('T005', where, `{"result": "${o.result}"} só vale em on_result.effects`);
        else if (resultFields !== true && !schemaHasPath(resultFields, o.result)) err('T005', where, `campo ${o.result} não está no result_schema da atividade`);
      }
      if (has(o, 'variable') && isStr(o.variable)) {
        const v = o.variable;
        const d = resolve(v, chapterId, scene);
        if (d === null) err('R005', where, `variável inexistente ou fora de escopo: ${v}`, { variavel: v });
        else if (CONTENT_FILTER_VARS.has(v)) err('R022', where, `${v}: o modo stream não pode mudar a história; use censored_text, censor ou assets censurados`);
        else {
          if (has(o, 'op') && get(d, 'derived') !== null) err('T002', where, `${v} é derivada (somente leitura)`);
          if (has(o, 'op') && v.startsWith('plugin.')) err('T002', where, `${v} é de plugin (somente leitura para o projeto)`);
          if (has(o, 'operator') && has(o, 'value')) {
            if (isDict(o.value) && isStr(get(o.value, 'var'))) {
              const d2 = resolve(o.value.var, chapterId, scene);
              if (truthy(d2) && family(get(d2, 'type')) !== family(get(d, 'type')) && get(d, 'type') !== 'any' && get(d2, 'type') !== 'any')
                err('T001', where, `${v} (${pyStr(get(d, 'type'))}) comparada com ${o.value.var} (${pyStr(get(d2, 'type'))})`);
            } else if (!literalTypeOk(d, o.value)) {
              err('T001', where, `${v} ${pyStr(o.operator)} ${pyRepr(o.value)}: tipo incompatível`, { variavel: v, tipo: pyStr(get(d, 'type')), valor: pyRepr(o.value) });
            }
          }
          const op = get(o, 'op');
          if ((op === 'add' || op === 'subtract' || op === 'multiply') && get(d, 'type') !== 'integer' && get(d, 'type') !== 'number')
            err('T003', where, `${op} exige variável numérica (${v})`);
          if (op === 'toggle' && get(d, 'type') !== 'boolean') err('T003', where, `toggle exige booleana (${v})`);
          if (op === 'set' && has(o, 'value') && !literalTypeOk(d, o.value))
            err('T001', where, `set ${v} = ${pyRepr(o.value)}: tipo incompatível`, { variavel: v, tipo: pyStr(get(d, 'type')), valor: pyRepr(o.value) });
        }
      }
      if (has(o, 'var') && isStr(o.var) && resolve(o.var, chapterId, scene) === null) err('R005', where, `variável inexistente ou fora de escopo: ${o.var}`, { variavel: o.var });
      else if (has(o, 'var') && isStr(o.var) && CONTENT_FILTER_VARS.has(o.var)) err('R022', where, `${o.var}: o modo stream não pode mudar a história`);
      const ev = get(o, 'event_since_last_selection');
      if (isStr(ev) && ev.startsWith('story.') && !storyEvents.has(ev)) warn('W015', where, `evento ${ev} não declarado em project.json → events`);
      if (isStr(ev) && ev.startsWith('sys.')) warn('W019', where, `${ev}: eventos sys.* não são registrados; a condição é sempre falsa`);
      if (has(o, 'op') && isStr(get(o, 'variable')) && has(o, 'value') && resultFields === null)
        checkValueType(o.variable, o.op, o.value, where, chapterId, scene); // on_result: ver nó plugin
    });
  };

  // --- variáveis derivadas: referências (R005) e ciclos (T004) ---
  const derived: Dict = {};
  for (const [q, d] of items(vars_)) if (get(d, 'derived') !== null) derived[q] = d;
  for (const [q, d] of items(derived)) {
    checkRefs(d.derived, `variables/${q}`, null, null);
    const t = infer(d.derived, null, null, null, `variables/${q}`);
    if (t !== null && family(t) !== family(get(d, 'type')))
      err('T006', `variables/${q}`, `derivada declarada ${pyStr(get(d, 'type'))} mas calcula ${t}`, { variavel: q, tipo: pyStr(get(d, 'type')) });
    let rnd = false;
    walk(d.derived, (o) => {
      if (get(o, 'fn') === 'random_int') rnd = true;
    });
    if (rnd) err('T008', `variables/${q}`, 'random_int numa variável derivada (recalculada a cada leitura)');
  }
  const dfs = (q: string, p: string[]): boolean => {
    for (const r of readVars(derived[q].derived)) {
      if (p.includes(r)) {
        err('T004', `variables/${q}`, `ciclo entre derivadas: ${[...p, r].join(' → ')}`);
        return true;
      }
      if (has(derived, r) && dfs(r, [...p, r])) return true;
    }
    return false;
  };
  for (const q of keys(derived)) dfs(q, [q]);

  // --- grupos (R015) ---
  const groups = new Set(list(get(project, 'exclusive_groups', [])).map((g: J) => get(g, 'id')));
  for (const [cid, c] of items(chapters)) {
    for (const g of list(get(c, 'exclusive_groups', []))) {
      if (groups.has(get(g, 'id'))) err('R015', `chapters/${cid}`, `grupo ${pyStr(get(g, 'id'))} também existe em project.json`, { grupo: pyStr(get(g, 'id')), capitulo: cid });
    }
  }

  const checkVnFormats = (schema: J, data: J, where: string) => {
    for (const [prop, ps] of items(get(schema, 'properties') ?? {})) {
      if (!has(data ?? {}, prop)) continue;
      const v = data[prop];
      const fmt = get(ps, 'format');
      for (const x of isList(v) ? v : [v]) {
        if (!isStr(x)) continue;
        if (fmt === 'vn-asset') {
          if (!has(assets, x)) err('P018', where, `${prop}: asset ${x} não existe`);
          else if (truthy(get(ps, 'vn-asset-type')) && assets[x].type !== ps['vn-asset-type'])
            warn('W014', where, `${prop}: ${x} é ${pyStr(assets[x].type)}, esperado ${pyStr(ps['vn-asset-type'])}`);
        } else if (fmt === 'vn-scene' && !has(scenes, x)) err('P018', where, `${prop}: cena ${x} não existe`);
        else if (fmt === 'vn-character' && !has(chars, x)) err('P018', where, `${prop}: personagem ${x} não existe`);
        else if (fmt === 'vn-variable' && resolve(x, null, null) === null) err('R005', where, `${prop}: variável ${x} não existe`, { variavel: x });
      }
    }
  };

  const sameChapter = (target: J, chapterId: J): boolean => {
    if (!isStr(target) || !has(scenes, target)) return false;
    const ch = get(scenes[target], 'chapter');
    return chapterId !== null && chapterId !== undefined ? ch === chapterId || ch === null : ch === null;
  };

  for (const [cid, c] of items(chapters)) {
    const completion = get(c, 'completion', {});
    checkRefs(completion, `chapters/${cid}`, cid, null);
    for (const n of list(get(c, 'next', []))) {
      checkRefs(get(n, 'conditions', []), `chapters/${cid}/next`, cid, null); // chapter.* ainda vale (RT §3.3)
      if (!has(chapters, get(n, 'chapter'))) err('R007', `chapters/${cid}`, `capítulo ${pyStr(get(n, 'chapter'))} não existe`);
    }
    for (const [k, target] of [['entry_scene', get(c, 'entry_scene')], ['fallback_scene', get(completion, 'fallback_scene')]] as const) {
      if (target === null) continue;
      if (!has(scenes, target)) err('R006', `chapters/${cid}`, `${k} ${pyStr(target)} não existe`);
      else if (!sameChapter(target, cid)) err('R014', `chapters/${cid}`, `${k} é de outro capítulo`, { onde: `chapters/${cid}` });
    }
    const fb = get(completion, 'fallback_scene');
    const conds = get(completion, 'conditions');
    if (isStr(fb) && has(scenes, fb) && truthy(conds)) {
      const w = writtenVars(scenes[fb]);
      if (![...readVars(conds)].some((x) => w.has(x))) warn('W010', `chapters/${cid}`, 'fallback_scene não altera nenhuma variável de completion.conditions', { capitulo: cid });
    }
  }
  if (!has(chapters, get(project, 'start_chapter'))) err('R007', 'project.json', 'start_chapter não existe');
  if (has(project, 'chapters')) {
    for (const cid of list(project.chapters)) if (!has(chapters, cid)) err('R007', 'project.json/chapters', `capítulo ${pyStr(cid)} não existe`);
    for (const cid of keys(chapters)) if (!pyIn(cid, project.chapters)) warn('W018', `chapters/${cid}`, 'capítulo fora de project.chapters');
  }
  if (EXPORT && !truthy(get(project, 'version'))) err('R021', 'project.json', 'version é obrigatória na exportação');
  for (const ch of values(chars)) for (const k of ['name', 'display_name']) checkText(get(ch, k), `characters/${pyStr(get(ch, 'id'))}/${k}`, null, null);
  for (const e of list(get(project, 'endings', []))) {
    for (const k of ['title', 'description']) checkText(get(e, k), `project.json/endings/${pyStr(get(e, 'id'))}/${k}`, null, null);
  }

  /** (camadas → estados, ids de hotspots) de um set. */
  const setParts = (setId: J): [Map<string, Set<string>>, Set<string>] => {
    const st = isStr(setId) ? get(sets, setId, {}) : {};
    const layers = new Map<string, Set<string>>();
    for (const l of list(get(st, 'layers', []))) {
      const states = get(l, 'states', {});
      layers.set(get(l, 'id'), new Set(['default', ...(isList(states) ? states : keys(states))]));
    }
    return [layers, new Set(list(get(st, 'hotspots', [])).map((h: J) => get(h, 'id')))];
  };
  const sceneSets = (scene: J): J[] =>
    list(get(scene, 'nodes', []))
      .filter((n: J) => get(n, 'type') === 'background' && truthy(get(n, 'set')))
      .map((n: J) => n.set);
  const styles = get(theme, 'styles', {});
  const checkStyle = (name: J, where: string) => {
    if (!has(styles, name) && !DEFAULT_STYLES.has(name)) err('U002', where, `estilo ${pyStr(name)} não existe no tema`);
  };
  for (const [name, st] of items(styles)) {
    const seenSt: J[] = [name];
    let cur: J = st;
    while (truthy(get(cur, 'extends'))) {
      checkStyle(cur.extends, `${themeName}/styles/${name}`);
      if (seenSt.includes(cur.extends)) {
        err('U002', `${themeName}/styles/${name}`, `ciclo em extends: ${[...seenSt, cur.extends].map(pyStr).join(' → ')}`);
        break;
      }
      seenSt.push(cur.extends);
      cur = get(styles, cur.extends, {});
    }
  }
  for (const [k, v] of [['choices.style', get(get(theme, 'choices', {}), 'style')], ['dialog.button_style', get(get(theme, 'dialog', {}), 'button_style')]] as const) {
    if (truthy(v)) checkStyle(v, `${themeName}/${k}`);
  }

  const textPaths = new Set<string>();
  const marked: string[] = []; // conteúdo marcado para o modo stream (W024)
  for (const [aid, a] of items(assets)) {
    const c = get(a, 'censored');
    if (!truthy(c)) continue;
    marked.push(`assets.json/${aid}`);
    const r = get(c, 'replace_with');
    if (r === null) continue;
    if (!has(assets, r)) err('R004', `assets.json/${aid}`, `censored.replace_with: asset ${pyStr(r)} não registrado`, { asset: pyStr(r) });
    else if (r === aid || truthy(get(assets[r], 'censored')))
      err('R024', `assets.json/${aid}`, `censored.replace_with ${r}: a substituta não pode ser o próprio asset nem ter censored`);
    else if (assets[r].type !== get(a, 'type')) warn('W014', `assets.json/${aid}`, `censored.replace_with ${r} é ${pyStr(assets[r].type)}, não ${pyStr(get(a, 'type'))}`);
  }
  const cf = get(project, 'content_filter', {});
  if (truthy(get(cf, 'placeholder'))) {
    const ph = cf.placeholder;
    if (!has(assets, ph)) err('R004', 'project.json/content_filter', `placeholder: asset ${pyStr(ph)} não registrado`, { asset: pyStr(ph) });
    else if (!IMG.has(assets[ph].type)) warn('W014', 'project.json/content_filter', `placeholder ${ph} é ${pyStr(assets[ph].type)}`);
    else if (truthy(get(assets[ph], 'censored'))) err('R024', 'project.json/content_filter', `placeholder ${ph} não pode ter censored`);
  }

  // ---------- cenas ----------
  for (const [sid, s] of items(scenes)) {
    const where = rel(root, scenePaths[sid]!);
    const cid = get(s, 'chapter');
    if (cid !== null && !has(chapters, cid)) err('R007', where, `capítulo ${pyStr(cid)} não existe`);
    const cgroups = union(groups, list(get(get(chapters, pyStr(cid), {}), 'exclusive_groups', [])).map((g: J) => get(g, 'id')));
    const scheduling = get(s, 'scheduling', {});
    for (const g of list(get(scheduling, 'exclusive_groups', []))) {
      if (!cgroups.has(g)) err('R008', where, `grupo de exclusividade ${pyStr(g)} não definido`);
    }
    checkRefs(scheduling, where, cid, null); // scene.* não existe antes da cena começar
    for (const d of list(get(s, 'variables', []))) {
      if (has(d, 'default') && !literalTypeOk(d, d.default))
        err('T001', where, `default de scene.${pyStr(get(d, 'key'))}`, { variavel: `scene.${pyStr(get(d, 'key'))}`, tipo: pyStr(get(d, 'type')), valor: pyRepr(d.default) });
      if (get(d, 'persistence') === 'profile') err('R017', where, `scene.${pyStr(get(d, 'key'))}: profile só em variáveis globais e de plugin`);
    }
    const nodes = list(get(s, 'nodes', []));
    const ids: J[] = nodes.map((n: J) => get(n, 'id'));
    const idx = new Map<J, number>();
    nodes.forEach((n: J, i: number) => idx.set(get(n, 'id'), i));
    const inIdx = (t: J) => (isStr(t) ? idx.has(t) : false);
    const following = (i: number): J => (i + 1 < ids.length ? ids[i + 1] : null);
    const or = (a: J, b: J) => (truthy(a) ? a : b);
    const succ = (i: number): J[] => {
      const n = nodes[i];
      const t = get(n, 'type');
      const nxt = or(get(n, 'next'), following(i));
      let out: J[];
      if (t === 'choice') out = [...list(get(n, 'options')).map((o: J) => or(get(o, 'goto'), nxt)), nxt]; // sem opção visível: next (A4)
      else if (t === 'interact')
        out = [...list(get(n, 'hotspots')).map((h: J) => or(get(h, 'goto'), nxt)), or(get(get(n, 'exit', {}), 'goto'), nxt), nxt];
      else if (t === 'jump') out = [get(n, 'goto')];
      else if (t === 'end') out = [];
      else if (t === 'branch') out = [...list(get(n, 'cases')).map((c: J) => get(c, 'goto')), or(get(n, 'else'), nxt)];
      else if (t === 'plugin') out = [...values(get(get(n, 'on_result', {}), 'outcomes', {})), get(n, 'on_error'), nxt];
      else if (t === 'effects') out = [get(n, 'on_fail'), nxt];
      else out = [nxt];
      return out.filter((x) => x !== null && x !== undefined);
    };
    nodes.forEach((n: J, i: number) => {
      const nid = pyStr(get(n, 'id'));
      const nw = `${where}#${nid}`;
      const type = get(n, 'type');
      for (const t of succ(i)) if (!inIdx(t)) err('R009', nw, `destino ${pyStr(t)} não existe`, { onde: where });
      if (type === 'plugin') {
        const act = activities.get(pyStr(get(n, 'activity')));
        const props = act ? get(get(act[1], 'result_schema') ?? {}, 'properties') : null;
        const rf = props !== null ? act![1].result_schema : true;
        const rest: Dict = {};
        for (const [k, v] of items(n)) if (k !== 'on_result') rest[k] = v;
        checkRefs(rest, nw, cid, s);
        const rs = act ? get(act[1], 'result_schema') : null;
        for (const eff of list(get(get(n, 'on_result', {}), 'effects', []))) {
          if (has(eff, 'value')) checkValueType(get(eff, 'variable'), get(eff, 'op'), eff.value, nw, cid, s, rs);
        }
        checkRefs(get(n, 'on_result', {}), nw, cid, s, rf);
      } else {
        checkRefs(n, nw, cid, s);
      }
      if (truthy(get(n, 'censor'))) {
        marked.push(nw);
        if (!CENSORABLE_NODES.has(type))
          err('R023', nw, `censor num passo ${pyStr(type)}: só line, background, show, audio (play) e wait podem mudar com o modo stream`);
        else if (type === 'audio' && get(n, 'action') !== 'play')
          err('R023', nw, `censor num audio com action ${pyStr(get(n, 'action'))}: só a entrada de um som pode depender do modo stream, não a saída (Runtime Spec §5.5)`);
      }
      for (const k of ['censored_text', 'censored_prompt']) {
        if (truthy(get(n, k))) {
          marked.push(nw);
          textPaths.add(`${sid}/${nid}/censored`);
          checkMarkup(n[k], nw);
          checkText(n[k], nw, cid, s);
        }
      }
      for (const o of list(get(n, 'options', []))) {
        if (truthy(get(o, 'censored_text'))) {
          marked.push(nw);
          textPaths.add(`${sid}/${nid}/${pyStr(get(o, 'id'))}/censored`);
          checkMarkup(o.censored_text, nw);
          checkText(o.censored_text, nw, cid, s);
        }
      }
      for (const h of list(get(n, 'hotspots', []))) {
        if (truthy(get(h, 'censored_label'))) {
          marked.push(nw);
          textPaths.add(`${sid}/${nid}/${pyStr(get(h, 'id'))}/censored`);
          checkText(h.censored_label, nw, cid, s);
        }
      }
      if (truthy(get(get(n, 'exit') ?? {}, 'censored_label'))) {
        marked.push(nw);
        textPaths.add(`${sid}/${nid}/exit/censored`);
        checkText(n.exit.censored_label, nw, cid, s);
      }
      if (truthy(get(n, 'censored_caption'))) {
        marked.push(nw);
        textPaths.add(`${sid}/${nid}/censored`);
        checkText(n.censored_caption, nw, cid, s);
      }
      const voice = get(n, 'voice');
      if (type === 'line' && truthy(get(n, 'censored_text')) && isStr(voice) && has(assets, voice) && !truthy(get(assets[voice], 'censored')))
        warn('W025', nw, `fala com censored_text, mas a voz ${voice} não tem censored: no modo stream o jogador ouve a fala original`);
      if (truthy(get(n, 'unresolved'))) {
        const reason = pyStr(get(n.unresolved, 'reason'));
        errOrWarn(EXPORT)('W013', nw, `passo incompleto: ${reason}`, { motivo: reason });
      }
      if (truthy(get(n, 'speaker')) && !has(chars, n.speaker)) err('R010', nw, `personagem ${pyStr(n.speaker)} não existe`);
      if ((type === 'show' || type === 'hide') && get(n, 'character') !== '*' && !has(chars, get(n, 'character')))
        err('R010', nw, `personagem ${pyStr(get(n, 'character'))} não existe`);
      if (truthy(get(n, 'expression'))) {
        const c = get(chars, pyStr(or(get(n, 'speaker'), get(n, 'character'))), {});
        if (truthy(c) && !has(get(c, 'expressions', {}), n.expression)) err('R011', nw, `expressão ${pyStr(n.expression)} não existe`);
      }
      for (const key of ['asset', 'voice']) {
        const a = get(n, key);
        if (a === null) continue;
        if (!has(assets, a)) {
          err('R004', nw, `asset ${pyStr(a)} não registrado`, { asset: pyStr(a) });
          continue;
        }
        const byType: Record<string, Set<string>> = { background: IMG, audio: AUDIO_TYPES[pyStr(get(n, 'channel'))] ?? new Set() };
        const ok = has(byType, type) ? byType[type]! : key === 'voice' ? S('audio_voice') : null;
        if (ok && ok.size && !ok.has(assets[a].type)) warn('W014', nw, `asset ${a} é ${pyStr(assets[a].type)}, não ${sorted(ok).join('/')}`);
      }
      if (type === 'end') {
        const then = has(n, 'then') ? n.then : 'schedule';
        if (truthy(get(n, 'ending')) && !endings.has(n.ending)) err('R012', nw, `final ${pyStr(n.ending)} não declarado em project.json → endings`, { final: pyStr(n.ending) });
        if (truthy(get(n, 'ending')) && then !== 'end_game') warn('W011', nw, 'ending só tem efeito com then: end_game');
        if (isDict(then)) {
          if (!has(scenes, get(then, 'scene'))) err('R006', nw, `cena ${pyStr(get(then, 'scene'))} não existe`);
          else if (!sameChapter(then.scene, cid)) err('R014', nw, 'then.scene aponta para cena de outro capítulo');
        }
      }
      if (type === 'emit' && isStr(get(n, 'event'))) {
        const ev = n.event;
        if (!ev.startsWith('story.')) err('R020', nw, `emit de ${ev}: cenas só emitem eventos story.*`, { evento: ev });
        if (ev.startsWith('story.') && !storyEvents.has(ev)) warn('W015', nw, `evento ${ev} não declarado em project.json → events`);
      }
      if (type === 'line' || type === 'choice') {
        textPaths.add(`${sid}/${nid}`);
        const texts = type === 'line' ? [get(n, 'text')] : [get(n, 'prompt'), ...list(get(n, 'options')).map((o: J) => get(o, 'text'))];
        for (const t of texts) {
          if (truthy(t)) {
            checkMarkup(t, nw);
            checkText(t, nw, cid, s);
          }
        }
      }
      if (type === 'interact') {
        if (truthy(get(n, 'prompt'))) textPaths.add(`${sid}/${nid}`);
        const hotspots = list(get(n, 'hotspots'));
        const texts = [get(n, 'prompt'), get(get(n, 'exit', {}), 'label'), ...hotspots.map((h: J) => get(h, 'label'))];
        if (has(n, 'exit')) textPaths.add(`${sid}/${nid}/exit`);
        for (const h of hotspots) {
          if (truthy(get(h, 'label'))) textPaths.add(`${sid}/${nid}/${pyStr(get(h, 'id'))}`);
          else warn('U008', nw, `hotspot ${pyStr(get(h, 'id'))} sem label (sem nome para teclado e acessibilidade)`);
          const a = get(h, 'area', {});
          if (has(a, 'character') && !has(chars, a.character)) err('R010', nw, `personagem ${pyStr(a.character)} não existe`);
          if (has(a, 'layer') && !sceneSets(s).some((x) => setParts(x)[0].has(a.layer)))
            err('U001', nw, `camada ${pyStr(a.layer)} não existe em nenhum set mostrado pela cena`, { alvo: pyStr(a.layer) });
        }
        for (const t of texts) {
          if (truthy(t)) {
            checkMarkup(t, nw);
            checkText(t, nw, cid, s);
          }
        }
        if (hotspots.every((h: J) => has(h, 'visible_if')) && !has(n, 'exit')) warn('W006', nw, 'o interact pode ficar sem hotspots visíveis');
        if (truthy(get(get(n, 'exit', {}), 'style'))) checkStyle(n.exit.style, nw);
        if (has(n, 'record')) checkRecord(n.record, hotspots, 'do hotspot', nw, cid, s);
      }
      if (type === 'background' && truthy(get(n, 'set')) && !has(sets, n.set)) err('U001', nw, `set ${pyStr(n.set)} não existe em sets/`, { alvo: pyStr(n.set) });
      if (type === 'audio' && truthy(get(n, 'caption'))) {
        textPaths.add(`${sid}/${nid}`);
        checkText(n.caption, nw, cid, s);
      }
      if (type === 'choice') {
        const options = list(get(n, 'options'));
        for (const o of options) textPaths.add(`${sid}/${nid}/${pyStr(get(o, 'id'))}`);
        if (options.every((o: J) => has(o, 'visible_if'))) warn('W006', nw, 'a escolha pode ficar sem opções visíveis');
        if (has(n, 'record')) checkRecord(n.record, options, 'da opção', nw, cid, s);
      }
      if (type === 'plugin') {
        const act = activities.get(pyStr(get(n, 'activity')));
        if (!act) err('P002', nw, `atividade ${pyStr(get(n, 'activity'))} não declarada por nenhum plugin`);
        else {
          const [m, a] = act;
          if (!usedPluginNs.has(m.namespace)) err('P003', nw, `plugin ${pyStr(m.id)} não está em plugins.json`);
          for (const e of schemas.checkAdhoc(get(a, 'params_schema', {}), get(n, 'params', {}))) err('P004', nw, `params: ${e.path ? e.path + ': ' : ''}${e.message}`);
          checkVnFormats(get(a, 'params_schema', {}), get(n, 'params', {}), nw);
          const outcomes = list(get(a, 'outcomes', []));
          const mapped = keys(get(get(n, 'on_result', {}), 'outcomes', {}));
          for (const oc of mapped) if (!outcomes.includes(oc)) err('P005', nw, `outcome ${oc} não declarado`);
          const missing = sorted(new Set(outcomes.filter((x: J) => !mapped.includes(x))));
          if (missing.length) warn('W002', nw, `outcomes sem destino (seguem 'next'): ${pyRepr(missing)}`);
        }
      }
    });
    const start = has(s, 'start') ? s.start : ids[0];
    if (!inIdx(start)) {
      err('R009', where, `start ${pyStr(start)} não existe`, { onde: where });
      continue;
    }
    const seen = new Set<number>();
    const stack = [idx.get(start)!];
    while (stack.length) {
      const i = stack.pop()!;
      if (seen.has(i)) continue;
      seen.add(i);
      for (const t of succ(i)) if (inIdx(t)) stack.push(idx.get(t)!);
    }
    nodes.forEach((n: J, i: number) => {
      if (!seen.has(i)) warn('W001', `${where}#${pyStr(get(n, 'id'))}`, 'nó inalcançável');
    });
  }

  function checkRecord(record: J, options: J[], what: string, nw: string, cid: J, s: J) {
    const d = resolve(record, cid, s);
    if (d !== null && get(d, 'type') !== 'string' && get(d, 'type') !== 'enum') {
      err('R016', nw, `record exige variável string/enum (${pyStr(record)} é ${pyStr(get(d, 'type'))})`);
    } else if (d !== null && get(d, 'type') === 'enum') {
      const vals = get(get(d, 'constraints', {}), 'values', []);
      for (const o of options) {
        const v = has(o, 'value') ? o.value : get(o, 'id');
        if (!pyIn(v, vals)) err('R016', nw, `valor ${pyStr(v)} ${what} não está no enum de ${pyStr(record)}`);
      }
    }
  }

  // ---------- telas e sets (UI Spec §11) ----------
  checkUi();

  // W024: há conteúdo marcado para o modo stream, mas o jogador não tem como ligar o filtro
  const edition = get(get(project, 'build', {}), 'edition', 'standard');
  if (marked.length && edition === 'standard' && !truthy(get(cf, 'ask_on_first_launch')) && !truthy(get(cf, 'default'))) {
    const pdir = path.join(PRESETS, pyStr(get(theme, 'preset', 'classic')), 'ui');
    const eff: Dict = {};
    if (isDir(pdir)) for (const q of globFiles(pdir, '.json')) eff[stem(q)] = safeLoad(q);
    Object.assign(eff, screens);
    let found = false;
    walk(eff, (o) => {
      if (get(o, 'bind') === 'content_filter' || (get(o, 'do') === 'set_setting' && get(o, 'setting') === 'content_filter')) found = true;
    });
    if (!found)
      warn('W024', marked[0]!, `${marked.length} conteúdo(s) marcado(s) para o modo stream, mas nenhuma tela liga content_filter e ask_on_first_launch está desligado`);
  }
  const localesRoot = J_('locales');
  for (const p of localeFiles) {
    const relParts = rel(localesRoot, p).split('/');
    const relRoot = rel(root, p);
    for (const [k, v] of items(get(safeLoad(p), 'strings', {}))) {
      const parts = k.split('/');
      const head = parts[0]!;
      const second = parts[1] ?? '';
      const expected = has(scenes, head)
        ? `scenes/${head}.json`
        : head === 'ui'
          ? `ui/${second}.json`
          : head === 'sets'
            ? `sets/${second}.json`
            : head === 'plugin'
              ? `plugins/${second}.json`
              : 'project.json';
      if (relParts.length > 1 && relParts.slice(1).join('/') !== expected)
        warn('W023', relRoot, `${k} deveria estar em locales/${relParts[0]}/${expected} (Data Model §9)`);
      if (parts.length > 1 && (has(scenes, head) || head === 'ui' || head === 'sets') && !textPaths.has(k)) warn('W003', relRoot, `tradução órfã ${k}`);
      const t = isStr(v) ? v : get(v, 'text', '');
      checkMarkup(t, `${relRoot}/${k}`);
      const sc = has(scenes, head) ? scenes[head] : null;
      checkText(t, `${relRoot}/${k}`, truthy(sc) ? get(sc, 'chapter') : null, sc);
    }
  }

  // assets referenciados por tema, finais e build (R004, W014)
  const ASSET_SKIP = S('if', 'visible_if', 'enabled_if', 'effects', 'payload', 'value', 'options', 'text', 'label', 'tooltip');
  const assetRefs = (o: J, where: string, ctx: Set<string> | null = null): void => {
    if (isDict(o)) {
      for (const [k, v] of Object.entries(o)) {
        if (k === '$schema' || k === 'id' || k === 'description' || k.startsWith('_')) continue;
        let sub: Set<string> | null = ctx ?? ASSET_CTX[k] ?? (k === 'image' && isDict(v) ? IMG : null);
        if (k === 'asset' && get(o, 'do') === 'play_sfx') sub = S('audio_sfx');
        if (isStr(v)) {
          const ok = sub ?? ASSET_KEYS[k] ?? null;
          if (ok === null || v.startsWith('#') || (k === 'cursor' && CURSORS.has(v))) continue;
          if (!has(assets, v)) err('R004', where, `asset ${v} não registrado (${k})`, { asset: v });
          else if (!ok.has(assets[v].type) && assets[v].type !== 'other') warn('W014', where, `${k} usa ${v} do tipo ${pyStr(assets[v].type)}`);
        } else if (!ASSET_SKIP.has(k)) assetRefs(v, where, sub);
      }
    } else if (isList(o)) {
      for (const v of o) assetRefs(v, where, ctx);
    }
  };
  assetRefs(theme, themeName);
  for (const [id, sc] of items(screens)) assetRefs(sc, `ui/${id}.json`);
  for (const [id, st] of items(sets)) assetRefs(st, `sets/${id}.json`);
  assetRefs(get(project, 'endings', []), 'project.json/endings');
  assetRefs(get(project, 'build', {}), 'project.json/build');

  // textos de plugin exibidos no Studio (W007), outcome_labels (P010), capacidades (W012, P016)
  for (const [pid, m] of items(manifests)) {
    for (const a of list(get(m, 'activities', []))) {
      const aw = `${pid}/${pyStr(get(a, 'id'))}`;
      for (const [prop, ps] of items(get(get(a, 'params_schema', {}), 'properties', {}))) {
        if (!has(ps, 'title')) warn('W007', aw, `parâmetro ${prop} sem 'title'; o Studio mostrará o nome técnico`, { plugin: pid, campo: prop });
      }
      const outcomes = list(get(a, 'outcomes', []));
      for (const oc of keys(get(a, 'outcome_labels', {}))) if (!outcomes.includes(oc)) err('P010', aw, `outcome_labels.${oc} não está em outcomes`);
      for (const oc of outcomes) {
        if (!has(get(a, 'outcome_labels', {}), oc)) warn('W007', aw, `outcome ${pyStr(oc)} sem rótulo em outcome_labels`, { plugin: pid, campo: pyStr(oc) });
      }
      if (truthy(get(a, 'default_outcome')) && !outcomes.includes(a.default_outcome)) err('P005', aw, `default_outcome ${pyStr(a.default_outcome)} não está em outcomes`);
    }
    const ns = pyStr(get(m, 'namespace'));
    const deps = union(keys(get(m, 'dependencies', {})), keys(get(m, 'optional_dependencies', {})));
    const depNs = new Set<string>();
    for (const x of deps) depNs.add(has(manifests, x) ? manifests[x].namespace : x.includes('.') ? x.slice(x.indexOf('.') + 1) : x);
    for (const d of list(get(m, 'variables', []))) {
      for (const bad of ['access', 'characters']) {
        if (has(d, bad)) err('P017', `${pid}/variables`, `plugin.${ns}.${pyStr(get(d, 'key'))}: '${bad}' não vale em variável de plugin`);
      }
      if (get(d, 'derived') !== null) {
        for (const r of readVars(d.derived)) {
          if (!r.startsWith(`plugin.${ns}.`)) err('P017', `${pid}/variables`, `derivada plugin.${ns}.${pyStr(get(d, 'key'))} lê ${r}, fora do próprio namespace`);
        }
      }
    }
    for (const mode of ['read', 'write']) {
      for (const pat of list(get(get(m, 'variable_permissions', {}), mode, []))) {
        if (!isStr(pat) || !pat.startsWith('plugin.')) continue;
        const other = pat.split('.')[1];
        if (other === ns) continue;
        if (mode === 'write') err('P017', pid, `${pat}: variáveis de outro plugin nunca são graváveis`);
        else if (!depNs.has(other!)) err('P017', pid, `${pat}: leitura de outro plugin exige dependência declarada`);
      }
    }
    for (const d of list(get(m, 'variables', []))) {
      if (!has(d, 'name'))
        warn('W007', `${pid}/variables`, `variável plugin.${ns}.${pyStr(get(d, 'key'))} sem 'name'; o Studio mostrará o nome técnico`, { plugin: pid, campo: `plugin.${ns}.${pyStr(get(d, 'key'))}` });
    }
    const caps = get(m, 'capabilities', {});
    const runtimeCaps = list(get(caps, 'runtime', []));
    if ((truthy(get(m, 'records')) || truthy(get(m, 'profile'))) && !runtimeCaps.includes('profile.data')) err('P019', pid, 'records/profile exigem a capacidade profile.data');
    for (const a of list(get(m, 'activities', []))) {
      if (has(a, 'free_play')) {
        for (const e of schemas.checkAdhoc(get(a, 'params_schema', {}), get(a.free_play, 'params', {})))
          err('P004', `${pid}/${pyStr(get(a, 'id'))}`, `free_play.params: ${e.path ? e.path + ': ' : ''}${e.message}`);
      }
    }
    if (truthy(get(get(m, 'events', {}), 'subscribes')) && !runtimeCaps.includes('events.subscribe')) warn('W012', pid, 'events.subscribes sem a capacidade events.subscribe');
    if (list(get(caps, 'editor', [])).includes('network') && !pid.startsWith('vnstudio.')) err('P016', pid, 'a capacidade network é só para plugins oficiais no v1');
    const plats = get(get(m, 'compatibility', {}), 'platforms');
    if (plats !== null) {
      for (const pl of list(get(get(project, 'build', {}), 'platforms', []))) {
        if (!pyIn(pl, plats)) warn('W008', pid, `projeto exporta para ${pyStr(pl)}, fora de compatibility.platforms`, { plugin: pid, plataforma: pyStr(pl) });
      }
    }
    checkPluginCode(pid, m, pluginRoots[pid]!, err, warn);
  }

  // W021: idioma do jogo fora dos idiomas do produto sem as chaves runtime/ traduzidas (Req §9.1)
  const presetEn = path.join(PRESETS, pyStr(get(theme, 'preset', 'classic')), 'locales', 'en.json');
  if (exists(presetEn)) {
    const runtimeKeys = keys(get(safeLoad(presetEn), 'strings', {})).filter((k) => k.startsWith('runtime/'));
    for (const lang of list(get(project, 'locales', []))) {
      if (!isStr(lang)) continue;
      if (PRODUCT_LOCALES.has(lang) || PRODUCT_LOCALES.has(lang.split('-')[0]!)) continue;
      const have = new Set<string>();
      const ldir = J_('locales', lang);
      if (isDir(ldir)) for (const p of rglobFiles(ldir, (n) => n.endsWith('.json'))) for (const k of keys(get(safeLoad(p), 'strings', {}))) have.add(k);
      const missing = sorted(runtimeKeys.filter((k) => !have.has(k)));
      if (missing.length) warn('W021', `locales/${lang}`, `${missing.length} textos prontos do runtime sem tradução (ex.: ${missing[0]}); caem no inglês`);
    }
  }

  // W022: recurso que depende de profile.data sem a concessão
  for (const [pid, m] of items(manifests)) {
    const cfg = get(cfgPlugins, pid);
    if (cfg === null || !truthy(get(m, 'records'))) continue;
    if (!list(get(get(cfg, 'grants', {}), 'capabilities', [])).includes('runtime:profile.data') && list(get(get(m, 'capabilities', {}), 'runtime', [])).includes('profile.data'))
      warn('W022', `plugins.json/${pid}`, 'o plugin tem quadros de recordes mas profile.data não foi concedido: recordes e dados de perfil serão recusados');
  }

  // idiomas do build (R013, Build System §5.3)
  const bl = get(get(project, 'build', {}), 'locales');
  if (bl !== null) {
    const dl = get(project, 'default_locale');
    if (!pyIn(dl, bl)) err('R013', 'project.json/build', `build.locales não contém ${pyStr(dl)}`);
    for (const l of list(bl)) if (!pyIn(l, get(project, 'locales', []))) err('R013', 'project.json/build', `idioma ${pyStr(l)} fora de locales`);
  }

  // vínculos de desenvolvimento (P013, só na exportação)
  for (const [pid, e] of [...items(get(lock, 'plugins', {})), ...items(get(localLock, 'plugins', {}))]) {
    if (truthy(get(e, 'link'))) errOrWarn(EXPORT)('P013', 'plugin-lock', `${pid} está vinculado a uma pasta de desenvolvimento`, { plugin: pid });
  }

  // coerência do lock (P015)
  for (const [pid, cfg] of items(cfgPlugins)) {
    const e = get(get(lock, 'plugins', {}), pid);
    if (e === null) {
      err('P015', 'plugin-lock.json', `${pid} está em plugins.json mas não no lock`);
      continue;
    }
    if (!satisfies(pyStr(get(e, 'version')), pyStr(get(cfg, 'version')))) err('P015', 'plugin-lock.json', `${pid} ${pyStr(get(e, 'version'))} fora da faixa ${pyStr(get(cfg, 'version'))}`);
    if (has(manifests, pid) && manifests[pid].namespace !== get(e, 'namespace'))
      err('P015', 'plugin-lock.json', `${pid}: namespace ${pyStr(get(e, 'namespace'))} ≠ ${pyStr(manifests[pid].namespace)} do manifesto`);
    if (has(manifests, pid) && manifests[pid].version !== get(e, 'version'))
      err('P015', 'plugin-lock.json', `${pid}: lock fixa ${pyStr(get(e, 'version'))}, manifesto é ${pyStr(manifests[pid].version)}`);
  }

  // permissões: concessão ⊆ pedido; variáveis concedidas devem aceitar plugins
  for (const [pid, cfg] of items(cfgPlugins)) {
    const m = get(manifests, pid);
    if (m === null) {
      warn('W004', 'plugins.json', `manifesto de ${pid} não fornecido; permissões não verificadas`);
      continue;
    }
    const caps = get(m, 'capabilities', {});
    const reqCaps = new Set([
      ...list(get(caps, 'runtime', [])).map((c: J) => `runtime:${pyStr(c)}`),
      ...list(get(caps, 'editor', [])).map((c: J) => `editor:${pyStr(c)}`),
    ]);
    const grants = get(cfg, 'grants', {});
    for (const c of list(get(grants, 'capabilities', []))) if (!reqCaps.has(c)) err('P006', `plugins.json/${pid}`, `capacidade ${pyStr(c)} concedida mas não pedida`);
    for (const mode of ['read', 'write']) {
      const asked = list(get(get(m, 'variable_permissions', {}), mode, [])).map((pat: J) =>
        isStr(pat) && pat.startsWith('$config.') ? pyStr(get(get(cfg, 'config', {}), pat.slice(8), '')) : pyStr(pat),
      );
      for (const v of list(get(get(grants, 'variables', {}), mode, []))) {
        const vs = pyStr(v);
        if (!asked.some((pat: string) => fnmatchcase(vs, pat))) err('P007', `plugins.json/${pid}`, `${mode} ${vs} concedido mas não pedido`);
        const d = get(vars_, vs);
        if (d === null) err('R005', `plugins.json/${pid}`, `variável ${vs} não existe`, { variavel: vs });
        else if (mode === 'write' && get(get(d, 'access', {}), 'plugins_write', 'none') === 'none')
          err('P008', `plugins.json/${pid}`, `${vs} não aceita escrita de plugins`, { plugin: pid, variavel: vs });
        else if (mode === 'read' && get(get(d, 'access', {}), 'plugins_read', 'none') === 'none') err('P014', `plugins.json/${pid}`, `${vs} não aceita leitura de plugins`);
      }
    }
    for (const sc of list(get(grants, 'scenes', []))) if (!has(scenes, sc)) err('R006', `plugins.json/${pid}`, `cena ${pyStr(sc)} não existe`);
    const confSchema = get(m, 'config_schema');
    if (truthy(confSchema)) {
      for (const e of schemas.checkAdhoc(confSchema, get(cfg, 'config', {}))) err('P004', `plugins.json/${pid}`, `config: ${e.path ? e.path + ': ' : ''}${e.message}`);
      checkVnFormats(confSchema, get(cfg, 'config', {}), `plugins.json/${pid}/config`);
    }
    for (const ev of list(get(get(m, 'events', {}), 'emits', []))) {
      if (!pyStr(get(ev, 'name')).startsWith(pyStr(get(m, 'namespace')) + '.')) err('P009', pid, `evento ${pyStr(get(ev, 'name'))} fora do namespace`);
    }
  }

  return { errors, warnings };

  // ---------- UI Spec §11: U001–U014 ----------
  function checkUi(): void {
    const stageParts = new Set<string>();
    for (const stId of keys(sets)) {
      const [layers, hs] = setParts(stId);
      for (const x of layers.keys()) stageParts.add(x);
      for (const x of hs) stageParts.add(x);
    }
    const knownScreens = new Set([...keys(screens), ...FIXED_SCREENS, ...PRESET_SCREENS]);
    const gallerySources: Record<string, Set<string>> = { images: S('image', 'background'), music: S('audio_music') };
    const gallerySections = list(get(get(project, 'gallery') ?? {}, 'sections', []));
    const opens = new Map<J, Set<J>>(); // tela → telas que ela abre (U010)
    const base = list(get(get(project, 'settings', {}), 'resolution', [1920, 1080]));
    const plays = new Set<J>();

    const profileOk = (ref: string) => {
      if (ref.startsWith('sys.ui.') || ref.startsWith('sys.endings.')) return true;
      const d = get(vars_, ref);
      return d !== null && get(d, 'persistence') === 'profile';
    };

    const checkConds = (conds: J, where: string, title: boolean) => {
      for (const c of walkConds(conds)) {
        const val = get(c, 'value');
        for (const ref of [get(c, 'variable'), isDict(val) ? get(val, 'var') : null]) {
          if (!isStr(ref)) continue;
          if (resolve(ref, null, null) === null) err('R005', where, `variável inexistente ou fora de escopo: ${ref}`, { variavel: ref });
          else if (title && !profileOk(ref)) err('U003', where, `${ref}: no título só valem variáveis profile, sys.endings.* e sys.ui.*`, { variavel: ref });
        }
      }
    };

    /** Devolve os estados válidos do alvo, ou null se não for camada. */
    const checkTarget = (target: J, where: string, elemIds: Set<J>, ownSet: J, inSet: boolean): Set<string> | null => {
      const t = pyStr(target);
      const i = t.lastIndexOf(':');
      const kind = i >= 0 ? t.slice(0, i) : '';
      const name = i >= 0 ? t.slice(i + 1) : t;
      if (inSet || kind === 'set') {
        const [layers, hs] = truthy(ownSet) ? setParts(ownSet) : [new Map<string, Set<string>>(), new Set<string>()];
        if (ownSet === null || ownSet === undefined) {
          err('U001', where, `${t}: a tela não tem set`, { alvo: t });
          return null;
        }
        if (!layers.has(name) && !hs.has(name)) err('U001', where, `${t}: camada ou hotspot inexistente no set ${pyStr(ownSet)}`, { alvo: t });
        return layers.get(name) ?? null;
      }
      if (kind === 'stage') {
        if (!stageParts.has(name)) err('U001', where, `${t}: nenhum set tem essa camada ou hotspot`, { alvo: t });
        return null;
      }
      if (!elemIds.has(name)) err('U001', where, `${t}: elemento inexistente na tela`, { alvo: t });
      return null;
    };

    interface Ctx {
      kind: J;
      elemIds: Set<J>;
      set: J;
      inSet: boolean;
      title: boolean;
      conf: number;
      path: string;
      screen: J;
    }

    const checkSettingValue = (setting: J, value: J, where: string) => {
      const t = SETTING_TYPES[pyStr(setting)];
      if (!t) return;
      const ok = { number: isNum(value), integer: isInt(value), boolean: isBool(value), string: isStr(value), list: isList(value) }[t];
      if (!ok) err('U005', where, `${pyStr(setting)} espera ${t}, recebeu ${pyRepr(value)}`);
      else if (setting === 'locale' && !pyIn(value, get(project, 'locales', []))) err('U005', where, `idioma ${pyStr(value)} fora de project.json → locales`);
    };

    const checkActions = (lst: J, where: string, ctx: Ctx) => {
      for (const a of uiActions(lst)) {
        const d0 = get(a, 'do');
        const doS = pyStr(d0);
        if (has(a, 'if')) checkConds(a.if, where, ctx.title);
        if (ctx.inSet && !COSMETIC.has(d0))
          err('U004', where, `ação ${doS} não é cosmética (hotspots de set só aceitam ${sorted(COSMETIC).join(', ')})`, { acao: doS });
        if (TITLE_ONLY.has(d0) && ctx.kind !== 'title') err('U004', where, `${doS} só vale na tela de título`, { acao: doS });
        if (GAME_ONLY.has(d0) && ctx.kind === 'title') err('U004', where, `${doS} só vale durante o jogo`, { acao: doS });
        if (d0 === 'open_screen') {
          if (!knownScreens.has(get(a, 'screen'))) err('U001', where, `tela ${pyStr(get(a, 'screen'))} não existe`, { alvo: pyStr(get(a, 'screen')) });
          if (get(a, 'screen') === 'gallery' && !gallerySections.length)
            warn('U014', where, 'open_screen abre a galeria, mas project.json não tem gallery: a ação não faz nada');
          if (!opens.has(ctx.screen)) opens.set(ctx.screen, new Set());
          opens.get(ctx.screen)!.add(get(a, 'screen'));
        }
        if (d0 === 'reset_profile' && (ctx.kind === 'pause' || ctx.kind === 'hud')) err('U004', where, 'reset_profile não vale durante o jogo', { acao: doS });
        if (d0 === 'skip_activity' && ctx.kind !== 'pause')
          err('U004', where, 'skip_activity só vale na tela de pausa (aberta durante um minijogo)', { acao: doS });
        if (has(a, 'target')) {
          const states = checkTarget(a.target, where, ctx.elemIds, ctx.set, ctx.inSet);
          for (const stn of has(a, 'state') ? [a.state] : list(get(a, 'states', []))) {
            if (states !== null && !states.has(stn)) err('U001', where, `estado ${pyStr(stn)} não existe em ${pyStr(a.target)}`, { alvo: `${pyStr(a.target)}:${pyStr(stn)}` });
          }
          if ((d0 === 'set_state' || d0 === 'toggle_state') && states === null && !pyStr(a.target).includes(':') && !ctx.inSet)
            err('U001', where, `${pyStr(a.target)}: só camadas de set têm estados`, { alvo: pyStr(a.target) });
        }
        if (d0 === 'effects') {
          for (const e of list(get(a, 'effects'))) {
            const d = resolve(get(e, 'variable', ''), null, null);
            if (d === null) err('R005', where, `variável inexistente ou fora de escopo: ${pyStr(get(e, 'variable'))}`, { variavel: pyStr(get(e, 'variable')) });
            else if (ctx.title && get(d, 'persistence') !== 'profile') err('U004', where, `${pyStr(e.variable)}: no título, effects só em variáveis profile`, { acao: doS });
          }
        }
        if (d0 === 'emit' && !pyStr(get(a, 'event')).startsWith('story.')) err('R020', where, `emit de ${pyStr(get(a, 'event'))}: só eventos story.*`, { evento: pyStr(get(a, 'event')) });
        if (d0 === 'set_setting') checkSettingValue(get(a, 'setting'), get(a, 'value'), where);
        if (d0 === 'play_activity') {
          plays.add(ctx.screen);
          if (ctx.kind === 'pause' || ctx.kind === 'hud') err('U004', where, 'play_activity só vale fora do jogo (título e telas abertas a partir dele)', { acao: doS });
          const act = activities.get(pyStr(get(a, 'activity')));
          if (!act || !has(act[1], 'free_play')) err('P020', where, `atividade ${pyStr(get(a, 'activity'))} inexistente ou sem free_play`);
          else {
            const merged = { ...get(act[1].free_play, 'params', {}), ...get(a, 'params', {}) };
            for (const e of schemas.checkAdhoc(get(act[1], 'params_schema', {}), merged))
              err('P004', where, `params do modo livre: ${e.path ? e.path + ': ' : ''}${e.message}`);
          }
        }
        if (d0 === 'confirm') {
          ctx.conf += 1;
          textPaths.add(`${ctx.path}/confirm${ctx.conf}`);
          checkMarkup(get(a, 'text'), where);
        }
      }
    };

    /** A condição ou expressão lê o estado do modo stream? */
    const readsCf = (obj: J): boolean => {
      if (!truthy(obj)) return false;
      const s = JSON.stringify(obj);
      return [...CONTENT_FILTER_VARS].some((v) => s.includes(`"${v}"`));
    };

    /** R022 nas telas: o modo stream não pode decidir effects nem emit (Data Model §10.4). */
    const checkCfGuard = (lst: J, guarded: boolean, where: string) => {
      for (const a of list(lst)) {
        const g = guarded || readsCf(get(a, 'if'));
        const d0 = get(a, 'do');
        if ((d0 === 'effects' || d0 === 'emit') && (g || readsCf(get(a, 'effects')) || readsCf(get(a, 'payload'))))
          err('R022', where, `${d0} depende do modo stream: a história não pode mudar com ele (use o estado do filtro só em enfeites)`);
        for (const k of ['then', 'else']) checkCfGuard(get(a, k), g, where);
      }
    };

    // galeria opcional (Data Model §10.5, UI Spec §11)
    if (has(screens, 'gallery') && !gallerySections.length)
      warn('U014', 'ui/gallery.json', 'o projeto tem tela de galeria, mas project.json não tem gallery: a tela não entra no jogo');
    for (const s of gallerySections) {
      if (s === 'endings' && !truthy(get(project, 'endings'))) warn('U011', 'project.json/gallery', 'seção endings da galeria vazia: nenhum final em project.json → endings');
      else if (has(gallerySources, s) && !values(assets).some((a: J) => truthy(get(a, 'gallery')) && gallerySources[s]!.has(get(a, 'type'))))
        warn('U011', 'project.json/gallery', `seção ${pyStr(s)} da galeria vazia: nenhum asset com gallery: true desse tipo`);
    }
    for (const aid of sorted(keys(assets))) {
      const a = assets[aid];
      if (truthy(get(a, 'gallery')) && !gallerySections.some((s: J) => (gallerySources[pyStr(s)] ?? new Set()).has(get(a, 'type')))) {
        const sec = Object.entries(gallerySources).find(([, t]) => t.has(get(a, 'type')))?.[0] ?? null;
        const why = sec ? `a seção ${sec} não está em project.json → gallery.sections` : `assets ${pyStr(get(a, 'type'))} não entram na galeria`;
        warn('U013', `assets.json#${aid}`, `gallery: true ignorado: ${why}`);
      }
    }
    for (const [scrId, scr] of items(screens)) {
      const where = `ui/${scrId}.json`;
      const kind = get(scr, 'kind');
      const title = kind === 'title';
      if (truthy(get(scr, 'set')) && !has(sets, scr.set)) err('U001', where, `set ${pyStr(scr.set)} não existe em sets/`, { alvo: pyStr(scr.set) });
      const elems = uiElements(get(scr, 'elements', []));
      const ids: J[] = elems.map((e) => get(e, 'id'));
      const dups = sorted(new Set(ids.filter((i, k) => ids.indexOf(i) !== k).map(pyStr)));
      for (const dup of dups) err('U001', where, `id de elemento duplicado ${dup}`, { alvo: dup });
      const elemIds = new Set(ids);
      if (truthy(get(scr, 'focus_start')) && !elemIds.has(scr.focus_start)) err('U001', where, `focus_start ${pyStr(scr.focus_start)} não existe`, { alvo: pyStr(scr.focus_start) });
      const mkCtx = (p: string): Ctx => ({ kind, elemIds, set: get(scr, 'set'), inSet: false, title, conf: 0, path: p, screen: scrId });
      for (const k of ['on_open', 'on_close', 'back']) {
        checkCfGuard(get(scr, k), false, `${where}/${k}`);
        checkActions(get(scr, k), `${where}/${k}`, mkCtx(`ui/${scrId}/${k}`));
      }
      const allDo = new Set<J>();
      for (const k of ['on_open', 'on_close', 'back']) for (const a of uiActions(get(scr, k))) allDo.add(get(a, 'do'));
      // R022: a guarda de um container (visible_if/enabled_if que lê o modo stream) vale para tudo que ele contém
      const cfParent = new Map<J, boolean>();
      const markCf = (es: J, g: boolean) => {
        for (const x of list(es)) {
          cfParent.set(get(x, 'id'), g);
          if (get(x, 'type') === 'container') markCf(get(x, 'children', []), g || readsCf(get(x, 'visible_if')) || readsCf(get(x, 'enabled_if')));
        }
      };
      markCf(get(scr, 'elements', []), false);
      for (const e of elems) {
        const eid = pyStr(get(e, 'id'));
        const ew = `${where}#${eid}`;
        const tp = `ui/${scrId}/${eid}`;
        const etype = get(e, 'type');
        for (const k of ['visible_if', 'enabled_if']) if (has(e, k)) checkConds(e[k], ew, title);
        for (const nb of values(get(e, 'focus') ?? {})) if (!elemIds.has(nb)) err('U001', ew, `vizinho de foco ${pyStr(nb)} não existe`, { alvo: pyStr(nb) });
        for (const k of ['style', 'slot_style']) if (truthy(get(e, k))) checkStyle(e[k], ew);
        for (const k of ['actions', 'on_hover']) {
          checkCfGuard(get(e, k), (cfParent.get(get(e, 'id')) ?? false) || readsCf(get(e, 'visible_if')) || readsCf(get(e, 'enabled_if')), ew);
          checkActions(get(e, k), ew, mkCtx(tp));
          for (const a of uiActions(get(e, k))) allDo.add(get(a, 'do'));
        }
        for (const k of ['text', 'label']) {
          if (truthy(get(e, k))) {
            textPaths.add(tp);
            checkMarkup(e[k], ew);
            for (const ref of interpRefs(e[k])) {
              if (resolve(ref, null, null) === null) err('R019', ew, `interpolação {${ref}}: variável inexistente ou fora de escopo`, { variavel: ref });
              else if (title && !profileOk(ref)) err('U003', ew, `{${ref}}: no título só valem variáveis profile, sys.endings.* e sys.ui.*`, { variavel: ref });
            }
          }
        }
        if (truthy(get(e, 'tooltip'))) textPaths.add(`${tp}/tooltip`);
        if (truthy(get(e, 'empty_text'))) textPaths.add(`${tp}/empty`);
        if (etype === 'records_list') {
          const board = pyStr(get(e, 'board'));
          const dot = board.indexOf('.');
          const ns = dot >= 0 ? board.slice(0, dot) : board;
          const b = dot >= 0 ? board.slice(dot + 1) : '';
          const m = values(manifests).find((x: J) => get(x, 'namespace') === ns);
          if (!m || !list(get(m, 'records', [])).some((r: J) => get(r, 'id') === b)) err('U001', ew, `quadro de recordes ${board} não existe`, { alvo: board });
        }
        if (etype === 'gallery_grid' && !pyIn(get(e, 'source'), gallerySections))
          err('U012', ew, `gallery_grid de ${pyStr(get(e, 'source'))}, mas essa seção não está em project.json → gallery.sections`);
        for (const o of list(get(e, 'options', []))) {
          textPaths.add(`${tp}/option/${pyStr(get(o, 'value'))}`);
          checkSettingValue(get(e, 'bind'), get(o, 'value'), ew);
        }
        if ((etype === 'button' || etype === 'hotspot') && !(truthy(get(e, 'text')) || truthy(get(e, 'label')) || truthy(get(e, 'tooltip'))))
          warn('U008', ew, 'elemento clicável sem texto nem tooltip (sem nome para teclado e acessibilidade)');
        const area = get(e, 'area', {});
        if (etype === 'hotspot' && has(area, 'layer')) checkTarget(`set:${pyStr(area.layer)}`, ew, elemIds, get(scr, 'set'), false);
        if (etype === 'hotspot' && has(area, 'character')) err('U001', ew, 'área character só vale em nós interact', { alvo: 'character' });
        if (has(e, 'bind')) {
          const t = SETTING_TYPES[pyStr(e.bind)];
          if (etype === 'slider' && t !== 'number' && t !== 'integer') err('U005', ew, `slider não serve para ${pyStr(e.bind)} (${pyStr(t ?? null)})`);
          if (etype === 'toggle' && t !== 'boolean') err('U005', ew, `toggle não serve para ${pyStr(e.bind)} (${pyStr(t ?? null)})`);
        }
        const pos = get(e, 'position');
        const size = get(e, 'size');
        if (truthy(pos) && truthy(size)) {
          const piv = list(get(e, 'pivot', [0.5, 0.5]));
          const x0 = num(pos[0]) * num(base[0]) - num(piv[0]) * num(size[0]);
          const y0 = num(pos[1]) * num(base[1]) - num(piv[1]) * num(size[1]);
          if (x0 < 0 || y0 < 0 || x0 + num(size[0]) > num(base[0]) || y0 + num(size[1]) > num(base[1]))
            warn('U007', ew, `elemento sai da tela na resolução base ${pyStr(base[0])}x${pyStr(base[1])}`);
        }
      }
      if (kind === 'title' && !allDo.has('new_game')) err('U006', where, 'tela de título sem ação new_game', {});
      const licensed = values(manifests).filter((m: J) => truthy(get(m, 'license'))).map((m: J) => pyStr(m.id));
      const credited = sorted(keys(assets).filter((aid) => truthy(get(assets[aid], 'credit'))));
      // U009: todo jogo leva o aviso de licença do motor e do runtime (UI Spec §3.1, Build System §4.5)
      if (kind === 'credits' && !elems.some((e) => get(e, 'type') === 'licenses_list')) {
        const quem = [
          'o aviso de licença do motor (Godot) e do runtime é obrigatório',
          ...(licensed.length ? [`os plugins ${sorted(licensed).join(', ')} têm licença`] : []),
          ...(credited.length ? [`os assets ${credited.join(', ')} têm credit`] : []),
        ];
        errOrWarn(EXPORT)('U009', where, `créditos sem licenses_list: ${quem.join('; ')} (Build System §4.5)`);
      }
      for (const e of elems) {
        if (kind !== 'credits' || get(e, 'type') !== 'licenses_list' || !has(e, 'include')) continue;
        if (credited.length && !pyIn('assets', e.include))
          warn('U009', `${where}#${pyStr(get(e, 'id'))}`, `licenses_list sem assets, mas os assets ${credited.join(', ')} têm credit`);
        if (!pyIn('engine', e.include)) warn('U009', `${where}#${pyStr(get(e, 'id'))}`, 'licenses_list sem engine: o runtime mostra o aviso do motor mesmo assim');
      }
      if (kind === 'pause' && !allDo.has('close_screen') && !allDo.has('back') && !has(scr, 'back')) err('U006', where, 'tela de pausa sem close_screen nem back', {});
    }

    // U010: play_activity numa tela alcançável a partir da pausa ou do HUD
    const ingameScreens = new Set(keys(screens).filter((k) => ['pause', 'hud'].includes(get(screens[k], 'kind'))));
    const inGame = new Set<J>([...ingameScreens, ...['pause', 'hud'].filter((k) => !has(screens, k))]);
    let frontier = new Set(inGame);
    while (frontier.size) {
      const nxt = new Set<J>();
      for (const k of frontier) for (const x of opens.get(k) ?? []) if (!inGame.has(x)) nxt.add(x);
      for (const x of nxt) inGame.add(x);
      frontier = nxt;
    }
    for (const k of sorted([...plays].filter((x) => inGame.has(x) && !ingameScreens.has(x)).map(pyStr))) {
      warn('U010', `ui/${k}.json`, 'play_activity numa tela que a pausa ou o HUD abrem: o botão fica escondido durante a partida (Runtime Spec §5.3)');
    }

    for (const [stId, st] of items(sets)) {
      const where = `sets/${stId}.json`;
      const [layers] = setParts(stId);
      const ids: J[] = [...list(get(st, 'layers', [])).map((l: J) => get(l, 'id')), ...list(get(st, 'hotspots', [])).map((h: J) => get(h, 'id'))];
      const dups = sorted(new Set(ids.filter((i, k) => ids.indexOf(i) !== k).map(pyStr)));
      for (const dup of dups) err('U001', where, `id duplicado ${dup} (camadas e hotspots dividem o espaço de ids)`, { alvo: dup });
      for (const h of list(get(st, 'hotspots', []))) {
        const hw = `${where}#${pyStr(get(h, 'id'))}`;
        const area = get(h, 'area', {});
        if (has(area, 'character')) err('U001', hw, 'área character só vale em nós interact', { alvo: 'character' });
        if (has(area, 'layer') && !layers.has(area.layer)) err('U001', hw, `camada ${pyStr(area.layer)} não existe`, { alvo: pyStr(area.layer) });
        if (truthy(get(h, 'label'))) textPaths.add(`sets/${stId}/${pyStr(get(h, 'id'))}`);
        else warn('U008', hw, 'hotspot sem label (sem nome para teclado e acessibilidade)');
        for (const k of ['on_hover', 'on_press', 'on_release']) {
          checkActions(get(h, k), hw, {
            kind: 'set', elemIds: new Set(), set: stId, inSet: true, title: false, conf: 0, path: `sets/${stId}/${pyStr(get(h, 'id'))}`, screen: null,
          });
        }
      }
    }
  }
}

const SCHEMA_CACHE = new Map<string, Schemas>();
/** Os schemas compilados ficam em cache por pasta: compilar todos leva centenas de milissegundos. */
function schemasFor(dir: string, make: () => Schemas): Schemas {
  let s = SCHEMA_CACHE.get(dir);
  if (!s) SCHEMA_CACHE.set(dir, (s = make()));
  return s;
}

/** Pastas imediatas de `dir`, na ordem de `sorted()` do Python. */
function listDirs(dir: string): string[] {
  try {
    return readdirSync(dir)
      .map((n) => path.join(dir, n))
      .filter(isDir)
      .sort(cmpPath);
  } catch {
    return [];
  }
}
