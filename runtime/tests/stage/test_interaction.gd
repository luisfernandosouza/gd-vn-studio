extends SceneTree
## Testes das escolhas e do nó interact no Stage (tarefa M2-04; RT §5.2, UI Spec §6).
##
##   godot --headless --path runtime --script res://tests/stage/test_interaction.gd
##
## O Stage real roda contra os dublês dos outros módulos (VNFakeModules), com as
## texturas e o interact da demo (docs/specs/examples/demo-project/). A entrada
## é simulada com eventos [code]vn_*[/code] (teclado, gamepad) chamados direto no
## [VNStageInteraction]. Sai com 1 se algo falhar.

const DEMO := "../docs/specs/examples/demo-project"
const ALICE := "019a7a00-0bb8-7dc0-b468-e39508f1443d"
const PROBE := "probe"

## Tamanhos das imagens da demo (gd-vn-studio-demo/assets).
const DEMO_SIZES := {
	"background": Vector2i(1920, 1080),
	"sprite": Vector2i(784, 1016),
	"obj/lamp_off": Vector2i(220, 420),
	"obj/lamp_on": Vector2i(220, 420),
	"obj/shell": Vector2i(140, 120),
}

var _passed := 0
var _failed := 0
var _host: SubViewport = null


func _initialize() -> void:
	# Em _initialize a raiz ainda não está na árvore: os testes rodam no primeiro quadro.
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	for t in [
		"escolhas_botoes_e_selecao", "escolhas_layouts", "escolhas_teclado_e_gamepad",
		"escolhas_tela_aberta_cede_a_entrada", "escolhas_estilo_do_tema", "escolhas_texto_sem_marcacao",
		"interact_demo_areas", "interact_selecao_hotspot_e_saida", "interact_teclado_em_ordem",
		"interact_area_personagem", "interact_area_sem_alvo", "interact_mascara_alfa",
		"interact_hotspot_desabilitado", "interact_cursor_e_destaque", "interact_21_9",
		"clear_e_detach",
	]:
		_run(t)
	print("%d/%d testes de escolhas e interact passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	var res: Variant = call("test_" + test)
	var err: String = res if res is String else "o teste não devolveu resultado (erro de script)"
	if _host != null:
		_host.free()
		_host = null
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Montagem ---------------------------------------------------------------

func _read_json(rel: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://").path_join(DEMO).path_join(rel)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _texture(size: Vector2i) -> Texture2D:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


## Bundle mínimo com os assets, a Alice e o set da demo, mais a personagem
## de teste "probe" (sem default_expression) e assets de teste.
func _demo_bundle() -> Dictionary:
	var assets: Dictionary = _read_json("assets.json").assets
	var alice: Dictionary = _read_json("characters/alice.json")
	var beach: Dictionary = _read_json("sets/beach_title.json")
	var project: Dictionary = _read_json("project.json")
	assets["test/tall"] = {"path": "t.png", "type": "sprite", "anchor": [0.0, 0.5], "scale": 0.5}
	assets["test/hot"] = {"path": "h.png", "type": "sprite", "censored": {"replace_with": "test/tall"}}
	assets["test/hidden"] = {"path": "x.png", "type": "sprite", "censored": {"hide": true}}
	assets["test/bg_hidden"] = {"path": "y.png", "type": "background", "censored": {"hide": true}}
	assets["test/placeholder"] = {"path": "p.png", "type": "background"}
	var probe := {"id": PROBE, "key": "probe", "name": "Probe",
		"expressions": {"tall": "test/tall", "hot": "test/hot", "hidden": "test/hidden", "plain": "char/alice/sad"}}
	project["content_filter"] = {"placeholder": "test/placeholder"}
	return {"assets": assets, "characters": {ALICE: alice, PROBE: probe}, "sets": {"beach_title": beach}, "project": project}


## Registro com o Stage real e um VNAssets dublê com texturas do tamanho da demo,
## preso a uma SubViewport do tamanho da área visível.
func _make(visible := Vector2i(1920, 1080)) -> VNModules:
	var m := VNFakeModules.create()
	m.stage = VNRuntimeStage.new()
	m.bind_all()
	var bundle := _demo_bundle()
	var fa := m.assets as FakeAssets
	fa.load_bundle(bundle)
	for id in bundle.assets:
		var a: Dictionary = bundle.assets[id]
		if a.has("censored"):
			fa.censored[id] = a.censored
		var size: Vector2i
		if DEMO_SIZES.has(id):
			size = DEMO_SIZES[id]
		elif id == "test/tall":
			size = Vector2i(100, 400)
		elif DEMO_SIZES.has(a.type):
			size = DEMO_SIZES[a.type]
		else:
			continue
		fa.resources[id] = _texture(size)
	m.stage.load_bundle(bundle)
	_host = SubViewport.new()
	_host.size = visible
	root.add_child(_host)
	m.stage.attach(_host)
	return m


func _stage(m: VNModules) -> VNRuntimeStage:
	return m.stage as VNRuntimeStage


## Nós background/show/hide de uma cena da demo, na ordem.
func _demo_stage_nodes(scene_rel: String) -> Array:
	var s: Dictionary = _read_json(scene_rel)
	return s.nodes.filter(func(n): return n.type in ["background", "show", "hide"])


func _run_nodes(st: VNRuntimeStage, nodes: Array) -> void:
	for n in nodes:
		match n.type:
			"background": st.set_background(n)
			"show": st.show_character(n)
			"hide": st.hide_character(n)


## Retângulo da personagem em pixels da área visível (o que aparece na janela).
func _screen_rect(st: VNRuntimeStage, id: String) -> Rect2:
	var r := st.character_rect(id)
	r.position += st.get_layer(VNLayers.CHARACTERS).offset
	return r


func _approx(a: Variant, b: Variant) -> bool:
	if a is Rect2:
		return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)
	if a is Vector2:
		return a.is_equal_approx(b)
	return is_equal_approx(float(a), float(b))


func _sprite(st: VNRuntimeStage, id: String) -> Sprite2D:
	var holder := st.get_layer(VNLayers.CHARACTERS).get_node_or_null(id)
	return holder.get_node_or_null("Sprite") as Sprite2D if holder != null else null


func _bg_view(st: VNRuntimeStage) -> Node2D:
	var holder := st.get_layer(VNLayers.BACKGROUND).get_node("Scenery")
	var live := holder.get_children().filter(func(c): return not c.is_queued_for_deletion())
	return live.back() if not live.is_empty() else null


# --- Auxiliares --------------------------------------------------------------

func _key(action: StringName) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


func _options(enabled_third := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "a", "text": "Primeira", "enabled": true},
		{"id": "b", "text": "Segunda", "enabled": true},
		{"id": "c", "text": "Terceira", "enabled": enabled_third},
		{"id": "d", "text": "Quarta", "enabled": true},
	]
	return out


