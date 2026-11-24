import { readdir, readFile } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';
import type { PluginManifest } from '@vnstudio/plugin-schema';
import { readZip, writeZip, type ZipEntry } from './zip.js';

/** Tamanho máximo de um `.vnplugin` (Plugin SDK §2.1). */
export const MAX_PACKAGE_BYTES = 100 * 1024 * 1024;

/**
 * O que nunca vai no pacote (Plugin SDK §2.1): arquivos do ambiente de desenvolvimento e `node_modules/`.
 * Caminho relativo à pasta do plugin, com `/`.
 */
export function isExcludedFromPackage(relPath: string): boolean {
  const parts = relPath.split('/');
  const name = parts[parts.length - 1] ?? '';
  if (parts.includes('node_modules') || parts.includes('.godot')) return true;
  if (parts.length > 1 && ['addons', 'sandbox', '.vnplugin'].includes(parts[0] ?? '')) return true;
  if (parts.length === 1 && ['project.godot', 'override.cfg'].includes(name)) return true;
  return name.endsWith('.import');
}

/**
 * Empacota a pasta `vn_plugins/<namespace>/` de um plugin com as regras do pacote reprodutível
 * (Plugin SDK §2.1–§2.2). É o que o Build System faz com um plugin embutido (BS §3.2 passo 4).
 */
export async function packPluginFolder(dir: string): Promise<Buffer> {
  const files = (await readdir(dir, { recursive: true, withFileTypes: true }))
    .filter((d) => d.isFile())
    .map((d) => relative(dir, join(d.parentPath, d.name)).split(sep).join('/'))
    .filter((p) => !isExcludedFromPackage(p));
  if (!files.includes('plugin.json')) throw new Error(`${dir} não tem plugin.json na raiz`);
  const entries: ZipEntry[] = [];
  for (const path of files) entries.push({ path, data: await readFile(join(dir, ...path.split('/'))) });
  const zip = writeZip(entries);
  if (zip.length > MAX_PACKAGE_BYTES) throw new Error(`o pacote de ${dir} passa de 100 MB`);
  return zip;
}

/** Lê o `plugin.json` da raiz de um `.vnplugin`. */
export function readPackageManifest(pkg: Uint8Array): PluginManifest {
  const entry = readZip(pkg).find((e) => e.path === 'plugin.json');
  if (!entry) throw new Error('o pacote não tem plugin.json na raiz');
  return JSON.parse(new TextDecoder().decode(entry.data)) as PluginManifest;
}
