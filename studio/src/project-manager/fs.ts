/**
 * Acesso ao disco do Project Manager. A interface nunca fala com o disco direto: no app, `tauri-fs.ts`
 * chama os comandos nativos (`src-tauri/src/project_fs.rs`); nos testes, `memory-fs.ts` guarda tudo na memória.
 * Caminhos são absolutos e usam `/` (o Rust aceita `/` também no Windows).
 */
export interface DirEntry {
  name: string;
  isDir: boolean;
}

export interface ProjectFs {
  readText(path: string): Promise<string>;
  /** Grava de forma atômica, criando as pastas que faltarem. */
  writeText(path: string, contents: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  createDir(path: string): Promise<void>;
  /** Entradas diretas da pasta, em ordem de nome. */
  readDir(path: string): Promise<DirEntry[]>;
  /** Apaga um arquivo; arquivo ausente não é erro. */
  removeFile(path: string): Promise<void>;
  copyFile(from: string, to: string): Promise<void>;
}

/** Junta partes de caminho com `/`, tirando barras repetidas (aceita raiz `C:\…` ou `/…`). */
export function joinPath(...parts: string[]): string {
  const cleaned = parts
    .filter((p) => p !== '')
    .map((p, i) => {
      const s = p.replace(/\\/g, '/');
      return i === 0 ? s.replace(/\/+$/, '') : s.replace(/^\/+|\/+$/g, '');
    });
  return cleaned.join('/') || '/';
}

/** Lista recursiva dos arquivos de uma pasta, relativos a ela, em ordem. Pasta ausente dá lista vazia. */
export async function listFilesRecursive(fs: ProjectFs, dir: string, prefix = ''): Promise<string[]> {
  if (!(await fs.exists(dir))) return [];
  const out: string[] = [];
  for (const entry of await fs.readDir(dir)) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDir) out.push(...(await listFilesRecursive(fs, joinPath(dir, entry.name), rel)));
    else out.push(rel);
  }
  return out;
}
