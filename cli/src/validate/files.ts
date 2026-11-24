/** Leitura de arquivos e listagem de pastas na mesma ordem que o `pathlib` do validador de referência. */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { cmpStr, parseJson, type J } from './py.js';

export function isFile(p: string): boolean {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
}
export function isDir(p: string): boolean {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
}
export { existsSync as exists };

/** Texto do arquivo com as quebras de linha normalizadas (como `read_text` do Python). */
export function readText(p: string): string {
  return readFileSync(p, 'utf8').replace(/\r\n?/g, '\n');
}
export function loadJson(p: string): J {
  return parseJson(readFileSync(p, 'utf8'));
}

/** Ordem de `sorted()` em objetos `Path`: parte a parte. */
export function cmpPath(a: string, b: string): number {
  const pa = a.split(/[\\/]+/);
  const pb = b.split(/[\\/]+/);
  for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
    const c = cmpStr(pa[i]!, pb[i]!);
    if (c) return c;
  }
  return pa.length - pb.length;
}

function entries(dir: string): string[] {
  try {
    return readdirSync(dir);
  } catch {
    return [];
  }
}

/** `sorted(dir.glob("*<ext>"))`, só arquivos. */
export function globFiles(dir: string, ext: string): string[] {
  return entries(dir)
    .filter((n) => n.endsWith(ext))
    .map((n) => path.join(dir, n))
    .filter(isFile)
    .sort(cmpPath);
}

/** `sorted(dir.rglob("*"))` com filtro, só arquivos. */
export function rglobFiles(dir: string, accept: (name: string) => boolean = () => true): string[] {
  const out: string[] = [];
  const walk = (d: string) => {
    for (const n of entries(d)) {
      const p = path.join(d, n);
      let st;
      try {
        st = statSync(p);
      } catch {
        continue;
      }
      if (st.isDirectory()) walk(p);
      else if (st.isFile() && accept(n)) out.push(p);
    }
  };
  walk(dir);
  return out.sort(cmpPath);
}

/** Caminho relativo com `/`, como `str(p.relative_to(root))` no Linux. */
export function rel(root: string, p: string): string {
  return path.relative(root, p).split(path.sep).join('/');
}
