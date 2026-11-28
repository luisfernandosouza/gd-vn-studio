/**
 * Modelo das configurações do projeto (M7-10): tudo que `project.json` aceita fora das listas de
 * entidades (Data Model §2). Funções puras: a tela edita uma cópia do `Project` e este módulo a
 * limpa, valida e grava no formato do Studio (UTF-8, 2 espaços, `\n` no fim).
 */
import type { Project, Theme } from '@vnstudio/plugin-schema';
import type { DocumentStore } from '../document/store';
import { joinPath, type ProjectFs } from '../project-manager/fs';
import { ID_PATTERN } from '../project-manager/ids';
import { LOCALE_PATTERN, ROOT_FILES } from '../project-manager/layout';
import type { OpenedProject } from '../project-manager/open';

export type Ending = NonNullable<Project['endings']>[number];
export type EventDecl = NonNullable<Project['events']>[number];

export interface SettingsIssue {
  /** Rótulo do campo, como a tela o mostra. */
  field: string;
  message: string;
}

export interface ChapterInfo {
  id: string;
  title: string;
}

export interface AssetInfo {
  id: string;
  type: string;
}

/** O que a tela precisa ler do disco além do `project.json`. */
export interface SettingsContext {
  chapters: ChapterInfo[];
  assets: AssetInfo[];
  theme: Theme | null;
  /** Cenas (título) que usam cada final em um nó `end` (regra R012). */
  endingUsage: Record<string, string[]>;
}

const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
const ASSET_REF = /^[a-z][a-z0-9_./-]{0,127}$/;
const EVENT_NAME = /^story\.[a-z][a-z0-9_.]*$/;
const EXECUTABLE_NAME = /^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$/;

async function readJson<T>(fs: ProjectFs, path: string): Promise<T | null> {
  try {
    if (!(await fs.exists(path))) return null;
    return JSON.parse(await fs.readText(path)) as T;
  } catch {
    return null;
  }
}

/** Lê capítulos, assets, tema e o uso dos finais. Arquivo ilegível vira lista vazia: a tela segue editável. */
export async function loadSettingsContext(fs: ProjectFs, opened: OpenedProject): Promise<SettingsContext> {
  const { root, project, entities } = opened;
  const chapters: ChapterInfo[] = [];
  for (const file of entities.chapters) {
    const c = await readJson<{ id?: string; title?: string }>(fs, joinPath(root, file));
    if (c?.id) chapters.push({ id: c.id, title: c.title?.trim() || c.id });
  }
  const assetsFile = await readJson<{ assets?: Record<string, { type?: string }> }>(fs, joinPath(root, ROOT_FILES.assets));
  const assets = Object.entries(assetsFile?.assets ?? {}).map(([id, a]) => ({ id, type: a.type ?? 'other' }));
  const theme = await readJson<Theme>(fs, joinPath(root, project.theme ?? ROOT_FILES.theme));

  const endingUsage: Record<string, string[]> = {};
  for (const file of entities.scenes) {
    const scene = await readJson<{ title?: string; nodes?: { type?: string; ending?: string }[] }>(fs, joinPath(root, file));
    for (const node of scene?.nodes ?? []) {
      if (node.type === 'end' && node.ending) (endingUsage[node.ending] ??= []).push(scene?.title ?? file);
    }
  }
  return { chapters, assets, theme, endingUsage };
}

const isEmptyObject = (v: unknown) => typeof v === 'object' && v !== null && !Array.isArray(v) && Object.keys(v).length === 0;

/** Remove `undefined`, textos vazios opcionais, listas vazias opcionais e objetos que ficaram vazios. */
export function prune<T>(value: T): T {
  const walk = (v: unknown): unknown => {
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === 'object') {
      const out: Record<string, unknown> = {};
      for (const [k, raw] of Object.entries(v)) {
        const next = walk(raw);
        // `group: ''` é válido e obrigatório em number_formats ("vazio = sem separador")
        if (next === undefined || (next === '' && k !== 'group') || isEmptyObject(next)) continue;
        out[k] = next;
      }
      return out;
    }
    return v;
  };
  const pruned = walk(value) as Record<string, unknown>;
  // Listas opcionais vazias somem do arquivo; `chapters` e `events[].payload` mantêm o que o autor deixou.
  for (const key of ['authors', 'locales', 'endings', 'events', 'exclusive_groups']) {
    if (Array.isArray(pruned[key]) && (pruned[key] as unknown[]).length === 0) delete pruned[key];
  }
  const settings = pruned.settings as Record<string, unknown> | undefined;
  if (settings) {
    const display = settings.display as Record<string, unknown> | undefined;
    if (display && Array.isArray(display.resolutions) && display.resolutions.length === 0) {
      delete display.resolutions;
      if (Object.keys(display).length === 0) delete settings.display;
    }
    if (Object.keys(settings).length === 0) delete pruned.settings;
  }
  const gallery = pruned.gallery as { sections?: unknown[] } | undefined;
  if (gallery && (gallery.sections?.length ?? 0) === 0) delete pruned.gallery;
  const build = pruned.build as Record<string, unknown> | undefined;
  if (build) {
    for (const key of ['platforms', 'locales']) {
      if (Array.isArray(build[key]) && (build[key] as unknown[]).length === 0) delete build[key];
    }
    if (Object.keys(build).length === 0) delete pruned.build;
  }
  return pruned as T;
}

