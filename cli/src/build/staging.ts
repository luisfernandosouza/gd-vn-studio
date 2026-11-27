/**
 * Build Staging (Build System §4, tarefa M5-06): monta a pasta do projeto Godot que o export usa, a
 * partir do template do runtime, do bundle compilado e dos plugins do lock. O projeto original nunca
 * é modificado (BS §1); tudo acontece na pasta de staging.
 *
 * Escolhas onde a spec é omissa (BS §4.2 não diz como o bundle fica antes do M5-03):
 * - o bundle entra na forma canônica em JSON (`bundle.json`, `locales/<idioma>.json`, `plugins.json`,
 *   `licenses.json`), que o runtime de debug lê (RT §2.1); o `.vnb` (Zstandard + AES) é a tarefa M5-03,
 *   então o tipo `release` é recusado aqui até lá. `CONTENT_HASHES` já traz o hash do JSON canônico de
 *   cada `.vnb`, como o §8.2 pede;
 * - sem `autoload/*`: o runtime monta os módulos pela cena `boot.tscn` e não tem scripts de autoload.
 */
import { copyFile, cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { hex, sha256, sri } from '../bundle/hash.js';
import { canonicalize } from '../bundle/jcs.js';
import type { JsonObject } from '../bundle/jcs.js';
import type { CompiledBundle } from '../bundle/compile.js';
import type { PreparedPlugin } from '../plugins/dependencies.js';
import { readZip } from '../plugins/zip.js';
import { satisfies } from '../validate/semver.js';
import { generateBuildConfig } from './build-config.js';
import { generateProjectGodot, PINNED_GODOT } from './godot-project.js';

/** Versão do runtime que esta CLI monta (o runtime 1.0, BS §2.1). */
export const RUNTIME_VERSION = '1.0.0';

const ASSET_ROOT = 'res://vn_content/assets/';

/** Erro de uma etapa do staging, com o código `B0xx` do BS §13. */
export class StagingError extends Error {
  constructor(
    readonly code: 'B005' | 'B014' | 'B018' | 'template' | 'unsupported',
    message: string,
  ) {
    super(code === 'template' || code === 'unsupported' ? message : `${code}: ${message}`);
    this.name = 'StagingError';
  }
}

export interface StageOptions {
  /** Pasta do projeto de jogo (somente leitura). */
  projectDir: string;
  compiled: CompiledBundle;
  /** Plugins do lock já conferidos (BS §3.2), de `prepareDependencies`. */
  plugins: PreparedPlugin[];
  /** Pasta `runtime/` do template (`project.godot`, `vn_runtime/`). */
  runtimeDir: string;
  /** Pasta com `addons/vn_runtime_sdk/` (no monorepo, `sdk/runtime/`). */
  sdkDir: string;
  /** Pasta do staging. Padrão: `~/.vnstudio/builds/<project_id>/<build_id>/staging` (BS §4.1). */
  stagingDir?: string;
  /** `debug` (padrão) ou `release`; `release` depende do `.vnb` (M5-03). */
  type?: 'debug' | 'release';
  /** Para o `build_id` e testes reprodutíveis. */
  now?: Date;
  runtimeVersion?: string;
  godotVersion?: string;
}

export interface StageResult {
  buildId: string;
  contentHash: string;
  stagingDir: string;
  /** Hash do JSON canônico de cada arquivo do bundle, como em `CONTENT_HASHES`. */
  contentHashes: Record<string, string>;
}

/** `AAAAMMDD-HHMMSS` em UTC. */
export function buildTimestamp(d: Date): string {
  return d.toISOString().replace(/\.\d+Z$/, '').replace(/[-:]/g, '').replace('T', '-');
}

/** `<AAAAMMDD-HHMMSS>-<8 hex do SHA-256 do bundle.json canônico>` (BS §4.1). */
export function makeBuildId(now: Date, contentHash: string): string {
  const raw = base64Decode(contentHash.replace(/^sha256-/, ''));
  return `${buildTimestamp(now)}-${hex(raw).slice(0, 8)}`;
}

function base64Decode(b64: string): Uint8Array {
  return new Uint8Array(Buffer.from(b64, 'base64'));
}

/** Pastas do template no monorepo, achadas subindo a partir deste módulo (vale para `src/` e `dist/`). */
export function defaultTemplateDirs(): { runtimeDir: string; sdkDir: string } {
  let dir = dirname(fileURLToPath(import.meta.url));
  for (;;) {
    if (existsSync(join(dir, 'runtime', 'project.godot')) && existsSync(join(dir, 'sdk', 'runtime', 'addons'))) {
      return { runtimeDir: join(dir, 'runtime'), sdkDir: join(dir, 'sdk', 'runtime') };
    }
    const up = dirname(dir);
    if (up === dir) throw new Error('não achei o template do runtime (runtime/ e sdk/runtime/); passe runtimeDir e sdkDir');
    dir = up;
  }
}

export function defaultStagingDir(projectId: string, buildId: string): string {
  return join(homedir(), '.vnstudio', 'builds', projectId, buildId, 'staging');
}

/** O que do template do runtime não vai para o jogo (spec 09 §1.2): testes, docs e caches do Godot. */
function templateExcluded(rel: string): boolean {
  const parts = rel.split('/');
  return parts.includes('tests') || parts.includes('.godot') || (parts.at(-1) ?? '').endsWith('.md');
}

async function copyTree(src: string, dst: string, excluded: (rel: string) => boolean): Promise<void> {
  await cp(src, dst, {
    recursive: true,
    filter: (s) => !excluded(relative(src, s).split(sep).join('/')),
  });
}

/** Do pacote ou da pasta de um plugin entram só `plugin.json`, `LICENSE` e `runtime/` (BS §4.5). */
export function pluginIncluded(rel: string): boolean {
  return rel === 'plugin.json' || rel === 'LICENSE' || rel.startsWith('runtime/');
}

async function stagePlugin(p: PreparedPlugin, dst: string): Promise<void> {
  await rm(dst, { recursive: true, force: true });
  if (p.package) {
    let n = 0;
    for (const e of readZip(p.package)) {
      if (!pluginIncluded(e.path)) continue;
      const target = join(dst, ...e.path.split('/'));
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, e.data);
      n++;
    }
    if (n === 0) throw new StagingError('template', `o pacote do plugin ${p.id} não tem plugin.json`);
    return;
  }
  if (!p.folder) throw new StagingError('template', `o plugin ${p.id} não tem pacote nem pasta`);
  const files = (await readdir(p.folder, { recursive: true, withFileTypes: true })).filter((d) => d.isFile());
  for (const f of files) {
    const rel = relative(p.folder, join(f.parentPath, f.name)).split(sep).join('/');
    if (!pluginIncluded(rel)) continue;
    const target = join(dst, ...rel.split('/'));
    await mkdir(dirname(target), { recursive: true });
    await copyFile(join(f.parentPath, f.name), target);
  }
}

