/* eslint-disable */
/**
 * GERADO por sdk/plugin-schema/scripts/generate.mjs a partir de docs/specs/schemas/. NÃO EDITE À MÃO.
 * Para atualizar: npm run generate (na raiz do repositório). A CI falha se este arquivo estiver desatualizado.
 */

/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Action".
 */
export type Action =
  | {
      do: 'new_game';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'continue';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'open_screen';
      if?: ConditionList;
      else?: ActionList;
      screen: Id;
    }
  | {
      do: 'close_screen';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'back';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'return_to_title';
      if?: ConditionList;
      else?: ActionList;
      confirm?: boolean;
    }
  | {
      do: 'quit';
      if?: ConditionList;
      else?: ActionList;
      confirm?: boolean;
    }
  | {
      do: 'save';
      if?: ConditionList;
      else?: ActionList;
      slot?: number;
    }
  | {
      do: 'load';
      if?: ConditionList;
      else?: ActionList;
      slot?: number;
    }
  | {
      do: 'quick_save';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'quick_load';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'toggle_auto';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'toggle_skip';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'hide_textbox';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'open_backlog';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'set_setting';
      if?: ConditionList;
      else?: ActionList;
      setting:
        | 'volume.master'
        | 'volume.music'
        | 'volume.ambient'
        | 'volume.sfx'
        | 'volume.voice'
        | 'display_mode'
        | 'resolution'
        | 'vsync'
        | 'fps_limit_vn'
        | 'fps_limit_activity'
        | 'text_speed'
        | 'auto_delay'
        | 'skip_unread'
        | 'locale'
        | 'text_scale'
        | 'reduce_motion'
        | 'subtitles'
        | 'high_contrast'
        | 'show_hotspots'
        | 'content_filter';
      value: Literal;
    }
  | {
      do: 'play_sfx';
      if?: ConditionList;
      else?: ActionList;
      asset: AssetRef;
    }
  | {
      do: 'set_state';
      if?: ConditionList;
      else?: ActionList;
      /**
       * Elemento da tela (id), camada/hotspot do set da tela (set:<id>) ou do set em cena (stage:<id>).
       */
      target: string;
      state: Id;
    }
  | {
      do: 'toggle_state';
      if?: ConditionList;
      else?: ActionList;
      /**
       * Elemento da tela (id), camada/hotspot do set da tela (set:<id>) ou do set em cena (stage:<id>).
       */
      target: string;
      /**
       * @minItems 2
       */
      states: [Id, Id, ...Id[]];
    }
  | {
      do: 'play_animation';
      if?: ConditionList;
      else?: ActionList;
      /**
       * Elemento da tela (id), camada/hotspot do set da tela (set:<id>) ou do set em cena (stage:<id>).
       */
      target: string;
      animation: Animation;
    }
  | {
      do: 'show';
      if?: ConditionList;
      else?: ActionList;
      /**
       * Elemento da tela (id), camada/hotspot do set da tela (set:<id>) ou do set em cena (stage:<id>).
       */
      target: string;
    }
  | {
      do: 'hide';
      if?: ConditionList;
      else?: ActionList;
      /**
       * Elemento da tela (id), camada/hotspot do set da tela (set:<id>) ou do set em cena (stage:<id>).
       */
      target: string;
    }
  | {
      do: 'toggle_visible';
      if?: ConditionList;
      else?: ActionList;
      /**
       * Elemento da tela (id), camada/hotspot do set da tela (set:<id>) ou do set em cena (stage:<id>).
       */
      target: string;
    }
  | {
      do: 'effects';
      if?: ConditionList;
      else?: ActionList;
      effects: EffectList;
    }
  | {
      do: 'emit';
      if?: ConditionList;
      else?: ActionList;
      event: EventName;
      payload?: {
        [k: string]: ValueExpr;
      };
    }
  | {
      do: 'open_url';
      if?: ConditionList;
      else?: ActionList;
      url: string;
    }
  | {
      do: 'confirm';
      if?: ConditionList;
      else?: ActionList;
      text: LocalizedText;
      then: ActionList;
    }
  | {
      do: 'skip_activity';
      if?: ConditionList;
      else?: ActionList;
    }
  | {
      do: 'play_activity';
      if?: ConditionList;
      else?: ActionList;
      /**
       * <namespace>.<atividade> com free_play no manifesto.
       */
      activity: string;
      /**
       * Sobrepõe free_play.params do manifesto; validado contra params_schema.
       */
      params?: {
        [k: string]: unknown;
      };
    }
  | {
      do: 'reset_profile';
      if?: ConditionList;
      else?: ActionList;
      text?: LocalizedText;
    };
/**
 * Forma abreviada usada em campos 'conditions': lista com semântica AND, ou uma única Condition.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ConditionList".
 */
export type ConditionList = Condition[] | Condition;
/**
 * Árvore de condição. Uma lista no lugar de uma condição equivale a {"all": [...]}. Lista vazia é verdadeira.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Condition".
 */
export type Condition =
  | Comparison
  | {
      all: Condition[];
    }
  | {
      /**
       * @minItems 1
       */
      any: [Condition, ...Condition[]];
    }
  | {
      not: Condition;
    }
  | {
      event_since_last_selection: EventName;
    };
/**
 * Referência totalmente qualificada a uma variável. Prefixos: global., character.<key do personagem>., chapter., scene., plugin.<namespace>., sys. (somente leitura; pode conter UUIDs de entidade, ex.: sys.scenes.<uuid>.plays).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "VariableRef".
 */
export type VariableRef = string;
/**
 * Valor literal permitido para variáveis.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Literal".
 */
export type Literal = boolean | number | string;
/**
 * Nome de evento: <namespace>.<nome>. O namespace 'story' é reservado ao projeto e 'sys' ao runtime.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "EventName".
 */
export type EventName = string;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ActionList".
 */
export type ActionList = Action[];
/**
 * Identificador legível: minúsculas, dígitos e underscore, começando com letra. Usado onde pessoas escrevem ou leem o ID (chaves de variável, expressões, grupos, finais, outcomes). Estável: nunca é regenerado.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Id".
 */
export type Id = string;
/**
 * ID de asset registrado em assets.json.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "AssetRef".
 */
export type AssetRef = string;
/**
 * Mutação de variável. Uma lista de efeitos é aplicada como uma única transação.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Effect".
 */
export type Effect = Effect1;
/**
 * Como VariableRef, mas sem o namespace sys.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "WritableVariableRef".
 */
export type WritableVariableRef = VariableRef;
/**
 * Expressão de valor (sem efeitos colaterais). Usada em efeitos e em variáveis derivadas.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ValueExpr".
 */
export type ValueExpr =
  | Literal
  | VarValue
  | {
      /**
       * Campo do payload; 'a.b' lê o campo b do objeto a.
       */
      result: string;
      default?: Literal;
    }
  | {
      fn:
        | 'add'
        | 'sub'
        | 'mul'
        | 'div'
        | 'mod'
        | 'min'
        | 'max'
        | 'clamp'
        | 'round'
        | 'floor'
        | 'ceil'
        | 'abs'
        | 'concat'
        | 'random_int';
      /**
       * @minItems 1
       * @maxItems 8
       */
      args:
        | [ValueExpr]
        | [ValueExpr, ValueExpr]
        | [ValueExpr, ValueExpr, ValueExpr]
        | [ValueExpr, ValueExpr, ValueExpr, ValueExpr]
        | [ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr]
        | [ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr]
        | [ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr]
        | [ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr, ValueExpr];
    }
  | {
      if: ConditionList;
      then: ValueExpr;
      else: ValueExpr;
    };
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "EffectList".
 */
export type EffectList = Effect[];
/**
 * Texto no idioma-fonte do projeto. Traduções ficam em locales/<lang>/ indexadas pelo caminho estável do nó. Interpolação: {global.player_money}; use {{ e }} para chaves literais.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "LocalizedText".
 */
export type LocalizedText = string;
/**
 * Área clicável (UI Spec §5.2).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Area".
 */
export type Area =
  | {
      /**
       * @minItems 4
       * @maxItems 4
       */
      rect: [number, number, number, number];
    }
  | {
      /**
       * @minItems 3
       * @maxItems 32
       */
      polygon: [Fraction2, Fraction2, Fraction2, ...Fraction2[]];
    }
  | {
      layer: Id;
    }
  | {
      character: EntityId;
    };
/**
 * @minItems 2
 * @maxItems 2
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Fraction2".
 */
export type Fraction2 = [number, number];
/**
 * Identificador de entidade: UUID em minúsculas (o Studio gera UUIDv7, ordenado pelo momento de criação). Usado em cenas, capítulos, personagens, nós e opções de escolha. Nunca é exibido nem digitado pelo autor; o Studio mostra o título.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "EntityId".
 */
export type EntityId = string;
/**
 * Forma canônica de um SHA-256 em JSON: 'sha256-' + base64 padrão (formato SRI). Em hexadecimal (build_id, nomes de arquivo) usam-se os mesmos 32 bytes em hex minúsculo; em binário (.vnb), os 32 bytes crus (Build System §5.1).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Hash".
 */
export type Hash = string;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "AudioNode".
 */
export type AudioNode = NodeBase & AudioNode1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "BackgroundNode".
 */
export type BackgroundNode = NodeBase & BackgroundNode1 & BackgroundNode2;
export type BackgroundNode1 = {
  [k: string]: unknown;
};
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "BacklogList".
 */
export type BacklogList = ElementBase & BacklogList1;
/**
 * Desvio condicional: primeiro caso verdadeiro vence; senão 'else' (ou 'next').
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "BranchNode".
 */
export type BranchNode = NodeBase & BranchNode1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "SemVer".
 */
export type SemVer = string;
/**
 * Tag BCP 47 (ex.: pt-BR, en, ja).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Locale".
 */
export type Locale = string;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "VariableDefinition".
 */
export type VariableDefinition = VariableDefinition1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "VariableType".
 */
export type VariableType = 'boolean' | 'integer' | 'number' | 'string' | 'enum';
/**
 * Namespace de plugin, único por projeto (ex.: fishing). Reservados: sys, story, vn, global, character, chapter, scene, plugin (Data Model §3).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Namespace".
 */
export type Namespace = string;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Button".
 */
export type Button = ElementBase & Button1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Case".
 */
export type Case =
  | (Base & {
      kind?: 'expression';
      expr: ValueExpr;
      variables?: ConformanceFileVariables;
      rng_state?: Hex64;
      expect?:
        | Error
        | {
            type: 'boolean' | 'integer' | 'number' | 'string';
            value: boolean | number | string;
          };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'condition';
      conditions: ConditionList;
      variables: ConformanceFileVariables;
      events?: EventName[];
      expect?:
        | Error
        | {
            value: boolean;
          };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'effects';
      effects: EffectList;
      variables: ConformanceFileVariables;
      rng_state?: Hex64;
      expect?:
        | Error
        | {
            changes: {
              variable: string;
              old: unknown;
              new: unknown;
            }[];
          };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'text';
      mode: 'concat' | 'interpolation' | 'record';
      locale?: Locale;
      value:
        | (boolean | number | string)
        | {
            type: 'number';
            value: number;
          };
      expect?: {
        text: string;
      };
      /**
       * Só no modo record (Plugin SDK §9.1).
       */
      format?: 'integer' | 'number' | 'time_ms';
      number_formats?: NumberFormats;
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'rng';
      op: 'sequence' | 'random_int' | 'activity_seed' | 'plugin_seed';
      seed: Hex64;
      count?: number;
      min?: number;
      max?: number;
      selection_count?: number;
      node?: EntityId;
      activity_index?: number;
      namespace?: Namespace;
      expect?: {
        values?: number[];
        state_after?: Hex64;
        seed?: Hex64;
      };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'selection';
      /**
       * Subconjunto de chapter.schema.json: id, scheduler, exclusive_groups, completion, include_global_scenes.
       */
      chapter: {
        [k: string]: unknown;
      };
      scenes: {
        id: EntityId;
        title?: string;
        chapter: EntityId | null;
        scheduling?: Scheduling;
        [k: string]: unknown;
      }[];
      project_groups?: unknown[];
      state?: {
        variables?: ConformanceFileVariables;
        /**
         * Mesmo formato de save.schema.json → state.history.
         */
        history?: {
          [k: string]: unknown;
        };
        rng_state?: Hex64;
      };
      content_request?: EntityId;
      expect?:
        | Error
        | {
            action: 'start_scene' | 'exit_chapter' | 'end_game';
            chosen: EntityId | null;
            reason: 'request' | 'plugin_request' | 'priority' | 'tie_break' | 'fallback' | 'completion' | 'exhausted';
            candidates: {
              scene: string;
              eligible: boolean;
              blocked_by?:
                | 'conditions'
                | 'max_plays'
                | 'cooldown'
                | 'exclusive_group'
                | 'mode_manual'
                | 'lower_priority'
                | 'tie_break';
            }[];
            request_refused?: {
              scene: string;
              by: 'content' | 'plugin';
            };
            selection_count_after: number;
            fallback_streak_after: number;
            rng_state_after?: Hex64;
          };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'record';
      board: {
        order: 'asc' | 'desc';
        keep: number;
        format: 'integer' | 'number' | 'time_ms';
      };
      entries: {
        score: number;
        at: string;
        meta?: {
          [k: string]: unknown;
        };
        [k: string]: unknown;
      }[];
      submit: {
        score: number;
        at: string;
        meta?: {
          [k: string]: unknown;
        };
        [k: string]: unknown;
      };
      locale?: Locale;
      expect?: {
        rank: number;
        entries: {
          score: number;
          at: string;
          meta?: {
            [k: string]: unknown;
          };
          [k: string]: unknown;
        }[];
        display?: string[];
      };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'flow';
      /**
       * Cena no formato de scene.schema.json (sem scheduling).
       */
      scene: {
        [k: string]: unknown;
      };
      variables?: ConformanceFileVariables;
      locale?: Locale;
      /**
       * Modo stream ligado (Data Model §10.4): passos censor: skip não rodam, censor: only rodam e falas usam censored_text. Ausente = desligado. Um input {content_filter} muda o modo no meio da cena.
       */
      content_filter?: boolean;
      inputs: (
        | 'advance'
        | {
            /**
             * Id da opção de uma choice, do hotspot de um interact ou, só num interact, "exit" (a saída, que não tem id próprio no cenário; UI Spec §6).
             */
            choose: EntityId | 'exit';
          }
        | {
            activity: {
              outcome?: string;
              payload?: {
                [k: string]: unknown;
              };
              skipped?: boolean;
              failed?: boolean;
            };
          }
        | {
            /**
             * O jogador liga ou desliga o modo stream com a fala na tela (Runtime Spec §5.5). O traço ganha o evento, o palco visível (stage) e a fala de novo.
             */
            content_filter: boolean;
          }
      )[];
      expect?: {
        trace: {
          event?: string;
          node?: EntityId;
          text?: string;
          options?: unknown[];
          changes?: unknown[];
          end?: unknown;
          waiting?: 'line' | 'choice' | 'interact' | 'plugin';
          error?: string;
          /**
           * Palco visível depois de mudar o modo: background (id do asset, {set: id} para um cenário composto, ou null = placeholder), characters (na ordem de entrada, cada uma com id, position e, se houver, expression) e audio (canal → asset).
           */
          stage?: {
            [k: string]: unknown;
          };
        }[];
      };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'canonical';
      /**
       * Texto JSON de entrada (qualquer formatação); a saída é o JCS (RFC 8785) e o sha256-SRI do texto canônico em UTF-8.
       */
      json: string;
      expect?: {
        text: string;
        hash: string;
      };
      [k: string]: unknown;
    })
  | (Base & {
      kind?: 'hmac';
      /**
       * Texto JSON de um save ou perfil; o campo integrity, se presente, é ignorado no cálculo (BS §8.3).
       */
      json: string;
      /**
       * Chave HMAC de 32 bytes em hexadecimal.
       */
      key: string;
      expect?: {
        integrity: string;
      };
      [k: string]: unknown;
    });
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Hex64".
 */
