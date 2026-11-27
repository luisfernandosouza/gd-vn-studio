/**
 * Compilador do bundle narrativo (Build System §5.1, Runtime Spec §2): da entrada lida do projeto
 * para a forma canônica (`bundle.json`, `locales/<idioma>.json`, `plugins.json`, `licenses.json`)
 * com o `content_hash`. Porte de `docs/specs/tools/compile_bundle.py`, que é a referência: para o
 * mesmo projeto os dois DEVEM gerar os mesmos bytes (JCS).
 *
 * Cada entidade do bundle (cena, capítulo, personagem, tela, set, asset, tema, texto) tem a própria
 * função, que só depende do {@link CompileContext}. O build completo é a soma delas, e a recarga
 * incremental do Preview recompila uma por vez (`incremental.ts`); as duas formas dão o mesmo
 * `bundle.json` (regra de equivalência incremental, BS §5.1).
 *
 * Não valida: quem chama roda o validador antes (M5-01) e para em erro, como a referência.
 * Puro (sem Node), para o Studio usar o mesmo código na WebView.
 */
import type { Bundle, BundleLicenses, BundleLocale, BundlePlugins } from '@vnstudio/plugin-schema';
import { canonicalHash } from './hash.js';
import type { Json, JsonObject } from './jcs.js';
import type { Edition, ProjectInput } from './input.js';

/** Idiomas do produto (Req §9.1). */
export const PRODUCT_LOCALES = ['en', 'pt-BR', 'es', 'fr', 'it', 'de', 'ja', 'zh-Hans', 'zh-Hant'] as const;

/** Ids reservados de assets que o runtime fornece (fontes do preset). */
export const PRESET_ASSETS: Record<string, { type: string; path: string }> = {
  'preset/font_body': { type: 'font', path: 'res://vn_runtime/presets/fonts/NotoSans-Regular.ttf' },
  'preset/font_ja': { type: 'font', path: 'res://vn_runtime/presets/fonts/NotoSansJP-Regular.ttf' },
  'preset/font_zh_hans': { type: 'font', path: 'res://vn_runtime/presets/fonts/NotoSansSC-Regular.ttf' },
  'preset/font_zh_hant': { type: 'font', path: 'res://vn_runtime/presets/fonts/NotoSansTC-Regular.ttf' },
  'preset/font_ko': { type: 'font', path: 'res://vn_runtime/presets/fonts/NotoSansKR-Regular.ttf' },
};

const ASSET_ROOT = 'res://vn_content/assets/';
const GALLERY_TYPES: Record<string, string[]> = { images: ['image', 'background'], music: ['audio_music'] };

export interface CompileOptions {
  /** Edição do build (BS §5.4). Sem ela, vale `project.json → build.edition`, ou `standard`. */
  edition?: Edition;
}

/** Locale compilado: `{ locale, strings }` (bundle-locale.schema.json). */
export type CompiledLocale = BundleLocale;

export interface CompiledBundle {
  /** `bundle.json`, com o `content_hash`. */
  bundle: Bundle;
  /** `locales/<idioma>.json`, na ordem de `project.locales`. */
  locales: Record<string, CompiledLocale>;
  plugins: BundlePlugins;
  licenses: BundleLicenses;
}

// ------------------------------------------------------------------ ajudantes com a semântica do Python

type Obj = JsonObject;

const has = (o: Obj, k: string): boolean => Object.prototype.hasOwnProperty.call(o, k);

/** `dict.get(k, padrão)`: o valor se a chave existe (mesmo null), senão o padrão. */
function get<T extends Json | undefined>(o: Json | undefined, k: string, d: T): Json | T {
  return o !== null && typeof o === 'object' && !Array.isArray(o) && has(o, k) ? o[k]! : d;
}

function obj(v: Json | undefined): Obj {
  return v !== null && typeof v === 'object' && !Array.isArray(v) ? v : {};
}

function arr(v: Json | undefined): Json[] {
  return Array.isArray(v) ? v : [];
}

/** Verdade no sentido do Python: vazio, zero, null e false são falsos. */
function truthy(v: Json | undefined): boolean {
  if (v === undefined || v === null) return false;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (typeof v === 'string') return v.length > 0;
  if (Array.isArray(v)) return v.length > 0;
  return Object.keys(v).length > 0;
}

