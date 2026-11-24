/**
 * Paridade com o validador de referência (Req §14, critério de aceite da M5-01): os 143 casos de
 * `docs/specs/tools/test_validate.py` mais o projeto de exemplo sem alterações.
 *
 * `cli/scripts/validate_parity.py` monta cada caso e grava o que `validate.py` acusa; aqui o validador
 * TypeScript roda nas mesmas pastas. Os diagnósticos têm de ser os mesmos, com o mesmo texto técnico.
 * Só S000 e P004 (erros de JSON Schema) comparam código e local, porque o texto vem da biblioteca de
 * JSON Schema de cada linguagem (`jsonschema` no Python, Ajv aqui, com mensagens em português).
 *
 * Precisa de Python 3 com `jsonschema` (`pip install 'jsonschema>=4.18'`, como na workflow das specs). Sem ele, o teste é
 * pulado, a não ser com VN_PARITY_REQUIRED=1 (como na CI), quando falha.
 */
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { formatDiagnostic, validateProject } from './validator.js';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const SCRIPT = path.join(REPO, 'cli', 'scripts', 'validate_parity.py');
const SCHEMA_CODES = new Set(['S000', 'P004']);
// códigos que, sem --export, são avisos (mesma regra de test_validate.py)
const WARN_U = new Set(['U007', 'U008', 'U009', 'U010', 'U011', 'U013', 'U014']);

interface Case {
  code: string | null;
  desc: string;
  export: boolean;
  project: string;
  plugins: string[];
  errors: string[];
  warnings: string[];
}

function loadCases(): Case[] | string {
  let manifest = process.env.VN_PARITY_MANIFEST;
  if (!manifest) {
    const out = mkdtempSync(path.join(tmpdir(), 'vn-parity-'));
    try {
      execFileSync('python3', [SCRIPT, out], { stdio: 'pipe' });
    } catch (e) {
      return `não deu para rodar validate_parity.py (Python 3 com jsonschema): ${(e as Error).message.split('\n')[0]}`;
    }
    manifest = path.join(out, 'manifest.json');
  }
  return (JSON.parse(readFileSync(manifest, 'utf8')) as { cases: Case[] }).cases;
}

/** S000/P004: só `[código] onde`; os demais, a linha inteira. Em ordem, para comparar como multiconjunto. */
function normalize(lines: string[]): string[] {
  return lines
    .map((l) => {
      const m = /^\[(\w+)\] /.exec(l);
      if (!m || !SCHEMA_CODES.has(m[1]!)) return l;
      // S000: "[S000] <arquivo>: <caminho>: <msg>"; P004: "[P004] <onde>: <prefixo>: <msg>"
      const rest = l.slice(m[0].length);
      const where = m[1] === 'S000' ? rest.slice(0, rest.indexOf('.json') + 5) : rest.slice(0, rest.indexOf(': '));
      return `[${m[1]}] ${where}`;
    })
    .filter((l, i, all) => !/^\[(S000|P004)\] /.test(l) || all.indexOf(l) === i)
    .sort();
}

const cases = loadCases();
const skip = typeof cases === 'string';
if (skip && process.env.VN_PARITY_REQUIRED === '1') throw new Error(cases);

describe.skipIf(skip)('paridade com validate.py (test_validate.py)', () => {
  const list = skip ? [] : cases;
  it('tem os 144 casos do critério de aceite', () => {
    expect(list.length).toBe(144);
  });
  for (const c of list) {
    const name = `${c.code ?? 'limpo'} ${c.desc}${c.export ? ' (--export)' : ''}`;
    it(name, () => {
      const r = validateProject(c.project, c.plugins, { export: c.export });
      const errors = r.errors.map(formatDiagnostic);
      const warnings = r.warnings.map(formatDiagnostic);
      expect({ errors: normalize(errors), warnings: normalize(warnings) }).toEqual({
        errors: normalize(c.errors),
        warnings: normalize(c.warnings),
      });
      if (c.code === null) {
        expect(errors.length + warnings.length).toBe(0);
      } else {
        const bucket = c.export || !(c.code.startsWith('W') || WARN_U.has(c.code)) ? errors : warnings;
        expect(bucket.some((m) => m.startsWith(`[${c.code}]`))).toBe(true);
      }
      for (const d of [...r.errors, ...r.warnings]) expect(d.message.length).toBeGreaterThan(0);
    });
  }
});
