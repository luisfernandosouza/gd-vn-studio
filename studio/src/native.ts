import { invoke, isTauri } from '@tauri-apps/api/core';

/**
 * Avisa o processo nativo que a interface montou. No modo de teste de fumaça
 * (VNSTUDIO_SMOKE_TEST=1, usado pela CI) o processo nativo fecha o app com código 0.
 * Fora do Tauri (testes, navegador) não faz nada.
 */
export async function notifyAppReady(): Promise<void> {
  if (!isTauri()) return;
  await invoke('app_ready');
}
