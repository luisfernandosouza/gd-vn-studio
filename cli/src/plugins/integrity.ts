import { createHash } from 'node:crypto';

/** `integrity` de um `.vnplugin`: `sha256-<base64>` do arquivo inteiro, formato SRI (Plugin SDK §2.3). */
export function sriSha256(data: Uint8Array): string {
  return `sha256-${createHash('sha256').update(data).digest('base64')}`;
}

export function integrityMatches(data: Uint8Array, expected: string): boolean {
  return sriSha256(data) === expected;
}
