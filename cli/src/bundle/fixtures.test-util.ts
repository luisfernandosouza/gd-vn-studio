// Ajudantes dos testes do compilador (não entram no build: ver tsconfig.build.json).
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { unescapePointer } from './incremental.js';

export const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
export const SPECS = join(REPO, 'docs', 'specs');
export const COMPILE_BASE = join(SPECS, 'conformance', 'compile', 'base');

export interface Edit {
  file: string;
  pointer: string;
  value?: unknown;
}

export interface CompileCase {
  id: string;
  description: string;
  project?: string;
  edition?: 'standard' | 'censored';
  edits?: Edit[];
  expect: {
    content_hash?: string;
    locales?: Record<string, string>;
    plugins?: string;
    licenses?: string;
    license_entries?: unknown[];
    present?: string[];
    absent?: string[];
  };
}

export function readCases(): CompileCase[] {
  return (JSON.parse(readFileSync(join(SPECS, 'conformance', 'compile', 'cases.json'), 'utf8')) as { cases: CompileCase[] }).cases;
}

/** Mesma troca de test_compile.py: JSON Pointer com setdefault nos objetos e insert nas listas. */
export function applyEdit(root: string, e: Edit): void {
  const p = join(root, e.file);
  const doc = JSON.parse(readFileSync(p, 'utf8')) as Record<string, unknown>;
  const toks = e.pointer.split('/').slice(1).map(unescapePointer);
  let cur: any = doc;
  for (const t of toks.slice(0, -1)) cur = Array.isArray(cur) ? cur[Number(t)] : (cur[t] ??= {});
  const last = toks[toks.length - 1]!;
  if ('value' in e) {
    if (Array.isArray(cur)) cur.splice(last === '-' ? cur.length : Number(last), 0, e.value);
    else cur[last] = e.value;
  } else if (Array.isArray(cur)) cur.splice(Number(last), 1);
  else delete cur[last];
  writeFileSync(p, JSON.stringify(doc, null, 2), 'utf8');
}

/** Copia o projeto congelado e o plugin para uma pasta temporária e aplica as trocas do caso. */
export function materialize(c: CompileCase): { project: string; plugin: string; dispose: () => void } {
  const tmp = mkdtempSync(join(tmpdir(), 'vn-compile-'));
  const project = join(tmp, 'demo');
  const plugin = join(tmp, 'fishing');
  cpSync(join(COMPILE_BASE, c.project ?? 'demo-project'), project, { recursive: true });
  cpSync(join(COMPILE_BASE, 'fishing-plugin'), plugin, { recursive: true });
  for (const e of c.edits ?? []) applyEdit(project, e);
  return { project, plugin, dispose: () => rmSync(tmp, { recursive: true, force: true }) };
}

export function resolvePointer(doc: unknown, pointer: string): unknown {
  let cur: any = doc;
  for (const t of pointer.split('/').slice(1).map(unescapePointer)) {
    if (Array.isArray(cur)) cur = /^\d+$/.test(t) && Number(t) < cur.length ? cur[Number(t)] : undefined;
    else if (cur && typeof cur === 'object') cur = cur[t];
    else return undefined;
    if (cur === undefined || cur === null) return undefined;
  }
  return cur;
}
