import { joinPath, type DirEntry, type ProjectFs } from './fs';

/** ProjectFs na memória, para testes e para a interface fora do Tauri. */
export class MemoryFs implements ProjectFs {
  readonly files = new Map<string, string>();
  readonly dirs = new Set<string>();

  private norm(path: string): string {
    return joinPath(path);
  }

  private addParents(path: string): void {
    const parts = this.norm(path).split('/');
    for (let i = 1; i < parts.length; i++) {
      const dir = parts.slice(0, i).join('/');
      if (dir) this.dirs.add(dir);
    }
  }

  async readText(path: string): Promise<string> {
    const text = this.files.get(this.norm(path));
    if (text === undefined) throw new Error(`${path}: arquivo não encontrado`);
    return text;
  }

  async writeText(path: string, contents: string): Promise<void> {
    this.addParents(path);
    this.files.set(this.norm(path), contents);
  }

  async exists(path: string): Promise<boolean> {
    const p = this.norm(path);
    return this.files.has(p) || this.dirs.has(p);
  }

  async createDir(path: string): Promise<void> {
    this.addParents(path);
    this.dirs.add(this.norm(path));
  }

  async readDir(path: string): Promise<DirEntry[]> {
    const p = this.norm(path);
    if (!this.dirs.has(p)) throw new Error(`${path}: pasta não encontrada`);
    const names = new Map<string, boolean>();
    const prefix = `${p}/`;
    for (const f of this.files.keys()) if (f.startsWith(prefix) && !f.slice(prefix.length).includes('/')) names.set(f.slice(prefix.length), false);
    for (const d of this.dirs) if (d.startsWith(prefix) && !d.slice(prefix.length).includes('/')) names.set(d.slice(prefix.length), true);
    return [...names].map(([name, isDir]) => ({ name, isDir })).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  }

  async removeFile(path: string): Promise<void> {
    this.files.delete(this.norm(path));
  }

  async copyFile(from: string, to: string): Promise<void> {
    await this.writeText(to, await this.readText(from));
  }
}
