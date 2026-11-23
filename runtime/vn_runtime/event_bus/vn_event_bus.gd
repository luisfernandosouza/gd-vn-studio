@abstract
class_name VNEventBus
extends VNModule
## Event Bus / Event Executor (RT §1): fila e entrega de eventos.
##
## [method emit] **enfileira** e nunca chama ouvintes na mesma pilha; a fila é
## drenada por [method drain] ao fim da operação atual (fim do nó, fim do
## commit, fim do callback do plugin), em ordem FIFO. Ouvintes que emitem vão
## para o fim da fila; mais de [constant MAX_CHAINED] eventos numa mesma
## drenagem é erro (provável ciclo) e a drenagem é interrompida.
##
## Ao entregar um evento [code]story.*[/code] ou de plugin, o bus registra o nome
## em [method VNSceneScheduler.record_event] ([code]history.events_since_selection[/code]);
## eventos [code]sys.*[/code] não entram (RT §7.2).
##
## Specs: RT §7, §7.1 (namespaces e tabela sys.*), §7.2 (entrega), §10;
## Plugin SDK §5.4 (EventAPI), §7. Tarefa: M1-09.

## Um evento foi entregue (para o Preview: [code]event.emitted[/code], PP §4).
signal event_delivered(name: String, payload: Dictionary, source: String)

## Limite de eventos encadeados numa drenagem (RT §7.2).
const MAX_CHAINED := 64

## Origem de eventos que não são de plugin. Plugins usam o id do plugin.
const SOURCE_SYS := "sys"
const SOURCE_STORY := "story"

## Eventos sys.* do RT §7.1, com os campos do payload.
const SYS_EVENTS := {
	"sys.game_started": ["new_game"],
	"sys.chapter_started": ["chapter", "entries"],
	"sys.chapter_ended": ["chapter"],
	"sys.scene_started": ["scene", "chapter"],
	"sys.scene_ended": ["scene", "chapter"],
	"sys.choice_made": ["scene", "node", "option", "value"],
	"sys.activity_started": ["activity", "scene", "node"],
	"sys.activity_completed": ["activity", "outcome", "skipped"],
	"sys.game_saved": ["slot", "autosave"],
	"sys.game_loaded": ["slot"],
	"sys.game_ended": ["ending"],
	"sys.profile_reset": [],
	"sys.content_filter_changed": ["enabled"],
}


func module_id() -> StringName:
	return &"events"


## Enfileira um evento. [param source] é [constant SOURCE_SYS],
## [constant SOURCE_STORY] ou o id do plugin. A checagem de namespace e de
## [code]events.emits[/code] de plugins é do Plugin Host (Plugin SDK §7); o
## bus confere só o formato e, em debug/Preview, o payload (só tipos JSON).
@abstract func emit(name: String, payload: Dictionary = {}, source: String = SOURCE_STORY) -> VNResult

## Assina um padrão ([code]"story.*"[/code], [code]"sys.scene_ended"[/code];
## [code]*[/code] só no fim). O callback recebe
## [code](name: String, payload: Dictionary, source: String)[/code]. Devolve o
## id da assinatura. [param owner] é o namespace do plugin dono, ou vazio.
@abstract func on(pattern: String, callback: Callable, owner: StringName = &"") -> int

## Cancela uma assinatura.
@abstract func off(subscription_id: int) -> void

## Remove todas as assinaturas de um dono (plugin *faulted* ou descarregado, RT §9).
@abstract func off_owner(owner: StringName) -> void

## Entrega os eventos enfileirados, em FIFO. Devolve quantos foram entregues.
## Chamado pelo Narrative Engine ao fim de cada nó, pelo State Manager ao fim
## do commit e pelo Plugin Host ao fim de cada callback (RT §7.2, §10).
@abstract func drain() -> int

## Quantos eventos esperam na fila.
@abstract func pending_count() -> int

## Esvazia a fila sem entregar (fim de jogo, carregar save).
@abstract func clear_queue() -> void