## Os hotspots do interact da demo no formato do Stage, mais a saída.
func _demo_interact() -> Dictionary:
	var node: Dictionary = (_read_json("scenes/ch01/scene_quiet_day.json").nodes as Array).filter(func(n): return n.type == "interact")[0]
	var hs: Array[Dictionary] = []
	for h in node.hotspots:
		hs.append({"id": h.id, "label": h.label, "area": h.area, "cursor": h.get("cursor", "default"), "enabled": true})
	return {"node": node, "hotspots": hs, "exit": {"label": node.exit.label}}


func _with_demo_set(m: VNModules) -> VNRuntimeStage:
	var st := _stage(m)
	st.reduce_motion_override = true
	st.set_background({"set": "beach_title"})
	return st


func _selected(st: VNRuntimeStage) -> Array:
	var got: Array = []
	st.option_selected.connect(func(id: String): got.append(id))
	return got


# --- Testes -----------------------------------------------------------------

func test_escolhas_botoes_e_selecao() -> String:
	var m := _make()
	var st := _stage(m)
	var got := _selected(st)
	st.show_choices("E agora?", _options())
	var it := st.interaction()
	if it.kind() != VNStageInteraction.KIND_CHOICES or it.item_ids() != PackedStringArray(["a", "b", "c", "d"]):
		return "itens %s" % [it.item_ids()]
	var b: Button = it.item("c")
	if not b.disabled or b.focus_mode != Control.FOCUS_NONE:
		return "opção desabilitada deve aparecer sem foco"
	if (it.item("a") as Button).disabled:
		return "opção habilitada veio desabilitada"
	var prompt := st.get_layer(VNLayers.TEXTBOX).get_node("Choices/Box/Prompt") as Label
	if prompt.text != "E agora?":
		return "prompt '%s'" % prompt.text
	(it.item("b") as Button).pressed.emit()
	(it.item("a") as Button).pressed.emit()   # a segunda escolha antes de limpar é ignorada
	if got != ["b"]:
		return "escolhas emitidas %s" % [got]
	st.clear_interaction()
	if it.kind() != VNStageInteraction.KIND_NONE or not it.item_ids().is_empty():
		return "clear_interaction não limpou"
	st.show_choices("", _options(true))
	(it.item("c") as Button).pressed.emit()
	if got != ["b", "c"]:
		return "nova escolha depois de limpar: %s" % [got]
	return ""


