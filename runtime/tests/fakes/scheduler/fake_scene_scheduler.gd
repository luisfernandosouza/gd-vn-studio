class_name FakeSceneScheduler
extends VNSceneScheduler
## Dublê do Scheduler: devolve as decisões programadas em [member decisions]
## (na ordem) e mantém um histórico simples no formato do save.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

## Próximas decisões de select(): { action, chosen?, reason? }. Vazia → end_game.
var decisions: Array[Dictionary] = []
## Capítulo devolvido por next_chapter(); vazio = GAME_END.
var next_chapter_id: String = ""
var history: Dictionary = {}


func _init() -> void:
	reset_history()


func select(content_request: String = "") -> Dictionary:
	_rec(&"select", [content_request])
	var d: Dictionary = decisions.pop_front() if not decisions.is_empty() else {"action": ACTION_END_GAME, "reason": "exhausted"}
	var ev := {"selection_count": history.selection_count, "action": d.get("action"), "chosen": d.get("chosen"), "reason": d.get("reason", "priority"), "candidates": []}
	history.pending_request = null
	if d.get("action") == ACTION_START_SCENE:
		_start(String(d.chosen))
	evaluated.emit(ev)
	return ev


func explain(scene: String = "") -> Dictionary:
	_rec(&"explain", [scene])
	return {"selection_count": history.selection_count, "candidates": []}


func start_direct(scene_id: String) -> void:
	_rec(&"start_direct", [scene_id])
	_start(scene_id)


func request(scene_id: String, plugin: StringName) -> VNResult:
	_rec(&"request", [scene_id, plugin])
	history.pending_request = {"scene": scene_id, "plugin": String(plugin)}
	return VNResult.success()


func complete_scene(scene_id: String) -> void:
	_rec(&"complete_scene", [scene_id])
	var s: Dictionary = history.scenes.get_or_add(scene_id, {"plays": 0, "starts": 0})
	s.plays += 1


func enter_chapter(chapter_id: String) -> int:
	_rec(&"enter_chapter", [chapter_id])
	var c: Dictionary = history.chapters.get_or_add(chapter_id, {"entries": 0, "completed": false})
	c.entries += 1
	return c.entries


func complete_chapter(chapter_id: String) -> void:
	_rec(&"complete_chapter", [chapter_id])
	history.chapters.get_or_add(chapter_id, {"entries": 0, "completed": false}).completed = true


func next_chapter(chapter_id: String) -> String:
	_rec(&"next_chapter", [chapter_id])
	return next_chapter_id


func record_event(name: String) -> void:
	if not name.begins_with("sys.") and not history.events_since_selection.has(name):
		history.events_since_selection.append(name)


func events_since_selection() -> PackedStringArray:
	return PackedStringArray(history.events_since_selection)


func selection_count() -> int:
	return history.selection_count


func get_history() -> Dictionary:
	return history.duplicate(true)


func restore_history(p_history: Dictionary) -> void:
	_rec(&"restore_history", [p_history])
	reset_history()
	history.merge(p_history.duplicate(true), true)


func reset_history() -> void:
	history = {"selection_count": 0, "scenes": {}, "groups": {}, "chapters": {}, "events_since_selection": [], "pending_request": null, "fallback_streak": 0}


func _start(scene_id: String) -> void:
	var s: Dictionary = history.scenes.get_or_add(scene_id, {"plays": 0, "starts": 0})
	s.last_selection = history.selection_count
	s.starts += 1
	history.selection_count += 1
	history.events_since_selection = []
