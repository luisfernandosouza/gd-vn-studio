import type { Assets, Chapter, PluginLock, Project, ProjectPlugins, Scene, Theme, Variables } from '@vnstudio/plugin-schema';
import { ProjectManagerError } from './errors';
import { joinPath, type ProjectFs } from './fs';
import { applyGitignoreBlock } from './gitignore';
import { slugify, uuidv7 } from './ids';
import { formatJson } from './json';
import {
  FORMAT_VERSION,
  LOCALE_PATTERN,
  NEW_PROJECT_GODOT_RANGE,
  NEW_PROJECT_RUNTIME_MIN,
  ROOT_FILES,
  STARTER_DIRS,
  schemaUrl,
  starterTexts,
} from './layout';

export interface NewProjectOptions {
  /** Pasta do projeto. Pode não existir; se existir, precisa estar vazia (fora `.git`, `README*`, `LICENSE*`, `.gitignore`). */
  root: string;
  title: string;
  /** Idioma-fonte (BCP 47). */
  defaultLocale: string;
  authors?: string[];
  /** Para testes: gerador de UUIDs. */
  newId?: () => string;
}

export interface CreatedProject {
  root: string;
  project: Project;
  /** Arquivos gravados, relativos à raiz. */
  files: string[];
}

/** O que pode já estar numa pasta escolhida para um projeto novo (ex.: um repositório recém-clonado). */
const ALLOWED_IN_NEW_FOLDER = /^(\.git|\.gitignore|\.gitattributes|readme(\..*)?|license(\..*)?)$/i;

/**
 * "Novo projeto" (Req §2; Data Model §2): grava a estrutura mínima que passa no validador, com um
 * capítulo e uma cena inicial, o tema no preset `classic` (UI Spec §2), sem galeria (Data Model §10.5),
 * e o `.gitignore` do Studio (spec 09 §3.4). IDs de entidade em UUIDv7; o id do projeto vem do título.
 */
export async function createProject(fs: ProjectFs, options: NewProjectOptions): Promise<CreatedProject> {
  const title = options.title.trim();
  if (!title) throw new ProjectManagerError('invalid_title', 'studio/error/needs_title');
  if (!LOCALE_PATTERN.test(options.defaultLocale)) {
    throw new ProjectManagerError('invalid_locale', 'studio/error/invalid_locale', { locale: options.defaultLocale });
  }
  const { root } = options;
  if (await fs.exists(root)) {
    const blocking = (await fs.readDir(root)).filter((e) => !ALLOWED_IN_NEW_FOLDER.test(e.name));
    if (blocking.length > 0) {
      throw new ProjectManagerError(
        'folder_not_empty',
        'studio/error/folder_not_empty',
        { names: blocking.map((e) => e.name).slice(0, 3).join(', ') },
      );
    }
  }

  const newId = options.newId ?? (() => uuidv7());
  const texts = starterTexts(options.defaultLocale);
  const chapterId = newId();
  const sceneId = newId();
  const chapterFile = slugify(texts.chapter, 'capitulo');
  const sceneFile = slugify(texts.scene, 'cena');

  const project: Project = {
    $schema: schemaUrl('project'),
    format_version: FORMAT_VERSION,
    id: slugify(title),
    title,
    version: '0.1.0',
    ...(options.authors && options.authors.length > 0 ? { authors: options.authors } : {}),
    default_locale: options.defaultLocale,
    locales: [options.defaultLocale],
    start_chapter: chapterId,
    chapters: [chapterId],
    runtime: { min_version: NEW_PROJECT_RUNTIME_MIN, godot: NEW_PROJECT_GODOT_RANGE },
    settings: { resolution: [1920, 1080], autosave: 'scene_start' },
  };
  const variables: Variables = { $schema: schemaUrl('variables'), global: [], character: [] };
  const assets: Assets = { $schema: schemaUrl('assets'), assets: {} };
  const plugins: ProjectPlugins = { $schema: schemaUrl('plugins'), plugins: {} };
  const lock: PluginLock = { lock_version: 1, plugins: {} };
  const theme: Theme = { $schema: schemaUrl('theme'), preset: 'classic' };
  const chapter: Chapter = { $schema: schemaUrl('chapter'), id: chapterId, title: texts.chapter, entry_scene: sceneId };
  const scene: Scene = {
    $schema: schemaUrl('scene'),
    id: sceneId,
    chapter: chapterId,
    title: texts.scene,
    scheduling: { mode: 'manual' },
    nodes: [
      { id: newId(), type: 'line', text: texts.line },
      { id: newId(), type: 'end', then: 'end_game' },
    ],
  };

  const files: [string, string][] = [
    [ROOT_FILES.project, formatJson(project)],
    [ROOT_FILES.variables, formatJson(variables)],
    [ROOT_FILES.assets, formatJson(assets)],
    [ROOT_FILES.plugins, formatJson(plugins)],
    [ROOT_FILES.pluginLock, formatJson(lock)],
    [ROOT_FILES.theme, formatJson(theme)],
    [`chapters/${chapterFile}.json`, formatJson(chapter)],
    [`scenes/${chapterFile}/${sceneFile}.json`, formatJson(scene)],
  ];

  await fs.createDir(root);
  for (const dir of STARTER_DIRS) await fs.createDir(joinPath(root, dir));
  await fs.createDir(joinPath(root, 'locales', options.defaultLocale));
  for (const [rel, text] of files) await fs.writeText(joinPath(root, rel), text);

  const gitignorePath = joinPath(root, ROOT_FILES.gitignore);
  const existing = (await fs.exists(gitignorePath)) ? await fs.readText(gitignorePath) : null;
  await fs.writeText(gitignorePath, applyGitignoreBlock(existing));

  return { root, project, files: [...files.map(([rel]) => rel), ROOT_FILES.gitignore] };
}
