import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { sriSha256 } from './integrity.js';
import { isExcludedFromPackage, packPluginFolder, readPackageManifest } from './pack.js';
import { readZip, writeZip } from './zip.js';

describe('ZIP reprodutível (Plugin SDK §2.2)', () => {
  it('ordena as entradas, fixa a data e lê de volta', () => {
    const a = writeZip([
      { path: 'runtime/b.gd', data: Buffer.from('b') },
      { path: 'plugin.json', data: Buffer.from('{"id":"x"}') },
    ]);
    const b = writeZip([
      { path: 'plugin.json', data: Buffer.from('{"id":"x"}') },
      { path: 'runtime/b.gd', data: Buffer.from('b') },
    ]);
    expect(sriSha256(a)).toBe(sriSha256(b));
    const entries = readZip(a);
    expect(entries.map((e) => e.path)).toEqual(['plugin.json', 'runtime/b.gd']);
    expect(Buffer.from(entries[1]!.data).toString()).toBe('b');
    // data DOS 1980-01-01 no cabeçalho local
    expect(a.readUInt16LE(12)).toBe(0x21);
  });

  it('recusa o que não é ZIP', () => {
    expect(() => readZip(Buffer.from('nada'))).toThrow(/ZIP/);
  });

  it('exclui os arquivos do ambiente de desenvolvimento (SDK §2.1)', () => {
    for (const p of ['project.godot', 'override.cfg', '.godot/x', 'runtime/a.png.import', 'addons/x/y.gd', 'sandbox/s.tscn', '.vnplugin/godot.json', 'editor/node_modules/a.js']) {
      expect(isExcludedFromPackage(p), p).toBe(true);
    }
    for (const p of ['plugin.json', 'runtime/src/a.gd', 'editor/dist/index.js', 'tests/runtime/t.gd', 'README.md']) {
      expect(isExcludedFromPackage(p), p).toBe(false);
    }
  });

  it('empacota uma pasta com o mesmo hash a cada vez', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'vnpack-'));
    await mkdir(join(dir, 'runtime', 'src'), { recursive: true });
    await mkdir(join(dir, 'editor', 'node_modules'), { recursive: true });
    await writeFile(join(dir, 'plugin.json'), JSON.stringify({ id: 'acme.quiz', version: '1.0.0' }));
    await writeFile(join(dir, 'runtime', 'src', 'quiz.gd'), 'extends Node\n');
    await writeFile(join(dir, 'runtime', 'src', 'quiz.gd.import'), 'x');
    await writeFile(join(dir, 'editor', 'node_modules', 'dep.js'), 'x');
    const one = await packPluginFolder(dir);
    const two = await packPluginFolder(dir);
    expect(sriSha256(one)).toBe(sriSha256(two));
    expect(readZip(one).map((e) => e.path)).toEqual(['plugin.json', 'runtime/src/quiz.gd']);
    expect(readPackageManifest(one).id).toBe('acme.quiz');
  });
});
