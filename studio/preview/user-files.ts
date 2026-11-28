/**
 * Dados do jogador no Preview (PP §1.4): com "Manter saves do Preview" (`user_data: "project"`), o runtime
 * do painel não grava no disco. O Studio manda o conteúdo de `.vnstudio/preview/user/` em `user_files` e
 * aplica `storage.write` / `storage.delete` nessa pasta.
 *
 * A mensagem vem de uma página onde também roda código de plugin (PP §1.1): caminho absoluto, com `..`,
 * com `\`, vazio ou fora da pasta é recusado e registrado no log, nunca aplicado.
 */
import { joinPath, listFilesRecursive, type ProjectFs } from '../src/project-manager/fs';
import { PREVIEW_USER_DIR } from './urls';

/** Caminho relativo seguro de `storage.*`: segmentos simples separados por `/`. */
export function safeUserPath(path: unknown): string | null {
  if (typeof path !== 'string' || path === '' || path.length > 512) return null;
  if (path.startsWith('/') || path.includes('\\') || path.includes('\0') || /^[A-Za-z]:/.test(path)) return null;
  const segments = path.split('/');
  if (segments.some((s) => s === '' || s === '.' || s === '..' || s.includes(':'))) return null;
  return path;
}

export function toBase64(text: string): string {
  let binary = '';
  for (const byte of new TextEncoder().encode(text)) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** Texto UTF-8 do base64, ou `null` se não for base64 válido ou não for UTF-8. */
export function fromBase64(data: unknown): string | null {
  if (typeof data !== 'string') return null;
  try {
    const binary = atob(data);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
}

/** `user_files` de `preview.load`: caminho relativo → base64, de tudo que está em `.vnstudio/preview/user/`. */
export async function readUserFiles(fs: ProjectFs, root: string): Promise<Record<string, string>> {
  const dir = joinPath(root, PREVIEW_USER_DIR);
  const out: Record<string, string> = {};
  for (const rel of await listFilesRecursive(fs, dir)) out[rel] = toBase64(await fs.readText(joinPath(dir, rel)));
  return out;
}
