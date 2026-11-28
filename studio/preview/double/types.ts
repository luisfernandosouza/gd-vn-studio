/**
 * Tipos do dublê do runtime do Preview (M0-09).
 *
 * As mensagens seguem `preview-protocol.schema.json` (tipos gerados em `@vnstudio/plugin-schema`). O conteúdo
 * que o dublê "roda" é uma `DoubleStory`: as cenas no formato do Data Model, mais o que o dublê não calcula
 * sozinho (as avaliações do Scheduler, gravadas por capítulo).
 */
import type { GameState, SchedulerEvaluation } from '@vnstudio/plugin-schema';

/** Estado do Preview (spec 07 §2), mais `CONNECTED` antes do `hello` e `CLOSED` depois do fechamento. */
export type PreviewState = 'CONNECTED' | 'READY' | 'LOADED' | 'RUNNING' | 'PAUSED' | 'CLOSED';

/** Estado do motor (RT §3), o `phase` das notificações e do `GameState`. */
export type EnginePhase = GameState['phase'];

export type Literal = boolean | number | string;

/** Painel (runtime Web, ponte `vnPreview`) ou janela (WebSocket com token), spec 07 §1.1 e §1.2. */
export type Transport = 'panel' | 'window';

export type JsonObject = Record<string, unknown>;

export interface RpcRequest {
  jsonrpc: '2.0';
  id: number | string;
  method: string;
  params?: JsonObject;
}

export interface RpcErrorObject {
  code: number;
  message: string;
  data?: JsonObject;
}

export type OutgoingMessage =
  | { jsonrpc: '2.0'; id: number | string | null; result: unknown }
  | { jsonrpc: '2.0'; id: number | string | null; error: RpcErrorObject }
  | { jsonrpc: '2.0'; method: string; params: JsonObject };

/**
 * Validação injetada no dublê. `schema.ts` implementa com o Ajv para os testes; no app não há validação
 * (a CSP do Studio não permite o `new Function` do Ajv).
 */
export interface MessageValidator {
  /** Erro de forma de uma requisição recebida, ou `null`. O dublê responde -32602 (ou -32600) com ele. */
  checkRequest(request: unknown): string | null;
  /** Erro de uma mensagem que o dublê vai mandar, ou `null`. `requestMethod` diz de que método é a resposta. */
  checkOutgoing(message: OutgoingMessage, requestMethod?: string): string | null;
}

export type VariableType = 'integer' | 'number' | 'boolean' | 'string' | 'enum';

export interface VariableConstraints {
  min?: number;
  max?: number;
  on_overflow?: 'clamp' | 'reject';
  max_length?: number;
  values?: string[];
}

/** Definição de variável como no Data Model (`VariableDefinition`), só com o que o dublê usa. */
export interface DoubleVariable {
  type: VariableType;
  default?: Literal;
  constraints?: VariableConstraints;
  /** Variável derivada: só leitura, recalculada a cada leitura. */
  derived?: unknown;
}

/** Nó de cena no formato do Data Model (`scene.schema.json → $defs/Node`), lido de forma tolerante. */
export interface SceneNode {
  id: string;
  type: string;
  next?: string;
  censor?: string;
  [field: string]: unknown;
}

/** Cena no formato do Data Model (`scene.schema.json`), a mesma entidade que o Build System grava no bundle. */
export interface SceneEntity {
  id: string;
  chapter: string | null;
  title?: string;
  start?: string;
  variables?: { key: string; type: string; default?: unknown; constraints?: unknown }[];
  nodes: SceneNode[];
  [field: string]: unknown;
}

/** Avaliação gravada de um ponto de seleção: `selection_count` e `chapter` o dublê preenche na hora. */
export type RecordedSelection = Omit<SchedulerEvaluation, 'selection_count' | 'chapter'>;

export interface DoubleChapter {
  id: string;
  title?: string;
  entry_scene?: string;
  /** Variáveis `chapter.<key>`. */
  variables?: Record<string, DoubleVariable>;
  /** Capítulo seguinte quando este termina; `null` ou ausente encerra o jogo. */
  next?: string | null;
  /**
   * Avaliações do Scheduler, na ordem dos pontos de seleção deste capítulo. O dublê não roda o Scheduler:
   * em cada ponto usa a próxima avaliação gravada e, quando acabam, sai do capítulo (`exit_chapter`, `completion`).
   */
  selections?: RecordedSelection[];
}

export interface DoubleActivity {
  outcomes: string[];
  skippable?: boolean;
  default_outcome?: string;
  /** Presente quando a atividade pode rodar no modo livre (`play_activity`). */
  free_play?: { params?: JsonObject };
}

export interface DoublePlugin {
  namespace: string;
  enabled?: boolean;
  activities: Record<string, DoubleActivity>;
}

export interface DoubleCharacter {
  id: string;
  key: string;
  name: string;
}

/** O conteúdo que o dublê carrega em `preview.load` (no lugar de ler o bundle do disco). */
export interface DoubleStory {
  project_id: string;
  content_hash: string;
  format_version: string;
  start_chapter: string;
  default_locale: string;
  locales: string[];
  chapters: DoubleChapter[];
  scenes: SceneEntity[];
  characters: DoubleCharacter[];
  /** Variáveis `global.*`, `character.<key>.*` e `plugin.<ns>.*`, por id qualificado. */
  variables: Record<string, DoubleVariable>;
  /** Plugins por id (`vnstudio.fishing`). */
  plugins: Record<string, DoublePlugin>;
  /** Ids das telas de `ui/` que `preview.show_screen` aceita. */
  screens: string[];
  endings: string[];
  /** Configurações do jogador (UI Spec §8) com os valores iniciais. */
  settings: Record<string, Literal>;
  /** `settings.autosave` do projeto: com `selection_point`, grava `saves/auto_<n>.json` em cada ponto de seleção. */
  autosave?: 'selection_point' | 'chapter' | 'off';
  reproducible_rng?: boolean;
}
