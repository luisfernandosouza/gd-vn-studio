import { describe, expect, it } from 'vitest';
import type { Scene, Variables } from '@vnstudio/plugin-schema';
import beach from '../../../docs/specs/examples/demo-project/scenes/ch01/scene_beach.json';
import variables from '../../../docs/specs/examples/demo-project/variables.json';
import { outlineScene, variableLabel } from './outline';

describe('outlineScene', () => {
  it('conta os nós por tipo numa cena do projeto de exemplo das specs', () => {
    const o = outlineScene(beach as Scene);
    expect(o.nodeCount).toBe(beach.nodes.length);
    expect(o.nodeTypes.line).toBeGreaterThan(0);
    expect(Object.values(o.nodeTypes).reduce((a, b) => a + (b ?? 0), 0)).toBe(o.nodeCount);
  });
});

describe('variableLabel', () => {
  it('usa o name e cai para a key', () => {
    const [first] = (variables as Variables).global ?? [];
    expect(first).toBeDefined();
    expect(variableLabel(first!)).toBe(first!.name);
    expect(variableLabel({ key: 'x', type: 'boolean' })).toBe('x');
  });
});
