/**
 * `build_config.gd` (Build System §4.4): as constantes que o runtime lê de `res://vn_runtime/build_config.gd`
 * (`VNBuildConfig`). Puro (sem Node).
 */
import { gdString } from './godot-project.js';

export interface BuildConfigInput {
  buildId: string;
  /** `sha256-<base64>` do `bundle.json`. */
  contentHash: string;
  /** Caminho de cada `.vnb`, relativo a `vn_content/` → `sha256-<base64>` do seu JSON canônico (§8.2). */
  contentHashes: Record<string, string>;
  runtimeVersion: string;
  debug: boolean;
  /** Chaves em base64 (32 bytes). Vazias em debug: o runtime usa a chave fixa de debug (§11.1). */
  contentKey?: string;
  saveKey?: string;
  saveTamperPolicy: 'ignore' | 'flag' | 'reject';
}

export function generateBuildConfig(c: BuildConfigInput): string {
  const hashes = Object.keys(c.contentHashes)
    .sort()
    .map((k) => `\t${gdString(k)}: ${gdString(c.contentHashes[k]!)},`);
  return [
    '# Gerado pelo Build System (Build System §4.4). Não edite.',
    'extends RefCounted',
    '',
    `const BUILD_ID = ${gdString(c.buildId)}`,
    `const CONTENT_HASH = ${gdString(c.contentHash)}`,
    'const CONTENT_HASHES = {',
    ...hashes,
    '}',
    `const RUNTIME_VERSION = ${gdString(c.runtimeVersion)}`,
    `const DEBUG_BUILD = ${c.debug ? 'true' : 'false'}`,
    `const CONTENT_KEY = ${gdString(c.contentKey ?? '')}`,
    `const SAVE_KEY = ${gdString(c.saveKey ?? '')}`,
    `const SAVE_TAMPER_POLICY = ${gdString(c.saveTamperPolicy)}`,
    '',
  ].join('\n');
}
