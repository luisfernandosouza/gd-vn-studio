import type { Project } from '@vnstudio/plugin-schema';
import { ProjectManagerError } from './errors';
import { joinPath, listFilesRecursive, type ProjectFs } from './fs';
import { applyGitignoreBlock } from './gitignore';
import { EDITOR_DIR, ENTITY_DIRS, FORMAT_VERSION, ROOT_FILES, type EntityKind } from './layout';
import { parseSemVer, planMigration, type MigrationPlan, type Migrator } from './migrate';

export interface OpenedProject {
  root: string;
  project: Project;
  /** O projeto foi gravado por um Studio mais novo, com campos opcionais que este talvez não conheça (Data Model §12). */
  newerMinor: boolean;
  /** Arquivos de cada pasta de entidades, relativos à raiz, em ordem. */
  entities: Record<EntityKind, string[]>;
  /** O bloco do `.gitignore` foi criado ou atualizado ao abrir (spec 09 §3.4). */
  gitignoreUpdated: boolean;
}

export type OpenResult =
  | { status: 'opened'; project: OpenedProject }
  | { status: 'needs_migration'; plan: MigrationPlan }
  | { status: 'too_new'; root: string; formatVersion: string };

export interface OpenOptions {
  migrators?: readonly Migrator[];
  /** Versão do formato deste Studio (testes). */
  formatVersion?: string;
}

/**
 * "Abrir projeto": lê o `project.json`, confere o `format_version` (Data Model §12) e, no mesmo MAJOR,
 * lista os arquivos de entidade e mantém o `.gitignore` e a pasta `.vnstudio/`. MAJOR menor devolve o
 * plano de migração para o autor confirmar; MAJOR maior não abre.
 */
export async function openProject(fs: ProjectFs, root: string, options: OpenOptions = {}): Promise<OpenResult> {
  const studioVersion = parseSemVer(options.formatVersion ?? FORMAT_VERSION);
  if (!studioVersion) throw new Error('formatVersion inválido');
  const projectPath = joinPath(root, ROOT_FILES.project);
  if (!(await fs.exists(projectPath))) {
    throw new ProjectManagerError('not_a_project', 'studio/error/not_a_project');
  }
  let project: Project;
  try {
    project = JSON.parse(await fs.readText(projectPath)) as Project;
  } catch {
    throw new ProjectManagerError('unreadable', 'studio/error/invalid_json');
  }
  const version = parseSemVer(project?.format_version);
  if (!version) throw new ProjectManagerError('unreadable', 'studio/error/invalid_format_version', { version: String(project?.format_version) });
  if (version.major > studioVersion.major) return { status: 'too_new', root, formatVersion: project.format_version };
  if (version.major < studioVersion.major) return { status: 'needs_migration', plan: await planMigration(fs, root, options) };

  await fs.createDir(joinPath(root, EDITOR_DIR));
  const gitignorePath = joinPath(root, ROOT_FILES.gitignore);
  const existing = (await fs.exists(gitignorePath)) ? await fs.readText(gitignorePath) : null;
  const updated = applyGitignoreBlock(existing);
  if (updated !== existing) await fs.writeText(gitignorePath, updated);

  const entities = {} as Record<EntityKind, string[]>;
  for (const [kind, dir] of Object.entries(ENTITY_DIRS) as [EntityKind, string][]) {
    entities[kind] = (await listFilesRecursive(fs, joinPath(root, dir))).filter((f) => f.endsWith('.json')).map((f) => `${dir}/${f}`);
  }
  const newerMinor = version.minor > studioVersion.minor;
  return { status: 'opened', project: { root, project, newerMinor, entities, gitignoreUpdated: updated !== existing } };
}
