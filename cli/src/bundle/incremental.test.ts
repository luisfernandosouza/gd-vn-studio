// Regra de equivalência incremental (Build System §5.1, Preview Protocol §3): para cada vetor de
// compilação, recompilar entidade por entidade e aplicar o patch sobre o bundle do caso-base dá o
// mesmo bundle que compilar tudo de novo. O que só muda na recarga completa é apontado no plano.
import { describe, expect, it } from 'vitest';
import { materialize, readCases } from './fixtures.test-util.js';
import {
  type CompiledBundle,
  applyPatch,
  canonicalize,
  compileProject,
  createContext,
  compileUi,
  loadProject,
  planReload,
  rehash,
} from './index.js';

const cases = readCases();

function compileCase(id: string): { compiled: CompiledBundle; input: ReturnType<typeof loadProject>; edition?: 'standard' | 'censored' } {
  const c = cases.find((x) => x.id === id)!;
  const m = materialize(c);
  try {
    const input = loadProject(m.project, { pluginDirs: [m.plugin] });
    return { compiled: compileProject(input, { edition: c.edition }), input, edition: c.edition };
  } finally {
    m.dispose();
  }
}

const base = compileCase('demo');

describe('equivalência incremental sobre o caso demo', () => {
  for (const c of cases) {
    it(c.id, () => {
      const target = compileCase(c.id);
      const plan = planReload(base.compiled, target.input, { edition: c.edition });
      let got = applyPatch(base.compiled, plan.patch);
      // o que o patch não cobre é exatamente o que o plano manda recarregar por completo
      const b = got.bundle as unknown as Record<string, unknown>;
      const t = target.compiled.bundle as unknown as Record<string, unknown>;
      const fullParts = ['project', 'variables', 'aliases', 'format_version', 'bundle_version'].filter(
        (k) => canonicalize(b[k]) !== canonicalize(t[k]),
      );
      expect(plan.fullReload.filter((r) => r.startsWith('bundle.json')).sort()).toEqual(fullParts.map((k) => `bundle.json /${k}`).sort());
      if (canonicalize(base.compiled.plugins) !== canonicalize(target.compiled.plugins)) expect(plan.fullReload).toContain('plugins.json');
      for (const k of fullParts) b[k] = structuredClone(t[k]);
      if (plan.fullReload.includes('idiomas')) got.locales = structuredClone(target.compiled.locales);
      expect(plan.fullReload.includes('idiomas')).toBe(canonicalize(Object.keys(base.compiled.locales)) !== canonicalize(Object.keys(target.compiled.locales)));
      got = rehash(got);
      expect(canonicalize(got.bundle)).toBe(canonicalize(target.compiled.bundle));
      expect(canonicalize(got.locales)).toBe(canonicalize(target.compiled.locales));
      expect(canonicalize(got.licenses)).toBe(canonicalize(target.compiled.licenses));
      if (c.id === 'demo') expect(plan.patch).toEqual([]);
    });
  }

  it('uma cena editada vira uma troca só, sem recarga completa', () => {
    const input = structuredClone(base.input);
    const scene = input.scenes[0]!;
    (scene.nodes as Record<string, unknown>[])[0]!.speaker = 'narrador_editado';
    const plan = planReload(base.compiled, input);
    expect(plan.fullReload).toEqual([]);
    expect(plan.patch.map((p) => p.pointer)).toEqual([`/scenes/${String(scene.id)}`]);
    const got = rehash(applyPatch(base.compiled, plan.patch));
    expect(canonicalize(got.bundle)).toBe(canonicalize(compileProject(input).bundle));
  });

  it('cena e tela removidas saem sem value', () => {
    const input = structuredClone(base.input);
    const removed = input.scenes.pop()!;
    input.screens = input.screens.filter(([id]) => id !== 'credits');
    const plan = planReload(base.compiled, input);
    expect(plan.patch).toContainEqual({ file: 'bundle.json', pointer: `/scenes/${String(removed.id)}` });
    const presetHasCredits = Object.keys(compileUi(createContext(input))).includes('credits');
    const got = rehash(applyPatch(base.compiled, plan.patch));
    expect(canonicalize(got.bundle)).toBe(canonicalize(compileProject(input).bundle));
    expect(presetHasCredits).toBe(true); // a tela do preset volta no lugar da do projeto
  });

  it('applyPatch recusa trocas fora das entidades', () => {
    expect(() => applyPatch(base.compiled, [{ file: 'bundle.json', pointer: '/project', value: {} }])).toThrow(/full_reload_required/);
  });
});
