/** Ajudantes dos testes do painel: o projeto de exemplo das specs numa `MemoryFs`. */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MemoryFs } from '../src/project-manager/memory-fs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const COMPILE_BASE = join(REPO, 'docs', 'specs', 'conformance', 'compile', 'base');

/** Copia uma pasta do disco para a `MemoryFs` em `target` (arquivos de texto). */
export function copyIntoMemory(fs: MemoryFs, source: string, target: string): void {
  for (const rel of readdirSync(source, { recursive: true, encoding: 'utf8' })) {
    const abs = join(source, rel);
    if (statSync(abs).isDirectory()) fs.dirs.add(`${target}/${rel.split('\\').join('/')}`);
    else fs.files.set(`${target}/${rel.split('\\').join('/')}`, readFileSync(abs, 'utf8'));
  }
}

export const PROJECT_ROOT = '/demo';
export const PLUGIN_DIR = '/fishing-plugin';

/** O projeto `demo` dos vetores de compilação e o plugin de pesca, prontos para `readProjectInput`. */
export function demoMemoryFs(): MemoryFs {
  const fs = new MemoryFs();
  copyIntoMemory(fs, join(COMPILE_BASE, 'demo-project'), PROJECT_ROOT);
  copyIntoMemory(fs, join(COMPILE_BASE, 'fishing-plugin'), PLUGIN_DIR);
  return fs;
}

export { REPO };
