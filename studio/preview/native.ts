import { invoke, isTauri } from '@tauri-apps/api/core';

/** Comandos nativos do protocolo `vnpreview` (`src-tauri/src/lib.rs`). Fora do Tauri não fazem nada. */

/** O export Web do runtime está embutido no Studio? Sem ele, o painel usa o dublê (até o M6-14). */
export async function runtimeAvailable(): Promise<boolean> {
  return isTauri() && (await invoke<boolean>('preview_runtime_available'));
}

/** Aponta o mapa de três prefixos do `vnpreview` para o projeto aberto (PP §1.1). */
export async function openPreviewProject(root: string): Promise<void> {
  if (isTauri()) await invoke('preview_open_project', { root });
}

export async function closePreviewProject(): Promise<void> {
  if (isTauri()) await invoke('preview_close_project');
}
