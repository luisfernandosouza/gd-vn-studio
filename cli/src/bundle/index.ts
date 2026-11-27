/**
 * Compilador do bundle narrativo em TypeScript (Build System §5.1, tarefa M5-02). `jcs`, `hash`,
 * `compile` e `incremental` são puros (servem ao Studio na WebView); `load` e `write` usam o disco.
 */
export * from './jcs.js';
export * from './hash.js';
export * from './input.js';
export * from './compile.js';
export * from './incremental.js';
export { loadProject, loadPreset, defaultPresetsDir, readText, type LoadOptions } from './load.js';
export { writeBundle } from './write.js';
export { assetFilesFor, stageAssets, type StageResult } from './stage.js';
