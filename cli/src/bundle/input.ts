/**
 * Entrada do compilador: os arquivos de um projeto de VN já lidos e interpretados, na ordem em que o
 * compilador de referência (`docs/specs/tools/compile_bundle.py`) os percorre. Separar a leitura
 * (`load.ts`, Node) da compilação (`compile.ts`, puro) deixa o Studio montar esta estrutura a partir
 * do próprio estado, sem disco, e recompilar uma entidade por vez (Preview Protocol §3).
 */
import type { JsonObject } from './jcs.js';

export type Edition = 'standard' | 'censored';

/** Um preset de interface (UI Spec §2.1): `docs/specs/presets/<nome>/`. */
export interface PresetInput {
  name: string;
  /** `theme.json` do preset. */
  theme: JsonObject;
  /** `ui/<id>.json`, em ordem de nome de arquivo. */
  ui: [id: string, screen: JsonObject][];
  /** `locales/<idioma>.json`, pelo nome do arquivo sem extensão. */
  locales: Record<string, JsonObject>;
}

/** Um plugin cujo manifesto o compilador conhece (pasta passada ou origem `path:`). */
export interface PluginInput {
  manifest: JsonObject;
  /** Texto do `LICENSE` na raiz do pacote, com fins de linha normalizados para `\n`. */
  license?: string;
}

export interface ProjectInput {
  project: JsonObject;
  variables: JsonObject;
  /** `assets.json → assets`, na ordem do arquivo. */
  assets: JsonObject;
  /** `characters/*.json`, `chapters/*.json` e `scenes/**\/*.json`, em ordem de caminho. */
  characters: JsonObject[];
  chapters: JsonObject[];
  scenes: JsonObject[];
  /** `ui/<id>.json` e `sets/<id>.json` do projeto, em ordem de nome. */
  screens: [id: string, screen: JsonObject][];
  sets: [id: string, set: JsonObject][];
  /** O arquivo de tema do projeto (`project.json → theme`, padrão `theme.json`), ou null se não existe. */
  theme: JsonObject | null;
  /** `plugins.json → plugins` e `plugin-lock.json → plugins` ({} se o arquivo não existe). */
  plugins: JsonObject;
  lock: JsonObject;
  /**
   * Manifestos na ordem em que o compilador os encontra: primeiro as pastas passadas, depois as
   * origens `path:` de `plugins.json`. Um id repetido substitui o anterior no mesmo lugar.
   */
  manifests: PluginInput[];
  /** `locales/<idioma>/**\/*.json` do projeto, por idioma, em ordem de caminho. */
  localeFiles: Record<string, JsonObject[]>;
  /** Texto de cada `credit.license_file` que existe em `assets/` (fins de linha em `\n`). */
  licenseFiles: Record<string, string>;
  preset: PresetInput;
}
