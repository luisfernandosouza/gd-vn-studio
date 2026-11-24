/**
 * Leitura de um projeto de VN do disco para a {@link ProjectInput} do compilador (Node). Segue a
 * ordem de leitura de `docs/specs/tools/compile_bundle.py`: arquivos em ordem de caminho (comparação
 * por partes e por pontos de código, como o `sorted()` de `pathlib`), textos de licença com os fins
 * de linha normalizados para `\n` (como o `read_text` do Python).
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { codePointCompare } from './compile.js';
import type { JsonObject } from './jcs.js';
import type { PluginInput, PresetInput, ProjectInput } from './input.js';

function readJson(path: string): JsonObject {
  return JSON.parse(readFileSync(path, 'utf8')) as JsonObject;
}

/** Texto com `\r\n` e `\r` virando `\n` (modo texto do Python). */
export function readText(path: string): string {
  return readFileSync(path, 'utf8').replace(/\r\n?/g, '\n');
}

const isDir = (p: string): boolean => existsSync(p) && statSync(p).isDirectory();
const isFile = (p: string): boolean => existsSync(p) && statSync(p).isFile();

function comparePaths(a: string, b: string): number {
  const pa = a.split('/'), pb = b.split('/');
  for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
    const c = codePointCompare(pa[i]!, pb[i]!);
    if (c) return c;
  }
  return pa.length - pb.length;
}

/** Arquivos `.json` de uma pasta (recursivo ou não), em ordem de caminho; [] se a pasta não existe. */
function jsonFiles(dir: string, recursive: boolean): string[] {
  if (!isDir(dir)) return [];
  return readdirSync(dir, { recursive, encoding: 'utf8' })
    .map((f) => f.split('\\').join('/'))
    .filter((f) => f.endsWith('.json') && isFile(join(dir, f)))
    .sort(comparePaths)
    .map((f) => join(dir, f));
}

function stem(path: string): string {
  const base = path.split(/[\\/]/).pop()!;
  return base.slice(0, -'.json'.length);
}

/**
 * Pasta dos presets: `docs/specs/presets/` do repositório, achada subindo a partir deste módulo
 * (vale para `cli/src/` e `cli/dist/`). A cópia que vai no pacote npm chega com a publicação da CLI.
 */
export function defaultPresetsDir(): string {
  let dir = dirname(fileURLToPath(import.meta.url));
  for (;;) {
    for (const cand of [join(dir, 'presets'), join(dir, 'docs', 'specs', 'presets')])
      if (isDir(join(cand, 'classic'))) return cand;
    const up = dirname(dir);
    if (up === dir) throw new Error('não achei a pasta dos presets (docs/specs/presets/); passe presetsDir');
    dir = up;
  }
}

export function loadPreset(presetsDir: string, name: string): PresetInput {
  const dir = join(presetsDir, name);
  if (!isDir(dir)) throw new Error(`preset ${name} não existe em ${presetsDir}`);
  const locales: Record<string, JsonObject> = {};
  for (const f of jsonFiles(join(dir, 'locales'), false)) locales[stem(f)] = readJson(f);
  return {
    name,
    theme: readJson(join(dir, 'theme.json')),
    ui: jsonFiles(join(dir, 'ui'), false).map((f) => [stem(f), readJson(f)]),
    locales,
  };
}

export interface LoadOptions {
  /** Pastas de plugins (com `plugin.json` na raiz), além das origens `path:` de `plugins.json`. */
  pluginDirs?: string[];
  presetsDir?: string;
}

export function loadProject(root: string, options: LoadOptions = {}): ProjectInput {
  root = resolve(root);
  const project = readJson(join(root, 'project.json'));
  const assetsDoc = readJson(join(root, 'assets.json'));
  const assets = (assetsDoc.assets ?? {}) as JsonObject;
  const pluginsCfg = isFile(join(root, 'plugins.json')) ? ((readJson(join(root, 'plugins.json')).plugins ?? {}) as JsonObject) : {};
  const lock = isFile(join(root, 'plugin-lock.json')) ? ((readJson(join(root, 'plugin-lock.json')).plugins ?? {}) as JsonObject) : {};
  const themeFile = join(root, typeof project.theme === 'string' ? project.theme : 'theme.json');
  const theme = isFile(themeFile) ? readJson(themeFile) : null;

  // manifestos: as pastas passadas, depois as origens path: (spec 09 §3.2)
  const dirs = (options.pluginDirs ?? []).map((d) => resolve(d));
  for (const cfg of Object.values(pluginsCfg)) {
    const source = String((cfg as JsonObject).source ?? '');
    if (!source.startsWith('path:') || source.endsWith('.vnplugin')) continue;
    const base = join(root, source.slice('path:'.length), 'vn_plugins');
    if (!isDir(base)) continue;
    for (const ns of readdirSync(base).sort(codePointCompare))
      if (isFile(join(base, ns, 'plugin.json'))) dirs.push(join(base, ns));
  }
  const manifests: PluginInput[] = dirs.map((d) => {
    const lic = join(d, 'LICENSE');
    return { manifest: readJson(join(d, 'plugin.json')), ...(isFile(lic) ? { license: readText(lic) } : {}) };
  });

  const localeFiles: Record<string, JsonObject[]> = {};
  const localesDir = join(root, 'locales');
  if (isDir(localesDir))
    for (const lang of readdirSync(localesDir))
      if (isDir(join(localesDir, lang))) localeFiles[lang] = jsonFiles(join(localesDir, lang), true).map(readJson);

  const licenseFiles: Record<string, string> = {};
  for (const a of Object.values(assets)) {
    const lf = ((a as JsonObject).credit as JsonObject | undefined)?.license_file;
    if (typeof lf === 'string' && lf && isFile(join(root, 'assets', lf))) licenseFiles[lf] = readText(join(root, 'assets', lf));
  }

  const presetName = theme && typeof theme.preset === 'string' ? theme.preset : 'classic';
  return {
    project,
    variables: readJson(join(root, 'variables.json')),
    assets,
    characters: jsonFiles(join(root, 'characters'), false).map(readJson),
    chapters: jsonFiles(join(root, 'chapters'), false).map(readJson),
    scenes: jsonFiles(join(root, 'scenes'), true).map(readJson),
    screens: jsonFiles(join(root, 'ui'), false).map((f) => [stem(f), readJson(f)]),
    sets: jsonFiles(join(root, 'sets'), false).map((f) => [stem(f), readJson(f)]),
    theme,
    plugins: pluginsCfg,
    lock,
    manifests,
    localeFiles,
    licenseFiles,
    preset: loadPreset(options.presetsDir ?? defaultPresetsDir(), presetName),
  };
}
