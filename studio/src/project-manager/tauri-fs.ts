import { invoke } from '@tauri-apps/api/core';
import type { DirEntry, ProjectFs } from './fs';

/** ProjectFs do app: os comandos `pm_*` de `src-tauri/src/project_fs.rs`. */
export const tauriFs: ProjectFs = {
  readText: (path) => invoke<string>('pm_read_text', { path }),
  writeText: (path, contents) => invoke<void>('pm_write_text', { path, contents }),
  exists: (path) => invoke<boolean>('pm_exists', { path }),
  createDir: (path) => invoke<void>('pm_create_dir', { path }),
  readDir: async (path) =>
    (await invoke<{ name: string; is_dir: boolean }[]>('pm_read_dir', { path })).map(
      (e): DirEntry => ({ name: e.name, isDir: e.is_dir }),
    ),
  removeFile: (path) => invoke<void>('pm_remove_file', { path }),
  copyFile: (from, to) => invoke<void>('pm_copy_file', { from, to }),
};
