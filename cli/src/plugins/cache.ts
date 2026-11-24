import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { integrityMatches } from './integrity.js';

/** `~/.vnstudio/cache/plugins/` (Build System §10.2). */
export function defaultPluginCacheRoot(): string {
  return join(homedir(), '.vnstudio', 'cache', 'plugins');
}

/**
 * Cache de pacotes de plugins: `<raiz>/<id>/<versão>/<id>-<versão>.vnplugin`. A chave é o `integrity`:
 * um arquivo com hash diferente do pedido é apagado, e quem chama baixa de novo (BS §10.2).
 */
export class PluginCache {
  constructor(readonly root: string = defaultPluginCacheRoot()) {}

  path(id: string, version: string): string {
    return join(this.root, id, version, `${id}-${version}.vnplugin`);
  }

  /** O pacote, se estiver no cache e (quando `integrity` é dado) com o hash certo. */
  async get(id: string, version: string, integrity?: string): Promise<Buffer | undefined> {
    const file = this.path(id, version);
    const data = await readFile(file).catch(() => undefined);
    if (!data) return undefined;
    if (integrity && !integrityMatches(data, integrity)) {
      await rm(file, { force: true });
      return undefined;
    }
    return data;
  }

  /** Grava de forma atômica (arquivo temporário + rename), para um build interrompido não deixar meio pacote. */
  async put(id: string, version: string, data: Uint8Array): Promise<string> {
    const file = this.path(id, version);
    await mkdir(dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.${Date.now()}.tmp`;
    await writeFile(tmp, data);
    await rename(tmp, file);
    return file;
  }
}