func test_escolhas_layouts() -> String:
	var base := Vector2(1920, 1080)
	var avail := base.y * (1.0 - 0.28)
	for layout in ["center", "list_left", "list_right"]:
		var m := _make()
		var st := _stage(m)
		st.load_bundle(_demo_bundle().merged({"theme": {"choices": {"layout": layout}, "textbox": {"position": "bottom", "height": 0.28}}}))
		st.show_choices("Pergunta", _options(true))
		var box := st.get_layer(VNLayers.TEXTBOX).get_node("Choices/Box") as Control
		var r := Rect2(box.position, box.size)
		if not Rect2(Vector2.ZERO, base).encloses(r):
			return "%s: caixa fora da tela %s" % [layout, r]
		if r.end.y > avail + 1.0:
			return "%s: as escolhas cobrem a caixa de texto (%s > %s)" % [layout, r.end.y, avail]
		var cx := r.get_center().x
		match layout:
			"center":
				if absf(cx - base.x / 2.0) > 1.0:
					return "center fora do centro: %s" % cx
			"list_left":
				if cx > base.x * 0.4:
					return "list_left não ficou à esquerda: %s" % cx
			"list_right":
				if cx < base.x * 0.6:
					return "list_right não ficou à direita: %s" % cx
		_host.free()
		_host = null
	return ""


func test_escolhas_teclado_e_gamepad() -> String:
	var m := _make()
	var st := _stage(m)
	var got := _selected(st)
	st.show_choices("", _options())
	var it := st.interaction()
	if it.handle_input(_key(&"vn_up")) != true or not (it.item("a") as Button).has_focus():
		return "a primeira direção deve focar a primeira opção"
	it.handle_input(_key(&"vn_down"))
	if not (it.item("b") as Button).has_focus():
		return "vn_down não foi para a segunda"
	it.handle_input(_key(&"vn_down"))   # pula a desabilitada
	if not (it.item("d") as Button).has_focus():
		return "vn_down não pulou a desabilitada"
	it.handle_input(_key(&"vn_down"))
	if not (it.item("a") as Button).has_focus():
		return "vn_down no fim deve voltar ao início"
	it.handle_input(_key(&"vn_up"))
	if not (it.item("d") as Button).has_focus():
		return "vn_up no início deve ir ao fim"
	it.handle_input(_key(&"vn_left"))
	if not (it.item("b") as Button).has_focus():
		return "vn_left deve voltar um item"
	var pad := InputEventJoypadButton.new()   # botão A do gamepad = vn_confirm
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	if not it.handle_input(pad) or got != ["b"]:
		return "o botão A do gamepad deveria escolher a opção focada: %s" % [got]
	if it.handle_input(_key(&"vn_down")):
		return "depois de escolher a entrada não deve mais ser consumida"
	# Teclado: Enter confirma a focada.
	st.clear_interaction()
	got.clear()
	st.show_choices("", _options())
	it.handle_input(_key(&"vn_confirm"))   # a primeira confirmação só foca
	if not got.is_empty() or not (it.item("a") as Button).has_focus():
		return "a primeira confirmação só deveria focar (escolheu %s)" % [got]
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	if not it.handle_input(enter) or got != ["a"]:
		return "Enter deveria escolher a focada: %s" % [got]
	return ""


func test_escolhas_tela_aberta_cede_a_entrada() -> String:
	var m := _make()
	var st := _stage(m)
	var got := _selected(st)
	st.show_choices("", _options())
	var it := st.interaction()
	(m.ui as FakeUIManager).stack = PackedStringArray(["pause"])
	if it.handle_input(_key(&"vn_down")) or it.handle_input(_key(&"vn_confirm")):
		return "com a pausa aberta a entrada é do UI Manager"
	(m.ui as FakeUIManager).stack = PackedStringArray()
	if not it.handle_input(_key(&"vn_down")):
		return "fechada a pausa, a navegação deve voltar"
	if not got.is_empty():
		return "nada deveria ter sido escolhido"
	return ""


