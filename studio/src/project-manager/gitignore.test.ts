import { describe, expect, it } from 'vitest';
import { applyGitignoreBlock, GITIGNORE_BLOCK } from './gitignore';

describe('applyGitignoreBlock (spec 09 §3.4)', () => {
  it('cria o bloco num projeto sem .gitignore', () => {
    expect(applyGitignoreBlock(null)).toBe(`${GITIGNORE_BLOCK}\n`);
    expect(GITIGNORE_BLOCK).toContain('.vnstudio/');
    expect(GITIGNORE_BLOCK).toContain('plugins/*/vn_plugins/*/editor/dist/');
    expect(GITIGNORE_BLOCK).toContain('build/');
  });

  it('acrescenta o bloco sem mexer nas linhas do autor', () => {
    const out = applyGitignoreBlock('*.psd\nnotas/\n');
    expect(out).toBe(`*.psd\nnotas/\n\n${GITIGNORE_BLOCK}\n`);
  });

  it('atualiza um bloco antigo e mantém o que vem depois', () => {
    const old = '*.psd\n\n# Visual Novel Studio\n.vnstudio/\nbuild/\n\n# meu\nrascunhos/\n';
    const out = applyGitignoreBlock(old);
    expect(out).toBe(`*.psd\n\n${GITIGNORE_BLOCK}\n\n# meu\nrascunhos/\n`);
  });

  it('é idempotente e respeita CRLF', () => {
    const once = applyGitignoreBlock('a\r\nb\r\n');
    expect(once).toContain('\r\n# Visual Novel Studio\r\n');
    expect(applyGitignoreBlock(once)).toBe(once);
  });
});
