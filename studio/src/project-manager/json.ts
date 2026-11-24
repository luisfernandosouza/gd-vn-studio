/**
 * Formato dos arquivos do projeto (Data Model §2): UTF-8, indentação de 2 espaços, `\n` no fim e chaves
 * na ordem em que o Studio as monta (a mesma de `tools/sync_demo_example.py`).
 */
export function formatJson(data: unknown): string {
  return `${JSON.stringify(data, null, 2)}\n`;
}
