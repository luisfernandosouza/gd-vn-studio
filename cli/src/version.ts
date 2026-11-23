import { readFileSync } from 'node:fs';

/** Versão do pacote da CLI (tag `cli-v<versão>`, spec 09 §1). */
export const CLI_VERSION: string = (
  JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')) as { version: string }
).version;
