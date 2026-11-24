// Vetores de compilação (conformance/compile/cases.json, spec 08; Build System §5.1), como test_compile.py.
import { describe, expect, it } from 'vitest';
import { materialize, readCases, resolvePointer } from './fixtures.test-util.js';
import { canonicalHash, compileProject, loadProject } from './index.js';

const cases = readCases();

describe('conformance/compile/cases.json', () => {
  it('tem os 8 vetores', () => expect(cases).toHaveLength(8));
  for (const c of cases) {
    it(`${c.id}: ${c.description}`, () => {
      const m = materialize(c);
      try {
        const out = compileProject(loadProject(m.project, { pluginDirs: [m.plugin] }), { edition: c.edition });
        const got = {
          content_hash: out.bundle.content_hash,
          locales: Object.fromEntries(Object.entries(out.locales).map(([k, v]) => [k, canonicalHash(v)])),
          plugins: canonicalHash(out.plugins),
          licenses: canonicalHash(out.licenses),
        };
        const e = c.expect;
        if (e.content_hash) expect(got.content_hash).toBe(e.content_hash);
        if (e.locales) expect(got.locales).toEqual(e.locales);
        if (e.plugins) expect(got.plugins).toBe(e.plugins);
        if (e.licenses) expect(got.licenses).toBe(e.licenses);
        if (e.license_entries) expect(out.licenses.entries).toEqual(e.license_entries);
        for (const p of e.present ?? []) expect(resolvePointer(out.bundle, p), `present ${p}`).not.toBeUndefined();
        for (const p of e.absent ?? []) expect(resolvePointer(out.bundle, p), `absent ${p}`).toBeUndefined();
      } finally {
        m.dispose();
      }
    });
  }
});
