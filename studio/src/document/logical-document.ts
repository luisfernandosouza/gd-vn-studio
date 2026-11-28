import { ProjectManagerError } from '../project-manager/errors';
import { joinPath, type ProjectFs } from '../project-manager/fs';
import { slugify, uniqueName } from '../project-manager/ids';
import { formatJson } from '../project-manager/json';
import { EDITOR_DIR, ROOT_FILES, schemaUrl } from '../project-manager/layout';
import type { OpenedProject } from '../project-manager/open';

/**
 * Documento lógico do projeto (Plugin SDK §10.4.1): a união dos arquivos num único objeto JSON, com as
 * entidades indexadas pelo id. É o que o undo/redo, os plugins (`getDocument`/`applyEdit`) e os editores
 * enxergam; o disco continua com um arquivo por entidade (Data Model §1).
 *
 * `$schema` não entra no documento (campo derivado): é regravado no topo de cada arquivo ao salvar.
 */
type Json = Record<string, unknown>;

export interface LogicalDocument {
  project: Json;
  /** `variables.json` inteiro: `{ global: […], character: […] }`. */
  variables: Json;
  /** Conteúdo de `assets.json → assets`, indexado pelo id do asset. */
  assets: Json;
  theme: Json;
  /** `plugins.json → plugins`, indexado pelo id do plugin. */
  plugins: Json;
  ui: Record<string, Json>;
  sets: Record<string, Json>;
  characters: Record<string, Json>;
  chapters: Record<string, Json>;
  scenes: Record<string, Json>;
  /** `locales[lang][caminho de texto]` (Data Model §9): a entrada é o texto ou `{ text, source_hash?, status? }`. */
  locales: Record<string, Record<string, unknown>>;
}

const SECTION_FILES = {
  project: [ROOT_FILES.project, 'project'],
  variables: [ROOT_FILES.variables, 'variables'],
  assets: [ROOT_FILES.assets, 'assets'],
  plugins: [ROOT_FILES.plugins, 'plugins'],
  theme: [ROOT_FILES.theme, 'theme'],
} as const;
type SectionKey = keyof typeof SECTION_FILES;
const SECTION_KEYS = Object.keys(SECTION_FILES) as SectionKey[];
/** Seções que o arquivo guarda dentro de uma chave (`assets.json → assets`). */
const WRAPPED: Partial<Record<SectionKey, string>> = { assets: 'assets', plugins: 'plugins' };

type EntityKind = 'characters' | 'chapters' | 'scenes' | 'ui' | 'sets';
const ENTITY_KINDS: readonly EntityKind[] = ['characters', 'chapters', 'scenes', 'ui', 'sets'];
const ENTITY_SCHEMA: Record<EntityKind, string> = { characters: 'character', chapters: 'chapter', scenes: 'scene', ui: 'ui-screen', sets: 'set' };

/** Acompanha o que já está no disco: de qual arquivo veio cada entidade e o que foi gravado por último. */
export interface DiskState {
  /** `scenes/<id>` → `scenes/ch01/scene_beach.json`; para locales, `locales/<lang>` → arquivos do idioma. */
  entityFiles: Map<string, string>;
  /** Referência do objeto gravado por último, por seção/entidade/idioma; igual na memória = nada a gravar. */
  savedRefs: Map<string, unknown>;
  /** Texto gravado por último, por caminho relativo. */
  savedTexts: Map<string, string>;
  /** Arquivos de tradução por idioma e por entrada (`<lang>/<caminho de texto>` → arquivo). */
  localeFiles: Map<string, string>;
  /** Arquivos de tradução existentes por idioma. */
  localeFileList: Map<string, Set<string>>;
}

export interface LoadedDocument {
  doc: LogicalDocument;
  disk: DiskState;
}

const JOURNAL = `${EDITOR_DIR}/journal.json`;

export interface SavePlan {
  writes: Map<string, string>;
  deletes: string[];
}

function stripSchema(data: Json): Json {
  const { $schema: _ignored, ...rest } = data;
  void _ignored;
  return rest;
}

async function readJson(fs: ProjectFs, root: string, rel: string): Promise<Json> {
  let text: string;
  try {
    text = await fs.readText(joinPath(root, rel));
  } catch {
    throw new ProjectManagerError('unreadable', `Não consegui ler ${rel}.`);
  }
  try {
    const data: unknown = JSON.parse(text);
    if (typeof data !== 'object' || data === null || Array.isArray(data)) throw new Error('não é um objeto');
    return data as Json;
  } catch {
    throw new ProjectManagerError('unreadable', `O arquivo ${rel} não é um JSON válido.`);
  }
}

/**
 * Termina uma gravação que o fechamento forçado interrompeu. Antes de tocar nos arquivos, o Studio grava
 * o lote inteiro em `.vnstudio/journal.json` (atômico); se o app morrer no meio, a abertura seguinte
 * refaz o lote até o fim, e nenhum arquivo fica pela metade.
 */
