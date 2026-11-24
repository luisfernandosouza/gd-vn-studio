import { describe, expect, it } from 'vitest';
import { slugify, uniqueName, uuidv7 } from './ids';

const ENTITY_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe('uuidv7', () => {
  it('segue o formato EntityId e a versão 7', () => {
    const id = uuidv7();
    expect(id).toMatch(ENTITY_ID);
    expect(id[14]).toBe('7');
  });

  it('é ordenado pelo momento da criação (Data Model §3)', () => {
    const a = uuidv7(1_700_000_000_000, new Uint8Array(10).fill(255));
    const b = uuidv7(1_700_000_000_001, new Uint8Array(10));
    expect(a < b).toBe(true);
    expect(a.slice(0, 13)).toBe('018bcfe5-6800');
  });
});

describe('slugify', () => {
  it('tira acentos, usa minúsculas e _ (Req §2)', () => {
    expect(slugify('Verão na Praia!')).toBe('verao_na_praia');
    expect(slugify('  Capítulo 1 ')).toBe('capitulo_1');
  });

  it('sempre começa com letra e cabe em 64 caracteres', () => {
    expect(slugify('1999')).toBe('projeto_1999');
    expect(slugify('物語')).toBe('projeto');
    expect(slugify('a'.repeat(100))).toHaveLength(64);
  });

  it('acrescenta sufixo numérico quando já existe', () => {
    expect(uniqueName('alice', ['alice', 'alice_2'])).toBe('alice_3');
    expect(uniqueName('bob', ['alice'])).toBe('bob');
  });
});
