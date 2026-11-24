import { isTauri } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import type { ProjectFs } from './fs';
import { MemoryFs } from './memory-fs';
import { tauriFs } from './tauri-fs';

/** Disco e seletor de pasta do app. Fora do Tauri (navegador de desenvolvimento) usa a memória. */
export function nativeProjectIo(): { fs: ProjectFs; pickFolder: (title: string) => Promise<string | null> } {
  if (isTauri()) {
    return {
      fs: tauriFs,
      pickFolder: async (title) => {
        const picked = await open({ directory: true, multiple: false, title });
        return typeof picked === 'string' ? picked : null;
      },
    };
  }
  return { fs: new MemoryFs(), pickFolder: async () => '/projetos' };
}
