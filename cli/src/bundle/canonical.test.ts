// Vetores de JCS e HMAC (conformance/canonical.json, spec 08; Build System §5.1 e §8.3).
import { createHash, createHmac, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { SPECS } from './fixtures.test-util.js';
import { base64, canonicalize, fromHex, hmacSha256, saveIntegrity, sha256, sri } from './index.js';

interface Case {
  id: string;
  kind: 'canonical' | 'hmac';
  json: string;
  key?: string;
  expect: { text?: string; hash?: string; integrity?: string };
}
const cases = (JSON.parse(readFileSync(join(SPECS, 'conformance', 'canonical.json'), 'utf8')) as { cases: Case[] }).cases;

describe('conformance/canonical.json', () => {
  it('tem os 7 vetores', () => expect(cases).toHaveLength(7));
  for (const c of cases) {
    it(c.id, () => {
      const doc = JSON.parse(c.json) as Record<string, unknown>;
      if (c.kind === 'canonical') {
        const text = canonicalize(doc);
        expect(text).toBe(c.expect.text);
        expect(sri(new TextEncoder().encode(text))).toBe(c.expect.hash);
      } else {
        expect(saveIntegrity(doc, fromHex(c.key!))).toBe(c.expect.integrity);
      }
    });
  }
});

describe('SHA-256 e HMAC em TypeScript puro', () => {
  it('batem com node:crypto em vários tamanhos', () => {
    for (const n of [0, 1, 55, 56, 63, 64, 65, 119, 120, 1000, 100_000]) {
      const data = randomBytes(n);
      expect(base64(sha256(data))).toBe(createHash('sha256').update(data).digest('base64'));
      for (const k of [0, 32, 64, 65, 200]) {
        const key = randomBytes(k);
        expect(base64(hmacSha256(key, data))).toBe(createHmac('sha256', key).update(data).digest('base64'));
      }
    }
  });
  it('recusa números não finitos', () => {
    expect(() => canonicalize([Number.NaN])).toThrow();
    expect(() => canonicalize({ a: Infinity })).toThrow();
  });
});