func test_escolhas_estilo_do_tema() -> String:
	var m := _make()
	var st := _stage(m)
	var theme := {
		"colors": {"text": "#ffffff", "accent": "#6aa9ff", "disabled": "#ffffff66"},
		"choices": {"layout": "center", "style": "gold"},
		"styles": {
			"button": {"shape": "rounded", "radius": 10, "border_width": 2, "font_size": 30, "padding": [24, 10, 24, 10],
				"fill": {"normal": "#101826cc", "hover": "#22406acc", "disabled": "#10182666", "focus": "#22406acc"}},
			"choice": {"extends": "button", "font_size": 28, "padding": [32, 14, 32, 14]},
			"gold": {"extends": "choice", "shape": "pill", "fill": {"normal": "#c8a040ff"}},
		},
	}
	st.load_bundle(_demo_bundle().merged({"theme": theme}))
	var it := st.interaction()
	var rs := it.resolved_style("gold")
	if rs.font_size != 28 or rs.shape != "pill" or rs.fill.normal != "#c8a040ff" or rs.fill.hover != "#22406acc" or rs.padding != [32, 14, 32, 14]:
		return "extends mal resolvido: %s" % [rs]
	st.show_choices("", _options())
	var b := it.item("a") as Button
	var normal := b.get_theme_stylebox("normal") as StyleBoxFlat
	if b.get_theme_font_size("font_size") != 28 or normal.bg_color != Color.from_string("#c8a040ff", Color.BLACK):
		return "estilo gold não aplicado ao botão"
	if normal.corner_radius_top_left != 999 or normal.content_margin_left != 32.0 or normal.content_margin_top != 14.0:
		return "forma ou padding errados"
	var dis := b.get_theme_stylebox("disabled") as StyleBoxFlat
	if dis.bg_color != Color.from_string("#10182666", Color.BLACK):
		return "fundo desabilitado"
	# Sem tema: valores do preset classic.
	var m2 := _make()
	var st2 := _stage(m2)
	if st2.interaction().resolved_style("choice").font_size != 28:
		return "sem tema deveria valer o padrão do classic"
	return ""


func test_escolhas_texto_sem_marcacao() -> String:
	var m := _make()
	var st := _stage(m)
	var opts: Array[Dictionary] = [{"id": "a", "text": "Dizer [b]sim[/b]", "enabled": true}]
	st.show_choices("", opts)
	if (st.interaction().item("a") as Button).text != "Dizer sim":
		return "texto '%s'" % (st.interaction().item("a") as Button).text
	return ""


func test_interact_demo_areas() -> String:
	var m := _make()
	var st := _with_demo_set(m)
	var d := _demo_interact()
	st.show_hotspots(d.hotspots, d.exit, "O que você quer olhar?")
	var it := st.interaction()
	if it.kind() != VNStageInteraction.KIND_HOTSPOTS:
		return "tipo %s" % it.kind()
	var ids := it.item_ids()
	if ids.size() != 3 or ids[2] != VNStage.EXIT_ID:
		return "itens %s (a saída vem por último, com o id reservado)" % [ids]
	var shell := it.item(d.hotspots[0].id) as VNUIHotspot
	if not _approx(Rect2(shell.position, shell.size), Rect2(0.55 * 1920, 0.82 * 1080, 0.05 * 1920, 0.05 * 1080)):
		return "concha em %s %s" % [shell.position, shell.size]
	# A lâmpada é a máscara alfa da camada "lamp" do set: cobre o sprite da camada.
	var lamp := it.item(d.hotspots[1].id) as VNUIHotspot
	var sp := st.set_layer_sprite("lamp")
	if sp == null:
		return "camada lamp não achada"
	if not _approx(Rect2(lamp.position, lamp.size), Rect2(sp.global_position, sp.texture.get_size() * sp.scale)):
		return "área da lâmpada %s %s ≠ sprite" % [lamp.position, lamp.size]
	if not lamp._has_point(lamp.size / 2.0) or lamp._has_point(lamp.size + Vector2.ONE):
		return "o centro da lâmpada deve responder e fora dela não"
	var layer := st.get_layer(VNLayers.HOTSPOTS)
	if shell.get_parent().get_parent() != layer:
		return "hotspots devem estar na camada 15"
	var prompt := layer.get_node("Interact/Prompt") as Label
	if prompt.text != "O que você quer olhar?":
		return "prompt '%s'" % prompt.text
	var exit_b := layer.get_node("Interact/Exit") as Button
	if exit_b.text != "Voltar para casa":
		return "saída '%s'" % exit_b.text
	return ""


