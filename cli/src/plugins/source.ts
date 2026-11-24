import { readdir, readFile, stat } from 'node:fs/promises';
import { isAbsolute, join, normalize, relative, sep } from 'node:path';
import type { PluginManifest } from '@vnstudio/plugin-schema';
import { DependencyError, issue } from './errors.js';

/** Origem de um plugin em `plugins.json` (spec 09 §3.1). */
export type PluginSource =
  | { kind: 'catalog'; catalog: 'official' }
  | { kind: 'github'; owner: string; repo: string }
  | { kind: 'path'; path: string };

const SOURCE_RE = /^(catalog:official|github:([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)|path:(.+))$/;

export function parseSource(source: string): PluginSource {
  const m = SOURCE_RE.exec(source);
  if (!m) throw new Error(`origem de plugin inválida: ${source}`);
  if (m[1] === 'catalog:official') return { kind: 'catalog', catalog: 'official' };
  if (m[2] && m[3]) return { kind: 'github', owner: m[2], repo: m[3] };
  return { kind: 'path', path: m[4] ?? '' };
}

/**
 * Caminho de uma origem `path:`, relativo à pasta do projeto. Recusa caminho absoluto ou que sai do
 * projeto (P021): o que vai para o Git precisa funcionar em qualquer clone.
 */
export function projectPath(projectDir: string, rel: string, plugin?: string): string {
  const norm = normalize(rel);
  if (isAbsolute(norm) || norm === '..' || norm.startsWith(`..${sep}`)) {
    throw new DependencyError([
      issue('bad-path', `O caminho ${rel} do plugin ${plugin ?? ''} precisa estar dentro da pasta do projeto.`, {
        ...(plugin ? { plugin } : {}),
      }),
    ]);
  }
  return join(projectDir, norm);
}

export type LocalPath =
  | { kind: 'vendored'; file: string }
  | { kind: 'embedded'; root: string; pluginDir: string; manifest: PluginManifest };

/**
 * Classifica uma origem `path:` (spec 09 §3.2, §3.3): arquivo = pacote guardado; pasta = projeto de
 * desenvolvimento de um plugin embutido, que deve ter exatamente um `vn_plugins/<namespace>/plugin.json`.
 * Faltando o caminho, ou com zero ou vários `plugin.json`, é P021.
 */
export async function inspectLocalPath(projectDir: string, rel: string, plugin: string): Promise<LocalPath> {
  const abs = projectPath(projectDir, rel, plugin);
  const st = await stat(abs).catch(() => undefined);
  if (!st) {
    throw new DependencyError([issue('bad-path', `O caminho ${rel} do plugin ${plugin} não existe.`, { plugin })]);
  }
  if (st.isFile()) return { kind: 'vendored', file: abs };
  return { kind: 'embedded', root: abs, ...(await findEmbeddedPlugin(abs, rel, plugin)) };
}

/**
 * Acha a pasta `vn_plugins/<namespace>/` de um projeto de desenvolvimento de plugin. Também aceita que
 * `root` já seja essa pasta (com `plugin.json`), que é o que o lock local de um vínculo guarda (SDK §12.3).
 */
export async function findEmbeddedPlugin(
  root: string,
  rel: string,
  plugin: string,
): Promise<{ pluginDir: string; manifest: PluginManifest }> {
  const direct = join(root, 'plugin.json');
  const candidates: string[] = [];
  if (await stat(direct).then((s) => s.isFile()).catch(() => false)) {
    candidates.push(root);
  } else {
    const vp = join(root, 'vn_plugins');
    const dirs = await readdir(vp, { withFileTypes: true }).catch(() => []);
    for (const d of dirs) {
      if (!d.isDirectory()) continue;
      const dir = join(vp, d.name);
      if (await stat(join(dir, 'plugin.json')).then((s) => s.isFile()).catch(() => false)) candidates.push(dir);
    }
  }
  const [only] = candidates;
  if (candidates.length !== 1 || !only) {
    throw new DependencyError([
      issue(
        'bad-path',
        `A pasta ${rel} do plugin ${plugin} precisa ter exatamente um vn_plugins/<namespace>/plugin.json (achei ${candidates.length}).`,
        { plugin, details: candidates.map((c) => relative(root, c)).join(', ') },
      ),
    ]);
  }
  const manifest = JSON.parse(await readFile(join(only, 'plugin.json'), 'utf8')) as PluginManifest;
  return { pluginDir: only, manifest };
}
