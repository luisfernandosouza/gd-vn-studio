/**
 * @vnstudio/editor-sdk: API das Editor Extensions (Plugin SDK §10).
 *
 * Esqueleto do workspace (M0-06). Por enquanto só traz a versão e os tipos base que a API usa; o
 * `PluginContext` completo do §10.3, a bridge e `@vnstudio/editor-sdk/testing` chegam com a tarefa M7-04.
 */
export type { Scene, Variable, VariableDefinition, PluginManifest } from '@vnstudio/plugin-schema';

/** Versão deste pacote, a que `PluginContext.sdkVersion` informa (Plugin SDK §10.3). */
export const SDK_VERSION = '0.0.0';

/** Erro com que toda chamada da bridge rejeita (Plugin SDK §10.3). */
export interface VNError {
  code: string;
  message: string;
}

/** Devolvido por todo `register`/`on` da API: desfaz o registro. */
export interface Disposable {
  dispose(): void;
}
