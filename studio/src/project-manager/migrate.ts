import { joinPath, listFilesRecursive, type ProjectFs } from './fs';
import { ProjectManagerError } from './errors';
import { formatJson } from './json';
import { BACKUPS_DIR, ENTITY_DIRS, FORMAT_VERSION, ROOT_FILES } from './layout';

/**
 * Migrador de um MAJOR do formato para o seguinte (Data Model §12). Recebe todos os JSON do projeto
 * (caminho relativo → conteúdo) e devolve o conjunto novo: arquivo ausente na saída é apagado.
 * `destructive` marca migrações que perdem dados; essas exigem confirmação explícita (ADD §10).
 */
export interface Migrator {
  from: number;
  to: number;
  destructive: boolean;
  /** Frase curta para o diálogo de migração. */
  description: string;
  migrate(files: ReadonlyMap<string, unknown>): Map<string, unknown>;
}

/**
 * Migradores encadeados do Studio (`1.x → 2.0`, `2.x → 3.0`…). O v1 só conhece o formato 1, então a
 * lista está vazia; quem criar o formato 2 acrescenta o migrador aqui, com testes.
 */
export const MIGRATORS: readonly Migrator[] = [];

export interface FileChange {
  path: string;
  kind: 'added' | 'changed' | 'removed';
  before: string | null;
  after: string | null;
}

export interface MigrationPlan {
  root: string;
  fromVersion: string;
  toVersion: string;
  steps: { from: number; to: number; description: string; destructive: boolean }[];
  destructive: boolean;
  /** O diff mostrado ao autor antes de confirmar. */
  changes: FileChange[];
  /** Todos os arquivos lidos, para o backup. */
  sourceFiles: string[];
}

export function parseSemVer(version: unknown): { major: number; minor: number; patch: number } | null {
  if (typeof version !== 'string') return null;
  const m = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+].*)?$/.exec(version);
  if (!m) return null;
  return { major: Number(m[1]), minor: Number(m[2]), patch: Number(m[3]) };
}

/** Os JSON do projeto: os arquivos da raiz e as pastas de entidades (Data Model §2). */
export async function collectProjectJson(fs: ProjectFs, root: string): Promise<string[]> {
  const out: string[] = [];
  for (const file of Object.values(ROOT_FILES)) {
    if (file.endsWith('.json') && (await fs.exists(joinPath(root, file)))) out.push(file);
  }
  for (const dir of Object.values(ENTITY_DIRS)) {
    for (const rel of await listFilesRecursive(fs, joinPath(root, dir))) if (rel.endsWith('.json')) out.push(`${dir}/${rel}`);
  }
  return out;
}

/**
 * Monta a migração do formato do projeto até o MAJOR deste Studio, sem gravar nada. Falta de
 * migrador no caminho é erro: o projeto não pode ser aberto por este Studio.
 */
export async function planMigration(
  fs: ProjectFs,
  root: string,
  options: { migrators?: readonly Migrator[]; formatVersion?: string } = {},
): Promise<MigrationPlan> {
  const migrators = options.migrators ?? MIGRATORS;
  const target = options.formatVersion ?? FORMAT_VERSION;
  const targetMajor = parseSemVer(target)?.major ?? 1;
  const sourceFiles = await collectProjectJson(fs, root);
  const before = new Map<string, string>();
  let files = new Map<string, unknown>();
  for (const rel of sourceFiles) {
    const text = await fs.readText(joinPath(root, rel));
    before.set(rel, text);
    try {
      files.set(rel, JSON.parse(text));
    } catch {
      throw new ProjectManagerError('unreadable', 'studio/error/file_invalid_json', { file: rel });
    }
  }
  const project = files.get(ROOT_FILES.project) as { format_version?: unknown } | undefined;
  const fromVersion = String(project?.format_version ?? '');
  const from = parseSemVer(fromVersion);
  if (!from) throw new ProjectManagerError('unreadable', 'studio/error/invalid_format_version', { version: fromVersion });

  const steps: MigrationPlan['steps'] = [];
  for (let major = from.major; major < targetMajor; major++) {
    const step = migrators.find((m) => m.from === major && m.to === major + 1);
    if (!step) {
      throw new ProjectManagerError('unreadable', 'studio/error/cannot_migrate', { from: major, to: major + 1 });
    }
    files = step.migrate(files);
    steps.push({ from: step.from, to: step.to, description: step.description, destructive: step.destructive });
  }
  const migrated = files.get(ROOT_FILES.project);
  if (migrated && typeof migrated === 'object') (migrated as { format_version: string }).format_version = target;

  const changes: FileChange[] = [];
  const paths = [...new Set([...before.keys(), ...files.keys()])].sort();
  for (const path of paths) {
    const old = before.get(path) ?? null;
    const next = files.has(path) ? formatJson(files.get(path)) : null;
    if (old === next) continue;
    changes.push({ path, kind: old === null ? 'added' : next === null ? 'removed' : 'changed', before: old, after: next });
  }
  return { root, fromVersion, toVersion: target, steps, destructive: steps.some((s) => s.destructive), changes, sourceFiles };
}

function stamp(date: Date): string {
  return date.toISOString().replace(/[:.]/g, '-');
}

/**
 * Grava a migração: primeiro o backup de todos os JSON em `.vnstudio/backups/<data>-format-<de>-para-<para>/`
 * (fora do Git; o histórico do Req §8 assume esse papel quando existir), depois os arquivos novos.
 * Migração destrutiva sem `confirmed` é recusada. Devolve a pasta do backup, relativa à raiz.
 */
export async function applyMigration(
  fs: ProjectFs,
  plan: MigrationPlan,
  options: { confirmed: boolean; now?: Date },
): Promise<string> {
  if (plan.destructive && !options.confirmed) {
    throw new ProjectManagerError('not_confirmed', 'studio/error/not_confirmed');
  }
  const backup = `${BACKUPS_DIR}/${stamp(options.now ?? new Date())}-format-${plan.fromVersion}-para-${plan.toVersion}`;
  for (const rel of plan.sourceFiles) await fs.copyFile(joinPath(plan.root, rel), joinPath(plan.root, backup, rel));
  for (const change of plan.changes) {
    const path = joinPath(plan.root, change.path);
    if (change.after === null) await fs.removeFile(path);
    else await fs.writeText(path, change.after);
  }
  return backup;
}