export async function recoverPendingSave(fs: ProjectFs, root: string): Promise<boolean> {
  const path = joinPath(root, JOURNAL);
  if (!(await fs.exists(path))) return false;
  type Journal = { writes?: Record<string, string>; deletes?: string[] };
  let plan: Journal | null;
  try {
    plan = JSON.parse(await fs.readText(path)) as Journal;
  } catch {
    plan = null;
  }
  if (plan && typeof plan === 'object') {
    for (const [rel, text] of Object.entries(plan.writes ?? {})) await fs.writeText(joinPath(root, rel), text);
    for (const rel of plan.deletes ?? []) await fs.removeFile(joinPath(root, rel));
  }
  await fs.removeFile(path);
  return true;
}

export async function loadLogicalDocument(fs: ProjectFs, opened: OpenedProject): Promise<LoadedDocument> {
  const { root } = opened;
  await recoverPendingSave(fs, root);
  const disk: DiskState = { entityFiles: new Map(), savedRefs: new Map(), savedTexts: new Map(), localeFiles: new Map(), localeFileList: new Map() };
  const doc: LogicalDocument = { project: {}, variables: {}, assets: {}, theme: {}, plugins: {}, ui: {}, sets: {}, characters: {}, chapters: {}, scenes: {}, locales: {} };

  for (const key of SECTION_KEYS) {
    const [rel] = SECTION_FILES[key];
    if (!(await fs.exists(joinPath(root, rel)))) continue;
    const raw = await readJson(fs, root, rel);
    disk.savedTexts.set(rel, await fs.readText(joinPath(root, rel)));
    const wrapped = WRAPPED[key];
    const value = wrapped ? ((raw[wrapped] as Json | undefined) ?? {}) : stripSchema(raw);
    doc[key] = value;
    disk.savedRefs.set(key, value);
  }

  for (const kind of ENTITY_KINDS) {
    for (const rel of opened.entities[kind]) {
      const entity = stripSchema(await readJson(fs, root, rel));
      const id = entity.id;
      if (typeof id !== 'string') throw new ProjectManagerError('unreadable', `${rel} não tem "id".`);
      if (Object.hasOwn(doc[kind], id)) throw new ProjectManagerError('unreadable', `${rel}: o id "${id}" já aparece em outro arquivo.`);
      doc[kind][id] = entity;
      disk.entityFiles.set(`${kind}/${id}`, rel);
      disk.savedRefs.set(`${kind}/${id}`, entity);
      disk.savedTexts.set(rel, await fs.readText(joinPath(root, rel)));
    }
  }

  for (const rel of opened.entities.locales) {
    const file = await readJson(fs, root, rel);
    const lang = typeof file.locale === 'string' ? file.locale : (rel.split('/')[1] ?? '');
    const strings = (file.strings as Json | undefined) ?? {};
    const target = (doc.locales[lang] ??= {});
    for (const [textPath, entry] of Object.entries(strings)) {
      target[textPath] = entry;
      disk.localeFiles.set(`${lang}/${textPath}`, rel);
    }
    (disk.localeFileList.get(lang) ?? disk.localeFileList.set(lang, new Set()).get(lang)!).add(rel);
    disk.savedTexts.set(rel, await fs.readText(joinPath(root, rel)));
  }
  for (const [lang, strings] of Object.entries(doc.locales)) disk.savedRefs.set(`locales/${lang}`, strings);
  return { doc, disk };
}

const withSchema = (schema: string, body: Json): Json => ({ $schema: schemaUrl(schema), ...body });

/** Arquivo de tradução de um texto (tabela do Data Model §9): a cena, o projeto, a tela, o set ou o plugin. */
export function localeFileFor(lang: string, textPath: string): string {
  const [head = '', second = ''] = textPath.split('/');
  const base = `locales/${lang}`;
  if (head === 'ui' && second) return `${base}/ui/${second}.json`;
  if (head === 'sets' && second) return `${base}/sets/${second}.json`;
  if (head === 'plugin' && second) return `${base}/plugins/${second}.json`;
  if (/^[0-9a-f]{8}-/.test(head)) return `${base}/scenes/${head}.json`;
  return `${base}/project.json`;
}

function entityPath(kind: EntityKind, entity: Json, disk: DiskState, taken: Set<string>): string {
  const id = entity.id as string;
  const dir = kind;
  const unique = (folder: string, base: string) => {
    const prefix = `${folder}/`;
    const names = [...taken].filter((p) => p.startsWith(prefix)).map((p) => p.slice(prefix.length, -'.json'.length));
    return `${prefix}${uniqueName(base, names)}.json`;
  };
  switch (kind) {
    case 'characters':
      return unique(dir, slugify(String(entity.key ?? id), 'personagem'));
    case 'chapters':
      return unique(dir, slugify(String(entity.title ?? id), 'capitulo'));
    case 'scenes': {
      const chapter = typeof entity.chapter === 'string' ? entity.chapter : null;
      const chapterFile = chapter ? disk.entityFiles.get(`chapters/${chapter}`) : undefined;
      const folder = chapterFile ? chapterFile.slice('chapters/'.length, -'.json'.length) : '_global';
      return unique(`scenes/${folder}`, slugify(String(entity.title ?? id), 'cena'));
    }
    default:
      return `${dir}/${id}.json`;
  }
}

