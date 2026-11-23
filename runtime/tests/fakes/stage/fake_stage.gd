class_name FakeStage
extends VNStage
## Dublê do Stage: guarda o palco como dados (sem desenhar) e cria as camadas
## de VNLayers em attach(). O teste simula o jogador com [method press_advance]
## e [method select_option].

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var background: Variant = null
var characters: Dictionary = {}   # id → { expression, position }
var line: Dictionary = {}
var choices: Array[Dictionary] = []
var hotspots: Array[Dictionary] = []
var textbox_hidden: bool = false
var content_filter: bool = false
var _root: Node = null
var _layers: Dictionary = {}      # layer → CanvasLayer


func attach(parent: Node) -> void:
	detach()
	_root = Node.new()
	_root.name = "Stage"
	for layer in [VNLayers.BACKGROUND, VNLayers.CHARACTERS, VNLayers.HOTSPOTS, VNLayers.PLUGIN_OVERLAYS, VNLayers.TEXTBOX, VNLayers.SYSTEM]:
		var cl := CanvasLayer.new()
		cl.layer = layer
		cl.name = VNLayers.layer_name(layer)
		_root.add_child(cl)
		_layers[layer] = cl
	parent.add_child(_root)


func detach() -> void:
	if _root != null:
		_root.free()
	_root = null
	_layers.clear()


## O jogador avançou a fala.
func press_advance() -> void:
	advanced.emit()


## O jogador escolheu uma opção ou hotspot.
func select_option(option_id: String) -> void:
	option_selected.emit(option_id)


func get_layer(layer: int) -> CanvasLayer:
	return _layers.get(layer)


func set_background(node: Dictionary) -> void:
	_rec(&"set_background", [node])
	background = node.get("asset", node.get("set"))


func show_character(node: Dictionary) -> void:
	_rec(&"show_character", [node])
	characters[String(node.get("character", ""))] = {"expression": node.get("expression"), "position": node.get("position")}


func hide_character(node: Dictionary) -> void:
	_rec(&"hide_character", [node])
	characters.erase(String(node.get("character", "")))


func is_busy(_target: StringName) -> bool:
	return false


func clear() -> void:
	_rec(&"clear")
	background = null
	characters.clear()
	clear_interaction()


func show_line(p_line: Dictionary) -> void:
	_rec(&"show_line", [p_line])
	line = p_line


func show_choices(prompt: String, options: Array[Dictionary]) -> void:
	_rec(&"show_choices", [prompt, options])
	choices = options


func show_hotspots(p_hotspots: Array[Dictionary], exit_option: Dictionary = {}) -> void:
	_rec(&"show_hotspots", [p_hotspots, exit_option])
	hotspots = p_hotspots


func clear_interaction() -> void:
	line = {}
	choices = []
	hotspots = []


func set_textbox_hidden(hidden: bool) -> void:
	textbox_hidden = hidden


func set_content_filter(enabled: bool) -> void:
	_rec(&"set_content_filter", [enabled])
	content_filter = enabled


func snapshot() -> Dictionary:
	var chars: Array = []
	var ids := characters.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = {"id": id}
		for k in ["expression", "position"]:
			if characters[id][k] != null:
				c[k] = characters[id][k]
		chars.append(c)
	return {"background": background, "characters": chars}


func restore(stage: Dictionary) -> void:
	_rec(&"restore", [stage])
	background = stage.get("background")
	characters.clear()
	for c in stage.get("characters", []):
		characters[c.id] = {"expression": c.get("expression"), "position": c.get("position")}


func capture_thumbnail() -> Image:
	return Image.create_empty(320, 180, false, Image.FORMAT_RGB8)


func is_showing_sensitive() -> bool:
	return false