/** Comparação de strings por pontos de código, como o `sorted()` do Python. */
export function codePointCompare(a: string, b: string): number {
  const ia = a[Symbol.iterator](), ib = b[Symbol.iterator]();
  for (;;) {
    const x = ia.next(), y = ib.next();
    if (x.done || y.done) return x.done ? (y.done ? 0 : -1) : 1;
    const cx = x.value.codePointAt(0)!, cy = y.value.codePointAt(0)!;
    if (cx !== cy) return cx < cy ? -1 : 1;
  }
}

const sortedStrings = (xs: Iterable<string>): string[] => [...xs].sort(codePointCompare);

function clone<T>(v: T): T {
  return structuredClone(v);
}

/** Cópia rasa sem `$schema` (o `strip` da referência). */
function strip(d: Obj): Obj {
  const out: Obj = { ...d };
  delete out.$schema;
  return out;
}

/** Tema do projeto sobre o do preset: objetos fundem, listas e valores substituem. */
function deepMerge(base: Obj, over: Obj): Obj {
  const out = clone(base);
  for (const [k, v] of Object.entries(over)) {
    const cur = out[k];
    out[k] = isObj(v) && isObj(cur) ? deepMerge(cur, v) : clone(v);
  }
  return out;
}

function isObj(v: Json | undefined): v is Obj {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function str(v: Json | undefined): string {
  return typeof v === 'string' ? v : String(v);
}

// ------------------------------------------------------------------ contexto

/** Tudo o que uma entidade precisa para ser compilada sozinha: o nível de projeto já resolvido. */
export interface CompileContext {
  input: ProjectInput;
  edition: Edition;
  censored: boolean;
  /** Seções de galeria ativas, na ordem endings, images, music. */
  sections: string[];
  projectScheduler: Obj;
  locales: string[];
  /** Manifestos por id, na ordem em que foram achados. */
  manifests: Map<string, Obj>;
  pluginLicenses: Map<string, string | undefined>;
  /** Atividades com `free_play` de plugins configurados: geram a tela `minigames` (UI Spec §4). */
  freePlay: { manifest: Obj; activity: Obj }[];
  presetUi: Map<string, Obj>;
  screens: Map<string, Obj>;
  sets: Map<string, Obj>;
  assets: Obj;
  scenesSrc: Obj[];
}

export function createContext(input: ProjectInput, options: CompileOptions = {}): CompileContext {
  input = clone(input);
  const project = input.project;
  const edition = (options.edition ?? str(get(obj(get(project, 'build', {})), 'edition', 'standard'))) as Edition;
  const sectionsSrc = arr(get(obj(get(project, 'gallery', {})), 'sections', []));
  const sections = ['endings', 'images', 'music'].filter((s) => sectionsSrc.includes(s));
  const projectScheduler: Obj = { tie_breaker: 'deterministic', include_global_scenes: true, ...obj(get(project, 'scheduler', {})) };
  let locales = arr(get(project, 'locales', null)).map(str);
  if (!locales.length) locales = [str(project.default_locale)];
  if (!locales.includes(str(project.default_locale))) locales = [str(project.default_locale), ...locales];
  // BS §5.3: `build.locales` limita os idiomas do build (R013 garante o default_locale e a inclusão em `locales`)
  const buildLocales = arr(get(obj(get(project, 'build', {})), 'locales', null)).map(str);
  if (buildLocales.length) locales = locales.filter((l) => buildLocales.includes(l));

  const manifests = new Map<string, Obj>();
  const pluginLicenses = new Map<string, string | undefined>();
  for (const p of input.manifests) {
    const id = str(p.manifest.id);
    manifests.set(id, p.manifest);
    pluginLicenses.set(id, p.license);
  }
  const byId = [...manifests].sort(([a], [b]) => codePointCompare(a, b));
  const freePlay: CompileContext['freePlay'] = [];
  for (const [pid, m] of byId) {
    if (!has(input.plugins, pid)) continue;
    for (const a of arr(get(m, 'activities', []))) if (isObj(a) && has(a, 'free_play')) freePlay.push({ manifest: m, activity: a });
  }

  return {
    input,
    edition,
    censored: edition === 'censored',
    sections,
    projectScheduler,
    locales,
    manifests,
    pluginLicenses,
    freePlay,
    presetUi: new Map(input.preset.ui.map(([id, s]) => [id, strip(s)])),
    screens: new Map(input.screens.map(([id, s]) => [id, strip(s)])),
    sets: new Map(input.sets.map(([id, s]) => [id, strip(s)])),
    assets: input.assets,
    scenesSrc: input.scenes,
  };
}

// ------------------------------------------------------------------ projeto, variáveis e aliases

export function compileProjectEntity(ctx: CompileContext): Obj {
  const project = ctx.input.project;
  const st = obj(get(project, 'settings', {}));
  const disp = obj(get(st, 'display', {}));
  const base = get(st, 'resolution', [1920, 1080]) as Json;
  const [bw, bh] = arr(base) as number[];
  const resolutions = truthy(get(disp, 'resolutions', null))
    ? disp.resolutions!
    : (() => {
        const same = [[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]].filter((r) => r[0]! * bh! === r[1]! * bw!);
        return same.length ? same : [base];
      })();
  const settings: Obj = {
    resolution: base,
    text_speed: get(st, 'text_speed', 40),
    auto_delay: get(st, 'auto_delay', 1.5),
    autosave: get(st, 'autosave', 'selection_point'),
    reproducible_rng: get(st, 'reproducible_rng', false),
    display: {
      resolutions,
      display_mode: get(disp, 'display_mode', 'windowed'),
      vsync: get(disp, 'vsync', true),
      fps_limit_vn: get(disp, 'fps_limit_vn', 60),
      fps_limit_activity: get(disp, 'fps_limit_activity', 0),
    },
    number_formats: get(st, 'number_formats', {}),
  };
  if (has(st, 'activity_timeout_seconds')) settings.activity_timeout_seconds = st.activity_timeout_seconds!;

  const proj: Obj = {};
  for (const [k, v] of Object.entries(strip(project))) if (k !== 'theme' && k !== 'build') proj[k] = v;
  const chapters = get(project, 'chapters', null);
  Object.assign(proj, {
    settings,
    scheduler: ctx.projectScheduler,
    locales: ctx.locales,
    chapters: truthy(chapters) ? chapters : sortedStrings(ctx.input.chapters.map((c) => str(c.id))),
    exclusive_groups: arr(get(project, 'exclusive_groups', [])).map((g) => ({ max_plays: 1, ...obj(g) })),
    endings: get(project, 'endings', []),
    events: get(project, 'events', []),
  });
  const cf = obj(get(project, 'content_filter', {}));
  proj.content_filter = {
    default: ctx.censored ? true : get(cf, 'default', false),
    ask_on_first_launch: ctx.censored ? false : get(cf, 'ask_on_first_launch', false),
    ...(truthy(get(cf, 'placeholder', null)) ? { placeholder: cf.placeholder! } : {}),
    edition: ctx.edition,
  };
  delete proj.gallery;
  if (ctx.sections.length) proj.gallery = { sections: ctx.sections };
  return clone(proj);
}

function variable(d: Obj, extra: Obj = {}): Obj {
  const out: Obj = {};
  for (const [k, v] of Object.entries(d)) if (k !== 'characters') out[k] = v;
  if (!has(out, 'derived') && !has(out, 'persistence')) out.persistence = 'save';
  return { ...out, ...extra };
}

/** Variáveis de escopo de jogo (RT §6): globais, de personagem (instanciadas) e de plugins habilitados. */
export function compileVariables(ctx: CompileContext): Obj {
  const { input } = ctx;
  const chars = characterMap(ctx);
  const charKeys = new Map<string, Obj>();
  for (const c of chars.values()) charKeys.set(str(c.key), c);
  const out: Obj = {};
  for (const d of arr(get(input.variables, 'global', []))) out[`global.${str(obj(d).key)}`] = variable(obj(d));
  for (const dj of arr(get(input.variables, 'character', []))) {
    const d = obj(dj);
    const list = has(d, 'characters') ? arr(d.characters).map(str) : sortedStrings(charKeys.keys());
    for (const ck of list) {
      const init = obj(get(charKeys.get(ck) ?? {}, 'initial_values', {}));
      const key = str(d.key);
      out[`character.${ck}.${key}`] = variable(d, has(init, key) ? { default: init[key]! } : {});
    }
  }
  for (const [pid, m] of ctx.manifests) {
    if (!has(input.plugins, pid) || !truthy(get(obj(input.plugins[pid]), 'enabled', true))) continue;
    for (const d of arr(get(m, 'variables', []))) out[`plugin.${str(m.namespace)}.${str(obj(d).key)}`] = variable(obj(d));
  }
  return clone(out);
}

/** Aliases de `renamed_from` (Data Model §12): variáveis, depois assets do preset, depois assets. */
export function compileAliases(ctx: CompileContext, variables = compileVariables(ctx)): Obj {
  const aliases: Obj = {};
  for (const [qid, d] of Object.entries(variables)) {
    const scope = qid.slice(0, qid.lastIndexOf('.'));
    for (const old of arr(get(d, 'renamed_from', []))) {
      const o = str(old);
      aliases[o.includes('.') ? o : `${scope}.${o}`] = qid;
    }
  }
  for (const aid of Object.keys(PRESET_ASSETS))
    for (const old of arr(get(obj(get(ctx.assets, aid, {})), 'renamed_from', []))) aliases[str(old)] = aid;
  for (const [aid, a] of Object.entries(ctx.assets))
    for (const old of arr(get(a, 'renamed_from', []))) aliases[str(old)] = aid;
  return aliases;
}

// ------------------------------------------------------------------ personagens, capítulos e cenas

function characterMap(ctx: CompileContext): Map<string, Obj> {
  const m = new Map<string, Obj>();
  for (const c of ctx.input.characters) m.set(str(c.id), strip(c));
  return m;
}

export function compileCharacters(ctx: CompileContext): Obj {
  return clone(Object.fromEntries(characterMap(ctx)));
}

function withPersistence(vars: Json | undefined): Json[] {
  return arr(vars).map((d) => (has(obj(d), 'persistence') ? d : { ...obj(d), persistence: 'save' }));
}

export function compileChapter(ctx: CompileContext, src: Obj): Obj {
  const c = strip(clone(src));
  c.scheduler = { ...ctx.projectScheduler, ...obj(get(c, 'scheduler', {})) };
  c.completion = { on_exhausted: 'advance', ...obj(get(c, 'completion', {})) };
  c.exclusive_groups = arr(get(c, 'exclusive_groups', [])).map((g) => ({ max_plays: 1, ...obj(g) }));
  c.next = arr(get(c, 'next', [])).map((n) => ({ priority: 100, ...obj(n) }));
  c.variables = withPersistence(has(c, 'variables') ? c.variables : []);
  return c;
}

export function compileChapters(ctx: CompileContext): Obj {
  const out: Obj = {};
  for (const c of ctx.input.chapters) out[str(c.id)] = compileChapter(ctx, c);
  return out;
}

export function compileScene(ctx: CompileContext, src: Obj): Obj {
  const s = strip(clone(src));
  const sc = obj(get(s, 'scheduling', {}));
  s.chapter = get(s, 'chapter', null);
  s.scheduling = {
    mode: get(sc, 'mode', 'scheduled'),
    priority: get(sc, 'priority', 100),
    max_plays: get(sc, 'max_plays', 1),
    cooldown: get(sc, 'cooldown', 0),
    exclusive_groups: get(sc, 'exclusive_groups', []),
    weight: get(sc, 'weight', 1),
    ...(has(sc, 'order') ? { order: sc.order! } : {}),
    ...(has(sc, 'conditions') ? { conditions: sc.conditions! } : {}),
  };
  const start = get(s, 'start', null);
  s.start = truthy(start) ? start : obj(arr(s.nodes)[0]).id!;
  s.variables = withPersistence(has(s, 'variables') ? s.variables : []);
  if (ctx.censored) s.nodes = censorNodes(arr(s.nodes).map(obj), ctx.assets);
  return s;
}

export function compileScenes(ctx: CompileContext): Obj {
  const out: Obj = {};
  for (const s of ctx.input.scenes) out[str(s.id)] = compileScene(ctx, s);
  return out;
}

/**
 * Edição censurada (BS §5.4): passos `censor: skip` viram um desvio para o seguinte (o id fica,
 * para saves e caminhos de texto continuarem válidos); o texto censurado substitui o original. A
 * legenda de um som escondido some; a de um som trocado vira `censored_caption` (Data Model §10.4).
 */
export function censorNodes(nodes: Obj[], assets: Obj): Obj[] {
  return nodes.map((src, i) => {
    const nextNode = nodes[i + 1];
    const next = truthy(get(src, 'next', null)) ? src.next! : nextNode ? nextNode.id! : null;
    if (get(src, 'censor', null) === 'skip')
      return truthy(next) ? { id: src.id!, type: 'jump', goto: next } : { id: src.id!, type: 'end', then: 'schedule' };
    const n: Obj = {};
    for (const [k, v] of Object.entries(src)) if (k !== 'censor') n[k] = v;
    if (has(n, 'censored_text')) { n.text = n.censored_text!; delete n.censored_text; }
    if (has(n, 'censored_prompt')) { n.prompt = n.censored_prompt!; delete n.censored_prompt; }
    if (has(n, 'options'))
      n.options = arr(n.options).map((oj) => {
        const o = obj(oj), out: Obj = {};
        for (const [k, v] of Object.entries(o)) if (k !== 'censored_text') out[k] = v;
        if (has(o, 'censored_text')) out.text = o.censored_text!;
        return out;
      });
    if (has(n, 'hotspots'))
      n.hotspots = arr(n.hotspots).map((hj) => {
        const h = obj(hj), out: Obj = {};
        for (const [k, v] of Object.entries(h)) if (k !== 'censored_label') out[k] = v;
        if (has(h, 'censored_label')) out.label = h.censored_label!;
        return out;
      });
    const exit = obj(get(n, 'exit', null));
    if (has(exit, 'censored_label')) {
      const out: Obj = {};
      for (const [k, v] of Object.entries(exit)) if (k !== 'censored_label') out[k] = v;
      out.label = exit.censored_label!;
      n.exit = out;
    }
    if (n.type === 'audio') {
      const c = obj(get(obj(get(assets, str(get(n, 'asset', null)), null)), 'censored', null));
      const hadCap = has(n, 'censored_caption');
      const cap = n.censored_caption;
      delete n.censored_caption;
      if (truthy(get(c, 'hide', null))) delete n.caption;
      else if (truthy(get(c, 'replace_with', null)) && hadCap && cap !== null) n.caption = cap!;
    }
    return n;
  });
}

// ------------------------------------------------------------------ preset: tema, telas e textos

export function compileTheme(ctx: CompileContext): Obj {
  const theme = ctx.input.theme ? strip(ctx.input.theme) : {};
  const out = deepMerge(strip(ctx.input.preset.theme), theme);
  out.preset = ctx.input.preset.name;
  return out;
}

function titleSub(o: Json, title: Json): Json {
  if (Array.isArray(o)) return o.map((x) => titleSub(x, title));
  if (isObj(o)) {
    const out: Obj = {};
    for (const [k, v] of Object.entries(o)) out[k] = v === '$project.title' ? title : titleSub(v, title);
    return out;
  }
  return o;
}

/** Telas do preset (com `$project.title` trocado e `minigames` gerada) sob as do projeto. */
export function compileUi(ctx: CompileContext): Obj {
  const title = ctx.input.project.title ?? null;
  const ui: Obj = {};
  for (const [id, s] of ctx.presetUi) ui[id] = titleSub(clone(s), title);
  if (ctx.freePlay.length && !ctx.screens.has('minigames')) {
    const games = arr(obj(arr(obj(ui.minigames).elements)[1]).children);
    for (const { manifest: m, activity: a } of ctx.freePlay)
      games.push({
        id: `btn_${str(m.namespace)}_${str(a.id)}`,
        type: 'button',
        text: a.name ?? null,
        actions: [{ do: 'play_activity', activity: `${str(m.namespace)}.${str(a.id)}` }],
      });
    const first = ctx.freePlay[0]!.manifest;
    for (const bj of arr(get(first, 'records', []))) {
      const b = obj(bj);
      games.push({ id: `rec_${str(first.namespace)}_${str(b.id)}`, type: 'records_list', board: `${str(first.namespace)}.${str(b.id)}`, max_items: 5 });
    }
  } else if (!ctx.freePlay.length && !ctx.screens.has('minigames')) {
    delete ui.minigames;
  }
  for (const [id, s] of ctx.screens) ui[id] = clone(s);
  if (!ctx.sections.length) delete ui.gallery;
  return ui;
}

export function compileSets(ctx: CompileContext): Obj {
  return clone(Object.fromEntries(ctx.sets));
}

// ------------------------------------------------------------------ assets

/**
 * Assets do bundle: `credit` fica de fora (vai para `licenses.json`), o caminho vira `res://`, as
 * fontes do preset entram, a edição censurada troca ou esconde e a galeria perde as marcas cuja
 * seção não está ativa (Data Model §10.5, U013).
 */
export function compileAssets(ctx: CompileContext): Obj {
  const out: Obj = {};
  for (const [aid, a] of Object.entries(ctx.assets)) {
    const b: Obj = {};
    for (const [k, v] of Object.entries(a as Obj)) if (k !== 'credit') b[k] = v;
    b.path = ASSET_ROOT + str((a as Obj).path);
    out[aid] = b;
  }
  for (const [aid, p] of Object.entries(PRESET_ASSETS)) if (!has(out, aid)) out[aid] = { type: p.type, path: p.path };
  if (ctx.censored) {
    for (const [aid, aj] of Object.entries(ctx.assets)) {
      const a = obj(aj);
      const c = obj(get(a, 'censored', null));
      if (truthy(get(c, 'replace_with', null))) {
        const rep: Obj = {};
        for (const [k, v] of Object.entries(obj(out[str(c.replace_with)])))
          if (k !== 'gallery' && k !== 'gallery_order' && k !== 'renamed_from') rep[k] = v;
        for (const k of ['type', 'gallery', 'gallery_order', 'renamed_from']) if (has(a, k)) rep[k] = a[k]!;
        out[aid] = rep;
      } else if (truthy(get(c, 'hide', null))) {
        const b = obj(out[aid]);
        delete b.gallery;
        delete b.gallery_order;
      }
    }
  }
  for (const [aid, aj] of Object.entries(ctx.assets)) {
    const a = obj(aj);
    if (!truthy(get(a, 'gallery', null))) continue;
    const shown = ctx.sections.some((s) => (GALLERY_TYPES[s] ?? []).includes(str(a.type)));
    if (!shown) {
      const b = obj(out[aid]);
      delete b.gallery;
      delete b.gallery_order;
    }
  }
  return clone(out);
}

// ------------------------------------------------------------------ bundle.json

export function bundleContentHash(bundle: Obj): string {
  const rest: Obj = {};
  for (const [k, v] of Object.entries(bundle)) if (k !== 'content_hash') rest[k] = v;
  return canonicalHash(rest);
}

export function compileBundleJson(ctx: CompileContext): Bundle {
  const variables = compileVariables(ctx);
  const bundle: Obj = {
    bundle_version: 1,
    format_version: ctx.input.project.format_version ?? null,
    project: compileProjectEntity(ctx),
    variables,
    aliases: compileAliases(ctx, variables),
    characters: compileCharacters(ctx),
    chapters: compileChapters(ctx),
    scenes: compileScenes(ctx),
    theme: compileTheme(ctx),
    ui: compileUi(ctx),
    sets: compileSets(ctx),
    assets: compileAssets(ctx),
  };
  bundle.content_hash = bundleContentHash(bundle);
  return bundle as unknown as Bundle;
}

// ------------------------------------------------------------------ traduções

/** Caminhos de texto cuja tradução original some na edição censurada (o texto censurado ocupa o lugar). */
function censoredPaths(ctx: CompileContext): Set<string> {
  const out = new Set<string>();
  for (const s of ctx.scenesSrc) {
    const sid = str(s.id);
    for (const nj of arr(s.nodes)) {
      const n = obj(nj);
      const path = `${sid}/${str(n.id)}`;
      if (truthy(get(n, 'censored_text', null)) || truthy(get(n, 'censored_prompt', null))) out.add(path);
      if (truthy(get(n, 'censored_caption', null))) out.add(path);
      for (const oj of [...arr(get(n, 'options', [])), ...arr(get(n, 'hotspots', []))]) {
        const o = obj(oj);
        if (truthy(get(o, 'censored_text', null)) || truthy(get(o, 'censored_label', null))) out.add(`${path}/${str(o.id)}`);
      }
      if (truthy(get(obj(get(n, 'exit', null)), 'censored_label', null))) out.add(`${path}/exit`);
    }
  }
  return out;
}

/** Textos de um idioma: preset (idiomas do produto) < plugins < projeto. */
export function compileLocale(ctx: CompileContext, lang: string): CompiledLocale {
  const strings = new Map<string, Json>();
  const pl = ctx.input.preset.locales;
  const presetDoc = pl[lang] ?? pl[lang.split('-')[0]!] ?? pl.en;
  if (presetDoc) for (const [k, v] of Object.entries(obj(presetDoc.strings))) strings.set(k, v);
  const byId = [...ctx.manifests].sort(([a], [b]) => codePointCompare(a, b));
  for (const [pid, m] of byId) {
    if (!has(ctx.input.plugins, pid)) continue;
    const pls = obj(get(m, 'plugin_locales', {}));
    const own = get(pls, lang, null);
    const src = obj(truthy(own) ? own : get(pls, str(get(m, 'default_locale', 'en')), {}));
    for (const [k, v] of Object.entries(src)) strings.set(`plugin/${str(m.namespace)}/${k}`, v);
    for (const { manifest: m2, activity: a } of ctx.freePlay) {
      const key = `activity/${str(a.id)}/name`;
      if (m2 === m && has(src, key)) strings.set(`ui/minigames/btn_${str(m.namespace)}_${str(a.id)}`, src[key]!);
    }
  }
  for (const doc of ctx.input.localeFiles[lang] ?? [])
    for (const [k, v] of Object.entries(obj(doc.strings))) strings.set(k, isObj(v) ? (v.text ?? null) : v);
  if (ctx.censored) {
    for (const k of censoredPaths(ctx)) strings.delete(k);
    for (const k of [...strings.keys()].filter((k) => k.endsWith('/censored'))) {
      const v = strings.get(k)!;
      strings.delete(k);
      strings.set(k.slice(0, -'/censored'.length), v);
    }
  }
  return clone({ locale: lang, strings: Object.fromEntries(strings) }) as unknown as CompiledLocale;
}

// ------------------------------------------------------------------ plugins.json e licenses.json

/** `plugins.json` do bundle: plugins habilitados, permissão efetiva = pedido ∩ concessão, dados do lock. */
export function compilePlugins(ctx: CompileContext): BundlePlugins {
  const out: Obj = {};
  for (const pid of sortedStrings(Object.keys(ctx.input.plugins))) {
    const cfg = obj(ctx.input.plugins[pid]);
    const m = ctx.manifests.get(pid);
    if (!truthy(get(cfg, 'enabled', true)) || !m) continue;
    const lk = obj(get(ctx.input.lock, pid, {}));
    const caps = obj(get(m, 'capabilities', {}));
    const asked = new Set([
      ...arr(get(caps, 'runtime', [])).map((c) => `runtime:${str(c)}`),
      ...arr(get(caps, 'editor', [])).map((c) => `editor:${str(c)}`),
    ]);
    const grants = obj(get(cfg, 'grants', {}));
    const gv = obj(get(grants, 'variables', {}));
    const conf: Obj = {};
    for (const [k, v] of Object.entries(obj(get(obj(get(m, 'config_schema', {})), 'properties', {}))))
      if (has(obj(v), 'default')) conf[k] = obj(v).default!;
    Object.assign(conf, obj(get(cfg, 'config', {})));
    out[pid] = {
      id: pid,
      namespace: m.namespace ?? null,
      version: m.version ?? null,
      path: `res://vn_plugins/${str(m.namespace)}/`,
      trust: get(lk, 'trust', 'local'),
      embedded: truthy(get(lk, 'embedded', false)),
      capabilities: sortedStrings(new Set(arr(get(grants, 'capabilities', [])).map(str).filter((c) => asked.has(c)))),
      variables: { read: sortedStrings(arr(get(gv, 'read', [])).map(str)), write: sortedStrings(arr(get(gv, 'write', [])).map(str)) },
      scenes: sortedStrings(arr(get(grants, 'scenes', [])).map(str)),
      config: conf,
    };
  }
  return clone({ plugins: out }) as unknown as BundlePlugins;
}

/**
 * `licenses.json` (BS §4.5): plugins habilitados e o `credit` dos assets que entram no jogo, com
 * créditos iguais agrupados. O aviso do motor e do runtime não entra: o runtime o acrescenta sempre.
 * Como a referência, não faz a poda de assets sem uso do B008; entram todos os do bundle, menos os
 * escondidos na edição censurada.
 */
export function compileLicenses(ctx: CompileContext, plugins: BundlePlugins, bundleAssets: Obj): BundleLicenses {
  type Entry = Obj & { kind: string; title: Json };
  const entries: Entry[] = [];
  for (const pid of sortedStrings(Object.keys(plugins.plugins))) {
    const m = ctx.manifests.get(pid)!;
    const name = m.name;
    const e: Entry = {
      kind: 'plugin',
      title: typeof name === 'string' ? name : get(obj(name), str(get(m, 'default_locale', 'en')), pid),
    };
    const author = get(obj(get(m, 'author', {})), 'name', null);
    if (truthy(author)) e.author = author;
    if (truthy(get(m, 'license', null))) e.license = m.license!;
    if (truthy(get(m, 'homepage', null))) e.url = m.homepage!;
    const text = ctx.pluginLicenses.get(pid);
    if (text !== undefined) e.text = text;
    entries.push(e);
  }
  const groups = new Map<string, { credit: Json[]; items: [string, string][] }>();
  for (const aid of sortedStrings(Object.keys(ctx.assets))) {
    const a = obj(ctx.assets[aid]);
    const c = get(a, 'credit', null);
    if (!truthy(c) || !has(bundleAssets, aid)) continue;
    if (ctx.censored && truthy(get(obj(get(a, 'censored', {})), 'hide', null))) continue;
    const credit = ['author', 'license', 'url', 'notice', 'license_file'].map((k) => get(c, k, null));
    const key = JSON.stringify(credit);
    if (!groups.has(key)) groups.set(key, { credit, items: [] });
    groups.get(key)!.items.push([aid, str(a.type)]);
  }
  for (const { credit, items } of groups.values()) {
    const [author, lic, url, notice, lfile] = credit as [Json, Json, Json, Json, Json];
    const e: Entry = { kind: items.every(([, t]) => t === 'font') ? 'font' : 'asset', title: author, author };
    if (truthy(lic)) e.license = lic;
    if (truthy(url)) e.url = url;
    if (truthy(notice)) e.notice = notice;
    if (truthy(lfile) && ctx.input.licenseFiles[str(lfile)] !== undefined) e.text = ctx.input.licenseFiles[str(lfile)]!;
    e.assets = sortedStrings(items.map(([aid]) => aid));
    entries.push(e);
  }
  const order: Record<string, number> = { plugin: 0, font: 1, asset: 2 };
  const sortKey = (e: Entry): [number, string, string, string] => [
    order[e.kind]!,
    str(e.title ?? ''),
    str(get(e, 'author', '') ?? ''),
    arr(e.assets).length ? str(arr(e.assets)[0]) : '',
  ];
  entries.sort((x, y) => {
    const a = sortKey(x), b = sortKey(y);
    if (a[0] !== b[0]) return a[0] - b[0];
    for (let i = 1; i < 4; i++) {
      const c = codePointCompare(a[i] as string, b[i] as string);
      if (c) return c;
    }
    return 0;
  });
  return clone({ entries }) as unknown as BundleLicenses;
}

// ------------------------------------------------------------------ tudo junto

export function compileProject(input: ProjectInput, options: CompileOptions = {}): CompiledBundle {
  const ctx = createContext(input, options);
  const bundle = compileBundleJson(ctx);
  const locales: Record<string, CompiledLocale> = {};
  for (const lang of ctx.locales) locales[lang] = compileLocale(ctx, lang);
  const plugins = compilePlugins(ctx);
  const licenses = compileLicenses(ctx, plugins, bundle.assets as unknown as Obj);
  return { bundle, locales, plugins, licenses };
}
