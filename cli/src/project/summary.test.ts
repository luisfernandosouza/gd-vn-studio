import { describe, expect, it } from 'vitest';
import { fileURLToPath } from 'node:url';
import { formatSummary, summarizeProject } from './summary.js';

const DEMO = fileURLToPath(new URL('../../../docs/specs/examples/demo-project', import.meta.url));

describe('summarizeProject', () => {
  it('lê as cenas e as variáveis do projeto de exemplo das specs', async () => {
    const s = await summarizeProject(DEMO);
    expect(s.scenes.length).toBeGreaterThan(0);
    expect(s.scenes.every((sc) => sc.nodes > 0)).toBe(true);
    expect(s.variables.length).toBeGreaterThan(0);
    expect(formatSummary(s)).toContain('cena(s)');
  });
});