export type Hex64 = string;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Changes".
 */
export type Changes = {
  variable: string;
  old: unknown;
  new: unknown;
}[];
/**
 * Menu de escolhas. Cada opção define o próximo nó em 'goto'. 'next' do nó (ou o nó seguinte do array) é usado quando nenhuma opção está visível e pelas opções sem 'goto'.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ChoiceNode".
 */
export type ChoiceNode = NodeBase & ChoiceNode1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Color".
 */
export type Color = string;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Container".
 */
export type Container = ElementBase & Container1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Element".
 */
export type Element =
  | Button
  | Image
  | Label
  | Hotspot
  | Slider
  | Toggle
  | Select
  | SlotGrid
  | GalleryGrid
  | BacklogList
  | Container
  | RecordsList
  | LicensesList;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Image".
 */
export type Image = ElementBase & Image1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Label".
 */
export type Label = ElementBase & Label1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Hotspot".
 */
export type Hotspot = ElementBase & Hotspot1;
/**
 * Cursor ao passar sobre a área: um dos nomes prontos ou um asset de imagem. Um nome pronto vence um asset de mesmo id.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Cursor".
 */
export type Cursor = ('default' | 'look' | 'talk' | 'use' | 'walk') | AssetRef;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Highlight".
 */
export type Highlight = 'none' | 'outline' | 'glow' | 'tint';
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Slider".
 */
export type Slider = ElementBase & Slider1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Toggle".
 */
export type Toggle = ElementBase & Toggle1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Select".
 */
export type Select = ElementBase & Select1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "SlotGrid".
 */
export type SlotGrid = ElementBase & SlotGrid1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "GalleryGrid".
 */
export type GalleryGrid = ElementBase & GalleryGrid1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "RecordsList".
 */
export type RecordsList = ElementBase & RecordsList1;
/**
 * Lista rolável com as licenças dos plugins e das fontes do jogo (Build System §4.5).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "LicensesList".
 */
export type LicensesList = ElementBase & LicensesList1;
/**
 * Aplica uma lista de efeitos como uma transação.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "EffectsNode".
 */
export type EffectsNode = NodeBase & EffectsNode1;
/**
 * Emite um evento narrativo. Só o namespace story (R020).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "EmitNode".
 */
export type EmitNode = NodeBase & EmitNode1;
/**
 * Termina a cena e diz ao Narrative Engine o que fazer em seguida.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "EndNode".
 */
export type EndNode = NodeBase & EndNode1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "HideNode".
 */
export type HideNode = NodeBase & HideNode1;
/**
 * Escolha espacial: o jogador clica em áreas da cena (UI Spec §6). Mesma semântica da choice.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "InteractNode".
 */
export type InteractNode = NodeBase & InteractNode1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "JumpNode".
 */
export type JumpNode = NodeBase & JumpNode1;
/**
 * Fala ou narração.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "LineNode".
 */
export type LineNode = NodeBase & LineNode1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Node".
 */
export type Node =
  | LineNode
  | ChoiceNode
  | InteractNode
  | EffectsNode
  | BranchNode
  | JumpNode
  | BackgroundNode
  | ShowNode
  | HideNode
  | AudioNode
  | WaitNode
  | EmitNode
  | PluginNode
  | EndNode;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ShowNode".
 */
export type ShowNode = NodeBase & ShowNode1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "WaitNode".
 */
export type WaitNode = NodeBase & WaitNode1;
/**
 * Executa uma atividade declarada por um plugin (ex.: minigame). A cena fica suspensa até a atividade terminar.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "PluginNode".
 */
export type PluginNode = NodeBase & PluginNode1;
/**
 * Raiz de plugin.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/plugin.schema.json).
 *
 * Manifesto declarativo de um plugin .vnplugin. Declara o que o plugin PEDE; o que ele RECEBE é decidido pelo projeto em plugins.json.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "PluginManifest".
 */
export type PluginManifest = PluginManifest1;
/**
 * Faixa no formato npm/node-semver (ex.: ^1.2.0, >=1.0.0 <2.0.0).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "SemVerRange".
 */
export type SemVerRange = string;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "VariablePattern".
 */
export type VariablePattern = string;
/**
 * Identificador legível: minúsculas, dígitos e underscore, começando com letra. Usado onde pessoas escrevem ou leem o ID (chaves de variável, expressões, grupos, finais, outcomes). Estável: nunca é regenerado.
 */
export type Id1 = string;
/**
 * Raiz de preview-protocol.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/preview-protocol.schema.json).
 *
 * Uma mensagem JSON-RPC 2.0 trocada entre o Studio e o runtime no Preview (spec 07). Os resultados de cada método estão em $defs/<Método>_result; a resposta em si só é validada na forma.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "PreviewMessage".
 */
export type PreviewMessage =
  | (
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'session.hello';
          params?: SessionHelloParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.load';
          params?: PreviewLoadParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.start';
          params?: PreviewStartParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.stop';
          params?: PreviewStopParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.pause';
          params?: PreviewPauseParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.resume';
          params?: PreviewResumeParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.step';
          params?: PreviewStepParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.input';
          params?: PreviewInputParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.set_variables';
          params?: PreviewSetVariablesParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.get_state';
          params?: PreviewGetStateParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.explain_selection';
          params?: PreviewExplainSelectionParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.reload';
          params?: PreviewReloadParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.reload_plugins';
          params?: PreviewReloadPluginsParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.show_screen';
          params?: PreviewShowScreenParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.set_setting';
          params?: PreviewSetSettingParams;
        }
      | {
          jsonrpc: '2.0';
          id: number | string;
          method: 'preview.set_locale';
          params?: PreviewSetLocaleParams;
        }
    )
  | (
      | {
          jsonrpc: '2.0';
          method: 'session.closing';
          params: NotifySessionClosing;
        }
      | {
          jsonrpc: '2.0';
          method: 'storage.write';
          params: NotifyStorageWrite;
        }
      | {
          jsonrpc: '2.0';
          method: 'storage.delete';
          params: NotifyStorageDelete;
        }
      | {
          jsonrpc: '2.0';
          method: 'chapter.started';
          params: NotifyChapterStarted;
        }
      | {
          jsonrpc: '2.0';
          method: 'chapter.ended';
          params: NotifyChapterEnded;
        }
      | {
          jsonrpc: '2.0';
          method: 'scene.started';
          params: NotifySceneStarted;
        }
      | {
          jsonrpc: '2.0';
          method: 'scene.ended';
          params: NotifySceneEnded;
        }
      | {
          jsonrpc: '2.0';
          method: 'node.entered';
          params: NotifyNodeEntered;
        }
      | {
          jsonrpc: '2.0';
          method: 'state.changed';
          params: NotifyStateChanged;
        }
      | {
          jsonrpc: '2.0';
          method: 'event.emitted';
          params: NotifyEventEmitted;
        }
      | {
          jsonrpc: '2.0';
          method: 'scheduler.evaluated';
          params: NotifySchedulerEvaluated;
        }
      | {
          jsonrpc: '2.0';
          method: 'activity.started';
          params: NotifyActivityStarted;
        }
      | {
          jsonrpc: '2.0';
          method: 'activity.ended';
          params: NotifyActivityEnded;
        }
      | {
          jsonrpc: '2.0';
          method: 'game.ended';
          params: NotifyGameEnded;
        }
      | {
          jsonrpc: '2.0';
          method: 'log';
          params: NotifyLog;
        }
      | {
          jsonrpc: '2.0';
          method: 'error';
          params: NotifyError;
        }
      | {
          jsonrpc: '2.0';
          method: 'plugin.log';
          params: NotifyPluginLog;
        }
      | {
          jsonrpc: '2.0';
          method: 'plugin.permission_denied';
          params: NotifyPluginPermissionDenied;
        }
      | {
          jsonrpc: '2.0';
          method: 'plugin.faulted';
          params: NotifyPluginFaulted;
        }
    )
  | ({
      [k: string]: unknown;
    } & {
      jsonrpc: '2.0';
      id: number | string | null;
      result?: unknown;
      error?: ErrorObject;
    });
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_load_params".
 */
export type PreviewLoadParams = PreviewLoadParams1 & PreviewLoadParams2;
export type PreviewLoadParams1 = {
  [k: string]: unknown;
};
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_input_params".
 */
export type PreviewInputParams = PreviewInputParams1;
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_reload_params".
 */
export type PreviewReloadParams = PreviewReloadParams1 & PreviewReloadParams2;
export type PreviewReloadParams1 = {
  [k: string]: unknown;
};

/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Comparison".
 */
