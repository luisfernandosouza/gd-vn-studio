# Spike do Preview Web (proposta A): o mínimo de runtime para medir a recarga.
#
# Não é o runtime do v1. Mostra falas (`line`), muda a cor do fundo (`background`)
# e anda pela lista de nós. Expõe ao JavaScript da página (o "Studio") as
# operações que o Preview Protocol usaria, e avisa a página quando o quadro
# com o resultado foi desenhado, para a página medir o tempo de ponta a ponta.
extends Control

const FishingPluginScript := preload("res://vn_plugins/fishing/runtime/src/fishing_plugin.gd")

@onready var _bg: ColorRect = $Background
@onready var _speaker: Label = $Box/VBox/Speaker
@onready var _text: Label = $Box/VBox/Text
@onready var _overlays: Control = $Overlays

var bundle: Dictionary = {}
var strings: Dictionary = {}       # idioma atual, fora o default (chave → texto)
var locale := ""
var variables: Dictionary = {}
var scene_id := ""
var node_index := 0
var _scene_nodes: Array = []

var _js_callbacks: Array = []      # referências vivas dos callbacks (o GC do JS)
var _host: JavaScriptObject = null
var _plugin = null


func _ready() -> void:
	if OS.has_feature("web"):
		_install_bridge()
	_text.text = "Preview pronto"
	await RenderingServer.frame_post_draw
	_notify("ready", {"godot": Engine.get_version_info().string})


# ---------------------------------------------------------------- ponte JS

func _install_bridge() -> void:
	var window := JavaScriptBridge.get_interface("window")
	_host = window.vnPreviewHost if window.vnPreviewHost else null
	var api: JavaScriptObject = JavaScriptBridge.create_object("Object")
	for name in ["load_text", "load_url", "patch_scene", "patch_locale", "start", "start_activity", "advance"]:
		var cb: JavaScriptObject = JavaScriptBridge.create_callback(Callable(self, "_js_" + name))
		_js_callbacks.append(cb)
		api[name] = cb
	window.vnPreview = api
	if _host == null:
		_host = window.parent.vnPreviewHost if window.parent else null


func _notify(kind: String, info: Dictionary) -> void:
	var text := JSON.stringify(info)
	if _host != null:
		_host.onEvent(kind, text)
	else:
		print("[preview] ", kind, " ", text)


# Cada chamada recebe (pedido, ...) e responde com notify("done", {req, ms...}).
# ms_runtime = tempo dentro do runtime até o quadro ser desenhado.

func _js_load_text(args: Array) -> void:
	# Bundle inteiro em memória. args: req, bundle_text, locale, locale_text, verify
	_reload_from_text(int(args[0]), str(args[1]), str(args[2]), str(args[3]), bool(args[4]))


func _js_load_url(args: Array) -> void:
	# Bundle lido de "arquivo" (URL servida pela página, como a pasta .vnstudio/preview/).
	# args: req, bundle_url, locale, locale_url, verify
	var req := int(args[0])
	var t0 := Time.get_ticks_usec()
	var bundle_text := await _fetch(str(args[1]))
	var locale_text := await _fetch(str(args[3])) if str(args[3]) != "" else ""
	var fetch_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_reload_from_text(req, bundle_text, str(args[2]), locale_text, bool(args[4]), {"fetch_ms": fetch_ms})


func _js_patch_scene(args: Array) -> void:
	# Recarga incremental: só a cena alterada. args: req, scene_json
	var req := int(args[0])
	var t0 := Time.get_ticks_usec()
	var scene = JSON.parse_string(str(args[1]))
	if typeof(scene) != TYPE_DICTIONARY:
		_notify("error", {"req": req, "message": "cena inválida"})
		return
	bundle.scenes[scene.id] = scene
	if scene.id == scene_id:
		_scene_nodes = scene.nodes
		node_index = mini(node_index, _scene_nodes.size() - 1)
	var parse_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await _show_and_report(req, t0, {"parse_ms": parse_ms, "resumed": "node"})


func _js_patch_locale(args: Array) -> void:
	# Recarga incremental de textos traduzidos. args: req, {chave: texto}
	var req := int(args[0])
	var t0 := Time.get_ticks_usec()
	var patch = JSON.parse_string(str(args[1]))
	for k in patch:
		strings[k] = patch[k]
	await _show_and_report(req, t0, {"resumed": "node"})


func _js_start(args: Array) -> void:
	# preview.start com cena, nó e variáveis. args: req, scene, node, variables_json
	var req := int(args[0])
	var t0 := Time.get_ticks_usec()
	var vars = JSON.parse_string(str(args[3])) if str(args[3]) != "" else {}
	_reset_variables()
	for k in vars:
		variables[k] = vars[k]
	_enter(str(args[1]), str(args[2]))
	await _show_and_report(req, t0, {"resumed": "start"})


func _js_advance(args: Array) -> void:
	var req := int(args[0])
	var t0 := Time.get_ticks_usec()
	_step()
	await _show_and_report(req, t0, {})