/** Confere o que o schema e as regras de projeto exigem. Com problemas, a tela não grava. */
export function validateSettings(project: Project, ctx: Pick<SettingsContext, 'chapters' | 'endingUsage'> & Partial<Pick<SettingsContext, 'assets'>>): SettingsIssue[] {
  const issues: SettingsIssue[] = [];
  const add = (field: string, message: string) => issues.push({ field, message });
  const p = prune(project);

  if (!p.title?.trim()) add('Título', 'o jogo precisa de um título.');
  if (p.version !== undefined && !SEMVER.test(p.version)) add('Versão do jogo', 'use o formato 1.2.3 (maior.menor.correção).');
  if (!LOCALE_PATTERN.test(p.default_locale ?? '')) add('Idioma-fonte', 'escolha um idioma válido (por exemplo pt-BR ou en).');
  for (const l of p.locales ?? []) if (!LOCALE_PATTERN.test(l)) add('Idiomas', `"${l}" não é um idioma válido.`);
  if (p.locales?.length && !p.locales.includes(p.default_locale)) add('Idiomas', 'a lista de idiomas precisa incluir o idioma-fonte.');
  if (p.runtime?.min_version !== undefined && !SEMVER.test(p.runtime.min_version)) add('Versão mínima do runtime', 'use o formato 1.0.0.');

  const size = (field: string, v: readonly number[] | undefined) => {
    if (v && !(v.length === 2 && v.every((n) => Number.isInteger(n) && n >= 1))) add(field, 'largura e altura são números inteiros a partir de 1.');
  };
  size('Resolução base', p.settings?.resolution);
  const resolutions = p.settings?.display?.resolutions ?? [];
  resolutions.forEach((r, i) => size(`Tamanho de janela ${i + 1}`, r));
  if (new Set(resolutions.map((r) => r.join('x'))).size !== resolutions.length) add('Tamanhos de janela', 'há tamanhos repetidos.');

  const s = p.settings;
  if (s?.text_speed !== undefined && !(s.text_speed >= 0)) add('Velocidade do texto', 'use 0 (instantâneo) ou mais.');
  if (s?.auto_delay !== undefined && !(s.auto_delay >= 0)) add('Pausa do modo automático', 'use 0 ou mais.');
  if (s?.activity_timeout_seconds !== undefined && !(Number.isInteger(s.activity_timeout_seconds) && s.activity_timeout_seconds >= 1)) {
    add('Tempo máximo de uma atividade', 'use um número inteiro de segundos a partir de 1, ou deixe em branco para não limitar.');
  }
  for (const [label, v] of [['Limite de FPS da novel', s?.display?.fps_limit_vn], ['Limite de FPS dos minijogos', s?.display?.fps_limit_activity]] as const) {
    if (v !== undefined && !(Number.isInteger(v) && v >= 0 && v <= 360)) add(label, 'use um inteiro de 0 (sem limite) a 360.');
  }
  for (const [locale, f] of Object.entries(s?.number_formats ?? {})) {
    if (!LOCALE_PATTERN.test(locale)) add('Formato de números', `"${locale}" não é um idioma válido.`);
    if (!f.decimal || f.decimal.length > 2) add(`Formato de números (${locale})`, 'o separador decimal tem 1 ou 2 caracteres.');
    if ((f.group ?? '').length > 2) add(`Formato de números (${locale})`, 'o separador de milhar tem até 2 caracteres.');
    if (f.min_grouping !== undefined && !(Number.isInteger(f.min_grouping) && f.min_grouping >= 4 && f.min_grouping <= 9)) {
      add(`Formato de números (${locale})`, 'o mínimo de dígitos para agrupar vai de 4 a 9.');
    }
  }

  if (!ctx.chapters.length || ctx.chapters.some((c) => c.id === p.start_chapter)) {
    // sem capítulos lidos (arquivo ilegível) não dá para conferir
  } else add('Capítulo inicial', 'escolha um capítulo que exista no projeto.');

  const groupIds = new Set<string>();
  for (const g of p.exclusive_groups ?? []) {
    if (!ID_PATTERN.test(g.id)) add('Grupos de exclusividade', `o identificador "${g.id}" usa minúsculas, dígitos e _ e começa com letra.`);
    if (groupIds.has(g.id)) add('Grupos de exclusividade', `o grupo "${g.id}" aparece duas vezes.`);
    groupIds.add(g.id);
    if (g.max_plays !== undefined && !(Number.isInteger(g.max_plays) && g.max_plays >= 1)) add(`Grupo ${g.id}`, 'o máximo de execuções é um inteiro a partir de 1.');
  }

  const endingIds = new Set<string>();
  for (const e of p.endings ?? []) {
    if (!ID_PATTERN.test(e.id)) add('Finais', `o identificador "${e.id}" usa minúsculas, dígitos e _ e começa com letra.`);
    if (endingIds.has(e.id)) add('Finais', `o final "${e.id}" aparece duas vezes.`);
    endingIds.add(e.id);
    if (!e.title?.trim()) add(`Final ${e.id}`, 'o final precisa de um título.');
    if (e.image && !ASSET_REF.test(e.image)) add(`Final ${e.id}`, 'a imagem precisa ser um asset registrado.');
  }
  for (const [id, scenes] of Object.entries(ctx.endingUsage)) {
    if (!endingIds.has(id)) add('Finais', `o final "${id}" é usado em ${scenes.length} cena(s) (${scenes.slice(0, 3).join(', ')}) e não pode sumir da lista.`);
  }

  const eventNames = new Set<string>();
  for (const ev of p.events ?? []) {
    if (!EVENT_NAME.test(ev.name)) add('Eventos', `"${ev.name}" precisa começar com story. (por exemplo story.met_master).`);
    if (eventNames.has(ev.name)) add('Eventos', `o evento "${ev.name}" aparece duas vezes.`);
    eventNames.add(ev.name);
  }

  const known = ctx.assets ? new Set(ctx.assets.map((a) => a.id)) : null;
  const assetRefs: [string, string | undefined][] = [
    ...(p.endings ?? []).map((e): [string, string | undefined] => [`Final ${e.id}`, e.image]),
    ['Imagem neutra do modo stream', p.content_filter?.placeholder],
    ['Ícone', p.build?.icon],
    ['Imagem de abertura', p.build?.splash],
  ];
  if (known) for (const [label, ref] of assetRefs) if (ref && ASSET_REF.test(ref) && !known.has(ref)) add(label, `o asset "${ref}" não está registrado em assets.json.`);
  for (const [label, ref] of [['Imagem neutra do modo stream', p.content_filter?.placeholder], ['Ícone', p.build?.icon], ['Imagem de abertura', p.build?.splash]] as const) {
    if (ref && !ASSET_REF.test(ref)) add(label, 'precisa ser um asset registrado (por exemplo ui/icon).');
  }
  if (p.build?.executable_name && !EXECUTABLE_NAME.test(p.build.executable_name)) {
    add('Nome do executável', 'até 64 caracteres: letras, números, espaço, ponto, _ e -, começando por letra ou número.');
  }
  if (p.build?.locales) {
    if (!p.build.locales.includes(p.default_locale)) add('Idiomas do build', 'precisa incluir o idioma-fonte.');
    for (const l of p.build.locales) if (p.locales?.length && !p.locales.includes(l)) add('Idiomas do build', `"${l}" não está nos idiomas do jogo.`);
  }
  return issues;
}

