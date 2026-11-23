@abstract
class_name VNSceneScheduler
extends VNModule
## Scene Scheduler (RT §1): escolhe a próxima cena e o próximo capítulo.
##
## Só roda em pontos de seleção, nunca no meio de uma cena (RT §4.1). É o dono
## do histórico do save ([code]save.schema.json → state.history[/code]):
## [code]selection_count[/code], [code]scenes[/code], [code]groups[/code],
## [code]chapters[/code], [code]events_since_selection[/code],
## [code]pending_request[/code] e [code]fallback_streak[/code].
##
## Specs: RT §3.2–§3.3 (capítulos), §4.1–§4.4 (algoritmo), §11 e Preview
## Protocol §4.3 ([code]SchedulerEvaluation[/code]); DM §7, §8.1; Plugin SDK §5.5.
## Vetores: [code]conformance/selection.json[/code]. Tarefa: M1-10.

## Uma seleção foi decidida. [param evaluation] tem o formato
## [code]SchedulerEvaluation[/code] (PP §4.3): [code]selection_count[/code],
## [code]chapter[/code], [code]action[/code], [code]chosen[/code],
## [code]reason[/code], [code]candidates[/code] e, se houve,
## [code]request_refused[/code]. Em modo preview vira [code]scheduler.evaluated[/code].
signal evaluated(evaluation: Dictionary)

## Ações de [method select] (RT §4.3).
const ACTION_START_SCENE := &"start_scene"
const ACTION_EXIT_CHAPTER := &"exit_chapter"
const ACTION_END_GAME := &"end_game"

## Limite de fallback_scene seguidas (RT §4.3, W010).
const MAX_FALLBACK_STREAK := 100


func module_id() -> StringName:
	return &"scheduler"


# --- Seleção ----------------------------------------------------------------

## Ponto de seleção (RT §4.3). [param content_request] é o
## [code]end.then.scene[/code] da cena anterior, ou vazio. Consome o
## [code]pending_request[/code], decide e, se a decisão for iniciar uma cena,
## registra a seleção ([code]last_selection[/code], [code]starts[/code],
## [code]selection_count += 1[/code], zera [code]events_since_selection[/code]
## e atualiza [code]fallback_streak[/code]). Emite [signal evaluated] e devolve
## a mesma avaliação; o Narrative Engine age conforme [code]action[/code].
@abstract func select(content_request: String = "") -> Dictionary

## A avaliação atual, sem alterar nada (preview.explain_selection, RT §11).
## Com [param scene], o Studio pede o detalhe só daquela cena.
@abstract func explain(scene: String = "") -> Dictionary

## Inicia uma cena sem passar pela elegibilidade: a [code]entry_scene[/code] do
## capítulo (RT §3.2 passo 5). Conta como seleção (RT §4.4).
@abstract func start_direct(scene_id: String) -> void

## Pedido de plugin (Plugin SDK §5.5), guardado em [code]pending_request[/code]
## até o próximo ponto de seleção; o último pedido vence. A concessão
## [code]grants.scenes[/code] é conferida antes, pelo Plugin Host; aqui só se
## confere que a cena existe. A elegibilidade é conferida em [method select].
@abstract func request(scene_id: String, plugin: StringName) -> VNResult

## A cena chegou a [code]end[/code] ou ao fim do grafo (RT §4.4, §5.4 passo 1):
## [code]plays += 1[/code] e entra nos grupos de exclusividade dela.
@abstract func complete_scene(scene_id: String) -> void


# --- Capítulos (RT §3.2–§3.3) -----------------------------------------------

## Entrada em capítulo: zera os grupos de exclusividade do capítulo e faz
## [code]entries += 1[/code]. Devolve o novo [code]entries[/code].
@abstract func enter_chapter(chapter_id: String) -> int

## Marca o capítulo como concluído ([code]completed = true[/code]).
@abstract func complete_chapter(chapter_id: String) -> void

## Próximo capítulo entre [code]next[][/code] (RT §3.3 passo 2), ou vazio
## para [code]GAME_END[/code]. Chamado antes de descartar [code]chapter.*[/code].
@abstract func next_chapter(chapter_id: String) -> String


# --- Histórico --------------------------------------------------------------

## Registra um evento entregue em [code]events_since_selection[/code] (sem
## repetir). Chamado pelo Event Bus; eventos [code]sys.*[/code] são ignorados.
@abstract func record_event(name: String) -> void

## Eventos [code]story.*[/code] e de plugins desde a última seleção (DM §5.2).
@abstract func events_since_selection() -> PackedStringArray

## [code]sys.selection_count[/code].
@abstract func selection_count() -> int

## O histórico no formato do save ([code]state.history[/code]).
@abstract func get_history() -> Dictionary

## Restaura o histórico de um save (RT §8.3 passo 4).
@abstract func restore_history(history: Dictionary) -> void

## Zera o histórico (novo jogo, RT §3.1 passo 3).
@abstract func reset_history() -> void