func test_interact_selecao_hotspot_e_saida() -> String:
	var m := _make()
	var st := _with_demo_set(m)
	var got := _selected(st)
	var d := _demo_interact()
	st.show_hotspots(d.hotspots, d.exit)
	var it := st.interaction()
	var shell := it.item(d.hotspots[0].id) as VNUIHotspot
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	shell._gui_input(click)
	if got != [d.hotspots[0].id]:
		return "clique no hotspot: %s" % [got]
	st.clear_interaction()
	st.show_hotspots(d.hotspots, d.exit)
	(it.item(VNStage.EXIT_ID) as Button).pressed.emit()
	if got != [d.hotspots[0].id, VNStage.EXIT_ID]:
		return "saída: %s" % [got]
	# Id de saída informado pelo Narrative Engine.
	st.clear_interaction()
	st.show_hotspots(d.hotspots, {"id": "leave", "label": "Sair"})
	(it.item("leave") as Button).pressed.emit()
	if got.back() != "leave":
		return "id próprio da saída: %s" % [got]
	return ""


func test_interact_teclado_em_ordem() -> String:
	var m := _make()
	var st := _with_demo_set(m)
	var got := _selected(st)
	var d := _demo_interact()
	st.show_hotspots(d.hotspots, d.exit)
	var it := st.interaction()
	var order: Array = []
	for i in 4:
		it.handle_input(_key(&"vn_right"))
		order.append(String((it._focus_owner() as Control).name))
	var want := [
		"Hotspot_" + d.hotspots[0].id, "Hotspot_" + d.hotspots[1].id, "Exit", "Hotspot_" + d.hotspots[0].id]
	if order != want:
		return "ordem do foco %s" % [order]
	it.handle_input(_key(&"vn_left"))
	it.handle_input(_key(&"vn_confirm"))   # no Exit
	if got != [VNStage.EXIT_ID]:
		return "confirmar a saída focada: %s" % [got]
	st.clear_interaction()
	st.show_hotspots(d.hotspots, {})
	it.handle_input(_key(&"vn_down"))
	it.handle_input(_key(&"vn_confirm"))
	if got.back() != d.hotspots[0].id:
		return "confirmar o primeiro hotspot: %s" % [got]
	return ""


func test_interact_area_personagem() -> String:
	var m := _make()
	var st := _stage(m)
	st.reduce_motion_override = true
	st.show_character({"character": ALICE, "expression": "happy", "position": "right"})
	var hs: Array[Dictionary] = [{"id": "alice", "label": "Alice", "area": {"character": ALICE}, "enabled": true}]
	st.show_hotspots(hs)
	var h := st.interaction().item("alice") as VNUIHotspot
	var r := st.character_rect(ALICE)
	if r.size == Vector2.ZERO or not _approx(Rect2(h.position, h.size), r):
		return "área da personagem %s %s ≠ %s" % [h.position, h.size, r]
	# Troca de posição: o refit acompanha o sprite.
	st.show_character({"character": ALICE, "position": "left"})
	st.interaction().refit()
	if not _approx(Rect2(h.position, h.size), st.character_rect(ALICE)):
		return "a área não seguiu a personagem"
	return ""


func test_interact_area_sem_alvo() -> String:
	var m := _make()
	var st := _stage(m)
	st.reduce_motion_override = true
	var hs: Array[Dictionary] = [
		{"id": "p", "label": "Alice", "area": {"character": ALICE}, "enabled": true},
		{"id": "l", "label": "Lamp", "area": {"layer": "lamp"}, "enabled": true},
		{"id": "r", "label": "Rect", "area": {"rect": [0.1, 0.1, 0.1, 0.1]}, "enabled": true},
	]
	st.show_hotspots(hs)   # sem personagem no palco e sem set
	var it := st.interaction()
	if it.item_ids() != PackedStringArray(["r"]):
		return "só o rect tem área: %s" % [it.item_ids()]
	if (it.item("p") == null) == false:
		return "hotspot sem área não deve ser navegável"
	st.show_character({"character": ALICE, "position": "center"})
	it.refit()
	if it.item_ids() != PackedStringArray(["p", "r"]):
		return "a personagem entrou em cena e o hotspot deveria ganhar área: %s" % [it.item_ids()]
	return ""


