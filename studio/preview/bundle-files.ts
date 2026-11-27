/**
 * O bundle do Preview em disco (PP §1.3): `.vnstudio/preview/narrative/` com a forma canônica (RT §2),
 * byte a byte o que o Build System gravaria (`cli/src/bundle/write.ts`), em JCS. É o que `bundle_url`
 * aponta; o painel o lê pelo protocolo `vnpreview` (`/project/preview/narrative/`).
 */
import { canonicalize } from '../../cli/src/bundle/jcs';
import type { CompiledBundle } from '../../cli/src/bundle/compile';
import type { PatchOp } from '../../cli/src/bundle/incremental';
import { joinPath, type ProjectFs } from '../src/project-manager/fs';
import { PREVIEW_BUNDLE_DIR } from './urls';

/** Que arquivos do bundle um patch toca. */
export function filesTouchedBy(patch: readonly PatchOp[]): Set<string> {
  const files = new Set<string>();
  for (const op of patch) files.add(op.file);
  return files;
}

/**
 * Grava o bundle. Com `only` (os `file` de um patch), grava só esses arquivos, mais `bundle.json`
 * quando o `content_hash` mudou; sem `only`, grava todos e remove os idiomas que saíram do projeto.
 */
export async function writeBundleFiles(fs: ProjectFs, root: string, compiled: CompiledBundle, only?: ReadonlySet<string>): Promise<void> {
  const dir = joinPath(root, PREVIEW_BUNDLE_DIR);
  const wants = (name: string): boolean => !only || only.has(name);
  const put = (name: string, doc: unknown): Promise<void> => fs.writeText(joinPath(dir, name), canonicalize(doc));
  if (wants('licenses.json')) await put('licenses.json', compiled.licenses);
  if (wants('bundle.json')) await put('bundle.json', compiled.bundle);
  for (const [lang, doc] of Object.entries(compiled.locales)) if (wants(`locales/${lang}.json`)) await put(`locales/${lang}.json`, doc);
  if (wants('plugins.json')) await put('plugins.json', compiled.plugins);
  if (!only) {
    const keep = new Set(Object.keys(compiled.locales).map((l) => `${l}.json`));
    const localesDir = joinPath(dir, 'locales');
    if (await fs.exists(localesDir))
      for (const entry of await fs.readDir(localesDir)) if (!entry.isDir && !keep.has(entry.name)) await fs.removeFile(joinPath(localesDir, entry.name));
  }
}