/**
 * Aplica as configurações ao documento do projeto (M6-02): um único passo de undo ("Configurações do
 * projeto") e gravação pelo autosave do documento, que aqui é esperada. Devolve o projeto gravado.
 */
export async function applyProjectSettings(store: DocumentStore, project: Project): Promise<Project> {
  const clean = prune(project);
  store.applyEdit([{ op: 'replace', path: '/project', value: clean }], { label: 'Configurações do projeto', autoTest: true });
  await store.flush();
  const { saveStatus, saveError } = store.getState();
  if (saveStatus === 'error') throw new Error(saveError ?? 'falha ao gravar project.json');
  return clean;
}

export type PayloadType = 'string' | 'integer' | 'number' | 'boolean';
export const PAYLOAD_TYPES: readonly PayloadType[] = ['string', 'integer', 'number', 'boolean'];

export interface PayloadField {
  name: string;
  type: PayloadType;
  required: boolean;
}

/**
 * O payload de um evento é um JSON Schema (Data Model §2). A tela edita o caso comum: um objeto com
 * campos simples (texto, inteiro, número, sim/não). Qualquer outra forma devolve `null` e é preservada
 * como está, sem edição na tela.
 */
export function payloadToFields(payload: EventDecl['payload']): PayloadField[] | null {
  if (payload === undefined) return [];
  const keys = Object.keys(payload);
  if (keys.some((k) => !['type', 'properties', 'required'].includes(k)) || (payload as { type?: unknown }).type !== 'object') return null;
  const props = (payload as { properties?: Record<string, { type?: string } & Record<string, unknown>> }).properties ?? {};
  const required = new Set((payload as { required?: string[] }).required ?? []);
  const fields: PayloadField[] = [];
  for (const [name, def] of Object.entries(props)) {
    if (Object.keys(def).length !== 1 || !PAYLOAD_TYPES.includes(def.type as PayloadType)) return null;
    fields.push({ name, type: def.type as PayloadType, required: required.has(name) });
  }
  return fields;
}

export function fieldsToPayload(fields: readonly PayloadField[]): EventDecl['payload'] {
  const named = fields.filter((f) => f.name.trim());
  if (!named.length) return undefined;
  const required = named.filter((f) => f.required).map((f) => f.name);
  return {
    type: 'object',
    properties: Object.fromEntries(named.map((f) => [f.name, { type: f.type }])),
    ...(required.length ? { required } : {}),
  };
}