func test_interact_mascara_alfa() -> String:
	var img := Image.create_empty(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for x in range(0, 5):
		for y in range(0, 10):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	var h := VNUIHotspot.new()
	h.fit_mask(Rect2(100, 100, 50, 50), img, Vector2(5, 5))
	var ok_left := h._has_point(Vector2(10, 10))
	var ok_right := h._has_point(Vector2(40, 10))
	var out := h._has_point(Vector2(60, 10))
	h.free()
	if not ok_left or ok_right or out:
		return "máscara: esquerda=%s direita=%s fora=%s" % [ok_left, ok_right, out]
	return ""


func test_interact_hotspot_desabilitado() -> String:
	var m := _make()
	var st := _stage(m)
	var got := _selected(st)
	var hs: Array[Dictionary] = [
		{"id": "x", "label": "Trancado", "area": {"rect": [0.1, 0.1, 0.1, 0.1]}, "enabled": false},
		{"id": "y", "label": "Aberto", "area": {"rect": [0.5, 0.1, 0.1, 0.1]}, "enabled": true},
	]
	st.show_hotspots(hs)
	var it := st.interaction()
	var x := it.item("x") as VNUIHotspot
	if not x.disabled or x.focus_mode != Control.FOCUS_NONE or x.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return "desabilitado deve aparecer sem resposta"
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	x._gui_input(click)
	x.activated.emit()
	if not got.is_empty():
		return "um hotspot desabilitado nunca vira escolha: %s" % [got]
	it.handle_input(_key(&"vn_down"))
	if (it._focus_owner() as Control).name != "Hotspot_y":
		return "o foco deve pular o desabilitado"
	if x.tooltip_text != "Trancado":
		return "o rótulo ainda aparece como dica"
	return ""


func test_interact_cursor_e_destaque() -> String:
	var m := _make()
	var st := _stage(m)
	var hs: Array[Dictionary] = []
	for c in ["default", "look", "talk", "use", "walk"]:
		hs.append({"id": c, "label": c, "area": {"rect": [0.1, 0.1, 0.1, 0.1]}, "cursor": c, "highlight": "glow", "enabled": true})
	st.show_hotspots(hs)
	var it := st.interaction()
	for c in ["default", "look", "talk", "use", "walk"]:
		var h := it.item(c) as VNUIHotspot
		if h.mouse_default_cursor_shape != VNStageInteraction.CURSORS[c] or h.highlight != "glow":
			return "cursor/destaque de %s" % c
	(m.ui as FakeUIManager).settings["show_hotspots"] = true
	st.show_hotspots(hs)
	if not (it.item("look") as VNUIHotspot).show_always:
		return "PlayerSettings.show_hotspots deve destacar todos"
	return ""


func test_interact_21_9() -> String:
	var m := _make(Vector2i(2560, 1080))
	var st := _with_demo_set(m)
	var d := _demo_interact()
	st.show_hotspots(d.hotspots, d.exit)
	var shell := st.interaction().item(d.hotspots[0].id) as VNUIHotspot
	var screen := Rect2(shell.position + st.get_layer(VNLayers.HOTSPOTS).offset, shell.size)
	# Em 21:9 a área base fica centrada: 320 px de cada lado.
	if not _approx(screen.position, Vector2(0.55 * 1920 + 320, 0.82 * 1080)):
		return "concha na tela %s" % screen.position
	if not st.view_rect().encloses(Rect2(shell.position, shell.size)):
		return "a concha deveria estar na área visível"
	return ""


func test_clear_e_detach() -> String:
	var m := _make()
	var st := _with_demo_set(m)
	var d := _demo_interact()
	st.show_choices("p", _options())
	st.show_hotspots(d.hotspots, d.exit)
	if st.interaction().kind() != VNStageInteraction.KIND_HOTSPOTS or st.interaction().item_ids().size() != 3:
		return "a nova interação deve substituir a anterior: %s" % [st.interaction().item_ids()]
	var choices_root := st.get_layer(VNLayers.TEXTBOX).get_node("Choices")
	if choices_root.get_child_count() != 0:
		return "as escolhas antigas deveriam ter saído"
	st.clear()
	if st.interaction().kind() != VNStageInteraction.KIND_NONE:
		return "clear() deve limpar a interação"
	st.detach()
	if st.interaction() != null:
		return "detach deve soltar a interação"
	st.show_choices("", _options())   # sem árvore: só guarda os ids, sem erro
	return ""
