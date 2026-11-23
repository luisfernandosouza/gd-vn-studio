class_name FakeNarrativeEngine
extends VNNarrativeEngine
## Dublê do Narrative Engine: guarda fase, capítulo, cena e nó, e registra as
## chamadas. Os testes mudam o estado com [method set_phase] e [method goto_node].

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var _phase: StringName = VNPhase.BOOT
var chapter: String = ""
var scene: String = ""
var node: String = ""
var paused: bool = false
## Valor de can_save() para qualquer tipo.
var save_allowed: bool = true


func set_phase(p: StringName) -> void:
	var prev := _phase
	_phase = p
	phase_changed.emit(p, prev)


func goto_node(p_scene: String, p_node: String, node_type: StringName = &"line") -> void:
	scene = p_scene
	node = p_node
	node_entered.emit(p_scene, p_node, node_type)


func phase() -> StringName:
	return _phase


func current_chapter() -> String:
	return chapter


func current_scene() -> String:
	return scene


func current_node() -> String:
	return node


func is_write_allowed() -> bool:
	return _phase not in [VNPhase.LOAD_GAME, VNPhase.GAME_END]


func can_save(kind: StringName = SAVE_MANUAL) -> bool:
	return save_allowed and VNPhase.is_in_game(_phase) and _phase != VNPhase.ACTIVITY


func snapshot() -> Dictionary:
	return {
		"chapter": null if chapter.is_empty() else {"id": chapter},
		"scene": null if scene.is_empty() else {"id": scene, "node": node},
		"backlog": [],
	}


func enter_title() -> void:
	_rec(&"enter_title")
	set_phase(VNPhase.TITLE)


func new_game() -> void:
	_rec(&"new_game")
	set_phase(VNPhase.NEW_GAME)


func resume_from_save(state: Dictionary) -> void:
	_rec(&"resume_from_save", [state])
	var c: Variant = state.get("chapter")
	var s: Variant = state.get("scene")
	chapter = c.id if c is Dictionary else ""
	scene = s.id if s is Dictionary else ""
	node = s.node if s is Dictionary else ""
	set_phase(VNPhase.SCENE_RUNNING if s is Dictionary else VNPhase.SELECTION_POINT)


func return_to_title() -> void:
	_rec(&"return_to_title")
	chapter = ""
	scene = ""
	node = ""
	set_phase(VNPhase.TITLE)


func set_paused(p: bool) -> void:
	_rec(&"set_paused", [p])
	paused = p


func is_paused() -> bool:
	return paused


func advance() -> void:
	_rec(&"advance")


func choose(option_id: String) -> VNResult:
	_rec(&"choose", [option_id])
	if _phase != VNPhase.SCENE_RUNNING:
		return VNResult.failure(VNErrors.INVALID_STATE)
	return VNResult.success()


func content_filter_changed(enabled: bool) -> void:
	_rec(&"content_filter_changed", [enabled])