/**
 * Compara o documento com o que está no disco e devolve só o que mudou. Seções e entidades cuja
 * referência não mudou (Immer compartilha o que não foi editado) nem são serializadas. Atualiza o `disk`
 * recebido como se a gravação já tivesse dado certo: passe uma cópia (`cloneDiskState`) e só fique com
 * ela depois que `commitSave` terminar, como faz o autosave.
 */
export function planSave(doc: LogicalDocument, disk: DiskState): SavePlan {
  const writes = new Map<string, string>();
  const deletes: string[] = [];
  const put = (rel: string, text: string) => {
    if (disk.savedTexts.get(rel) !== text) writes.set(rel, text);
  };

  for (const key of SECTION_KEYS) {
    if (disk.savedRefs.get(key) === doc[key]) continue;
    const [rel, schema] = SECTION_FILES[key];
    const wrapped = WRAPPED[key];
    put(rel, formatJson(withSchema(schema, wrapped ? { [wrapped]: doc[key] } : doc[key])));
    disk.savedRefs.set(key, doc[key]);
  }

  const taken = new Set<string>([...disk.entityFiles.values()]);
  for (const kind of ENTITY_KINDS) {
    for (const [id, entity] of Object.entries(doc[kind])) {
      const refKey = `${kind}/${id}`;
      if (disk.savedRefs.get(refKey) === entity) continue;
      let rel = disk.entityFiles.get(refKey);
      if (!rel) {
        rel = entityPath(kind, entity, disk, taken);
        taken.add(rel);
        disk.entityFiles.set(refKey, rel);
      }
      put(rel, formatJson(withSchema(ENTITY_SCHEMA[kind], entity)));
      disk.savedRefs.set(refKey, entity);
    }
    for (const refKey of [...disk.savedRefs.keys()]) {
      if (!refKey.startsWith(`${kind}/`)) continue;
      const id = refKey.slice(kind.length + 1);
      if (Object.hasOwn(doc[kind], id)) continue;
      const rel = disk.entityFiles.get(refKey);
      if (rel) deletes.push(rel);
      disk.entityFiles.delete(refKey);
      disk.savedRefs.delete(refKey);
    }
  }

  const langs = new Set([...Object.keys(doc.locales), ...[...disk.savedRefs.keys()].filter((k) => k.startsWith('locales/')).map((k) => k.slice(8))]);
  for (const lang of langs) {
    const strings = doc.locales[lang];
    if (disk.savedRefs.get(`locales/${lang}`) === strings) continue;
    const byFile = new Map<string, Json>();
    for (const [textPath, entry] of Object.entries(strings ?? {})) {
      const known = disk.localeFiles.get(`${lang}/${textPath}`);
      const rel = known ?? localeFileFor(lang, textPath);
      disk.localeFiles.set(`${lang}/${textPath}`, rel);
      (byFile.get(rel) ?? byFile.set(rel, {}).get(rel)!)[textPath] = entry;
    }
    for (const key of [...disk.localeFiles.keys()]) {
      if (key.startsWith(`${lang}/`) && !Object.hasOwn(strings ?? {}, key.slice(lang.length + 1))) disk.localeFiles.delete(key);
    }
    for (const [rel, entries] of byFile) put(rel, formatJson(withSchema('locale', { locale: lang, strings: entries })));
    const previous = disk.localeFileList.get(lang) ?? new Set<string>();
    for (const rel of previous) if (!byFile.has(rel)) deletes.push(rel);
    disk.localeFileList.set(lang, new Set(byFile.keys()));
    if (strings) disk.savedRefs.set(`locales/${lang}`, strings);
    else disk.savedRefs.delete(`locales/${lang}`);
  }
  return { writes, deletes };
}

/** Grava o plano: primeiro o diário (o lote inteiro, atômico), depois os arquivos, por fim apaga o diário. */
export async function commitSave(fs: ProjectFs, root: string, plan: SavePlan, disk: DiskState): Promise<void> {
  if (plan.writes.size === 0 && plan.deletes.length === 0) return;
  const journal = formatJson({ writes: Object.fromEntries(plan.writes), deletes: plan.deletes });
  await fs.writeText(joinPath(root, JOURNAL), journal);
  for (const [rel, text] of plan.writes) await fs.writeText(joinPath(root, rel), text);
  for (const rel of plan.deletes) await fs.removeFile(joinPath(root, rel));
  await fs.removeFile(joinPath(root, JOURNAL));
  for (const [rel, text] of plan.writes) disk.savedTexts.set(rel, text);
  for (const rel of plan.deletes) disk.savedTexts.delete(rel);
}

export function cloneDiskState(disk: DiskState): DiskState {
  return {
    entityFiles: new Map(disk.entityFiles),
    savedRefs: new Map(disk.savedRefs),
    savedTexts: new Map(disk.savedTexts),
    localeFiles: new Map(disk.localeFiles),
    localeFileList: new Map([...disk.localeFileList].map(([k, v]) => [k, new Set(v)])),
  };
}