func _js_start_activity(args: Array) -> void:
	# Roda o GDScript real do plugin de pesca, sem mock. args: req, params_json
	var req := int(args[0])
	var t0 := Time.get_ticks_usec()
	if _plugin == null:
		_plugin = FishingPluginScript.new()
		var cfg: Dictionary = bundle.get("_plugins", {}).get("vnstudio.fishing", {}).get("config", {"rare_fish_chance": 0.05, "show_tutorial": true, "rare_fish_sound": ""})
		_plugin._vn_init(VNPluginContext.create(_overlays, cfg, variables, strings))
		_plugin._vn_game_started(true)
	var handle := VNActivityHandle.new(&"story", 1234)
	handle.completed.connect(func(outcome, payload): _notify("activity_completed", {"outcome": outcome, "payload": payload}))
	_plugin._vn_start_activity(&"fishing_game", JSON.parse_string(str(args[1])), handle)
	await RenderingServer.frame_post_draw
	_notify("done", {"req": req, "runtime_ms": (Time.get_ticks_usec() - t0) / 1000.0, "overlays": _overlays.get_child_count()})
	if bool(args[2]) if args.size() > 2 else false:
		_plugin._vn_cancel_activity(handle)


# ---------------------------------------------------------------- carga

func _fetch(url: String) -> String:
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var res: Array = await http.request_completed
	http.queue_free()
	return (res[3] as PackedByteArray).get_string_from_utf8()


func _reload_from_text(req: int, bundle_text: String, loc: String, locale_text: String, verify: bool, extra: Dictionary = {}) -> void:
	var t0 := Time.get_ticks_usec()
	var parsed = JSON.parse_string(bundle_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_notify("error", {"req": req, "message": "bundle inválido"})
		return
	var parse_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var hash_ms := 0.0
	if verify:
		var t1 := Time.get_ticks_usec()
		var expected: String = parsed.get("content_hash", "")
		var copy: Dictionary = parsed.duplicate()
		copy.erase("content_hash")
		var got := Canonical.sri(Canonical.jcs(copy))
		hash_ms = (Time.get_ticks_usec() - t1) / 1000.0
		extra["hash_ok"] = got == expected
	strings = {}
	if locale_text != "":
		var lp = JSON.parse_string(locale_text)
		strings = lp.get("strings", {})
	locale = loc
	var keep_scene := scene_id
	var keep_index := node_index
	bundle = parsed
	if variables.is_empty():
		_reset_variables()
	var resumed := "selection_point"
	if keep_scene != "" and bundle.scenes.has(keep_scene):
		_scene_nodes = bundle.scenes[keep_scene].nodes
		node_index = mini(keep_index, _scene_nodes.size() - 1)
		resumed = "node"
	else:
		_enter(bundle.chapters[bundle.project.start_chapter].entry_scene, "")
	extra.merge({"parse_ms": parse_ms, "hash_ms": hash_ms, "resumed": resumed, "scenes": bundle.scenes.size()})
	await _show_and_report(req, t0, extra)


func _reset_variables() -> void:
	variables = {}
	for id in bundle.get("variables", {}):
		variables[id] = bundle.variables[id].get("default")


# ---------------------------------------------------------------- execução mínima

func _enter(sid: String, node_id: String) -> void:
	scene_id = sid
	_scene_nodes = bundle.scenes[sid].nodes
	node_index = 0
	var target := node_id if node_id != "" else str(bundle.scenes[sid].get("start", ""))
	for i in _scene_nodes.size():
		if _scene_nodes[i].id == target:
			node_index = i
			break
	_settle()


func _step() -> void:
	node_index += 1
	if node_index >= _scene_nodes.size():
		node_index = _scene_nodes.size() - 1
	_settle()


# Anda até o próximo nó que espera o jogador, aplicando o fundo pelo caminho.
func _settle() -> void:
	while node_index < _scene_nodes.size() - 1 and str(_scene_nodes[node_index].type) not in ["line", "choice", "plugin", "interact", "end"]:
		_apply(_scene_nodes[node_index])
		node_index += 1


func _apply(node: Dictionary) -> void:
	if node.type == "background":
		var h := hash(str(node.get("asset", "")))
		_bg.color = Color.from_hsv(float(h % 360) / 360.0, 0.35, 0.35)


func _show_current() -> void:
	if _scene_nodes.is_empty():
		return
	var node: Dictionary = _scene_nodes[node_index]
	var key := "%s/%s" % [scene_id, node.id]
	match str(node.type):
		"line":
			var sp := str(node.get("speaker", ""))
			_speaker.text = bundle.characters[sp].name if sp != "" and bundle.characters.has(sp) else ""
			_text.text = _interpolate(strings.get(key, str(node.get("text", ""))))
		"choice":
			_speaker.text = ""
			var parts: PackedStringArray = []
			for o in node.options:
				parts.append("• " + strings.get("%s/%s" % [key, o.id], str(o.get("text", ""))))
			_text.text = "\n".join(parts)
		_:
			_speaker.text = ""
			_text.text = "[%s]" % node.type


func _interpolate(t: String) -> String:
	var re := RegEx.create_from_string("\\{([a-z~][a-z0-9_.]*)\\}")
	var out := t
	for m in re.search_all(t):
		var v = variables.get(m.get_string(1), "")
		out = out.replace(m.get_string(0), str(int(v)) if typeof(v) == TYPE_FLOAT and v == floor(v) else str(v))
	return out


func _show_and_report(req: int, t0: int, extra: Dictionary) -> void:
	_show_current()
	await RenderingServer.frame_post_draw
	extra.merge({"req": req, "runtime_ms": (Time.get_ticks_usec() - t0) / 1000.0, "text": _text.text, "scene": scene_id, "index": node_index})
	_notify("done", extra)
