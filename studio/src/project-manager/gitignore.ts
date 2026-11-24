/** Bloco do `.gitignore` que o Studio cria e mantém no projeto (spec 09 §3.4). */
export const GITIGNORE_HEADER = '# Visual Novel Studio';

export const GITIGNORE_LINES = [
  '.vnstudio/',
  'plugins/*/.godot/',
  'plugins/*/addons/vn_runtime_sdk/',
  'plugins/*/.vnplugin/local.json',
  'plugins/*/vn_plugins/*/editor/node_modules/',
  'plugins/*/vn_plugins/*/editor/dist/',
  'build/',
] as const;

export const GITIGNORE_BLOCK = [GITIGNORE_HEADER, ...GITIGNORE_LINES].join('\n');

/**
 * Devolve o `.gitignore` com o bloco do Studio em dia. O bloco vai do cabeçalho até a primeira linha
 * em branco; o resto do arquivo (linhas do autor) fica como está. Sem bloco, ele é acrescentado no fim.
 * Idempotente: aplicar de novo não muda nada.
 */
export function applyGitignoreBlock(existing: string | null): string {
  if (existing === null || existing.trim() === '') return `${GITIGNORE_BLOCK}\n`;
  const eol = existing.includes('\r\n') ? '\r\n' : '\n';
  const lines = existing.split(/\r?\n/);
  if (lines[lines.length - 1] === '') lines.pop();
  const start = lines.findIndex((l) => l.trim() === GITIGNORE_HEADER);
  const block = GITIGNORE_BLOCK.split('\n');
  if (start === -1) {
    const sep = lines[lines.length - 1]?.trim() === '' ? [] : [''];
    return [...lines, ...sep, ...block].join(eol) + eol;
  }
  let end = start + 1;
  while (end < lines.length && lines[end]?.trim() !== '') end++;
  return [...lines.slice(0, start), ...block, ...lines.slice(end)].join(eol) + eol;
}