export interface Comparison {
  variable: VariableRef;
  operator:
    | 'equals'
    | 'not_equals'
    | 'greater_than'
    | 'greater_than_or_equal'
    | 'less_than'
    | 'less_than_or_equal'
    | 'in'
    | 'not_in'
    | 'contains'
    | 'is_default';
  /**
   * Literal, lista de literais (para in/not_in) ou referência a outra variável do mesmo tipo (integer e number se comparam entre si). Ausente apenas para is_default, que é verdadeiro quando o valor atual é igual ao padrão efetivo (initial_values do personagem, senão default).
   */
  value?: Literal | Literal[] | VarValue;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "VarValue".
 */
export interface VarValue {
  var: VariableRef;
}
/**
 * Animação pronta (UI Spec §7.3). Com reduce_motion, só fade.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Animation".
 */
export interface Animation {
  kind: 'fade' | 'slide' | 'scale' | 'pulse' | 'float' | 'shake' | 'rotate' | 'blink';
  from?: 'left' | 'right' | 'top' | 'bottom';
  duration?: number;
  delay?: number;
  amount?: number;
  loop?: boolean;
  easing?: 'linear' | 'ease_in' | 'ease_out' | 'ease_in_out' | 'back' | 'elastic' | 'bounce';
}
export interface Effect1 {
  op: 'set' | 'add' | 'subtract' | 'multiply' | 'toggle' | 'reset';
  variable: WritableVariableRef;
  value?: ValueExpr;
}
/**
 * Raiz de assets.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/assets.schema.json).
 *
 * Registro de assets. Conteúdo narrativo referencia assets por ID, nunca por caminho, para que renomear arquivos não quebre cenas.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Assets".
 */
export interface Assets {
  $schema?: string;
  assets: {
    [k: string]: {
      /**
       * Relativo a assets/.
       */
      path: string;
      type:
        'image' | 'sprite' | 'background' | 'audio_music' | 'audio_sfx' | 'audio_voice' | 'video' | 'font' | 'other';
      hash?: Hash;
      tags?: string[];
      /**
       * Opções de importação repassadas ao Godot.
       */
      import?: {
        [k: string]: unknown;
      };
      /**
       * Só sprite: ponto do sprite que fica na posição do palco, em fração da imagem ([0.5, 1.0] = centro dos pés, padrão).
       *
       * @minItems 2
       * @maxItems 2
       */
      anchor?: [number, number];
      /**
       * Só sprite: escala aplicada no palco (padrão 1.0).
       */
      scale?: number;
      /**
       * Só image usada no tema: margens [esquerda, topo, direita, base] em pixels que não esticam.
       *
       * @minItems 4
       * @maxItems 4
       */
      nine_slice?: [number, number, number, number];
      /**
       * Inclui o asset no build mesmo sem referência no conteúdo (ex.: usado só por um plugin via config). Build System §6.1.
       */
      always_include?: boolean;
      /**
       * IDs anteriores deste asset (Data Model §12), aplicados ao restaurar o palco de saves antigos.
       */
      renamed_from?: AssetRef[];
      /**
       * Entra na galeria (Data Model §10.5, UI Spec §3.1, gallery_grid). Vale para image, background (seção images) e audio_music (seção music), e só se a seção estiver em project.json → gallery.sections; senão a marca é ignorada (U013). O runtime marca o asset como visto em profile.seen_assets na primeira vez que ele aparece numa cena (Runtime Spec §5.2).
       */
      gallery?: boolean;
      /**
       * Ordem na galeria; ausente = depois dos ordenados, pelo id.
       */
      gallery_order?: number;
      /**
       * Modo stream (Data Model §10.4): o que aparece no lugar deste asset quando o filtro de conteúdo está ligado. replace_with troca por outro asset do mesmo tipo em todo lugar onde este aparece (cena, expressão, tela, set, galeria, final, plugin); hide não desenha nem toca nada (cenário e imagem viram o placeholder de project.json → content_filter). A substituta não pode ter censored (R024).
       */
      censored?:
        | {
            replace_with: AssetRef;
          }
        | {
            hide: true;
          };
      /**
       * Crédito de um asset de terceiros (Data Model §10.1, Build System §4.5): o Build System reúne em licenses.json (um arquivo do bundle) o crédito de cada asset que entra no jogo, e a tela de créditos o mostra com licenses_list (UI Spec §3.1). Assets que não entram no jogo não aparecem. Não entra no bundle.json nem no content_hash.
       */
      credit?: {
        /**
         * Quem deve ser creditado, como a licença pede (ex.: "Noraneko Games").
         */
        author: string;
        /**
         * Nome curto ou resumo dos termos (ex.: "CC BY 4.0", "Pack terms, see ReadMe.txt"). Fica no idioma original da licença e não é traduzido: o Studio sugere inglês.
         */
        license?: string;
        /**
         * Página do autor ou do pacote.
         */
        url?: string;
        /**
         * Texto exato que a licença pede para mostrar, quando houver; senão o crédito mostra author e license. Não é traduzido.
         */
        notice?: string;
        /**
         * Arquivo com o texto completo da licença, relativo a assets/ (ex.: fonts/OFL-Nunito.txt). O texto vai inteiro para licenses.json; é o caso das fontes OFL, que pedem a licença junto de cada cópia.
         */
        license_file?: string;
      };
    };
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "NodeBase".
 */
export interface NodeBase {
  id: EntityId;
  type: string;
  next?: EntityId;
  /**
   * Comentário do autor; ignorado pelo runtime.
   */
  note?: string;
  /**
   * Dados de layout do Studio (posição no grafo etc.); ignorado pelo runtime.
   */
  editor?: {
    [k: string]: unknown;
  };
  /**
   * Passo incompleto criado pela importação de roteiro ou por um plugin (ex.: asset ou personagem não encontrado). O validador avisa (W013) e bloqueia a exportação.
   */
  unresolved?: {
    reason: string;
  };
  /**
   * Modo stream (Data Model §10.4): skip = o passo só acontece com o filtro desligado; only = só com o filtro ligado. Quando o passo não vale, o runtime segue 'next' (ou o nó seguinte) sem executá-lo. Só nestes passos de apresentação: line, background, show, audio com action play e wait (R023). hide e audio com action stop não aceitam: o que muda com o modo é a entrada de um item, não a saída (Runtime Spec §5.5).
   */
  censor?: 'skip' | 'only';
  [k: string]: unknown;
}
export interface AudioNode1 {
  type?: 'audio';
  action: 'play' | 'stop';
  channel: 'music' | 'ambient' | 'sfx' | 'voice';
  asset?: AssetRef;
  loop?: boolean;
  volume?: number;
  fade?: number;
  caption?: LocalizedText;
  censored_caption?: LocalizedText;
  [k: string]: unknown;
}
export interface BackgroundNode2 {
  type?: 'background';
  asset?: AssetRef;
  transition?: Transition;
  set?: Id;
  [k: string]: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Transition".
 */
export interface Transition {
  kind?: 'none' | 'fade' | 'dissolve' | 'slide_left' | 'slide_right';
  duration?: number;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ElementBase".
 */
export interface ElementBase {
  id: Id;
  type: string;
  position?: Fraction2;
  pivot?: Fraction2;
  /**
   * Pixels da resolução base.
   *
   * @minItems 2
   * @maxItems 2
   */
  size?: [number, number];
  anchor?: 'stretch' | 'edge';
  z?: number;
  visible_if?: ConditionList;
  enabled_if?: ConditionList;
  style?: Id;
  tooltip?: LocalizedText;
  shortcut?: string;
  focus?: {
    up?: Id;
    down?: Id;
    left?: Id;
    right?: Id;
  };
  appear?: Animation;
  /**
   * Só na hud: recebe input durante atividades com input.capture.
   */
  during_activity?: boolean;
  [k: string]: unknown;
}
export interface BacklogList1 {
  type?: 'backlog_list';
  max_items?: number;
  [k: string]: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Base".
 */
export interface Base {
  id: string;
  description: string;
  kind: string;
  [k: string]: unknown;
}
export interface BranchNode1 {
  type?: 'branch';
  /**
   * @minItems 1
   */
  cases: [
    {
      id: EntityId;
      conditions: ConditionList;
      goto: EntityId;
    },
    ...{
      id: EntityId;
      conditions: ConditionList;
      goto: EntityId;
    }[]
  ];
  else?: EntityId;
  [k: string]: unknown;
}
/**
 * Raiz de build-manifest.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/build-manifest.schema.json).
 *
 * Manifesto gravado na pasta de saída de cada build (Build System §9.2). O Build Reporter e a CI o leem.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "BuildManifest".
 */
export interface BuildManifest {
  $schema?: string;
  manifest_version: 1;
  /**
   * <AAAAMMDD-HHMMSS>-<8 hex do content_hash> (Build System §4.1).
   */
  build_id: string;
  project: {
    id: Id;
    version: SemVer;
    content_hash: Hash;
  };
  created_at: string;
  type: 'release' | 'debug';
  /**
   * project.json → build.edition (Build System §5.4).
   */
  edition?: 'standard' | 'censored';
  tools: {
    studio: SemVer;
    runtime: SemVer;
    runtime_sdk: SemVer;
    godot: string;
    godot_label?: string;
    /**
     * Compilador de bundle usado, quando não é o do Studio (ex.: tools/compile_bundle.py).
     */
    compiler?: string;
  };
  plugins: {
    id: string;
    version: SemVer;
    integrity: Hash;
    /**
     * Plugin embutido, empacotado da pasta do projeto neste build (spec 09 §3.2).
     */
    embedded?: boolean;
  }[];
  /**
   * @minItems 1
   */
  locales: [Locale, ...Locale[]];
  protection?: {
    encrypt_pck?: boolean;
    save_tamper?: 'ignore' | 'flag' | 'reject';
    save_key_id?: string;
  };
  outputs: {
    platform: 'windows' | 'macos' | 'linux' | 'web';
    file: string;
    bytes: number;
    sha256: string;
    signed?: boolean;
  }[];
  warnings?: string[];
}
/**
 * Raiz de bundle.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/bundle.schema.json).
 *
 * Bundle narrativo que o runtime lê (Runtime Spec §2, Build System §5.1). Gerado pelo compilador a partir do projeto já validado, com defaults resolvidos e o preset do tema aplicado. Todo mapa é ordenado por chave. content_hash = SHA-256 do JCS do bundle sem o campo content_hash.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Bundle".
 */
export interface Bundle {
  $schema?: string;
  bundle_version: 1;
  format_version: SemVer;
  content_hash: Hash;
  /**
   * project.json sem $schema, theme e build, com settings resolvido (todos os padrões preenchidos), scheduler resolvido e exclusive_groups com max_plays.
   */
  project: {
    /**
     * Modo stream resolvido (Data Model §10.4, Build System §5.4): default, ask_on_first_launch, placeholder (se houver) e edition.
     */
    content_filter: {
      default: boolean;
      ask_on_first_launch: boolean;
      placeholder?: AssetRef;
      edition: 'standard' | 'censored';
      [k: string]: unknown;
    };
    /**
     * Galeria resolvida (Data Model §10.5): igual a project.json → gallery, com sections na ordem endings, images, music. Ausente = jogo sem galeria.
     */
    gallery?: {
      /**
       * @minItems 1
       */
      sections: ['endings' | 'images' | 'music', ...('endings' | 'images' | 'music')[]];
      [k: string]: unknown;
    };
    [k: string]: unknown;
  };
  /**
   * Variáveis de escopo de jogo, por id qualificado (global.*, character.<key>.*, plugin.<ns>.*), com default e persistence resolvidos. As de personagem já vêm instanciadas, com initial_values como default. chapter.* e scene.* ficam no capítulo e na cena.
   */
  variables: {
    [k: string]: VariableDefinition;
  };
  /**
   * renamed_from reunidos: id antigo → id atual, para variáveis (qualificadas), cenas, capítulos, nós e assets.
   */
  aliases: {
    [k: string]: string;
  };
  /**
   * Personagens por UUID, como em characters/*.json, sem $schema.
   */
  characters: {
    [k: string]: {
      [k: string]: unknown;
    };
  };
  /**
   * Capítulos por UUID, sem $schema, com scheduler (do capítulo sobre o do projeto), completion.on_exhausted, exclusive_groups[].max_plays e next[].priority resolvidos.
   */
  chapters: {
    [k: string]: {
      [k: string]: unknown;
    };
  };
  /**
   * Cenas por UUID, sem $schema, com chapter (null para globais), scheduling (mode, priority, max_plays, cooldown, exclusive_groups, weight, order) e start resolvidos.
   */
  scenes: {
    [k: string]: {
      [k: string]: unknown;
    };
  };
  /**
   * Tema do projeto aplicado sobre o tema do preset (fusão profunda; listas substituem).
   */
  theme: {
    [k: string]: unknown;
  };
  /**
   * Telas por id: as do preset, substituídas inteiras pelas do projeto com o mesmo id, mais a tela minigames gerada (UI Spec §6.1).
   */
  ui: {
    [k: string]: {
      [k: string]: unknown;
    };
  };
  sets: {
    [k: string]: {
      [k: string]: unknown;
    };
  };
  /**
   * Assets por id. path é reescrito para res://vn_content/assets/<path> (assets do projeto) ou aponta para res://vn_runtime/… (assets do preset). O bundle do Preview é o mesmo do build: em modo preview, o runtime troca o prefixo res://vn_content/assets/ por preview.load → assets_base (spec 07 §1.3). O campo credit de assets.json não entra no bundle (vai para licenses.json, Build System §4.5).
   */
  assets: {
    [k: string]: {
      /**
       * Caminho res:// no pacote do jogo (o mesmo no Preview, spec 07 §1.3).
       */
      path: string;
      [k: string]: unknown;
    };
  };
}
export interface VariableDefinition1 {
  key: Id;
  /**
   * Rótulo exibido no Studio.
   */
  name?: string;
  description?: string;
  type: VariableType;
  default?: Literal;
  /**
   * save: vai para o save (padrão). profile: sobrevive entre saves e novos jogos (galeria, NG+); só em variáveis globais e de plugin. session: nunca é salva; volta ao padrão ao carregar.
   */
  persistence?: 'save' | 'profile' | 'session';
  constraints?: VariableConstraints;
  derived?: ValueExpr;
  /**
   * Permissões de plugins sobre esta variável (a concessão efetiva fica em plugins.json).
   */
  access?: {
    plugins_read?: 'none' | 'granted' | 'all';
    plugins_write?: 'none' | 'granted';
  };
  tags?: string[];
  /**
   * Somente em variables.json/character: restringe o modelo a estes personagens, pela key do personagem. Ausente = todos.
   */
  characters?: Id[];
  /**
   * Chaves anteriores desta variável (Data Model §12). O Save Manager aplica o alias ao carregar saves antigos, para que renomear depois de lançar o jogo não perca valores.
   */
  renamed_from?: Id[];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "VariableConstraints".
 */
export interface VariableConstraints {
  min?: number;
  max?: number;
  /**
   * clamp: ajusta ao limite (padrão). reject: a transação inteira falha.
   */
  on_overflow?: 'clamp' | 'reject';
  max_length?: number;
  /**
   * Valores permitidos (obrigatório para type=enum).
   *
   * @minItems 1
   */
  values?: [string, ...string[]];
  /**
   * Só enum: texto exibido ao jogador para cada valor na interpolação (Data Model §9). Traduzível por variable/<id qualificado>/value/<valor>.
   */
  labels?: {
    [k: string]: string;
  };
}
/**
 * Raiz de bundle-licenses.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/bundle-licenses.schema.json).
 *
 * Licenças e créditos de terceiros do jogo (Build System §4.5): plugins, e o credit dos assets que entram no jogo, agrupados. A tela de créditos os mostra com licenses_list (UI Spec §3.1). Os avisos do motor e do runtime (kind engine) não ficam aqui: o runtime os acrescenta sempre, de Engine.get_license_text(), Engine.get_copyright_info() e das licenças que vêm no pacote dele.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "BundleLicenses".
 */
export interface BundleLicenses {
  /**
   * Ordem: plugin, font, asset; dentro de cada tipo, por title e depois por author (comparação de strings por pontos de código).
   */
  entries: {
    /**
     * plugin: um plugin habilitado; font: credit de assets que são todos do tipo font; asset: credit dos demais assets.
     */
    kind: 'plugin' | 'font' | 'asset';
    /**
     * plugin: name do manifesto (no default_locale do plugin); font e asset: o author do credit.
     */
    title: string;
    author?: string;
    /**
     * SPDX no plugin; texto livre em credit.license, no idioma original, sem tradução (Data Model §10.1).
     */
    license?: string;
    url?: string;
    /**
     * Texto exato que a licença pede para mostrar (credit.notice).
     */
    notice?: string;
    /**
     * Texto completo da licença: o LICENSE do plugin ou o arquivo de credit.license_file.
     */
    text?: string;
    /**
     * Assets que este crédito cobre, em ordem lexicográfica (font e asset).
     */
    assets?: AssetRef[];
  }[];
}
/**
 * Raiz de bundle-locale.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/bundle-locale.schema.json).
 *
 * Todas as traduções de um idioma do jogo, por caminho de texto (Data Model §9): as do projeto sobre as do preset. Inclui o idioma-fonte só com os textos do preset e dos plugins, porque os do projeto estão inline no bundle.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "BundleLocale".
 */
export interface BundleLocale {
  locale: Locale;
  strings: {
    [k: string]: string;
  };
}
/**
 * Raiz de bundle-plugins.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/bundle-plugins.schema.json).
 *
 * Plugins habilitados no bundle, com a permissão efetiva (pedido ∩ concessão ∩ aceite, Plugin SDK §4.1) e a configuração com os defaults do config_schema.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "BundlePlugins".
 */
export interface BundlePlugins {
  plugins: {
    [k: string]: {
      id: string;
      namespace: Namespace;
      version: SemVer;
      /**
       * Pasta do plugin no jogo.
       */
      path: string;
      trust?: 'official' | 'reviewed' | 'local';
      embedded?: boolean;
      /**
       * Capacidades efetivas, com prefixo runtime:/editor:.
       */
      capabilities: string[];
      variables: {
        read: string[];
        write: string[];
      };
      scenes: string[];
      config: {
        [k: string]: unknown;
      };
    };
  };
}
export interface Button1 {
  type?: 'button';
  text?: LocalizedText;
  icon?: AssetRef;
  actions?: ActionList;
  [k: string]: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ConformanceFileVariables".
 */
export interface ConformanceFileVariables {
  [k: string]: TypedVar;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "TypedVar".
 */
export interface TypedVar {
  type: 'boolean' | 'integer' | 'number' | 'string' | 'enum';
  value: boolean | number | string;
  default?: boolean | number | string;
  constraints?: VariableConstraints;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Error".
 */
export interface Error {
  error: 'VARIABLE_NOT_FOUND' | 'TYPE_MISMATCH' | 'OUT_OF_RANGE' | 'CONSTRAINT_VIOLATION';
}
/**
 * Formato de números por idioma do jogo, com precedência sobre a tabela do runtime (Runtime Spec §12.1). Útil para idiomas fora da tabela.
 */
export interface NumberFormats {
  [k: string]: {
    decimal: string;
    /**
     * Separador de milhar; vazio = sem separador.
     */
    group: string;
    /**
     * Número mínimo de dígitos da parte inteira para usar o separador de milhar.
     */
    min_grouping?: number;
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Scheduling".
 */
export interface Scheduling {
  /**
   * scheduled (padrão): candidata ao Scene Scheduler. manual: só é executada por link direto (entry_scene, fallback_scene, end.then.scene, SceneAPI.request de plugin autorizado).
   */
  mode?: 'scheduled' | 'manual';
  priority?: number;
  conditions?: ConditionList;
  /**
   * Quantas vezes a cena pode ser concluída. Padrão 1. null = ilimitado.
   */
  max_plays?: number | null;
  /**
   * Número de pontos de seleção que devem passar antes de a cena voltar a ser elegível. Padrão 0.
   */
  cooldown?: number;
  /**
   * Grupos (definidos no capítulo ou no projeto) de que esta cena participa.
   */
  exclusive_groups?: Id[];
  /**
   * Peso no sorteio quando o capítulo usa tie_breaker=weighted_random. Padrão 1.
   */
  weight?: number;
  /**
   * Ordem de autoria usada no desempate determinístico. Cenas sem 'order' vêm depois de todas as que têm 'order' e, entre si, ficam na ordem do id (Runtime Spec §4.3).
   */
  order?: number;
}
/**
 * Raiz de chapter.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/chapter.schema.json).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Chapter".
 */
export interface Chapter {
  $schema?: string;
  id: EntityId;
  title: LocalizedText;
  /**
   * Variáveis de capítulo (chapter.<key>). Reiniciadas ao entrar no capítulo e descartadas ao sair.
   */
  variables?: VariableDefinition[];
  entry_scene?: EntityId;
  scheduler?: SchedulerSettings;
  /**
   * Grupos de exclusividade com tempo de vida do capítulo. Não podem repetir um id dos grupos do projeto (R015).
   */
  exclusive_groups?: ExclusiveGroup[];
  /**
   * Quando o capítulo termina. O capítulo é verificado em cada ponto de seleção.
   */
  completion?: {
    conditions?: ConditionList;
    /**
     * O que fazer quando nenhuma cena é elegível. advance (padrão): termina o capítulo. scene: executa 'fallback_scene'. end_game: termina o jogo.
     */
    on_exhausted?: 'advance' | 'scene' | 'end_game';
    fallback_scene?: EntityId;
  };
  /**
   * Capítulos candidatos ao terminar. Mesmo algoritmo do Scheduler (condições → prioridade → ordem do project.json). As condições são avaliadas antes de descartar as variáveis chapter.*, então podem usá-las. Pode apontar para um capítulo já visitado. Vazio ou nenhum elegível = fim de jogo.
   */
  next?: {
    chapter: EntityId;
    conditions?: ConditionList;
    priority?: number;
  }[];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "SchedulerSettings".
 */
export interface SchedulerSettings {
  /**
   * deterministic (padrão): menos execuções → executada há mais tempo → ordem de autoria → id. weighted_random: sorteio ponderado por 'weight' entre as empatadas; reproduzível (e salvo no save) só com settings.reproducible_rng (Runtime Spec §12.2).
   */
  tie_breaker?: 'deterministic' | 'weighted_random';
  /**
   * Se cenas sem capítulo (chapter: null) entram na lista de candidatas. Padrão: true.
   */
  include_global_scenes?: boolean;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ExclusiveGroup".
 */
export interface ExclusiveGroup {
  id: Id;
  description?: string;
  /**
   * Quantas cenas distintas do grupo podem ser executadas no tempo de vida do grupo. Padrão: 1.
   */
  max_plays?: number;
}
/**
 * Raiz de character.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/character.schema.json).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Character".
 */
export interface Character {
  $schema?: string;
  id: EntityId;
  key: Id;
  /**
   * Keys anteriores do personagem (Data Model §12), aplicadas ao carregar saves antigos.
   */
  renamed_from?: Id[];
  name: LocalizedText;
  display_name?: LocalizedText;
  color?: string;
  /**
   * Mapa expressão → asset de sprite.
   */
  expressions?: {
    [k: string]: AssetRef;
  };
  default_expression?: Id;
  voice?: {
    blip?: AssetRef;
  };
  /**
   * Sobrescreve o default de variáveis de personagem para este personagem (chave = key).
   */
  initial_values?: {
    [k: string]: Literal;
  };
  tags?: string[];
}
export interface ChoiceNode1 {
  type?: 'choice';
  prompt?: LocalizedText;
  speaker?: EntityId | null;
  record?: WritableVariableRef;
  /**
   * @minItems 1
   */
  options: [
    {
      id: EntityId;
      text: LocalizedText;
      value?: Id;
      visible_if?: ConditionList;
      enabled_if?: ConditionList;
      effects?: EffectList;
      goto?: EntityId;
      censored_text?: LocalizedText;
    },
    ...{
      id: EntityId;
      text: LocalizedText;
      value?: Id;
      visible_if?: ConditionList;
      enabled_if?: ConditionList;
      effects?: EffectList;
      goto?: EntityId;
      censored_text?: LocalizedText;
    }[]
  ];
  censored_prompt?: LocalizedText;
  [k: string]: unknown;
}
/**
 * Raiz de conformance.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/conformance.schema.json).
 *
 * Arquivo de vetores de conformidade (spec 08). Cada caso tem entradas e o resultado esperado; os dois interpretadores DEVEM produzir exatamente o expect.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ConformanceFile".
 */
export interface ConformanceFile {
  $schema?: string;
  title: string;
  covers: string[];
  /**
   * @minItems 1
   */
  cases: [Case, ...Case[]];
}
export interface Container1 {
  type?: 'container';
  layout?: 'row' | 'column' | 'grid';
  spacing?: number;
  columns?: number;
  children: Element[];
  [k: string]: unknown;
}
export interface Image1 {
  type?: 'image';
  asset: AssetRef;
  animation?: Animation;
  [k: string]: unknown;
}
export interface Label1 {
  type?: 'label';
  text: LocalizedText;
  align?: 'left' | 'center' | 'right';
  [k: string]: unknown;
}
export interface Hotspot1 {
  type?: 'hotspot';
  area: Area;
  cursor?: Cursor;
  highlight?: Highlight;
  actions?: ActionList;
  on_hover?: ActionList;
  label?: LocalizedText;
  [k: string]: unknown;
}
export interface Slider1 {
  type?: 'slider';
  bind:
    | 'volume.master'
    | 'volume.music'
    | 'volume.ambient'
    | 'volume.sfx'
    | 'volume.voice'
    | 'display_mode'
    | 'resolution'
    | 'vsync'
    | 'fps_limit_vn'
    | 'fps_limit_activity'
    | 'text_speed'
    | 'auto_delay'
    | 'skip_unread'
    | 'locale'
    | 'text_scale'
    | 'reduce_motion'
    | 'subtitles'
    | 'high_contrast'
    | 'show_hotspots'
    | 'content_filter';
  label?: LocalizedText;
  min?: number;
  max?: number;
  step?: number;
  [k: string]: unknown;
}
export interface Toggle1 {
  type?: 'toggle';
  bind:
    | 'volume.master'
    | 'volume.music'
    | 'volume.ambient'
    | 'volume.sfx'
    | 'volume.voice'
    | 'display_mode'
    | 'resolution'
    | 'vsync'
    | 'fps_limit_vn'
    | 'fps_limit_activity'
    | 'text_speed'
    | 'auto_delay'
    | 'skip_unread'
    | 'locale'
    | 'text_scale'
    | 'reduce_motion'
    | 'subtitles'
    | 'high_contrast'
    | 'show_hotspots'
    | 'content_filter';
  label?: LocalizedText;
  [k: string]: unknown;
}
export interface Select1 {
  type?: 'select';
  bind:
    | 'volume.master'
    | 'volume.music'
    | 'volume.ambient'
    | 'volume.sfx'
    | 'volume.voice'
    | 'display_mode'
    | 'resolution'
    | 'vsync'
    | 'fps_limit_vn'
    | 'fps_limit_activity'
    | 'text_speed'
    | 'auto_delay'
    | 'skip_unread'
    | 'locale'
    | 'text_scale'
    | 'reduce_motion'
    | 'subtitles'
    | 'high_contrast'
    | 'show_hotspots'
    | 'content_filter';
  label?: LocalizedText;
  options?: {
    value: Literal;
    text: LocalizedText;
  }[];
  [k: string]: unknown;
}
export interface SlotGrid1 {
  type?: 'slot_grid';
  mode: 'save' | 'load';
  columns?: number;
  rows?: number;
  slot_style?: Id;
  [k: string]: unknown;
}
export interface GalleryGrid1 {
  type?: 'gallery_grid';
  source: 'endings' | 'images' | 'music';
  columns?: number;
  locked_asset?: AssetRef;
  [k: string]: unknown;
}
export interface RecordsList1 {
  type?: 'records_list';
  /**
   * <namespace>.<quadro> declarado em records do plugin.
   */
  board: string;
  max_items?: number;
  empty_text?: LocalizedText;
  [k: string]: unknown;
}
export interface LicensesList1 {
  type?: 'licenses_list';
  /**
   * O que listar, a partir do licenses.json do bundle (Build System §4.5): engine (o aviso de licença do Godot, das bibliotecas dele, do runtime e das fontes do preset, que o runtime acrescenta e mostra sempre, mesmo fora da lista), plugins (licenças dos plugins), fonts (credit dos assets do tipo font) e assets (credit dos demais assets que entram no jogo). Padrão: os quatro.
   */
  include?: ('engine' | 'plugins' | 'fonts' | 'assets')[];
  [k: string]: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "CosmeticHotspot".
 */
export interface CosmeticHotspot {
  id: Id;
  area: Area;
  label?: LocalizedText;
  cursor?: Cursor;
  highlight?: Highlight;
  on_hover?: ActionList;
  on_press?: ActionList;
  on_release?: ActionList;
}
export interface EffectsNode1 {
  type?: 'effects';
  effects: EffectList;
  on_fail?: EntityId;
  [k: string]: unknown;
}
export interface EmitNode1 {
  type?: 'emit';
  event: EventName;
  payload?: {
    [k: string]: ValueExpr;
  };
  [k: string]: unknown;
}
export interface EndNode1 {
  type?: 'end';
  /**
   * schedule (padrão): ponto de seleção normal. {scene}: pedido de cena seguinte do mesmo capítulo ou global (R014) — aceito se a cena for elegível ou 'manual', senão cai na seleção normal. end_chapter / end_game: encerramento explícito.
   */
  then?:
    | ('schedule' | 'end_chapter' | 'end_game')
    | {
        scene: EntityId;
      };
  ending?: Id;
  [k: string]: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ErrorObject".
 */
export interface ErrorObject {
  code: number;
  message: string;
  data?: {
    code?:
      | 'UNAUTHENTICATED'
      | 'UNSUPPORTED_VERSION'
      | 'INVALID_PREVIEW_STATE'
      | 'BUNDLE_INVALID'
      | 'NOT_FOUND'
      | 'STATE_REJECTED'
      | 'BUSY'
      | 'INTERNAL';
    vn_code?: string;
    state?: string;
    kind?: string;
    id?: string;
    path?: string;
    detail?: string;
    message?: string;
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "GameState".
 */
export interface GameState {
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  preview: 'RUNNING' | 'PAUSED';
  chapter: EntityId | null;
  scene: EntityId | null;
  node: EntityId | null;
  variables?: VariableValues;
  history?: History;
  stage?: Stage;
  /**
   * @maxItems 50
   */
  backlog?: {
    speaker?: string | null;
    text: string;
    path?: string;
  }[];
  plugins?: {
    [k: string]: {
      enabled: boolean;
      faulted: boolean;
      activity?: string | null;
    };
  };
  rng?: {
    seed: string;
    state: string;
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "VariableValues".
 */
export interface VariableValues {
  [k: string]: boolean | number | string;
}
export interface History {
  selection_count: number;
  scenes: {
    [k: string]: {
      plays: number;
      starts?: number;
      last_selection?: number;
    };
  };
  /**
   * Grupo de exclusividade → cenas do grupo já executadas. Ids de grupo são únicos entre projeto e capítulo (R015).
   */
  groups?: {
    [k: string]: EntityId[];
  };
  chapters?: {
    [k: string]: {
      entries?: number;
      completed?: boolean;
    };
  };
  /**
   * Eventos story.* e de plugins emitidos desde o último ponto de seleção. Eventos sys.* não entram (Runtime Spec §7.2).
   */
  events_since_selection?: EventName[];
  /**
   * Pedido de cena de plugin (SceneAPI.request) ainda não atendido; é consumido no próximo ponto de seleção (Runtime Spec §4.3).
   */
  pending_request?: EntityId | null;
  /**
   * Seleções seguidas da fallback_scene do capítulo ativo (Runtime Spec §4.3).
   */
  fallback_streak?: number;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Stage".
 */
export interface Stage {
  /**
   * Asset do cenário atual; null quando o cenário é um set (aí set e set_states ficam preenchidos).
   */
  background?: AssetRef | null;
  /**
   * Modo stream (Runtime Spec §5.5): censor do passo que pôs o cenário atual (background ou, se for set, set e set_states). Ao mudar o modo ou ao carregar, se o passo não valeria no modo atual, o palco mostra background_base. Ausente = passo sem censor.
   */
  background_censor?: 'skip' | 'only';
  /**
   * Modo stream: último cenário posto por um passo sem censor (um asset, ou um set com o estado das camadas), mostrado quando o cenário atual sai do palco por background_censor (Runtime Spec §5.5). Ausente ou null = content_filter.placeholder, senão a cor de fundo do tema.
   */
  background_base?:
    | AssetRef
    | {
        set: Id;
        set_states?: {
          [k: string]: string;
        };
      }
    | null;
  characters?: {
    id: EntityId;
    expression?: Id;
    position?: string | number;
    /**
     * Modo stream (Runtime Spec §5.5): censor do passo show que deixou a personagem como está. Ao mudar o modo ou ao carregar, se o passo não valeria no modo atual, a personagem volta a base ou, sem base, sai do palco. Ausente = passo sem censor.
     */
    censor?: 'skip' | 'only';
    /**
     * Modo stream: expressão e posição da personagem imediatamente antes do passo censurado (Runtime Spec §5.5). Um hide sem censor tira a personagem e a base junto. Ausente = ela não estava no palco nesse momento; some enquanto o passo não vale.
     */
    base?: {
      expression?: Id;
      position?: string | number;
    };
  }[];
  audio?: {
    [k: string]: {
      asset: AssetRef;
      loop?: boolean;
      volume?: number;
      /**
       * Modo stream (Runtime Spec §5.5): censor do passo audio play que pôs este som no canal. Ao mudar o modo ou ao carregar, se o passo não valeria no modo atual, o canal volta a base ou, sem base, silencia. Ausente = passo sem censor.
       */
      censor?: 'skip' | 'only';
      /**
       * Modo stream: o som que tocava no canal imediatamente antes do passo censurado (Runtime Spec §5.5). Um stop sem censor silencia o canal e apaga a base. Ausente = o canal estava em silêncio.
       */
      base?: {
        asset: AssetRef;
        loop?: boolean;
        volume?: number;
      };
    };
  };
  /**
   * Set em cena, se o fundo for um cenário composto.
   */
  set?: Id | null;
  /**
   * Estado atual de cada camada do set (camada → estado) e visibilidade alterada.
   */
  set_states?: {
    [k: string]: string;
  };
}
export interface HideNode1 {
  type?: 'hide';
  character: EntityId | '*';
  transition?: Transition;
  [k: string]: unknown;
}
export interface InteractNode1 {
  type?: 'interact';
  prompt?: LocalizedText;
  record?: WritableVariableRef;
  /**
   * @minItems 1
   */
  hotspots: [
    {
      id: EntityId;
      label?: LocalizedText;
      censored_label?: LocalizedText;
      value?: Id;
      area: Area;
      cursor?: Cursor;
      highlight?: Highlight;
      visible_if?: ConditionList;
      enabled_if?: ConditionList;
      /**
       * Some depois de usado nesta execução da cena.
       */
      once?: boolean;
      effects?: EffectList;
      goto?: EntityId;
    },
    ...{
      id: EntityId;
      label?: LocalizedText;
      censored_label?: LocalizedText;
      value?: Id;
      area: Area;
      cursor?: Cursor;
      highlight?: Highlight;
      visible_if?: ConditionList;
      enabled_if?: ConditionList;
      /**
       * Some depois de usado nesta execução da cena.
       */
      once?: boolean;
      effects?: EffectList;
      goto?: EntityId;
    }[]
  ];
  exit?: {
    label: LocalizedText;
    censored_label?: LocalizedText;
    goto?: EntityId;
    style?: Id;
  };
  censored_prompt?: LocalizedText;
  [k: string]: unknown;
}
export interface JumpNode1 {
  type?: 'jump';
  goto: EntityId;
  [k: string]: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Layer".
 */
export interface Layer {
  id: Id;
  asset: AssetRef;
  position?: Fraction2;
  pivot?: Fraction2;
  scale?: number;
  z?: number;
  opacity?: number;
  /**
   * Deslocamento máximo com o mouse, em fração da tela. Desligado com reduce_motion.
   */
  parallax?: number;
  animation?: Animation;
  /**
   * Variações nomeadas. O estado inicial é 'default'.
   */
  states?: {
    [k: string]: {
      asset?: AssetRef;
      visible?: boolean;
      opacity?: number;
      tint?: Color;
      animation?: Animation;
    };
  };
}
export interface LineNode1 {
  type?: 'line';
  /**
   * ID do personagem, ou null/ausente para narração.
   */
  speaker?: EntityId | null;
  text: LocalizedText;
  expression?: Id;
  voice?: AssetRef;
  censored_text?: LocalizedText;
  [k: string]: unknown;
}
/**
 * Raiz de locale.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/locale.schema.json).
 *
 * Traduções. Chave = caminho estável do texto (ex.: scene_beach/n3, scene_beach/n7/opt_fish, character/alice/name). Valor = texto traduzido. 'source_hash' detecta tradução desatualizada.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "LocaleFile".
 */
export interface LocaleFile {
  $schema?: string;
  locale: Locale;
  strings: {
    [k: string]:
      | string
      | {
          text: string;
          /**
           * 16 primeiros caracteres hex do SHA-256 do texto-fonte normalizado (Data Model §9).
           */
          source_hash?: string;
          /**
           * 'desatualizada' não é gravado: o Studio calcula pelo source_hash (Req §9).
           */
          status?: 'draft' | 'reviewed';
        };
  };
}
export interface ShowNode1 {
  type?: 'show';
  character: EntityId;
  expression?: Id;
  position?: ('far_left' | 'left' | 'center' | 'right' | 'far_right') | number;
  transition?: Transition;
  [k: string]: unknown;
}
export interface WaitNode1 {
  type?: 'wait';
  seconds: number;
  skippable?: boolean;
  [k: string]: unknown;
}
export interface PluginNode1 {
  type?: 'plugin';
  /**
   * <namespace>.<atividade>, ex.: fishing.fishing_game.
   */
  activity: string;
  /**
   * Validado contra o params_schema da atividade no plugin.json.
   */
  params?: {
    [k: string]: unknown;
  };
  on_result?: {
    effects?: EffectList;
    /**
     * Mapa outcome → nó. Outcomes devem existir na declaração da atividade.
     */
    outcomes?: {
      [k: string]: EntityId;
    };
  };
  on_error?: EntityId;
  [k: string]: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_activity_ended".
 */
export interface NotifyActivityEnded {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  activity: string;
  /**
   * story: nó plugin de uma cena (scene e node obrigatórios); free_play: modo livre, sem cena (Plugin SDK §6.1).
   */
  mode: 'story' | 'free_play';
  scene?: EntityId;
  node?: EntityId;
  /**
   * O outcome do complete; no modo livre, também 'cancelled' (o jogador saiu) ou 'failed'. null quando a atividade falhou na história.
   */
  outcome: string | null;
  skipped: boolean;
  failed: boolean;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_activity_started".
 */
export interface NotifyActivityStarted {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  activity: string;
  /**
   * story: nó plugin de uma cena (scene e node obrigatórios); free_play: modo livre, sem cena (Plugin SDK §6.1).
   */
  mode: 'story' | 'free_play';
  scene?: EntityId;
  node?: EntityId;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_chapter_ended".
 */
export interface NotifyChapterEnded {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  chapter: EntityId;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_chapter_started".
 */
export interface NotifyChapterStarted {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  chapter: EntityId;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_error".
 */
export interface NotifyError {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  code: string;
  message: string;
  scene?: EntityId;
  node?: EntityId;
  variable?: string;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_event_emitted".
 */
export interface NotifyEventEmitted {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  name: EventName;
  payload: unknown;
  source?: string;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_game_ended".
 */
export interface NotifyGameEnded {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  ending: Id | null;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_log".
 */
export interface NotifyLog {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  level: 'debug' | 'info' | 'warning' | 'error';
  message: string;
  scene?: EntityId;
  node?: EntityId;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_node_entered".
 */
export interface NotifyNodeEntered {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  scene: EntityId;
  node: EntityId;
  type: string;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_plugin_faulted".
 */
export interface NotifyPluginFaulted {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  plugin: string;
  error: string;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_plugin_log".
 */
export interface NotifyPluginLog {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  plugin: string;
  level: 'debug' | 'info' | 'warning' | 'error';
  message: string;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_plugin_permission_denied".
 */
export interface NotifyPluginPermissionDenied {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  plugin: string;
  capability: string;
  call: string;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_scene_ended".
 */
export interface NotifySceneEnded {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  scene: EntityId;
  then: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_scene_started".
 */
export interface NotifySceneStarted {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  scene: EntityId;
  chapter: EntityId | null;
  selection_count: number;
  /**
   * Motivo da seleção (SchedulerEvaluation.reason); entry = entry_scene do capítulo (RT §3.2); start = cena forçada por preview.start.
   */
  reason: 'request' | 'plugin_request' | 'priority' | 'tie_break' | 'fallback' | 'entry' | 'start';
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_scheduler_evaluated".
 */
export interface NotifySchedulerEvaluated {
  selection_count: number;
  chapter: EntityId;
  action: 'start_scene' | 'exit_chapter' | 'end_game';
  chosen: EntityId | null;
  reason: 'request' | 'plugin_request' | 'priority' | 'tie_break' | 'fallback' | 'completion' | 'exhausted';
  candidates: {
    scene: EntityId;
    eligible: boolean;
    blocked_by?:
      'mode_manual' | 'max_plays' | 'cooldown' | 'exclusive_group' | 'conditions' | 'lower_priority' | 'tie_break';
    detail?: {
      [k: string]: unknown;
    };
    failed?: {
      path: string;
      variable?: string;
      operator?: string;
      expected?: unknown;
      actual?: unknown;
      event?: string;
    }[];
  }[];
  request_refused?: {
    scene: EntityId;
    by: 'content' | 'plugin';
  };
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_session_closing".
 */
export interface NotifySessionClosing {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  reason: 'window_closed' | 'stop' | 'error';
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_state_changed".
 */
export interface NotifyStateChanged {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  changes: Changes;
  source: string;
}
/**
 * Só no painel com user_data 'project': o VNStorage gravou ou apagou um arquivo, e o Studio aplica em .vnstudio/preview/user/ (spec 07 §1.4).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_storage_delete".
 */
export interface NotifyStorageDelete {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  /**
   * Caminho relativo a .vnstudio/preview/user/, com '/'. O Studio recusa o que sair da pasta (spec 07 §1.4).
   */
  path: string;
}
/**
 * Só no painel com user_data 'project': o VNStorage gravou ou apagou um arquivo, e o Studio aplica em .vnstudio/preview/user/ (spec 07 §1.4).
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Notify_storage_write".
 */
export interface NotifyStorageWrite {
  seq: number;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  batch?: unknown[];
  /**
   * Caminho relativo a .vnstudio/preview/user/, com '/'. O Studio recusa o que sair da pasta (spec 07 §1.4).
   */
  path: string;
  data: string;
}
/**
 * settings.json do jogador (Runtime Spec §8.5): preferências do jogo, sem assinatura e fora do save e do perfil.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "PlayerSettings".
 */
export interface PlayerSettings {
  locale?: Locale;
  /**
   * Caracteres por segundo; 0 = texto instantâneo. Padrão: project.json → settings.text_speed, senão 40.
   */
  text_speed?: number;
  /**
   * Segundos de espera no modo automático depois de a fala terminar. Padrão: project.json → settings.auto_delay, senão 1,5.
   */
  auto_delay?: number;
  skip_unread?: boolean;
  volume?: {
    master?: number;
    music?: number;
    ambient?: number;
    sfx?: number;
    voice?: number;
  };
  /**
   * Escala do texto (Req §12).
   */
  text_scale?: number;
  /**
   * Desliga transições e animações de texto (Req §12).
   */
  reduce_motion?: boolean;
  /**
   * Mostra legendas de sons com caption (Req §12).
   */
  subtitles?: boolean;
  /**
   * Caixa de diálogo opaca e texto de alto contraste (Req §12).
   */
  high_contrast?: boolean;
  display_mode?: 'windowed' | 'fullscreen' | 'borderless';
  /**
   * Tamanho da janela; a resolução base do jogo continua settings.resolution do projeto.
   *
   * @minItems 2
   * @maxItems 2
   */
  resolution?: [number, number];
  vsync?: boolean;
  /**
   * Limite de quadros por segundo fora de minijogos; 0 = sem limite (UI Spec §8).
   */
  fps_limit_vn?: number;
  /**
   * Limite durante atividades de plugin; 0 = sem limite.
   */
  fps_limit_activity?: number;
  /**
   * Destaca todos os hotspots (acessibilidade).
   */
  show_hotspots?: boolean;
  /**
   * Modo stream: mostra as versões censuradas (Data Model §10.4). Padrão: project.json → content_filter.default, senão false. Na edição censurada é sempre true.
   */
  content_filter?: boolean;
}
/**
 * Raiz de plugin-lock.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/plugin-lock.schema.json).
 *
 * Gerado pelo Dependency Resolver. Versionado no Git. O Build System só usa o que está aqui e recusa pacotes cujo hash não confere. O mesmo schema vale para .vnstudio/plugin-lock.local.json, fora do Git, que guarda vínculos de desenvolvimento e sobrepõe entradas deste arquivo só naquela máquina.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "PluginLock".
 */
export interface PluginLock {
  lock_version: 1;
  plugins: {
    [k: string]: {
      version: SemVer;
      namespace: Namespace;
      /**
       * URL ou caminho exato do pacote usado.
       */
      resolved: string;
      integrity?: Hash;
      enabled: boolean;
      trust?: 'official' | 'reviewed' | 'local';
      /**
       * 'project' ou ids dos plugins que exigiram este como dependência.
       */
      requested_by?: string[];
      dependencies?: {
        [k: string]: SemVer;
      };
      /**
       * Vínculo de desenvolvimento com uma pasta local (fonte path:). Só aparece em .vnstudio/plugin-lock.local.json. O Studio lê os arquivos direto da pasta, sem pacote nem hash. A exportação recusa o vínculo até o plugin ser empacotado (P013).
       */
      link?: boolean;
      /**
       * Plugin embutido no repositório do jogo (fonte path: para uma pasta, spec 09 §3.2). Vai para o Git com o projeto; o Studio lê a pasta direto e o Build System empacota e calcula o integrity no build.
       */
      embedded?: boolean;
    };
  };
}
export interface PluginManifest1 {
  $schema?: string;
  manifest_version: 1;
  /**
   * <publisher>.<nome>, globalmente único. O publisher 'vnstudio' é reservado a plugins oficiais.
   */
  id: string;
  namespace: Namespace;
  name: string;
  version: SemVer;
  description?: string;
  default_locale: Locale;
  author?: {
    name: string;
    url?: string;
  };
  /**
   * Identificador SPDX.
   */
  license: string;
  homepage?: string;
  repository?: string;
  /**
   * Versões dos SDKs contra as quais o plugin foi escrito.
   */
  sdk: {
    runtime?: SemVerRange;
    editor?: SemVerRange;
  };
  /**
   * runtime é obrigatório. studio e data_model ausentes = qualquer versão; godot ausente = a do runtime.
   */
  compatibility: {
    studio?: SemVerRange;
    runtime: SemVerRange;
    godot?: SemVerRange;
    data_model?: SemVerRange;
    /**
     * Plataformas de exportação em que o plugin foi testado. Ausente = todas. O validador avisa (W008) quando o projeto exporta para uma plataforma fora da lista.
     */
    platforms?: ('windows' | 'linux' | 'macos' | 'android' | 'web')[];
  };
  /**
   * [editor] = Editor Extension, [runtime] = Runtime Extension, ambos = Full Extension.
   *
   * @minItems 1
   */
  targets: ['editor' | 'runtime', ...('editor' | 'runtime')[]];
  entrypoints: {
    /**
     * Script GDScript que estende VNRuntimePlugin.
     */
    runtime?: string;
    /**
     * Módulo ES compilado que exporta activate(ctx).
     */
    editor?: string;
  };
  /**
   * Capacidades solicitadas. Nada é concedido por padrão.
   */
  capabilities?: {
    runtime?: (
      | 'variables.read'
      | 'variables.write'
      | 'events.emit'
      | 'events.subscribe'
      | 'transactions'
      | 'characters.read'
      | 'scenes.request'
      | 'save.data'
      | 'assets.read'
      | 'audio.play'
      | 'ui.overlay'
      | 'input.capture'
      | 'profile.data'
    )[];
    /**
     * 'network' só é aceita em plugins oficiais no v1 (P016).
     */
    editor?: (
      | 'panels'
      | 'commands'
      | 'node_inspector'
      | 'project.read'
      | 'project.write'
      | 'assets.read'
      | 'assets.write'
      | 'notifications'
      | 'preview'
      | 'network'
    )[];
  };
  /**
   * Variáveis do projeto que o plugin pede para ler/escrever. Aceita '*' como segmento (ex.: character.*.affection) ou '$config.<campo>' para a variável que o autor escolher num campo do config_schema com format 'vn-variable'. As do próprio namespace são implícitas. Variáveis de outro plugin só podem ser lidas, e só com o plugin em dependencies ou optional_dependencies (P017).
   */
  variable_permissions?: {
    read?: VariablePattern[];
    write?: VariablePattern[];
  };
  /**
   * Variáveis próprias (plugin.<namespace>.<key>). Vivem durante todo o jogo. O Studio as mostra ao autor como 'do plugin <name>', somente leitura na definição; cada uma DEVERIA ter 'name' (aviso W007), traduzível em plugin_locales (variable/<key>/name). Não aceitam 'access' nem 'characters', e 'derived' só pode ler variáveis do próprio namespace (P017).
   */
  variables?: VariableDefinition[];
  events?: {
    /**
     * Eventos que o plugin emite. Nomes devem começar com '<namespace>.'.
     */
    emits?: {
      name: EventName;
      description?: string;
      /**
       * JSON Schema do payload; validado em debug/preview.
       */
      payload?: {
        [k: string]: unknown;
      };
    }[];
    /**
     * Eventos (ou padrões com * no final) que o plugin escuta. Exige a capacidade runtime events.subscribe (W012).
     */
    subscribes?: string[];
  };
  /**
   * Atividades que nós 'plugin' das cenas podem invocar (minigames, telas de inventário…).
   */
  activities?: {
    id: Id;
    name: string;
    description?: string;
    /**
     * JSON Schema dos params; o Studio gera o formulário a partir dele. Cada propriedade DEVERIA ter 'title' e 'description' (aviso W007), traduzíveis em plugin_locales. Aceita os mesmos formatos vn-* do config_schema.
     */
    params_schema?: {
      [k: string]: unknown;
    };
    /**
     * Resultados possíveis; o nó da cena mapeia cada um para um nó. 'cancelled' e 'failed' são reservados para o modo livre (Plugin SDK §6.1).
     *
     * @minItems 1
     */
    outcomes: [Id1, ...Id1[]];
    /**
     * JSON Schema do payload de resultado.
     */
    result_schema?: {
      [k: string]: unknown;
    };
    /**
     * Se o jogador pode pular (o runtime usa default_outcome).
     */
    skippable?: boolean;
    default_outcome?: Id;
    /**
     * Nome legível de cada outcome, exibido no Studio (ex.: won → 'Ganhou'). Traduzível em plugin_locales.
     */
    outcome_labels?: {
      [k: string]: string;
    };
    /**
     * Mapeamentos prontos de resultado → variável que o Studio oferece ao autor. O autor só escolhe a variável (do tipo indicado); o Studio grava o efeito em on_result.effects.
     */
    suggested_effects?: {
      id: Id;
      label: string;
      description?: string;
      op: 'set' | 'add' | 'subtract';
      variable_type: 'boolean' | 'integer' | 'number' | 'string';
      value: ValueExpr;
    }[];
    /**
     * Taxa mínima de quadros de que o minijogo precisa; o runtime a usa se o limite do jogador para atividades for menor, salvo escolha explícita (UI Spec §8).
     */
    min_fps?: number;
    /**
     * A atividade pode ser jogada fora da história, no modo livre (SDK §6.1), a partir de um botão de menu (ação play_activity, UI Spec §4). params são os parâmetros padrão do modo livre, validados contra params_schema.
     */
    free_play?: {
      params?: {
        [k: string]: unknown;
      };
    };
  }[];
  /**
   * JSON Schema da configuração por projeto (em plugins.json → config). Campos com format 'vn-variable' (com 'vn-variable-type'), 'vn-asset' (com 'vn-asset-type'), 'vn-scene' ou 'vn-character' viram seletores no Studio e são conferidos pelo validador (P018); assets citados assim entram no build sem always_include (Plugin SDK §4.4).
   */
  config_schema?: {
    [k: string]: unknown;
  };
  /**
   * Migrações declarativas da config salva no projeto, aplicadas em ordem pelo Studio ao atualizar o plugin (Plugin SDK §8). Servem também para plugins sem parte de editor; migrateConfig() do Editor SDK roda depois, se existir.
   */
  config_migrations?: {
    /**
     * MAJOR da versão do plugin que gravou a config.
     */
    from_major: number;
    /**
     * Se remove dados; o Studio pede confirmação (ADD §10).
     */
    destructive?: boolean;
    /**
     * Operações JSON Patch (RFC 6902) sobre a config.
     */
    ops: {
      [k: string]: unknown;
    }[];
  }[];
  save?: {
    /**
     * Versão do formato dos dados salvos via SaveAPI. Incrementar exige implementar _vn_migrate_save_data().
     */
    data_version?: number;
  };
  /**
   * Dados próprios do plugin no perfil do jogador (profile.json), que sobrevivem entre partidas: progresso de modo livre, desbloqueios, estatísticas. Exige a capacidade profile.data (SDK §9.1).
   */
  profile?: {
    /**
     * Versão do formato dos dados de perfil. Incrementar exige implementar _vn_migrate_profile_data().
     */
    data_version?: number;
  };
  /**
   * Quadros de recordes guardados no perfil do jogador (SDK §9.1). Exigem a capacidade profile.data. Nome traduzível em plugin_locales (record/<id>/name).
   */
  records?: {
    id: Id;
    name: string;
    /**
     * desc (padrão): maior é melhor. asc: menor é melhor (tempo).
     */
    order?: 'desc' | 'asc';
    /**
     * Quantas marcas o quadro guarda. Padrão 10.
     */
    keep?: number;
    /**
     * Como a UI mostra a marca. Padrão integer.
     */
    format?: 'integer' | 'number' | 'time_ms';
  }[];
  /**
   * Modo stream (SDK §5.6): supported = o plugin trata o próprio conteúdo adulto quando ctx.content_filter está ligado; o catálogo mostra o selo. Assets do projeto já chegam filtrados sem isso.
   */
  content_filter?: 'supported';
  /**
   * id do plugin → faixa semver.
   */
  dependencies?: {
    [k: string]: SemVerRange;
  };
  optional_dependencies?: {
    [k: string]: SemVerRange;
  };
  /**
   * Contribuições declarativas ao Studio (carregadas antes de executar código do plugin).
   */
  editor?: {
    panels?: {
      id: Id;
      title: string;
      location?: 'sidebar' | 'bottom' | 'main_tab' | 'modal';
      icon?: string;
    }[];
    commands?: {
      id: Id;
      title: string;
      shortcut?: string;
    }[];
    /**
     * Atividades que têm inspetor próprio no Scene Editor (senão o Studio gera um formulário do params_schema).
     */
    node_inspectors?: Id[];
  };
  /**
   * Traduções dos textos do plugin: locale → (caminho → texto). Caminhos exibidos no Studio: activity/<id>/name, activity/<id>/description, activity/<id>/outcome/<outcome>, activity/<id>/param/<prop>/title, activity/<id>/param/<prop>/description, activity/<id>/suggested/<id>, config/<prop>/title, config/<prop>/description, variable/<key>/name, variable/<key>/description. Caminhos runtime/<...> são textos mostrados ao jogador dentro do minijogo, lidos por ctx.i18n.text() no idioma atual do jogo.
   */
  plugin_locales?: {
    [k: string]: {
      [k: string]: string;
    };
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Session_hello_params".
 */
export interface SessionHelloParams {
  /**
   * Obrigatório na janela (WebSocket); ausente no painel (Preview Protocol §1).
   */
  token?: string;
  protocol: string;
  studio_version?: string;
}
export interface PreviewLoadParams2 {
  /**
   * Janela (runtime nativo): caminho absoluto da pasta do bundle no sistema.
   */
  bundle_path?: string;
  /**
   * Painel (runtime Web): URL /project/preview/narrative/ do protocolo vnpreview, na origem daquele sistema (vnpreview://localhost/ no macOS e no Linux, http://vnpreview.localhost/ no Windows; spec 07 §1.1 e §1.3).
   */
  bundle_url?: string;
  /**
   * Onde está a pasta assets/ do projeto (spec 07 §1.3). Em modo preview, o runtime troca o prefixo res://vn_content/assets/ dos caminhos do bundle por esta base. Painel: a URL /project/assets/ do protocolo vnpreview (o runtime codifica cada segmento do resto do caminho); janela: o caminho absoluto da pasta no sistema.
   */
  assets_base: string;
  locale?: Locale;
  /**
   * Onde ficam saves, perfil e configurações do Preview: memory (padrão) ou a pasta .vnstudio/preview/user/ do projeto (spec 07 §1.4).
   */
  user_data?: 'memory' | 'project';
  /**
   * Só no painel com user_data 'project' (spec 07 §1.4): o conteúdo atual de .vnstudio/preview/user/, caminho relativo → bytes em base64. O VNStorage do runtime começa com esses arquivos na memória.
   */
  user_files?: {
    [k: string]: string;
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_start_params".
 */
export interface PreviewStartParams {
  chapter?: EntityId;
  scene?: EntityId;
  node?: EntityId;
  variables?: VariableValues;
  profile?: Profile;
  /**
   * Liga ou desliga o modo stream desde o início, sem mexer nas configurações guardadas (spec 07 §3).
   */
  content_filter?: boolean;
  seed?: string;
  paused?: boolean;
}
/**
 * profile.json: dados que sobrevivem entre saves e novos jogos.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Profile".
 */
export interface Profile {
  save_format: SemVer;
  project_id: Id;
  variables: {
    [k: string]: Literal;
  };
  endings?: Id[];
  /**
   * Textos já lidos (para 'pular apenas texto lido'), como os 16 primeiros caracteres hex do SHA-256 do caminho de texto, em ordem. Mantém o perfil pequeno.
   */
  seen_text?: string[];
  /**
   * Dados de perfil e recordes de cada plugin, por namespace (SDK §9.1).
   */
  plugins?: {
    [k: string]: {
      plugin_version?: SemVer;
      data_version?: number;
      /**
       * Opaco; JSON de até 64 KB.
       */
      data?: {
        [k: string]: unknown;
      };
      records?: {
        [k: string]: {
          score: number;
          at: string;
          /**
           * Até 1 KB; textos curtos e números (ex.: dificuldade).
           */
          meta?: {
            [k: string]: unknown;
          };
        }[];
      };
    };
  };
  /**
   * Assinatura hmac-sha256-<base64> do JSON canônico sem este campo, com a chave de saves do projeto (Build System §8.3).
   */
  integrity?: string;
  /**
   * Assets da galeria que o jogador já viu numa cena (Runtime Spec §5.2), por id, em ordem lexicográfica. Só recebe assets com gallery: true cuja seção está em project.json → gallery.sections; jogo sem galeria não acrescenta nada.
   */
  seen_assets?: AssetRef[];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_stop_params".
 */
export interface PreviewStopParams {}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_pause_params".
 */
export interface PreviewPauseParams {}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_resume_params".
 */
export interface PreviewResumeParams {}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_step_params".
 */
export interface PreviewStepParams {
  until?: 'node' | 'blocking' | 'scene_end' | 'selection';
}
export interface PreviewInputParams1 {
  action: 'advance' | 'choose' | 'click' | 'skip_activity' | 'cancel_activity' | 'complete_activity' | 'play_activity';
  option?: EntityId;
  hotspot?: EntityId;
  outcome?: string;
  payload?: {
    [k: string]: unknown;
  };
  /**
   * play_activity: <namespace>.<atividade> com free_play (Plugin SDK §6.1).
   */
  activity?: string;
  /**
   * play_activity: sobrepõe os params de free_play.
   */
  params?: {
    [k: string]: unknown;
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_set_variables_params".
 */
export interface PreviewSetVariablesParams {
  variables: VariableValues;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_get_state_params".
 */
export interface PreviewGetStateParams {
  include?: ('variables' | 'history' | 'stage' | 'backlog' | 'plugins')[];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_explain_selection_params".
 */
export interface PreviewExplainSelectionParams {
  scene?: EntityId;
}
export interface PreviewReloadParams2 {
  /**
   * Recarga incremental (Preview Protocol §3).
   *
   * @minItems 1
   */
  patch?: [
    {
      file: string;
      pointer: string;
      value?: unknown;
    },
    ...{
      file: string;
      pointer: string;
      value?: unknown;
    }[]
  ];
  bundle_path?: string;
  bundle_url?: string;
  changed?: string[];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_reload_plugins_params".
 */
export interface PreviewReloadPluginsParams {
  /**
   * @minItems 1
   */
  ids: [string, ...string[]];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_show_screen_params".
 */
export interface PreviewShowScreenParams {
  screen: Id;
  simulate?: {
    has_save?: boolean;
    in_game?: boolean;
    platform?: 'windows' | 'linux' | 'macos' | 'web';
    endings?: Id[];
    content_filter?: boolean;
    content_filter_available?: boolean;
    last_activity_outcome?: string;
    last_record_rank?: number;
    seen_assets?: AssetRef[];
    gallery_unlock_all?: boolean;
  };
}
/**
 * Muda uma configuração do jogador como se ele a mudasse numa tela (UI Spec §8); emite o evento correspondente, como sys.content_filter_changed.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_set_setting_params".
 */
export interface PreviewSetSettingParams {
  /**
   * Um bind de configuração da UI Spec §8, como content_filter ou locale.
   */
  setting: string;
  value: unknown;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_set_locale_params".
 */
export interface PreviewSetLocaleParams {
  locale: Locale;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_explain_selection_result".
 */
export interface PreviewExplainSelectionResult {
  selection_count: number;
  chapter: EntityId;
  action: 'start_scene' | 'exit_chapter' | 'end_game';
  chosen: EntityId | null;
  reason: 'request' | 'plugin_request' | 'priority' | 'tie_break' | 'fallback' | 'completion' | 'exhausted';
  candidates: {
    scene: EntityId;
    eligible: boolean;
    blocked_by?:
      'mode_manual' | 'max_plays' | 'cooldown' | 'exclusive_group' | 'conditions' | 'lower_priority' | 'tie_break';
    detail?: {
      [k: string]: unknown;
    };
    failed?: {
      path: string;
      variable?: string;
      operator?: string;
      expected?: unknown;
      actual?: unknown;
      event?: string;
    }[];
  }[];
  request_refused?: {
    scene: EntityId;
    by: 'content' | 'plugin';
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_get_state_result".
 */
export interface PreviewGetStateResult {
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  preview: 'RUNNING' | 'PAUSED';
  chapter: EntityId | null;
  scene: EntityId | null;
  node: EntityId | null;
  variables?: VariableValues;
  history?: History;
  stage?: Stage;
  /**
   * @maxItems 50
   */
  backlog?: {
    speaker?: string | null;
    text: string;
    path?: string;
  }[];
  plugins?: {
    [k: string]: {
      enabled: boolean;
      faulted: boolean;
      activity?: string | null;
    };
  };
  rng?: {
    seed: string;
    state: string;
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_input_result".
 */
export interface PreviewInputResult {
  accepted: boolean;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_load_result".
 */
export interface PreviewLoadResult {
  content_hash: string;
  format_version: string;
  chapters: number;
  scenes: number;
  plugins: string[];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_pause_result".
 */
export interface PreviewPauseResult {
  node: EntityId | null;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_reload_plugins_result".
 */
export interface PreviewReloadPluginsResult {
  reloaded: string[];
  activity_restarted: boolean;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_reload_result".
 */
export interface PreviewReloadResult {
  content_hash?: string;
  resumed: 'node' | 'scene_restarted' | 'selection_point' | 'ui_only' | 'not_running';
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_resume_result".
 */
export interface PreviewResumeResult {
  node: EntityId | null;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_set_locale_result".
 */
export interface PreviewSetLocaleResult {}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_set_setting_result".
 */
export interface PreviewSetSettingResult {}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_set_variables_result".
 */
export interface PreviewSetVariablesResult {
  changes: Changes;
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_show_screen_result".
 */
export interface PreviewShowScreenResult {}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_start_result".
 */
export interface PreviewStartResult {
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
  preview: 'RUNNING' | 'PAUSED';
  chapter: EntityId | null;
  scene: EntityId | null;
  node: EntityId | null;
  variables?: VariableValues;
  history?: History;
  stage?: Stage;
  /**
   * @maxItems 50
   */
  backlog?: {
    speaker?: string | null;
    text: string;
    path?: string;
  }[];
  plugins?: {
    [k: string]: {
      enabled: boolean;
      faulted: boolean;
      activity?: string | null;
    };
  };
  rng?: {
    seed: string;
    state: string;
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_step_result".
 */
export interface PreviewStepResult {
  node: EntityId | null;
  phase:
    | 'BOOT'
    | 'TITLE'
    | 'NEW_GAME'
    | 'LOAD_GAME'
    | 'CHAPTER_ENTER'
    | 'SELECTION_POINT'
    | 'SCENE_RUNNING'
    | 'ACTIVITY'
    | 'SCENE_END'
    | 'CHAPTER_EXIT'
    | 'GAME_END';
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Preview_stop_result".
 */
export interface PreviewStopResult {}
/**
 * Raiz de project.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/project.schema.json).
 *
 * Raiz de um projeto do Visual Novel Studio.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Project".
 */
export interface Project {
  $schema?: string;
  format_version: SemVer;
  id: Id;
  /**
   * Nome do jogo no idioma-fonte. Tradução pela chave project/title (Data Model §9).
   */
  title: string;
  version?: SemVer;
  authors?: string[];
  default_locale: Locale;
  locales?: Locale[];
  start_chapter: EntityId;
  /**
   * Ordem de autoria dos capítulos (também é o desempate final entre capítulos).
   */
  chapters?: EntityId[];
  runtime?: {
    min_version?: SemVer;
    godot?: SemVerRange;
  };
  scheduler?: SchedulerSettings;
  /**
   * Grupos de exclusividade com tempo de vida de jogo inteiro. Um id não pode se repetir num capítulo (R015).
   */
  exclusive_groups?: ExclusiveGroup[];
  /**
   * Eventos do namespace story usados pelo projeto. Emitir ou testar um evento story.* não declarado gera aviso W015.
   */
  events?: {
    name: EventName;
    description?: string;
    /**
     * JSON Schema do payload.
     */
    payload?: {
      [k: string]: unknown;
    };
  }[];
  settings?: {
    /**
     * @minItems 2
     * @maxItems 2
     */
    resolution?: [number, number];
    /**
     * Padrão do jogo para PlayerSettings.text_speed (caracteres por segundo).
     */
    text_speed?: number;
    autosave?: 'off' | 'scene_start' | 'selection_point';
    /**
     * Tempo máximo de uma atividade de plugin; ao estourar, a atividade falha e segue on_error (Runtime Spec §5.3). Ausente = sem limite.
     */
    activity_timeout_seconds?: number;
    /**
     * Opcional, desligado por padrão. Ligado, todo sorteio (random_int, weighted_random, ctx.rng) usa o RNG reproduzível do Runtime Spec §12.2: estado no save e traço idêntico entre Preview no Studio e Runtime. Desligado, os sorteios usam o RNG comum do motor e não entram no save nem nos vetores de conformidade.
     */
    reproducible_rng?: boolean;
    /**
     * Padrões de exibição e o que o jogador pode mudar (UI Spec §8).
     */
    display?: {
      /**
       * Tamanhos de janela oferecidos ao jogador. Ausente = 1280x720, 1600x900, 1920x1080, 2560x1440 com a mesma proporção da resolução base.
       */
      resolutions?: [number, number][];
      display_mode?: 'windowed' | 'fullscreen' | 'borderless';
      vsync?: boolean;
      fps_limit_vn?: number;
      fps_limit_activity?: number;
    };
    number_formats?: NumberFormats;
    /**
     * Padrão do jogo para PlayerSettings.auto_delay (segundos).
     */
    auto_delay?: number;
  };
  /**
   * Finais do jogo. Todo 'ending' de nó end DEVE estar aqui (R012). Alimenta a galeria de finais e sys.endings.<id>.
   */
  endings?: {
    id: Id;
    title: LocalizedText;
    description?: LocalizedText;
    image?: AssetRef;
    order?: number;
  }[];
  /**
   * Modo stream / filtro de conteúdo (Data Model §10.4, UI Spec §8). O jogador liga pela configuração content_filter; o conteúdo é marcado em assets.json (censored) e nas cenas (censored_text, censor).
   */
  content_filter?: {
    /**
     * Valor inicial da configuração do jogador.
     */
    default?: boolean;
    /**
     * Na primeira vez que o jogo abre, antes do título, pergunta se o jogador quer ligar o modo stream (Runtime Spec §3.0).
     */
    ask_on_first_launch?: boolean;
    placeholder?: AssetRef;
  };
  /**
   * Galeria do jogo (Data Model §10.5, UI Spec §3.1). Opcional: ausente = o jogo não tem galeria (a tela gallery do preset não entra, o botão do título some e nada é marcado em profile.seen_assets). O autor escolhe quais seções entram.
   */
  gallery?: {
    /**
     * Seções da galeria. endings: finais de project.json → endings; images: assets image e background com gallery: true; music: assets audio_music com gallery: true. O preset mostra as abas nesta ordem fixa, não na ordem da lista.
     *
     * @minItems 1
     */
    sections: ['endings' | 'images' | 'music', ...('endings' | 'images' | 'music')[]];
  };
  /**
   * Caminho do arquivo de tema, relativo à raiz do projeto. Ausente = theme.json se existir, senão o preset 'classic'.
   */
  theme?: string;
  /**
   * Metadados de exportação editados no assistente de exportação do Studio.
   */
  build?: {
    /**
     * Nome do arquivo gerado, sem extensão. Padrão: derivado de title.
     */
    executable_name?: string;
    icon?: AssetRef;
    company?: string;
    splash?: AssetRef;
    /**
     * Plataformas de exportação do v1. Android fica para depois (Build System §14).
     */
    platforms?: ('windows' | 'linux' | 'macos' | 'web')[];
    /**
     * Assinatura de código por plataforma. Credenciais nunca ficam no projeto: só o nome de um perfil guardado no cofre do sistema operacional.
     */
    signing?: {
      windows?: string;
      macos?: string;
    };
    /**
     * Idiomas incluídos no build (Build System §5.3). Ausente = todos de locales. Deve conter default_locale.
     *
     * @minItems 1
     */
    locales?: [Locale, ...Locale[]];
    /**
     * Compressão das imagens no build (Build System §6.2): lossless (padrão) ou lossy (WebP, menor; recomendado para Web).
     */
    textures?: 'lossless' | 'lossy';
    /**
     * Proteção do conteúdo (Build System §8). Ofuscação e detecção de alteração, não segurança.
     */
    protection?: {
      /**
       * Opção avançada: cifra o PCK com templates personalizados (Build System §8.4).
       */
      encrypt_pck?: boolean;
      /**
       * O que fazer com save ou perfil cuja assinatura não confere (Build System §8.3).
       */
      save_tamper?: 'ignore' | 'flag' | 'reject';
      /**
       * Impressão digital da chave de saves: 8 primeiros caracteres hex do SHA-256 da chave (não é segredo). Gravada pelo Studio no primeiro build de release. Se presente e a chave disponível (cofre ou VNSTUDIO_SAVE_KEY) faltar ou tiver outra impressão digital, o build para com B017 (Build System §8.1).
       */
      save_key_id?: string;
    };
    /**
     * Permite a ação open_url nas telas (UI Spec §4). Padrão true; sempre pede confirmação.
     */
    allow_urls?: boolean;
    /**
     * standard (padrão): o jogador liga e desliga o modo stream. censored: edição censurada, com o filtro sempre ligado, o controle oculto e sem os originais no pacote (Build System §5.4).
     */
    edition?: 'standard' | 'censored';
  };
}
/**
 * Raiz de plugins.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/plugins.schema.json).
 *
 * Plugins usados pelo projeto, com faixas de versão, permissões CONCEDIDAS e configuração. Editado pelo Plugin Manager; o plugin-lock.json é gerado a partir dele.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "ProjectPlugins".
 */
export interface ProjectPlugins {
  $schema?: string;
  plugins: {
    [k: string]: {
      version: SemVerRange;
      /**
       * Origem do pacote (spec 09 §3.1). catalog:<nome do catálogo> (ex.: catalog:official; o plugin é a chave deste mapa; no v1 só existe catalog:official, o índice dos plugins oficiais, e o schema recusa outro nome; Plugin SDK §13.2) | github:<owner>/<repo> | path:<arquivo .vnplugin relativo ao projeto> (pacote guardado, ex.: vendor/plugins/acme.cards-1.2.0.vnplugin) | path:<pasta relativa ao projeto> (plugin embutido, ex.: plugins/quiz). Vínculos de desenvolvimento não ficam aqui, e sim em .vnstudio/plugin-lock.local.json (Plugin SDK §12.3).
       */
      source: string;
      enabled?: boolean;
      grants?: {
        /**
         * Subconjunto das capacidades pedidas (runtime e editor juntos, ex.: 'runtime:variables.write').
         */
        capabilities?: string[];
        /**
         * Variáveis concedidas. Leitura exige plugins_read diferente de none na variável (P014); escrita exige plugins_write: granted (P008).
         */
        variables?: {
          read?: string[];
          write?: string[];
        };
        /**
         * Cenas que o plugin pode pedir via SceneAPI.request(). Vazio = nenhuma. No runtime, o pedido só é aceito para cena do capítulo ativo ou global (Runtime Spec §4.3).
         */
        scenes?: EntityId[];
      };
      /**
       * Validado contra config_schema do plugin.
       */
      config?: {
        [k: string]: unknown;
      };
    };
  };
}
/**
 * Raiz de save.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/save.schema.json).
 *
 * Snapshot completo do estado narrativo. Gerado e lido apenas pelo Save Manager. Arquivos de perfil usam $defs/Profile e as preferências do jogador, $defs/PlayerSettings.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Save".
 */
export interface Save {
  save_format: SemVer;
  project: {
    id: Id;
    version: SemVer;
    content_hash?: Hash;
  };
  runtime_version: SemVer;
  created_at: string;
  label?: string;
  /**
   * Caminho relativo da miniatura.
   */
  thumbnail?: string;
  /**
   * A miniatura foi capturada com o filtro desligado e o palco mostrava algum asset com censored. Com o filtro ligado, a tela de saves mostra o placeholder no lugar dela (Runtime Spec §8.5).
   */
  thumbnail_sensitive?: boolean;
  state: {
    /**
     * Todas as variáveis com persistence=save do escopo ativo, inclusive as que estão no padrão (Runtime Spec §8.2). Chave = ID qualificado.
     */
    variables: {
      [k: string]: Literal;
    };
    chapter: null | {
      id: EntityId;
      /**
       * selection_count no momento da entrada.
       */
      entered_at?: number;
    };
    /**
     * Cena em andamento, ou null se o save foi feito num ponto de seleção.
     */
    scene?: null | {
      id: EntityId;
      node: EntityId;
      stage?: Stage;
      /**
       * Hotspots 'once' de nós interact já usados nesta execução da cena (UI Spec §6).
       */
      used_hotspots?: EntityId[];
    };
    history: History;
    /**
     * Só presente com settings.reproducible_rng (Runtime Spec §12.2). Estado em hexadecimal, porque inteiros de 64 bits perdem precisão em JSON no JavaScript.
     */
    rng?: {
      algorithm: 'pcg32';
      seed: string;
      state: string;
      /**
       * Estado do fluxo de RNG de cada plugin fora de atividades (ctx.rng), por namespace (Runtime Spec §12.2).
       */
      streams?: {
        [k: string]: string;
      };
    };
    /**
     * Dados opacos de cada plugin (via SaveAPI), versionados para migração.
     */
    plugins?: {
      [k: string]: {
        plugin_version: SemVer;
        data_version: number;
        data: unknown;
      };
    };
    /**
     * Últimas falas exibidas, limitado pelo runtime. Guarda o caminho do texto e os valores interpolados, não o texto pronto, para que trocar de idioma ou atualizar o jogo se reflita no histórico.
     */
    backlog?: {
      /**
       * Caminho de texto (<cena>/<nó> ou <cena>/<nó>/<opção> para a escolha feita).
       */
      path: string;
      speaker?: EntityId | null;
      /**
       * Valores das variáveis interpoladas no momento da fala.
       */
      vars?: {
        [k: string]: Literal;
      };
    }[];
  };
  /**
   * Assinatura hmac-sha256-<base64> do JSON canônico sem este campo, com a chave de saves do projeto (Build System §8.3).
   */
  integrity?: string;
}
/**
 * Raiz de scene.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/scene.schema.json).
 *
 * Uma cena: metadados de agendamento + grafo plano de nós. Um arquivo por cena para reduzir conflitos de merge no Git.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Scene".
 */
export interface Scene {
  $schema?: string;
  id: EntityId;
  /**
   * Capítulo dono da cena, ou null para cena global (candidata em qualquer capítulo que inclua cenas globais).
   */
  chapter: EntityId | null;
  title?: string;
  description?: string;
  tags?: string[];
  scheduling?: Scheduling;
  /**
   * Variáveis locais (scene.<key>). Reiniciadas a cada execução da cena e descartadas ao terminar.
   */
  variables?: VariableDefinition[];
  start?: EntityId;
  /**
   * @minItems 1
   */
  nodes: [Node, ...Node[]];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "SchedulerEvaluation".
 */
export interface SchedulerEvaluation {
  selection_count: number;
  chapter: EntityId;
  action: 'start_scene' | 'exit_chapter' | 'end_game';
  chosen: EntityId | null;
  reason: 'request' | 'plugin_request' | 'priority' | 'tie_break' | 'fallback' | 'completion' | 'exhausted';
  candidates: {
    scene: EntityId;
    eligible: boolean;
    blocked_by?:
      'mode_manual' | 'max_plays' | 'cooldown' | 'exclusive_group' | 'conditions' | 'lower_priority' | 'tie_break';
    detail?: {
      [k: string]: unknown;
    };
    failed?: {
      path: string;
      variable?: string;
      operator?: string;
      expected?: unknown;
      actual?: unknown;
      event?: string;
    }[];
  }[];
  request_refused?: {
    scene: EntityId;
    by: 'content' | 'plugin';
  };
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Session_hello_result".
 */
export interface SessionHelloResult {
  runtime_version: string;
  godot_version: string;
  protocol: string;
  platform: 'windows' | 'macos' | 'linux' | 'web';
  features: string[];
}
/**
 * Raiz de set.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/set.schema.json).
 *
 * Cenário composto: camadas com estados e hotspots cosméticos. Usado como fundo de telas (ui/*.json → set) e de cenas (nó background → set). UI Spec §5.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "SetFile".
 */
export interface SetFile {
  $schema?: string;
  id: Id;
  description?: string;
  /**
   * @minItems 1
   */
  layers: [Layer, ...Layer[]];
  /**
   * Áreas clicáveis cosméticas. Só aceitam ações cosméticas (U004).
   */
  hotspots?: CosmeticHotspot[];
}
/**
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Style".
 */
export interface Style {
  extends?: Id;
  image?: {
    normal?: AssetRef;
    hover?: AssetRef;
    pressed?: AssetRef;
    disabled?: AssetRef;
    focus?: AssetRef;
    selected?: AssetRef;
  };
  shape?: 'rect' | 'rounded' | 'pill' | 'circle';
  radius?: number;
  fill?: {
    normal?: Color;
    hover?: Color;
    pressed?: Color;
    disabled?: Color;
    focus?: Color;
    selected?: Color;
  };
  border?: {
    normal?: Color;
    hover?: Color;
    pressed?: Color;
    disabled?: Color;
    focus?: Color;
    selected?: Color;
  };
  border_width?: number;
  font?: AssetRef;
  font_size?: number;
  text_color?: {
    normal?: Color;
    hover?: Color;
    pressed?: Color;
    disabled?: Color;
    focus?: Color;
    selected?: Color;
  };
  outline?: {
    color?: Color;
    size?: number;
  };
  shadow?: {
    color?: Color;
    /**
     * @minItems 2
     * @maxItems 2
     */
    offset?: [number, number];
  };
  /**
   * @minItems 4
   * @maxItems 4
   */
  padding?: [number, number, number, number];
  icon_position?: 'left' | 'right' | 'top' | 'only';
  hover?: {
    scale?: number;
    /**
     * @minItems 2
     * @maxItems 2
     */
    offset?: [number, number];
    rotation?: number;
    tint?: Color;
    glow?: Color;
    duration?: number;
    easing?: 'linear' | 'ease_in' | 'ease_out' | 'ease_in_out' | 'back' | 'elastic' | 'bounce';
  };
  press?: {
    scale?: number;
    /**
     * @minItems 2
     * @maxItems 2
     */
    offset?: [number, number];
    rotation?: number;
    tint?: Color;
    glow?: Color;
    duration?: number;
    easing?: 'linear' | 'ease_in' | 'ease_out' | 'ease_in_out' | 'back' | 'elastic' | 'bounce';
  };
  focus?: {
    scale?: number;
    /**
     * @minItems 2
     * @maxItems 2
     */
    offset?: [number, number];
    rotation?: number;
    tint?: Color;
    glow?: Color;
    duration?: number;
    easing?: 'linear' | 'ease_in' | 'ease_out' | 'ease_in_out' | 'back' | 'elastic' | 'bounce';
  };
  idle?: Animation;
  sounds?: {
    hover?: AssetRef;
    press?: AssetRef;
    disabled_press?: AssetRef;
  };
  cursor?: Cursor;
  auto_shrink?: boolean;
}
/**
 * Raiz de theme.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/theme.schema.json).
 *
 * Estilos do jogo: fontes, cores, caixa de diálogo, escolhas e estilos de botão. O layout das telas fica em ui/*.json (UI Spec). Tudo é opcional; o que faltar vem do preset.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Theme".
 */
export interface Theme {
  $schema?: string;
  /**
   * Preset da interface (UI Spec §2.1): o tema e as telas do projeto ficam por cima dele. O v1 só tem 'classic'; outros presets entram nesta lista quando existirem.
   */
  preset?: 'classic';
  fonts?: {
    dialogue?: AssetRef;
    name?: AssetRef;
    ui?: AssetRef;
    dialogue_size?: number;
    name_size?: number;
    ui_size?: number;
    title?: AssetRef;
    /**
     * Fontes de reserva por idioma ou sistema de escrita (ja, zh-Hans, zh-Hant, ko…), para caracteres que a fonte principal não tem (UI Spec §7.2, W020). Ausente = Noto do preset.
     */
    fallbacks?: {
      /**
       * @minItems 1
       */
      [k: string]: [AssetRef, ...AssetRef[]];
    };
  };
  colors?: {
    text?: Color;
    accent?: Color;
    panel?: Color;
    disabled?: Color;
    focus?: Color;
  };
  textbox?: {
    image?: AssetRef;
    position?: 'bottom' | 'top' | 'full_screen';
    /**
     * Fração da altura da tela.
     */
    height?: number;
    /**
     * @minItems 4
     * @maxItems 4
     */
    padding?: [number, number, number, number];
    opacity?: number;
    name_plate?: {
      image?: AssetRef;
      /**
       * @minItems 2
       * @maxItems 2
       */
      offset?: [number, number];
      use_character_color?: boolean;
    };
    advance_indicator?: AssetRef;
  };
  choices?: {
    button?: AssetRef;
    button_hover?: AssetRef;
    button_disabled?: AssetRef;
    layout?: 'center' | 'list_left' | 'list_right';
    style?: Id;
  };
  sounds?: {
    click?: AssetRef;
    hover?: AssetRef;
    choice?: AssetRef;
  };
  /**
   * Estilos com nome, usados por elementos das telas (UI Spec §7.1). Os nomes button, choice, slot, slider, toggle, select e hotspot são os estilos padrão de cada tipo.
   */
  styles?: {
    [k: string]: Style;
  };
  cursor?: AssetRef;
  /**
   * Caixa de confirmação (ação confirm).
   */
  dialog?: {
    image?: AssetRef;
    button_style?: Id;
  };
}
/**
 * Raiz de ui-screen.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/ui-screen.schema.json).
 *
 * Uma tela da interface do jogo (título, pausa, salvar/carregar, configurações, galeria, créditos, HUD ou tela própria). UI Spec §3.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "UiScreen".
 */
export interface UiScreen {
  $schema?: string;
  id: Id;
  kind: 'title' | 'pause' | 'save' | 'load' | 'settings' | 'gallery' | 'credits' | 'hud' | 'custom';
  set?: Id;
  background?: AssetRef;
  music?: AssetRef;
  transition?: Transition;
  modal?: boolean;
  focus_start?: Id;
  elements: Element[];
  on_open?: ActionList;
  on_close?: ActionList;
  back?: ActionList;
}
/**
 * Raiz de variables.schema.json (https://schemas.vnstudio.dev/specs-v1.0.0/variables.schema.json).
 *
 * Variáveis globais e de personagem do projeto. Variáveis de capítulo e de cena ficam nos próprios arquivos; as de plugin, no plugin.json.
 *
 * This interface was referenced by `VnStudioSchemas`'s JSON-Schema
 * via the `definition` "Variables".
 */
export interface Variables {
  $schema?: string;
  global?: VariableDefinition[];
  /**
   * Modelos instanciados para cada personagem (character.<key do personagem>.<key>). 'characters' restringe a quais personagens o modelo se aplica.
   */
  character?: VariableDefinition[];
}

/** Apelido de VariableDefinition. */
export type Variable = VariableDefinition;
