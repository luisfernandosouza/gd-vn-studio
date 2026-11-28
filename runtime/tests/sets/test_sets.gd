extends SceneTree
## Testes dos sets compostos e dos hotspots cosméticos (tarefa M2-08; UI Spec §5).
##
##   godot --headless --path runtime --script res://tests/sets/test_sets.gd
##
## Cobre o [VNSetView] sozinho (camadas, estados, ações, parallax, animação,
## hotspots e máscara alfa) e o encaixe no Stage real: o set da demo
## ([code]docs/specs/examples/demo-project/sets/beach_title.json[/code]) como
## cenário, com o estado no snapshot. O encaixe na tela de título (UI Manager)
## é conferido em tests/ui_manager/test_ui_manager.gd. Sai com 1 se algo falhar.

const DEMO := "../docs/specs/examples/demo-project"
const SIZES := {
	"bg/sky_day": Vector2i(1920, 1080), "bg/sky_night": Vector2i(1920, 1080), "bg/sea": Vector2i(1920, 1080),
	"obj/lamp_off": Vector2i(220, 420), "obj/lamp_on": Vector2i(220, 420), "obj/shell": Vector2i(140, 120),
}

var _passed := 0
var _failed := 0
var _host: Node = null
var _textures: Dictionary = {}


func _initialize() -> void:
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	for t in [
		"camadas_e_ordem", "estados_e_toggle", "visibilidade", "acoes_com_prefixo", "acoes_cosmeticas_apenas",
		"parallax", "animacao_e_reduce_motion", "hotspot_rect_e_polygon", "hotspot_mascara_alfa",
		"hotspot_ciclo_press_release_hover", "hotspot_gate", "hotspot_da_demo",
		"stage_set_e_snapshot", "stage_acao_stage", "stage_gate_na_transicao", "stage_show_hotspots",
	]:
		await _run(t)
	print("%d/%d testes dos sets passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	_host = Node.new()
	root.add_child(_host)
	var err: Variant = await call("test_" + test)
	var msg: String = err if err is String else "o teste não devolveu resultado (erro de script)"
	if msg.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", msg)
	_host.queue_free()
	_host = null
	await process_frame


# --- Montagem ---------------------------------------------------------------

func _read_json(rel: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://").path_join(DEMO).path_join(rel)
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null


func _solid(size: Vector2i, color := Color.WHITE) -> Texture2D:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Imagem com um quadrado opaco no meio e o resto transparente.
func _holey(size: Vector2i, hole: Rect2i) -> Texture2D:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(hole, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _loader(id: String) -> Resource:
	if not _textures.has(id):
		_textures[id] = _solid(SIZES.get(id, Vector2i(64, 64)))
	return _textures[id]


func _view(def: Dictionary, states := {}, reduce := false, keyboard := false) -> VNSetView:
	var v := VNSetView.new()
	v.reduce_motion = reduce
	v.keyboard_focus = keyboard
	v.asset_loader = _loader
	v.sfx_fn = func(asset: String): _sfx.append(asset)
	v.check_fn = func(conditions: Array) -> bool: return bool(conditions[0].get("value", false))
	_host.add_child(v)
	v.build(def, states)
	return v

var _sfx: Array = []


func _beach() -> Dictionary:
	return _read_json("sets/beach_title.json")


func _approx(a: Vector2, b: Vector2) -> bool:
	return a.is_equal_approx(b)


func _layer_names(v: VNSetView) -> Array:
	return v.get_children().filter(func(c): return c.has_meta(&"vn_set_layer")).map(func(c): return String(c.name))


# --- VNSetView --------------------------------------------------------------

func test_camadas_e_ordem() -> String:
	var def := {"id": "t", "layers": [
		{"id": "front", "asset": "obj/shell", "z": 5, "position": [0.5, 0.5]},
		{"id": "back", "asset": "bg/sky_day"},
		{"id": "mid", "asset": "obj/lamp_off", "position": [0.8, 0.62], "scale": 2.0, "pivot": [0.0, 0.0]},
		{"id": "same_z_later", "asset": "obj/shell", "z": 5, "position": [0.1, 0.1]},
		{"id": "ghost", "asset": "nao/existe"},
	]}
	_textures["nao/existe"] = null
	var v := _view(def)
	# O loader devolve null para "nao/existe" (sem textura, a camada não é desenhada).
	if _layer_names(v) != ["back", "mid", "front", "same_z_later"]:
		return "ordem por z e depois da lista: %s" % [_layer_names(v)]
	var back := v.layer_node("back") as Sprite2D
	if back.scale != Vector2.ONE or back.position != Vector2.ZERO:
		return "camada sem position cobre a tela: %s %s" % [back.scale, back.position]
	var mid := v.layer_node("mid") as Sprite2D
	if mid.scale != Vector2(2, 2) or not _approx(mid.position, Vector2(0.8 * 1920, 0.62 * 1080)):
		return "scale e pivot [0,0]: %s %s" % [mid.scale, mid.position]
	var front := v.layer_node("front") as Sprite2D
	if not _approx(front.position, Vector2(960 - 70, 540 - 60)):
		return "pivot padrão [0.5, 0.5] centra a imagem: %s" % front.position
	var wide := _view(def)
	wide.view_size = Vector2(2520, 1080)
	wide.relayout()
	var wb := wide.layer_node("back") as Sprite2D
	var covered := wb.texture.get_size() * wb.scale
	if covered.x < 2520.0 - 0.5 or covered.y < 1080.0 - 0.5:
		return "em 21:9 a camada de fundo cobre a área visível: %s" % covered
	return ""


func test_estados_e_toggle() -> String:
	var v := _view(_beach())
	var changes: Array = []
	v.state_changed.connect(func(layer, state): changes.append([layer, state]))
	if v.states() != {} or v.state_of("sky") != "default":
		return "estado inicial é default"
	if not v.set_state("sky", "night"):
		return "set_state night"
	if (v.layer_node("sky") as Sprite2D).texture != _textures["bg/sky_night"]:
		return "o estado troca o asset"
	if v.states() != {"sky": "night"}:
		return "states() só lista fora do default: %s" % v.states()
	if v.set_state("sky", "nao_existe") or v.set_state("nao_existe", "night"):
		return "estado ou camada inexistente é recusado"
	if v.state_of("sky") != "night":
		return "recusa não muda nada"
	v.set_state("sky", "default")
	if (v.layer_node("sky") as Sprite2D).texture != _textures["bg/sky_day"] or v.states() != {}:
		return "volta ao default"
	if v.toggle_state("lamp", ["default", "on"]) != true or v.state_of("lamp") != "on":
		return "toggle default → on"
	v.toggle_state("lamp", ["default", "on"])
	if v.state_of("lamp") != "default":
		return "toggle on → default"
	v.toggle_state("lamp", ["a", "b"])
	if v.state_of("lamp") != "default":
		return "estado fora da lista vai ao primeiro e recusa se ele não existe"
	if changes != [["sky", "night"], ["sky", "default"], ["lamp", "on"], ["lamp", "default"]]:
		return "state_changed: %s" % [changes]
	var restored := _view(_beach(), {"lamp": "on", "sky": "night", "sea": "inexistente"})
	if restored.states() != {"lamp": "on", "sky": "night"}:
		return "estados iniciais (nome desconhecido vale default): %s" % restored.states()
	var def := {"id": "t", "layers": [{"id": "a", "asset": "obj/shell", "position": [0.5, 0.5], "states": {
		"dim": {"opacity": 0.4, "tint": "#ff0000", "asset": "obj/lamp_on"}, "off": {"visible": false}}}]}
	var w := _view(def)
	w.set_state("a", "dim")
	var a := w.layer_node("a") as Sprite2D
	if not is_equal_approx(a.modulate.a, 0.4) or a.modulate.r != 1.0 or a.modulate.g != 0.0:
		return "opacity e tint do estado: %s" % a.modulate
	if not _approx(a.position, Vector2(960 - 110, 540 - 210)):
		return "troca de asset recalcula a posição pelo novo tamanho: %s" % a.position
	w.set_state("a", "off")
	if (w.layer_node("a")).visible:
		return "visible: false do estado"
	w.set_state("a", "default")
	if not w.layer_node("a").visible:
		return "default volta a mostrar"
	return ""


func test_visibilidade() -> String:
	var v := _view(_beach())
	v.hide_layer("lamp")
	if v.layer_node("lamp").visible:
		return "hide"
	v.toggle_visible("lamp")
	if not v.layer_node("lamp").visible:
		return "toggle_visible mostra"
	v.toggle_visible("lamp")
	v.show_layer("lamp")
	if not v.layer_node("lamp").visible:
		return "show"
	v.hide_layer("lamp")
	v.set_state("lamp", "on")
	if v.layer_node("lamp").visible:
		return "trocar o estado não desfaz o hide"
	if v.states() != {"lamp": "on"}:
		return "a visibilidade não entra em states()"
	if v.hide_layer("nao_existe"):
		return "camada inexistente"
	return ""


func test_acoes_com_prefixo() -> String:
	var v := _view(_beach())
	if not v.apply_action("set_state", "set:sky", {"state": "night"}) or v.state_of("sky") != "night":
		return "set:sky"
	if not v.apply_action("toggle_state", "stage:lamp", {"states": ["default", "on"]}) or v.state_of("lamp") != "on":
		return "stage:lamp"
	if v.apply_action("set_state", "lamp", {"state": "xyz"}):
		return "estado inexistente é recusado"
	if v.apply_action("new_game", "lamp"):
		return "ação desconhecida"
	return ""


func test_acoes_cosmeticas_apenas() -> String:
	_sfx.clear()
	var v := _view(_beach())
	v.run_actions([
		{"do": "new_game"},
		{"do": "effects", "effects": []},
		{"do": "open_screen", "screen": "title"},
		{"do": "set_state", "target": "lamp", "state": "on"},
		{"do": "play_sfx", "asset": "sfx/click"},
		{"do": "set_state", "target": "sky", "state": "night", "if": [{"value": false}], "else": [
			{"do": "hide", "target": "shell"}]},
		{"do": "set_state", "target": "sea", "state": "default", "if": [{"value": true}]},
	])
	if v.state_of("lamp") != "on" or _sfx != ["sfx/click"]:
		return "ações cosméticas rodam em ordem: %s %s" % [v.states(), _sfx]
	if v.state_of("sky") != "default" or v.layer_node("shell").visible:
		return "if falso roda o else"
	if v.states() != {"lamp": "on"}:
		return "ação não cosmética não pode mudar nada: %s" % v.states()
	return ""


func test_parallax() -> String:
	var def := {"id": "t", "layers": [
		{"id": "sky", "asset": "bg/sky_day", "parallax": 0.02},
		{"id": "still", "asset": "bg/sea"},
		{"id": "obj", "asset": "obj/shell", "position": [0.5, 0.5], "parallax": 0.1},
	]}
	var v := _view(def)
	var sky := v.layer_node("sky") as Sprite2D
	var covered := sky.texture.get_size() * sky.scale
	if covered.x < 1920.0 + 2 * 0.02 * 1920.0 - 0.5:
		return "camada com parallax cobre uma margem a mais: %s" % covered
	v.set_parallax_pointer(Vector2(1, 0))
	if not _approx(sky.offset * sky.scale, Vector2(-0.02 * 1920.0, 0)):
		return "ponteiro à direita empurra a camada para a esquerda: %s" % (sky.offset * sky.scale)
	var obj := v.layer_node("obj") as Sprite2D
	v.set_parallax_pointer(Vector2(-1, 1))
	if not _approx(obj.offset * obj.scale, Vector2(0.1 * 1920.0, -0.1 * 1080.0)):
		return "parallax de camada com position: %s" % (obj.offset * obj.scale)
	if (v.layer_node("still") as Sprite2D).offset != Vector2.ZERO:
		return "camada sem parallax não se move"
	v.set_parallax_pointer(Vector2.ZERO)
	if sky.offset != Vector2.ZERO:
		return "ponteiro no centro"
	var calm := _view(def, {}, true)
	if calm.is_processing():
		return "reduce_motion desliga o parallax"
	var csky := calm.layer_node("sky") as Sprite2D
	if (csky.texture.get_size() * csky.scale).x > 1920.0 + 0.5:
		return "sem parallax, sem margem"
	return ""


func test_animacao_e_reduce_motion() -> String:
	var def := {"id": "t", "layers": [
		{"id": "sea", "asset": "bg/sea", "position": [0.5, 0.5], "animation": {"kind": "float", "amount": 6, "duration": 4, "loop": true}},
		{"id": "obj", "asset": "obj/shell", "position": [0.5, 0.5]},
	]}
	var v := _view(def)
	if not v._tweens.has("sea"):
		return "animação da camada roda ao montar"
	var obj := v.layer_node("obj") as Sprite2D
	var rest := obj.position
	if not v.play_animation("obj", {"kind": "shake", "amount": 4, "duration": 0.4}) or not v._tweens.has("obj"):
		return "play_animation"
	var tw: Tween = v._tweens["obj"]
	tw.custom_step(0.1)
	if obj.position == rest:
		return "a animação mexe na camada"
	tw.custom_step(10.0)
	if obj.position != rest or obj.rotation != 0.0:
		return "no fim volta ao repouso: %s" % obj.position
	v.play_animation("obj", {"kind": "rotate", "duration": 1.0})
	tw = v._tweens["obj"]
	tw.custom_step(0.5)
	var half := obj.rotation
	tw.custom_step(10.0)
	if absf(half) < 0.1 or obj.rotation != 0.0 or not _approx(obj.position, rest):
		return "rotate gira e volta: %s" % half
	v.play_animation("obj", {"kind": "pulse", "amount": 0.5, "duration": 1.0})
	tw = v._tweens["obj"]
	tw.custom_step(0.5)
	if obj.scale.x <= 1.0 or obj.scale.x > 1.5 + 0.001:
		return "pulse aumenta a escala: %s" % obj.scale
	tw.custom_step(10.0)
	if obj.scale != Vector2.ONE or not _approx(obj.position, rest):
		return "pulse volta ao repouso: %s %s" % [obj.scale, obj.position]
	var calm := _view(def, {}, true)
	if calm._tweens.has("sea"):
		return "reduce_motion: sem animação ociosa"
	calm.play_animation("obj", {"kind": "shake", "duration": 0.4})
	if calm._tweens.has("obj"):
		return "reduce_motion: só fade anima"
	calm.play_animation("obj", {"kind": "fade", "duration": 0.4})
	if not calm._tweens.has("obj"):
		return "reduce_motion deixa o fade"
	return ""


# --- Hotspots ---------------------------------------------------------------

func test_hotspot_rect_e_polygon() -> String:
	var def := {"id": "t", "layers": [{"id": "bg", "asset": "bg/sky_day"}], "hotspots": [
		{"id": "r", "area": {"rect": [0.1, 0.2, 0.3, 0.4]}, "label": "Retângulo"},
		{"id": "p", "area": {"polygon": [[0.5, 0.5], [0.9, 0.5], [0.5, 0.9]]}},
		{"id": "c", "area": {"character": "x"}},
	]}
	var v := _view(def)
	var r := v.hotspot_node("r")
	if not _approx(r.position, Vector2(192, 216)) or not _approx(r.size, Vector2(576, 432)):
		return "rect em fração da base: %s %s" % [r.position, r.size]
	if not r._has_point(Vector2(10, 10)) or r._has_point(Vector2(-1, 10)):
		return "ponto dentro/fora do retângulo"
	if r.tooltip_text != "Retângulo" or r.accessibility_label != "Retângulo":
		return "rótulo vira dica e nome acessível"
	var p := v.hotspot_node("p")
	var local := Vector2(0.55, 0.55) * Vector2(1920, 1080) - p.position
	var outside := Vector2(0.85, 0.85) * Vector2(1920, 1080) - p.position
	if not p._has_point(local) or p._has_point(outside):
		return "polígono: dentro e fora"
	if v.hotspot_node("c").has_area():
		return "area.character não vale num set"
	return ""


func test_hotspot_mascara_alfa() -> String:
	_textures["obj/holey"] = _holey(Vector2i(100, 100), Rect2i(40, 40, 20, 20))
	var def := {"id": "t", "layers": [
		{"id": "thing", "asset": "obj/holey", "position": [0.5, 0.5], "scale": 2.0},
	], "hotspots": [{"id": "h", "area": {"layer": "thing"}, "highlight": "glow"}]}
	var v := _view(def)
	var h := v.hotspot_node("h")
	if not h.has_area():
		return "a máscara da camada vira a área"
	var sp := v.layer_node("thing") as Sprite2D
	if not _approx(h.position, sp.position) or not _approx(h.size, Vector2(200, 200)):
		return "o nó cobre a camada: %s %s" % [h.position, h.size]
	# O miolo opaco (40..60 em 100 px) fica em 80..120 depois da escala 2.
	if not h._has_point(Vector2(100, 100)):
		return "pixel opaco responde"
	if h._has_point(Vector2(10, 10)) or h._has_point(Vector2(190, 190)):
		return "pixel transparente não responde"
	if h._has_point(Vector2(-5, 100)) or h._has_point(Vector2(100, 300)):
		return "fora da imagem não responde"
	v.hide_layer("thing")
	if h.mouse_filter != Control.MOUSE_FILTER_IGNORE or h.has_area():
		return "camada escondida: sem área"
	v.show_layer("thing")
	if not h.has_area() or h.mouse_filter != Control.MOUSE_FILTER_STOP:
		return "camada mostrada de novo volta a responder"
	_textures["obj/holey_b"] = _holey(Vector2i(100, 100), Rect2i(0, 0, 10, 10))
	var def2 := {"id": "t", "layers": [{"id": "thing", "asset": "obj/holey", "position": [0.5, 0.5], "scale": 2.0,
		"states": {"b": {"asset": "obj/holey_b"}}}], "hotspots": [{"id": "h", "area": {"layer": "thing"}}]}
	var w := _view(def2)
	var wh := w.hotspot_node("h")
	if not wh._has_point(Vector2(100, 100)):
		return "estado inicial"
	w.set_state("thing", "b")
	if wh._has_point(Vector2(100, 100)) or not wh._has_point(Vector2(10, 10)):
		return "a máscara acompanha o asset do estado"
	return ""


func test_hotspot_ciclo_press_release_hover() -> String:
	_sfx.clear()
	var def := {"id": "t", "layers": [{"id": "lamp", "asset": "obj/lamp_off", "position": [0.5, 0.5],
		"states": {"on": {"asset": "obj/lamp_on"}}}], "hotspots": [{"id": "h", "area": {"rect": [0, 0, 1, 1]},
		"on_hover": [{"do": "play_sfx", "asset": "sfx/hover"}],
		"on_press": [{"do": "toggle_state", "target": "lamp", "states": ["default", "on"]}],
		"on_release": [{"do": "play_sfx", "asset": "sfx/click"}]}]}
	var v := _view(def)
	var h := v.hotspot_node("h")
	h.mouse_entered.emit()
	if _sfx != ["sfx/hover"]:
		return "on_hover: %s" % [_sfx]
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	h._gui_input(down)
	if v.state_of("lamp") != "on" or _sfx.size() != 1:
		return "on_press roda ao apertar, sem soltar: %s %s" % [v.states(), _sfx]
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	h._gui_input(up)
	if _sfx != ["sfx/hover", "sfx/click"]:
		return "on_release roda ao soltar: %s" % [_sfx]
	h._gui_input(up)
	if _sfx.size() != 2:
		return "soltar sem ter apertado não conta"
	h._gui_input(down)
	h.mouse_exited.emit()
	h.notification(Control.NOTIFICATION_MOUSE_EXIT)
	h._gui_input(up)
	if _sfx.size() != 2:
		return "soltar depois de sair da área não dispara on_release"
	v.activate_hotspot("h")
	if v.state_of("lamp") != "on" or _sfx.size() != 3:
		return "confirmar pelo teclado aperta e solta: %s %s" % [v.states(), _sfx]
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	h._gui_input(touch)
	if v.state_of("lamp") != "default":
		return "toque"
	var kb := _view(def, {}, false, true)
	if kb.hotspot_node("h").focus_mode != Control.FOCUS_ALL or h.focus_mode != Control.FOCUS_NONE:
		return "foco só nas telas (keyboard_focus)"
	var cur := _view({"id": "t", "layers": def.layers, "hotspots": [
		{"id": "a", "area": {"rect": [0, 0, 1, 1]}, "cursor": "look"},
		{"id": "b", "area": {"rect": [0, 0, 1, 1]}}]})
	if cur.hotspot_node("a").mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND or cur.hotspot_node("b").mouse_default_cursor_shape != Control.CURSOR_ARROW:
		return "cursor pelo nome"
	return ""


func test_hotspot_gate() -> String:
	var def := {"id": "t", "layers": [{"id": "lamp", "asset": "obj/lamp_off", "position": [0.5, 0.5],
		"states": {"on": {"asset": "obj/lamp_on"}}}], "hotspots": [{"id": "h", "area": {"rect": [0, 0, 1, 1]},
		"on_press": [{"do": "set_state", "target": "lamp", "state": "on"}]}]}
	var v := _view(def)
	var open := [false]
	v.gate = func() -> bool: return open[0]
	v.activate_hotspot("h")
	if v.state_of("lamp") != "default":
		return "com o gate fechado o hotspot não responde"
	open[0] = true
	v.activate_hotspot("h")
	if v.state_of("lamp") != "on":
		return "com o gate aberto responde"
	return ""


func test_hotspot_da_demo() -> String:
	var v := _view(_beach())
	var lamp := v.hotspot_node("lamp_click")
	if lamp == null or lamp.highlight != "outline" or not lamp.has_area():
		return "o hotspot da lâmpada tem a máscara da camada"
	if lamp.mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND:
		return "cursor use"
	_sfx.clear()
	v.activate_hotspot("lamp_click")
	if v.state_of("lamp") != "on" or _sfx != ["sfx/click"]:
		return "clicar acende a lâmpada e toca o clique: %s %s" % [v.states(), _sfx]
	v.activate_hotspot("lamp_click")
	if v.state_of("lamp") != "default":
		return "clicar de novo apaga"
	return ""


# --- Stage ------------------------------------------------------------------

func _stage_modules() -> VNModules:
	var m := VNFakeModules.create()
	m.stage = VNRuntimeStage.new()
	m.bind_all()
	var assets: Dictionary = _read_json("assets.json").assets
	var bundle := {"assets": assets, "characters": {}, "sets": {"beach_title": _beach()}, "project": _read_json("project.json")}
	var fa := m.assets as FakeAssets
	fa.load_bundle(bundle)
	for id in SIZES:
		fa.resources[id] = _solid(SIZES[id])
	m.stage.load_bundle(bundle)
	var sv := SubViewport.new()
	sv.size = Vector2i(1920, 1080)
	_host.add_child(sv)
	m.stage.attach(sv)
	return m


func test_stage_set_e_snapshot() -> String:
	var m := _stage_modules()
	var st := m.stage as VNRuntimeStage
	st.reduce_motion_override = true
	st.set_background({"set": "beach_title"})
	var v := st.set_view()
	if v == null or v.set_id != "beach_title" or v.name != "Set_beach_title":
		return "o cenário é um VNSetView"
	if _layer_names(v) != ["sky", "sea", "lamp", "shell"]:
		return "camadas %s" % [_layer_names(v)]
	v.activate_hotspot("lamp_click")
	var snap := st.snapshot()
	if snap.background != null or snap.set != "beach_title" or snap.set_states != {"lamp": "on"}:
		return "o snapshot guarda o estado mudado pelo hotspot: %s" % [snap]
	var m2 := _stage_modules()
	var st2 := m2.stage as VNRuntimeStage
	st2.restore(snap)
	if st2.set_view().state_of("lamp") != "on" or st2.snapshot() != snap:
		return "restore reaplica os estados"
	st2.set_background({"asset": "bg/sea"})
	if st2.set_view() != null or st2.snapshot().get("set", null) != null:
		return "trocar para imagem tira o set"
	# Janela larga: o set é refeito sem perder o estado.
	var sv := (st.get_layer(VNLayers.BACKGROUND).get_viewport() as SubViewport)
	sv.size = Vector2i(2520, 1080)
	await process_frame
	st._relayout()
	if st.set_view().state_of("lamp") != "on":
		return "o estado sobrevive a redimensionar a janela"
	var sky := st.set_view().layer_node("sky") as Sprite2D
	if sky.texture.get_size().x * sky.scale.x < 2520.0 - 0.5:
		return "em 21:9 o céu cobre a janela"
	return ""


func test_stage_acao_stage() -> String:
	var m := _stage_modules()
	var st := m.stage as VNRuntimeStage
	st.reduce_motion_override = true
	st.set_background({"set": "beach_title"})
	st._on_set_target_action(&"set", "lamp", &"set_state", {"state": "on"})
	if st.set_view().state_of("lamp") != "default":
		return "o escopo set é da tela, não do palco"
	st._on_set_target_action(&"stage", "lamp", &"set_state", {"state": "on"})
	st._on_set_target_action(&"stage", "sky", &"toggle_state", {"states": ["default", "night"]})
	if st.snapshot().set_states != {"lamp": "on", "sky": "night"}:
		return "stage:<camada> muda o set em cena: %s" % [st.snapshot()]
	st._on_set_target_action(&"stage", "lamp", &"hide", {})
	if st.set_view().layer_node("lamp").visible:
		return "stage:lamp hide"
	return ""


func test_stage_gate_na_transicao() -> String:
	var m := _stage_modules()
	var st := m.stage as VNRuntimeStage
	st.set_background({"set": "beach_title", "transition": {"kind": "dissolve", "duration": 1.0}})
	if not st.is_busy(&"background"):
		return "a transição devia estar em andamento"
	st.set_view().activate_hotspot("lamp_click")
	if st.set_view().state_of("lamp") != "default":
		return "durante a transição do cenário os hotspots não respondem"
	st.skip_transitions()
	st.set_view().activate_hotspot("lamp_click")
	if st.set_view().state_of("lamp") != "on":
		return "depois da transição respondem"
	st.set_view().set_state("lamp", "default")
	(m.plugins as FakePluginHost).activity = {"activity": &"fishing.fishing_game", "mode": VNPluginHost.MODE_STORY, "params": {}, "skippable": false}
	st.set_view().activate_hotspot("lamp_click")
	if st.set_view().state_of("lamp") != "default":
		return "com um minijogo na tela os hotspots não respondem"
	return ""


func test_stage_show_hotspots() -> String:
	var m := _stage_modules()
	var st := m.stage as VNRuntimeStage
	st.reduce_motion_override = true
	st.set_background({"set": "beach_title"})
	var h := st.set_view().hotspot_node("lamp_click")
	if h.show_always:
		return "show_hotspots começa desligado"
	st._on_setting_changed(&"show_hotspots", true)
	if not h.show_always:
		return "show_hotspots destaca todos"
	return ""
