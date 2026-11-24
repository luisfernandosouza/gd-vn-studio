import { describe, expect, it } from 'vitest';
import { fnmatchcase, parseJson, PyFloat, pyFloat, pyRepr, splitlines, truthy } from './py.js';
import { satisfies } from './semver.js';
import { KNOWN_CODES, plainMessage } from './messages.js';

describe('semântica do Python usada pelo validador', () => {
  it('JSON distingue 2 (int) de 2.0 (float)', () => {
    const d = parseJson('{"a": 2, "b": 2.0, "c": 2.5, "d": 1e3, "__proto__": {"x": 1}}');
    expect(d.a).toBe(2);
    expect(d.b).toBeInstanceOf(PyFloat);
    expect(d.c).toBe(2.5);
    expect(d.d).toBeInstanceOf(PyFloat);
    expect(Object.keys(d)).toEqual(['a', 'b', 'c', 'd', '__proto__']);
    expect(() => parseJson('{"a": }')).toThrow(/linha 1/);
  });
  it('repr() como o Python', () => {
    expect(pyRepr([true, null, 3, new PyFloat(30), 0.1, new PyFloat(1e16), 1.5e-5, 'it\'s', 'a'])).toBe(
      `[True, None, 3, 30.0, 0.1, 1e+16, 1.5e-05, "it's", 'a']`,
    );
    expect(pyRepr({ var: 'global.x' })).toBe("{'var': 'global.x'}");
  });
  it('verdade, float(), fnmatch e splitlines', () => {
    expect([[], {}, '', 0, new PyFloat(0), null].map(truthy)).toEqual([false, false, false, false, false, false]);
    expect([pyFloat(' 1_0.5 '), pyFloat('inf'), pyFloat('azul')]).toEqual([10.5, Infinity, null]);
    expect(fnmatchcase('global.fishing_skill', 'global.*')).toBe(true);
    expect(fnmatchcase('global.x', 'global.[!x]')).toBe(false);
    expect(splitlines('a\r\nb\n')).toEqual(['a', 'b']);
  });
  it('faixas SemVer', () => {
    expect(satisfies('1.2.3', '^1.0.0')).toBe(true);
    expect(satisfies('2.0.0', '^1.0.0')).toBe(false);
    expect(satisfies('0.1.5', '~0.1.0 || >=3')).toBe(true);
    expect(satisfies('1.0.0-beta', '>=1.0.0')).toBe(false);
  });
  it('todo código tem frase simples (Req §6)', () => {
    expect(KNOWN_CODES.length).toBeGreaterThanOrEqual(90);
    expect(plainMessage('R004', 'scenes/a.json#n1', 'x', { asset: 'bg/praia' })).toBe(
      'A imagem ou som "bg/praia" usado em scenes/a.json#n1 não está mais no projeto.',
    );
  });
});
