/**
 * Seleção e cópia dos assets de um bundle para a pasta de conteúdo (Build System §5.4, §6.1).
 * Na edição censurada o arquivo original de um asset com `censored.replace_with` ou
 * `censored.hide` nunca é copiado: o bundle já aponta a primeira para a substituta, e a segunda
 * fica só como marca. Porte do `stage` de `docs/specs/tools/compile_bundle.py` (a parte dos assets).
 *
 * `assetFilesFor` é puro; `stageAssets` usa o disco (Node).
 */
import { copyFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import type { Bundle } from '@vnstudio/plugin-schema';
import { codePointCompare } from './compile.js';
import type { JsonObject } from './jcs.js';

const ASSET_ROOT = 'res://vn_content/assets/';

/** Caminhos (relativos a `assets/`) que entram no pacote, sem repetição e em ordem de código. */
export function assetFilesFor(bundle: Bundle): string[] {
  const censored = (bundle.project as unknown as JsonObject & { content_filter: JsonObject }).content_filter.edition === 'censored';
  const out = new Set<string>();
  for (const a of Object.values(bundle.assets as unknown as Record<string, JsonObject>)) {
    const path = String(a.path ?? '');
    if (!path.startsWith(ASSET_ROOT)) continue; // fontes do preset e afins vêm do runtime
    const c = a.censored as JsonObject | undefined;
    if (censored && c && c.hide) continue; // nunca aparece nesta edição
    out.add(path.slice(ASSET_ROOT.length));
  }
  return [...out].sort(codePointCompare);
}

export interface StageResult {
  /** Arquivos copiados. */
  copied: string[];
  /** Caminhos do bundle sem arquivo no projeto (o build avisa; a tarefa de assets decide o resto). */
  missing: string[];
}

/** Copia os assets selecionados de `<projeto>/assets/` para `<saída>/assets/`. */
export function stageAssets(projectRoot: string, out: string, bundle: Bundle): StageResult {
  const copied: string[] = [];
  const missing: string[] = [];
  for (const rel of assetFilesFor(bundle)) {
    const src = join(projectRoot, 'assets', rel);
    if (!existsSync(src) || !statSync(src).isFile()) {
      missing.push(rel);
      continue;
    }
    const dst = join(out, 'assets', rel);
    mkdirSync(dirname(dst), { recursive: true });
    copyFileSync(src, dst);
    copied.push(rel);
  }
  return { copied, missing };
}
