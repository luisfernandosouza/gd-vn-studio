// M5-04: idiomas do build (BS §5.3) e edição censurada sem os originais (BS §5.4, §6.1).
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { runCompile } from './cli.js';
import { materialize, type CompileCase } from './fixtures.test-util.js';
import { assetFilesFor, compileProject, loadProject, stageAssets } from './index.js';

const base: CompileCase = { id: 'x', description: '', expect: {} };
function build(edits: CompileCase['edits'], edition?: 'standard' | 'censored') {
  const m = materialize({ ...base, edits });
  const out = compileProject(loadProject(m.project, { pluginDirs: [m.plugin] }), { edition });
  return { m, out };
}

describe('build.locales (BS §5.3)', () => {
  it('sem build.locales entram todos os idiomas', () => {
    const { m, out } = build([]);
    expect(Object.keys(out.locales)).toEqual(['pt-BR', 'en']);
    m.dispose();
  });
  it('build.locales limita os arquivos de idioma e project.locales', () => {
    const { m, out } = build([{ file: 'project.json', pointer: '/build/locales', value: ['pt-BR'] }]);
    expect(Object.keys(out.locales)).toEqual(['pt-BR']);
    expect((out.bundle.project as unknown as { locales: string[] }).locales).toEqual(['pt-BR']);
    m.dispose();
  });
  it('mantém a ordem de project.locales e o default_locale', () => {
    const { m, out } = build([{ file: 'project.json', pointer: '/build/locales', value: ['en', 'pt-BR'] }]);
    expect(Object.keys(out.locales)).toEqual(['pt-BR', 'en']);
    m.dispose();
  });
  it('o content_hash muda com a lista de idiomas', () => {
    const a = build([]), b = build([{ file: 'project.json', pointer: '/build/locales', value: ['pt-BR'] }]);
    expect(a.out.bundle.content_hash).not.toBe(b.out.bundle.content_hash);
    a.m.dispose();
    b.m.dispose();
  });
});

describe('edição censurada sem os originais (BS §5.4, §6.1)', () => {
  it('a substituta entra e o original não', () => {
    const std = build([]);
    const cen = build([], 'censored');
    expect(assetFilesFor(std.out.bundle)).toContain('backgrounds/noraneko/Train_Evening.png');
    const files = assetFilesFor(cen.out.bundle);
    expect(files).not.toContain('backgrounds/noraneko/Train_Evening.png');
    expect(files).toContain('backgrounds/noraneko/train_evening_safe.png');
    std.m.dispose();
    cen.m.dispose();
  });
  it('censored.hide: o arquivo não é copiado e a marca fica sem galeria', () => {
    const edits: CompileCase['edits'] = [{ file: 'assets.json', pointer: '/assets/bg~1sitting_room/censored', value: { hide: true } }];
    const std = build(edits);
    const cen = build(edits, 'censored');
    expect(assetFilesFor(std.out.bundle)).toContain('backgrounds/noraneko/Sitting_Room.png');
    expect(assetFilesFor(cen.out.bundle)).not.toContain('backgrounds/noraneko/Sitting_Room.png');
    std.m.dispose();
    cen.m.dispose();
  });
  it('stageAssets copia só o que entra no pacote', () => {
    const m = materialize({ ...base, edits: [] });
    const out = mkdtempSync(join(tmpdir(), 'vn-stage-'));
    try {
      // o projeto congelado não traz os binários: cria os dois para ver qual é copiado
      for (const rel of ['Train_Evening.png', 'train_evening_safe.png']) {
        const dir = join(m.project, 'assets', 'backgrounds', 'noraneko');
        require_mk(dir, rel);
      }
      const { bundle } = compileProject(loadProject(m.project, { pluginDirs: [m.plugin] }), { edition: 'censored' });
      const r = stageAssets(m.project, out, bundle);
      expect(r.copied).toEqual(['backgrounds/noraneko/train_evening_safe.png']);
      expect(existsSync(join(out, 'assets/backgrounds/noraneko/Train_Evening.png'))).toBe(false);
      expect(r.missing).not.toContain('backgrounds/noraneko/Train_Evening.png');
    } finally {
      rmSync(out, { recursive: true, force: true });
      m.dispose();
    }
  });
});

function require_mk(dir: string, name: string): void {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, name), 'x');
}

describe('vnstudio compile', () => {
  it('--edition censored --stage e idiomas do build', () => {
    const m = materialize({ ...base, edits: [{ file: 'project.json', pointer: '/build/locales', value: ['pt-BR'] }] });
    const out = mkdtempSync(join(tmpdir(), 'vn-cli-'));
    try {
      const lines: string[] = [];
      const code = runCompile(['--edition', 'censored', m.project, out, m.plugin], (s) => lines.push(s), () => undefined);
      expect(code, lines.join('\n')).toBe(0);
      expect(readdirSync(join(out, 'locales'))).toEqual(['pt-BR.json']);
    } finally {
      rmSync(out, { recursive: true, force: true });
      m.dispose();
    }
  });
  it('edição inválida é erro de uso', () => {
    expect(runCompile(['--edition', 'x', 'a', 'b'], () => undefined, () => undefined)).toBe(2);
  });
});
