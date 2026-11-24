/// <reference types="node" />
// @vitest-environment node
/**
 * Aceite do M6-01: "Novo projeto" gera um projeto que passa no validador. Grava o projeto num diretório
 * temporário de verdade e roda o validador de referência (`docs/specs/tools/validate.py`, Req §14),
 * inclusive com `--export`. Sem Python com jsonschema o teste é pulado, exceto na CI
 * (VNSTUDIO_REQUIRE_VALIDATOR=1), onde a falta é erro.
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { promises as nodeFs } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';
import { createProject } from './create';
import type { DirEntry, ProjectFs } from './fs';
import { openProject } from './open';
import { PRODUCT_LOCALES } from './layout';

const VALIDATE = resolve(__dirname, '../../../docs/specs/tools/validate.py');
const PYTHON = process.platform === 'win32' ? 'python' : 'python3';
const hasValidator = spawnSync(PYTHON, ['-c', 'import jsonschema, referencing'], { stdio: 'ignore' }).status === 0;
if (!hasValidator && process.env.VNSTUDIO_REQUIRE_VALIDATOR === '1') {
  throw new Error('VNSTUDIO_REQUIRE_VALIDATOR=1, mas não há Python com jsonschema para rodar validate.py');
}

const diskFs: ProjectFs = {
  readText: (p) => nodeFs.readFile(p, 'utf8'),
  writeText: async (p, text) => {
    await nodeFs.mkdir(resolve(p, '..'), { recursive: true });
    await nodeFs.writeFile(p, text, 'utf8');
  },
  exists: (p) =>
    nodeFs.access(p).then(
      () => true,
      () => false,
    ),
  createDir: async (p) => {
    await nodeFs.mkdir(p, { recursive: true });
  },
  readDir: async (p) =>
    (await nodeFs.readdir(p, { withFileTypes: true }))
      .map((e): DirEntry => ({ name: e.name, isDir: e.isDirectory() }))
      .sort((a, b) => (a.name < b.name ? -1 : 1)),
  removeFile: (p) => nodeFs.rm(p, { force: true }),
  copyFile: async (from, to) => {
    await nodeFs.mkdir(resolve(to, '..'), { recursive: true });
    await nodeFs.copyFile(from, to);
  },
};

const temp: string[] = [];
afterAll(async () => {
  for (const dir of temp) await rm(dir, { recursive: true, force: true });
});

function validate(root: string, ...flags: string[]): string {
  return execFileSync(PYTHON, [VALIDATE, ...flags, root], { encoding: 'utf8' });
}

describe.skipIf(!hasValidator)('Novo projeto passa no validador (aceite do M6-01)', () => {
  it.each(PRODUCT_LOCALES)('idioma-fonte %s', async (locale) => {
    const base = await mkdtemp(join(tmpdir(), 'vnstudio-novo-'));
    temp.push(base);
    const root = join(base, 'Meu Jogo');
    await createProject(diskFs, { root, title: 'Meu Jogo Ação', defaultLocale: locale, authors: ['Luis'] });
    expect(validate(root)).toContain('0 erro(s), 0 aviso(s).');
    expect(validate(root, '--export')).toContain('0 erro(s)');
    const opened = await openProject(diskFs, root);
    expect(opened.status).toBe('opened');
  });
});
