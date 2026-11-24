// "Bundle da demo idêntico ao do compilador Python" (aceite do M5-02, Build System §5.1): compila o
// exemplo das specs e os vetores com docs/specs/tools/compile_bundle.py e com este compilador e
// compara os arquivos byte a byte. A validação fica de fora dos dois lados (o validador em TypeScript
// é o M5-01); o que se compara é a compilação. Sem python3 no PATH, o teste é pulado.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';
import { SPECS, materialize, readCases } from './fixtures.test-util.js';
import { compileProject, loadProject, writeBundle } from './index.js';

const hasPython = spawnSync('python3', ['--version']).status === 0;
const tmp = mkdtempSync(join(tmpdir(), 'vn-parity-'));
afterAll(() => rmSync(tmp, { recursive: true, force: true }));

// compile_bundle.py sem o validador (que pede jsonschema): só a compilação e o write de referência
const DRIVER = `
import sys, types
sys.modules["validate"] = types.SimpleNamespace(run=lambda root, dirs: ([], []))
sys.path.insert(0, sys.argv[1])
import compile_bundle as cb
project, out, plugin, edition = sys.argv[2:6]
b, l, p, roots, lic = cb.compile_project(project, [plugin], edition or None)
cb.write(out, b, l, p, lic)
`;

function files(dir: string): Map<string, Buffer> {
  const out = new Map<string, Buffer>();
  for (const f of readdirSync(dir, { recursive: true, encoding: 'utf8' }).sort()) {
    const p = join(dir, f);
    try {
      out.set(relative(dir, p).split('\\').join('/'), readFileSync(p));
    } catch {
      /* pasta */
    }
  }
  return out;
}

let n = 0;
function compare(project: string, plugin: string, edition?: 'standard' | 'censored'): void {
  const py = join(tmp, `py${n}`), ts = join(tmp, `ts${n++}`);
  const r = spawnSync('python3', ['-c', DRIVER, join(SPECS, 'tools'), project, py, plugin, edition ?? ''], { encoding: 'utf8' });
  expect(r.status, r.stderr).toBe(0);
  writeBundle(ts, compileProject(loadProject(project, { pluginDirs: [plugin] }), { edition }));
  const a = files(py), b = files(ts);
  expect([...b.keys()]).toEqual([...a.keys()]);
  for (const [k, v] of a) expect(b.get(k)!.equals(v), `${k} difere do compilador Python`).toBe(true);
}

describe.skipIf(!hasPython)('mesmos bytes que compile_bundle.py', () => {
  const demo = join(SPECS, 'examples', 'demo-project');
  const fishing = join(SPECS, 'examples', 'fishing-plugin');
  it('exemplo das specs (demo), edição completa', () => compare(demo, fishing));
  it('exemplo das specs (demo), edição censurada', () => compare(demo, fishing, 'censored'));
  for (const c of readCases()) {
    it(`vetor ${c.id}`, () => {
      const m = materialize(c);
      try {
        compare(m.project, m.plugin, c.edition);
      } finally {
        m.dispose();
      }
    });
  }
});
