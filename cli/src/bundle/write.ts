/**
 * Grava a forma canônica (RT §2) numa pasta, em JCS, como o `write` de `compile_bundle.py`:
 * `bundle.json`, `locales/<idioma>.json`, `plugins.json` e `licenses.json`.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { CompiledBundle } from './compile.js';
import { canonicalize } from './jcs.js';

export function writeBundle(out: string, compiled: CompiledBundle): void {
  mkdirSync(join(out, 'locales'), { recursive: true });
  writeFileSync(join(out, 'licenses.json'), canonicalize(compiled.licenses), 'utf8');
  writeFileSync(join(out, 'bundle.json'), canonicalize(compiled.bundle), 'utf8');
  for (const [lang, doc] of Object.entries(compiled.locales))
    writeFileSync(join(out, 'locales', `${lang}.json`), canonicalize(doc), 'utf8');
  writeFileSync(join(out, 'plugins.json'), canonicalize(compiled.plugins), 'utf8');
}
