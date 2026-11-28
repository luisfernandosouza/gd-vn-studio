/**
 * Lê um projeto do disco (pela interface `ProjectFs` do Project Manager) para a entrada do compilador do
 * bundle (`cli/src/bundle/input.ts`). É o `load.ts` da CLI, que usa `node:fs`, reescrito sobre `ProjectFs`:
 * a mesma ordem de leitura (caminhos comparados por partes e por pontos de código) e o mesmo texto de
 * licença com fins de linha em `\n`, para o Preview e o build darem o mesmo `content_hash` (PP §1.3).
 *
 * O modelo em memória do M6-02 vai substituir esta leitura: o Studio monta a `ProjectInput` do próprio
 * estado e chama `PreviewSession.update`. Até lá, "Recarregar do disco" usa este leitor.
 */
import { codePointCompare } from '../../cli/src/bundle/compile';
import type { JsonObject } from '../../cli/src/bundle/jcs';
import type { PluginInput, PresetInput, ProjectInput } from '../../cli/src/bundle/input';
import { joinPath, listFilesRecursive, type ProjectFs } from '../src/project-manager/fs';
import { bundledPreset } from './presets';

export interface ReadProjectOptions {
  /** Pastas de plugins (com `plugin.json` na raiz), além das origens `path:` de `plugins.json`. */
  pluginDirs?: string[];
  /** Preset de interface; padrão: o que vem no Studio (`docs/specs/presets/<nome>/`). */
  preset?: (name: string) => PresetInput;
}

const readJson = async (fs: ProjectFs, path: string): Promise<JsonObject> => JSON.parse(await fs.readText(path)) as JsonObject;

/** `\r\n` e `\r` viram `\n`, como o modo texto do Python. */
const normalizeText = (text: string): string => text.replace(/\r\n?/g, '\n');

function comparePaths(a: string, b: string): number {
  const pa = a.split('/');
  const pb = b.split('/');
  for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
    const c = codePointCompare(pa[i]!, pb[i]!);
    if (c) return c;
  }
  return pa.length - pb.length;
}

const stem = (path: string): string => path.split('/').pop()!.slice(0, -'.json'.length);

/** Caminhos (relativos à pasta) dos `.json` de uma pasta, em ordem de caminho; pasta ausente dá lista vazia. */
async function jsonFiles(fs: ProjectFs, dir: string, recursive: boolean): Promise<string[]> {
  const all = recursive
    ? await listFilesRecursive(fs, dir)
    : (await fs.exists(dir))
      ? (await fs.readDir(dir)).filter((e) => !e.isDir).map((e) => e.name)
      : [];
  return all.filter((f) => f.endsWith('.json')).sort(comparePaths);
}

async function readAll(fs: ProjectFs, dir: string, recursive: boolean): Promise<[name: string, doc: JsonObject][]> {
  const out: [string, JsonObject][] = [];
  for (const rel of await jsonFiles(fs, dir, recursive)) out.push([rel, await readJson(fs, joinPath(dir, rel))]);
  return out;
}

export async function readProjectInput(fs: ProjectFs, root: string, options: ReadProjectOptions = {}): Promise<ProjectInput> {
  const project = await readJson(fs, joinPath(root, 'project.json'));
  const assetsDoc = await readJson(fs, joinPath(root, 'assets.json'));
  const assets = (assetsDoc.assets ?? {}) as JsonObject;
  const optional = async (name: string): Promise<JsonObject> => {
    const path = joinPath(root, name);
    return (await fs.exists(path)) ? (((await readJson(fs, path)).plugins ?? {}) as JsonObject) : {};
  };
  const pluginsCfg = await optional('plugins.json');
  const lock = await optional('plugin-lock.json');
  const themePath = joinPath(root, typeof project.theme === 'string' ? project.theme : 'theme.json');
  const theme = (await fs.exists(themePath)) ? await readJson(fs, themePath) : null;

  // manifestos: as pastas passadas, depois as origens path: (spec 09 §3.2)
  const dirs = [...(options.pluginDirs ?? [])];
  for (const cfg of Object.values(pluginsCfg)) {
    const source = String((cfg as JsonObject).source ?? '');
    if (!source.startsWith('path:') || source.endsWith('.vnplugin')) continue;
    const base = joinPath(root, source.slice('path:'.length), 'vn_plugins');
    if (!(await fs.exists(base))) continue;
    const namespaces = (await fs.readDir(base)).filter((e) => e.isDir).map((e) => e.name).sort(codePointCompare);
    for (const ns of namespaces) if (await fs.exists(joinPath(base, ns, 'plugin.json'))) dirs.push(joinPath(base, ns));
  }
  const manifests: PluginInput[] = [];
  for (const dir of dirs) {
    const license = joinPath(dir, 'LICENSE');
    manifests.push({
      manifest: await readJson(fs, joinPath(dir, 'plugin.json')),
      ...((await fs.exists(license)) ? { license: normalizeText(await fs.readText(license)) } : {}),
    });
  }

  const localeFiles: Record<string, JsonObject[]> = {};
  const localesDir = joinPath(root, 'locales');
  if (await fs.exists(localesDir)) {
    for (const entry of await fs.readDir(localesDir)) {
      if (!entry.isDir) continue;
      localeFiles[entry.name] = (await readAll(fs, joinPath(localesDir, entry.name), true)).map(([, doc]) => doc);
    }
  }

  const licenseFiles: Record<string, string> = {};
  for (const asset of Object.values(assets)) {
    const file = ((asset as JsonObject).credit as JsonObject | undefined)?.license_file;
    if (typeof file !== 'string' || !file) continue;
    const path = joinPath(root, 'assets', file);
    if (await fs.exists(path)) licenseFiles[file] = normalizeText(await fs.readText(path));
  }

  const presetName = theme && typeof theme.preset === 'string' ? theme.preset : 'classic';
  const docs = async (dir: string): Promise<[string, JsonObject][]> =>
    (await readAll(fs, joinPath(root, dir), false)).map(([name, doc]) => [stem(name), doc]);
  return {
    project,
    variables: await readJson(fs, joinPath(root, 'variables.json')),
    assets,
    characters: (await readAll(fs, joinPath(root, 'characters'), false)).map(([, d]) => d),
    chapters: (await readAll(fs, joinPath(root, 'chapters'), false)).map(([, d]) => d),
    scenes: (await readAll(fs, joinPath(root, 'scenes'), true)).map(([, d]) => d),
    screens: await docs('ui'),
    sets: await docs('sets'),
    theme,
    plugins: pluginsCfg,
    lock,
    manifests,
    localeFiles,
    licenseFiles,
    preset: (options.preset ?? bundledPreset)(presetName),
  };
}