const obj = (v: unknown): JsonObject => (v !== null && typeof v === 'object' && !Array.isArray(v) ? (v as JsonObject) : {});

/** B014: o runtime e o Godot que o Studio traz precisam servir ao projeto (BS §2.1). */
export function checkEngineConstraints(project: JsonObject, runtimeVersion: string, godotVersion: string): void {
  const rt = obj(project.runtime);
  if (typeof rt.min_version === 'string' && !satisfies(runtimeVersion, `>=${rt.min_version}`)) {
    throw new StagingError('B014', `o projeto pede o runtime ${rt.min_version} ou maior, e este Studio traz o ${runtimeVersion}`);
  }
  if (typeof rt.godot === 'string' && !satisfies(godotVersion, rt.godot)) {
    throw new StagingError('B014', `o projeto aceita o Godot ${rt.godot}, e o runtime fixa o ${godotVersion}`);
  }
}

export async function stageBuild(o: StageOptions): Promise<StageResult> {
  const type = o.type ?? 'debug';
  if (type === 'release') {
    throw new StagingError('unsupported', 'o build de release precisa do formato .vnb (tarefa M5-03); use o tipo debug por enquanto');
  }
  const runtimeVersion = o.runtimeVersion ?? RUNTIME_VERSION;
  const godotVersion = o.godotVersion ?? PINNED_GODOT;
  const { bundle, locales, plugins, licenses } = o.compiled;
  const project = bundle.project as unknown as JsonObject;
  checkEngineConstraints(project, runtimeVersion, godotVersion);

  const contentHash = bundle.content_hash;
  const buildId = makeBuildId(o.now ?? new Date(), contentHash);
  const staging = o.stagingDir ?? defaultStagingDir(String(project.id), buildId);

  const templateProject = join(o.runtimeDir, 'project.godot');
  const runtimeSrc = join(o.runtimeDir, 'vn_runtime');
  const sdkSrc = join(o.sdkDir, 'addons', 'vn_runtime_sdk');
  for (const [p, what] of [
    [templateProject, 'project.godot do runtime'],
    [join(runtimeSrc, 'boot.tscn'), 'vn_runtime/boot.tscn'],
    [join(runtimeSrc, 'presets'), 'vn_runtime/presets (rode docs/specs/tools/sync_generated_copies.py runtime)'],
    [sdkSrc, 'addons/vn_runtime_sdk'],
  ] as const) {
    if (!existsSync(p)) throw new StagingError('template', `o template do runtime está incompleto: falta ${what} em ${p}`);
  }

  // Assets do jogo (BS §4.2: mesma árvore de assets/ do projeto). A seleção só dos usados é a M5-07.
  const censored = obj(project.content_filter).edition === 'censored';
  const assetFiles: { rel: string; src: string }[] = [];
  for (const a of Object.values(bundle.assets) as unknown as JsonObject[]) {
    const path = String(a.path ?? '');
    if (!path.startsWith(ASSET_ROOT)) continue;
    if (censored && obj(a.censored).hide) continue;
    const rel = path.slice(ASSET_ROOT.length);
    if (rel.split('/').includes('..')) throw new StagingError('B018', `o pacote do jogo aponta para um arquivo fora dele (${path})`);
    const src = join(o.projectDir, 'assets', ...rel.split('/'));
    if (!existsSync(src)) throw new StagingError('B005', `o arquivo ${rel} não pôde ser lido (não existe em ${src})`);
    assetFiles.push({ rel, src });
  }

  await rm(staging, { recursive: true, force: true });
  await mkdir(staging, { recursive: true });

  await copyTree(runtimeSrc, join(staging, 'vn_runtime'), templateExcluded);
  await copyTree(sdkSrc, join(staging, 'addons', 'vn_runtime_sdk'), templateExcluded);

  // Conteúdo: forma canônica do bundle + assets + manifesto resumido.
  const content = join(staging, 'vn_content');
  await mkdir(join(content, 'locales'), { recursive: true });
  const bundleText = canonicalize(bundle);
  const files: Record<string, string> = {
    'bundle.json': bundleText,
    'plugins.json': canonicalize(plugins),
    'licenses.json': canonicalize(licenses),
  };
  const contentHashes: Record<string, string> = {
    'narrative.vnb': sri(sha256(new TextEncoder().encode(bundleText))),
    'plugins.vnb': sri(sha256(new TextEncoder().encode(files['plugins.json']!))),
    'licenses.vnb': sri(sha256(new TextEncoder().encode(files['licenses.json']!))),
  };
  for (const [lang, doc] of Object.entries(locales)) {
    const text = canonicalize(doc);
    files[`locales/${lang}.json`] = text;
    contentHashes[`locales/${lang}.vnb`] = sri(sha256(new TextEncoder().encode(text)));
  }
  for (const [name, text] of Object.entries(files)) await writeFile(join(content, ...name.split('/')), text, 'utf8');
  for (const { rel, src } of assetFiles) {
    const dst = join(content, 'assets', ...rel.split('/'));
    await mkdir(dirname(dst), { recursive: true });
    await copyFile(src, dst);
  }
  await writeFile(
    join(content, 'build.json'),
    canonicalize({
      build_id: buildId,
      version: project.version,
      content_hash: contentHash,
      runtime: runtimeVersion,
      godot: godotVersion,
    }),
    'utf8',
  );

  // Plugins (BS §4.5), um por plugin do lock.
  for (const p of o.plugins) await stagePlugin(p, join(staging, 'vn_plugins', p.namespace));

  // build_config.gd e project.godot, gerados.
  await writeFile(
    join(staging, 'vn_runtime', 'build_config.gd'),
    generateBuildConfig({
      buildId,
      contentHash,
      contentHashes,
      runtimeVersion,
      debug: true,
      saveTamperPolicy: 'flag', // debug força flag (BS §11.1); a política do projeto e as chaves entram com a M5-10
    }),
    'utf8',
  );

  const defaultLocale = String(project.default_locale);
  const strings = obj(obj(locales[defaultLocale]).strings);
  // `build` (ícone, splash) não vai para o bundle: lê-se do project.json do projeto.
  const build = obj(obj(JSON.parse(await readFile(join(o.projectDir, 'project.json'), 'utf8'))).build);
  const assetPath = (id: unknown): string | undefined => {
    const a = typeof id === 'string' ? obj((bundle.assets as unknown as JsonObject)[id]) : undefined;
    return a && typeof a.path === 'string' ? a.path : undefined;
  };
  const colors = obj(obj(bundle.theme).colors);
  const godotProject = generateProjectGodot({
    project,
    title: typeof strings['project/title'] === 'string' ? (strings['project/title'] as string) : String(project.title),
    template: await readFile(templateProject, 'utf8'),
    iconPath: assetPath(build.icon),
    splashPath: assetPath(build.splash),
    backgroundColor: typeof colors.background === 'string' ? colors.background : undefined,
  });
  await writeFile(join(staging, 'project.godot'), godotProject, 'utf8');

  return { buildId, contentHash, stagingDir: staging, contentHashes };
}
