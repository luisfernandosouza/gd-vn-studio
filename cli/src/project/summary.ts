import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import type { Scene, Variable, Variables } from '@vnstudio/plugin-schema';

/** Resumo de um projeto de VN (Data Model §2): o que `vnstudio info` imprime. */
export interface ProjectSummary {
  scenes: { id: Scene['id']; chapter: Scene['chapter']; nodes: number }[];
  variables: { scope: 'global' | 'character'; key: Variable['key']; type: Variable['type'] }[];
}

async function readJson<T>(path: string): Promise<T> {
  return JSON.parse(await readFile(path, 'utf8')) as T;
}

/** Lê `scenes/<capítulo>/*.json` e `variables.json`. Não valida: isso é do validador (M5-01). */
export async function summarizeProject(dir: string): Promise<ProjectSummary> {
  const scenes: ProjectSummary['scenes'] = [];
  const scenesDir = join(dir, 'scenes');
  const files = (await readdir(scenesDir, { recursive: true }))
    .filter((f) => f.endsWith('.json'))
    .sort();
  for (const file of files) {
    const scene = await readJson<Scene>(join(scenesDir, file));
    scenes.push({ id: scene.id, chapter: scene.chapter, nodes: scene.nodes.length });
  }
  const vars = await readJson<Variables>(join(dir, 'variables.json'));
  const variables: ProjectSummary['variables'] = [
    ...(vars.global ?? []).map((v) => ({ scope: 'global' as const, key: v.key, type: v.type })),
    ...(vars.character ?? []).map((v) => ({ scope: 'character' as const, key: v.key, type: v.type })),
  ];
  return { scenes, variables };
}

export function formatSummary(s: ProjectSummary): string {
  const lines = [`${s.scenes.length} cena(s)`];
  for (const sc of s.scenes) lines.push(`  ${sc.id}  capítulo ${sc.chapter ?? '(global)'}  ${sc.nodes} nó(s)`);
  lines.push(`${s.variables.length} variável(is)`);
  for (const v of s.variables) lines.push(`  ${v.scope}.${v.key}  ${v.type}`);
  return lines.join('\n');
}
