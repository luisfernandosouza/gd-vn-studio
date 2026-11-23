import type { Node, Scene, Variable } from '@vnstudio/plugin-schema';

/**
 * Resumos de cena e de variável para listas do Studio. Os tipos vêm de @vnstudio/plugin-schema,
 * gerados de docs/specs/schemas/ (spec 09 §1): o Studio não declara à mão a forma dos dados.
 */
export interface SceneOutline {
  id: Scene['id'];
  title: string;
  nodeCount: number;
  /** Quantos nós de cada tipo (Data Model §4), na ordem em que aparecem. */
  nodeTypes: Partial<Record<Node['type'], number>>;
}

export function outlineScene(scene: Scene): SceneOutline {
  const nodeTypes: SceneOutline['nodeTypes'] = {};
  for (const node of scene.nodes) nodeTypes[node.type] = (nodeTypes[node.type] ?? 0) + 1;
  return { id: scene.id, title: scene.title ?? scene.id, nodeCount: scene.nodes.length, nodeTypes };
}

/** Rótulo de uma variável no Studio: o `name` (Data Model §3), ou a `key` se não houver. */
export function variableLabel(variable: Variable): string {
  return variable.name?.trim() || variable.key;
}
