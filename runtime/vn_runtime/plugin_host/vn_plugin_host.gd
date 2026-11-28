@abstract
class_name VNPluginHost
extends VNModule
## Plugin Host / Plugin Manager (RT §1): carrega plugins, aplica permissões e
## roda atividades. É a autoridade sobre o ciclo de vida dos plugins.
##
## Monta o [code]VNPluginContext[/code] do Runtime SDK de cada plugin (Plugin
## SDK §5.2). Os serviços do SDK ([code]VNNarrativeAPI[/code],
## [code]VNEventAPI[/code], [code]VNSceneAPI[/code]…) são fachadas finas: a
## permissão é conferida aqui ([method has_capability],
## [method can_read_variable], [method can_write_variable],
## [method can_request_scene]) e a operação vai ao módulo dono (State Manager
## com [method VNStateManager.plugin_caller], Event Bus com o id do plugin,
## Scheduler). Plugins identificados pelo namespace ([code]&"fishing"[/code]).
##
## Specs: Plugin SDK §4 (permissões, confiança), §5.1 (ciclo de vida e ordem),
## §5.2–§5.5 (contexto e APIs), §6 e §6.1 (atividades), §9 (saves); RT §3.0
## passo 5, §3.1 passo 4, §3.4, §5.3, §8.3 passos 2 e 5, §9. Tarefas: M3-01,
## M3-02, M3-04, M3-05.

## A atividade terminou. [param status] é um de [constant STATUS_COMPLETED],
## [constant STATUS_FAILED], [constant STATUS_CANCELLED] ou
## [constant STATUS_SKIPPED]. Com [code]completed[/code], [param outcome] é o
## do plugin; com [code]skipped[/code], o [code]default_outcome[/code];
## nos outros, vazio. [param payload] é o do [code]complete[/code].
signal activity_ended(status: StringName, outcome: StringName, payload: Dictionary)

## Um plugin passou a [i]faulted[/i] (RT §9): ouvintes removidos, atividades
## vão direto para [code]on_error[/code]. Para o Preview: [code]plugin.faulted[/code].
signal plugin_faulted(plugin: StringName, error: String)

## Chamada recusada por falta de capacidade (Plugin SDK §5.2). Para o Preview:
## [code]plugin.permission_denied { plugin, capability, call }[/code].
signal permission_denied(plugin: StringName, capability: StringName, call: String)

const STATUS_COMPLETED := &"completed"
const STATUS_FAILED := &"failed"
const STATUS_CANCELLED := &"cancelled"
const STATUS_SKIPPED := &"skipped"

const MODE_STORY := &"story"         ## nó plugin de uma cena
const MODE_FREE_PLAY := &"free_play" ## modo livre (Plugin SDK §6.1)

## Erros por sessão até o plugin virar faulted (RT §9).
const FAULT_THRESHOLD := 5


func module_id() -> StringName:
	return &"plugins"


# --- Carga e ciclo de vida (Plugin SDK §5.1) --------------------------------

## Boot, passo 5 (RT §3.0): lê [code]plugins.json[/code]
## ([code]bundle-plugins.schema.json[/code]), carrega em ordem topológica de
## dependências com empate pela ordem lexicográfica do id, chama
## [code]_vn_init(ctx)[/code] em todos e depois [code]_vn_ready()[/code] em
## todos. Um plugin que falha fica de fora e o jogo segue (RT §9).
@abstract func load_plugins(plugins: Dictionary) -> void

## Namespaces carregados, na ordem de inicialização.
@abstract func loaded_plugins() -> PackedStringArray

@abstract func is_loaded(plugin: StringName) -> bool
@abstract func is_faulted(plugin: StringName) -> bool

## Conta um erro do plugin (script, fail, timeout, PERMISSION_DENIED,
## WRONG_THREAD) e o marca faulted ao chegar a [constant FAULT_THRESHOLD].
@abstract func report_error(plugin: StringName, error: String) -> void

## [code]_vn_game_started(is_new_game)[/code] em todos (RT §3.1 passo 4).
@abstract func notify_game_started(is_new_game: bool) -> void

## [code]_vn_game_ended()[/code] em todos (RT §3.4, §8.3 passo 2).
@abstract func notify_game_ended() -> void

## [code]_vn_shutdown()[/code] em todos, ao fechar o jogo.
@abstract func shutdown() -> void


# --- Permissões (Plugin SDK §4; DM §4.6) ------------------------------------

## O plugin tem a capacidade concedida ([code]&"variables.read"[/code],
## [code]&"scenes.request"[/code], [code]&"input.capture"[/code]…).
@abstract func has_capability(plugin: StringName, capability: StringName) -> bool

## Permissão efetiva de leitura/escrita de uma variável: o que o plugin pede,
## o que o projeto concede e o que a variável aceita (DM §4.6). O State
## Manager consulta na verificação 6 do RT §6.2.
@abstract func can_read_variable(plugin: StringName, variable: String) -> bool
@abstract func can_write_variable(plugin: StringName, variable: String) -> bool

## A cena está em [code]grants.scenes[/code] do plugin (Plugin SDK §5.5).
@abstract func can_request_scene(plugin: StringName, scene_id: String) -> bool

## O plugin pode emitir o evento: no próprio namespace e declarado em
## [code]events.emits[/code] (Plugin SDK §7).
@abstract func can_emit(plugin: StringName, event_name: String) -> bool


# --- Atividades (RT §5.3; Plugin SDK §6) ------------------------------------

## Inicia uma atividade ([code]<namespace>.<atividade>[/code]) com
## [code]_vn_start_activity[/code]. Recusa ([code]ok = false[/code]) se o
## plugin não está carregado, está faulted ou já há atividade. O fim chega
## por [signal activity_ended]. O autosave de segurança e o evento
## [code]sys.activity_started[/code] são do Narrative Engine, antes desta chamada.
@abstract func start_activity(activity: StringName, params: Dictionary, mode: StringName = MODE_STORY) -> VNResult

## Encerra a atividade em curso sem outcome: o handle fica inativo **antes**
## de [code]_vn_cancel_activity[/code] (Plugin SDK §6). [param status] é
## [constant STATUS_SKIPPED] (pulo, com [code]default_outcome[/code]),
## [constant STATUS_FAILED] (timeout) ou [constant STATUS_CANCELLED]
## (jogador saiu do modo livre ou voltou ao título).
@abstract func cancel_activity(status: StringName) -> void

## A atividade em curso: [code]{ activity, mode, params, skippable, min_fps }[/code]
## ([code]min_fps[/code]: 0 se o manifesto não declara, Plugin SDK §6), ou vazio.
@abstract func current_activity() -> Dictionary


# --- Saves (RT §8.2–§8.3; Plugin SDK §9) ------------------------------------

## [code]state.plugins[/code] do save: [code]_vn_save()[/code] de cada plugin
## com [code]save.data[/code], com [code]plugin_version[/code] e
## [code]data_version[/code]. Dados de plugin ausente do jogo voltam intactos.
@abstract func save_data() -> Dictionary

## Carrega [code]state.plugins[/code] na ordem do RT §8.3 passo 5:
## [code]_vn_game_started(false)[/code], migração se preciso, [code]_vn_load(data)[/code]
## ([code]_vn_load(null)[/code] se o save não tem dados do plugin).
@abstract func load_data(plugins_state: Dictionary) -> void
