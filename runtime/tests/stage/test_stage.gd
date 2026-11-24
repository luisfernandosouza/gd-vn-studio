extends SceneTree
## Testes do Stage (tarefa M2-02): camadas, escala, cenário, personagens e transições.
##
##   godot --headless --path runtime --script res://tests/stage/test_stage.gd
##
## O Stage real roda contra os dublês dos outros módulos (VNFakeModules), com
## texturas sintéticas do tamanho das imagens da demo. As cenas da demo vêm de
## docs/specs/examples/demo-project/ (a cópia da demo nas specs). Sai com 1 se
## algo falhar.

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
		"camadas_fixas", "layout_puro", "demo_16_9", "demo_21_9", "redimensiona_janela",
		"cenario_cobre_a_tela", "show_padroes_e_ordem", "show_existente_troca_sem_reordenar",
		"posicoes_nomeadas_e_fracao", "ancora_e_escala_do_asset", "hide_e_hide_todos",
		"transicao_fade_personagem", "transicao_slide_personagem", "transicao_cenario_fade",
		"transicao_cenario_dissolve_e_slide", "novo_comando_termina_transicao", "reduce_motion_corta_seco",
		"set_parado_com_estado", "snapshot_e_restore", "modo_stream_resolve_assets",
		"conteudo_sensivel", "clear_e_detach",
	]:
		_run(t)
	print("%d/%d testes do Stage passaram." % [_passed, _passed + _failed])
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


# --- Testes -----------------------------------------------------------------

func test_camadas_fixas() -> String:
	var m := _make()
	var st := _stage(m)
	for layer in VNRuntimeStage.OWN_LAYERS:
		var cl := st.get_layer(layer)
		if cl == null or cl.layer != layer or cl.name != VNLayers.layer_name(layer):
			return "camada %d ausente ou errada" % layer
	for layer in [VNLayers.HUD, VNLayers.SCREENS, VNLayers.ACTIVITY]:
		if st.get_layer(layer) != null:
			return "camada %d é de outro módulo" % layer
	if st.base_size != Vector2(1920, 1080):
		return "resolução base %s" % st.base_size
	return ""


func test_layout_puro() -> String:
	if VNStageLayout.position_fraction("far_left") != 0.1 or VNStageLayout.position_fraction("far_right") != 0.9:
		return "posições nomeadas"
	if VNStageLayout.position_fraction(0.3) != 0.3 or VNStageLayout.position_fraction(1) != 1.0:
		return "fração numérica"
	if VNStageLayout.base_offset(Vector2(1920, 1080), Vector2(2520, 1080)) != Vector2(300, 0):
		return "deslocamento 21:9"
	if VNStageLayout.base_offset(Vector2(1920, 1080), Vector2(1920, 1440)) != Vector2(0, 180):
		return "deslocamento 4:3"
	var r := VNStageLayout.sprite_rect(Vector2(960, 1080), Vector2(784, 1016), Vector2(0.5, 1.0), 1.0)
	if r != Rect2(568, 64, 784, 1016):
		return "sprite_rect %s" % r
	return ""


## Cena da praia da demo em 16:9: a Alice no centro, pés na base da tela.
func test_demo_16_9() -> String:
	var m := _make(Vector2i(1920, 1080))
	var st := _stage(m)
	st.reduce_motion_override = true
	_run_nodes(st, _demo_stage_nodes("scenes/ch01/scene_beach.json"))
	var r := _screen_rect(st, ALICE)
	if not _approx(r, Rect2(568, 64, 784, 1016)):
		return "Alice em %s" % r
	var bg := _bg_view(st).get_node("Image") as Sprite2D
	if bg.texture != (m.assets as FakeAssets).resources["bg/train_beach"]:
		return "cenário errado"
	if not _approx(bg.position, Vector2.ZERO) or not _approx(bg.scale, Vector2.ONE):
		return "cenário em %s escala %s" % [bg.position, bg.scale]
	return ""


## A mesma cena em 21:9: a área base fica centrada (300 px de cada lado), a
## Alice continua no centro da janela e o cenário cobre a janela inteira.
func test_demo_21_9() -> String:
	var m := _make(Vector2i(2520, 1080))
	var st := _stage(m)
	st.reduce_motion_override = true
	_run_nodes(st, _demo_stage_nodes("scenes/ch01/scene_beach.json"))
	if st.get_layer(VNLayers.CHARACTERS).offset != Vector2(300, 0):
		return "offset %s" % st.get_layer(VNLayers.CHARACTERS).offset
	var r := _screen_rect(st, ALICE)
	if not _approx(r, Rect2(868, 64, 784, 1016)):
		return "Alice em %s" % r
	if not _approx(r.get_center().x, 1260.0):
		return "Alice fora do centro da janela"
	var bg := _bg_view(st).get_node("Image") as Sprite2D
	var screen_pos := bg.position + st.get_layer(VNLayers.BACKGROUND).offset
	var size := bg.texture.get_size() * bg.scale
	if not _approx(screen_pos.x, 0.0) or not _approx(size.x, 2520.0) or size.y < 1080.0 or screen_pos.y > 0.0:
		return "cenário não cobre a janela: %s %s" % [screen_pos, size]
	for name in ["left", "right", 0.2]:
		st.show_character({"character": ALICE, "position": name})
		var x := _screen_rect(st, ALICE).get_center().x
		if not _approx(x, 300.0 + 1920.0 * VNStageLayout.position_fraction(name)):
			return "posição %s em %s" % [name, x]
	return ""


func test_redimensiona_janela() -> String:
	var m := _make(Vector2i(1920, 1080))
	var st := _stage(m)
	st.show_character({"character": ALICE})
	_host.size = Vector2i(2520, 1080)
	if st.get_layer(VNLayers.BACKGROUND).offset != Vector2(300, 0):
		return "camadas não acompanharam a janela"
	if not _approx(_screen_rect(st, ALICE).position.x, 868.0):
		return "Alice em %s" % _screen_rect(st, ALICE)
	_host.size = Vector2i(1920, 1440)
	if st.get_layer(VNLayers.CHARACTERS).offset != Vector2(0, 180):
		return "4:3 offset %s" % st.get_layer(VNLayers.CHARACTERS).offset
	if not _approx(_screen_rect(st, ALICE).end.y, 1260.0):
		return "pés fora da base da área base"
	return ""


func test_cenario_cobre_a_tela() -> String:
	var m := _make(Vector2i(1920, 1440))
	var st := _stage(m)
	st.set_background({"asset": "bg/onsen_night"})
	var bg := _bg_view(st).get_node("Image") as Sprite2D
	var screen_pos := bg.position + st.get_layer(VNLayers.BACKGROUND).offset
	var size := bg.texture.get_size() * bg.scale
	if not _approx(size.y, 1440.0) or size.x < 1920.0 or not _approx(screen_pos.y, 0.0):
		return "não cobre: %s %s" % [screen_pos, size]
	if not _approx(screen_pos.x + size.x / 2.0, 960.0):
		return "não está centrado"
	return ""


func test_show_padroes_e_ordem() -> String:
	var m := _make()
	var st := _stage(m)
	st.show_character({"character": ALICE})
	st.show_character({"character": PROBE, "expression": "tall", "position": "right"})
	var snap := st.snapshot()
	var want := [{"id": ALICE, "expression": "neutral", "position": "center"}, {"id": PROBE, "expression": "tall", "position": "right"}]
	if snap.characters != want:
		return "snapshot %s" % [snap.characters]
	var layer := st.get_layer(VNLayers.CHARACTERS)
	if layer.get_child(0).name != ALICE or layer.get_child(1).name != PROBE:
		return "ordem de desenho"
	st.show_character({"character": "nao_existe"})
	if st.snapshot().characters.size() != 2:
		return "personagem desconhecida entrou"
	# Sem default_expression: entra sem sprite (como no vetor modo_stream_ligado_no_meio).
	st.hide_character({"character": PROBE})
	st.show_character({"character": PROBE})
	if st.snapshot().characters[1] != {"id": PROBE, "position": "center"} or _sprite(st, PROBE) != null:
		return "sem expressão: %s" % [st.snapshot().characters[1]]
	return ""


func test_show_existente_troca_sem_reordenar() -> String:
	var m := _make()
	var st := _stage(m)
	st.show_character({"character": ALICE, "position": "left"})
	st.show_character({"character": PROBE, "expression": "plain"})
	st.show_character({"character": ALICE, "expression": "happy"})
	var c: Dictionary = st.snapshot().characters[0]
	if c != {"id": ALICE, "expression": "happy", "position": "left"}:
		return "manteve a posição? %s" % c
	if _sprite(st, ALICE).texture != (m.assets as FakeAssets).resources["char/alice/happy"]:
		return "expressão não trocou"
	if st.get_layer(VNLayers.CHARACTERS).get_child(0).name != ALICE:
		return "show de quem já estava mudou a ordem"
	st.show_character({"character": ALICE, "expression": "nao_existe"})
	if st.snapshot().characters[0].expression != "happy":
		return "expressão inexistente trocou a atual"
	return ""


func test_posicoes_nomeadas_e_fracao() -> String:
	var m := _make()
	var st := _stage(m)
	for p in ["far_left", "left", "center", "right", "far_right", 0.0, 0.33, 1.0]:
		st.show_character({"character": ALICE, "position": p})
		var r := st.character_rect(ALICE)
		if not _approx(r.get_center().x, round(1920.0 * VNStageLayout.position_fraction(p))) or not _approx(r.end.y, 1080.0):
			return "%s: %s" % [p, r]
	return ""


func test_ancora_e_escala_do_asset() -> String:
	var m := _make()
	var st := _stage(m)
	st.show_character({"character": PROBE, "expression": "tall", "position": 0.5})
	# test/tall: 100×400, anchor [0, 0.5], scale 0.5 → 50×200, canto esquerdo no x 960, meio na base.
	var r := st.character_rect(PROBE)
	if not _approx(r, Rect2(960, 980, 50, 200)):
		return "rect %s" % r
	return ""


func test_hide_e_hide_todos() -> String:
	var m := _make()
	var st := _stage(m)
	st.show_character({"character": ALICE})
	st.show_character({"character": PROBE, "expression": "tall"})
	st.hide_character({"character": ALICE})
	if st.character_order() != PackedStringArray([PROBE]):
		return "hide: %s" % st.character_order()
	st.hide_character({"character": ALICE})  # quem não está no palco: nada
	st.show_character({"character": ALICE})
	st.hide_character({"character": "*"})
	if not st.character_order().is_empty() or not st.snapshot().characters.is_empty():
		return "hide *"
	var live := st.get_layer(VNLayers.CHARACTERS).get_children().filter(func(c): return not c.is_queued_for_deletion())
	if not live.is_empty():
		return "sprites ficaram na camada"
	return ""


func test_transicao_fade_personagem() -> String:
	var m := _make()
	var st := _stage(m)
	var done: Array = []
	st.transition_finished.connect(func(t): done.append(t))
	st.show_character({"character": ALICE, "transition": {"kind": "fade", "duration": 0.4}})
	var holder := st.get_layer(VNLayers.CHARACTERS).get_node(ALICE) as Node2D
	if not st.is_busy(StringName(ALICE)) or holder.modulate.a != 0.0:
		return "fade não começou"
	if st.is_busy(&"background"):
		return "alvo errado ocupado"
	st.skip_transitions()
	if st.is_busy(StringName(ALICE)) or holder.modulate.a != 1.0 or done != [StringName(ALICE)]:
		return "fade não terminou: %s %s" % [holder.modulate.a, done]
	st.hide_character({"character": ALICE, "transition": {"kind": "dissolve"}})
	if not st.is_busy(StringName(ALICE)) or st.snapshot().characters.size() != 0:
		return "hide com transição"
	st.skip_transitions()
	if not holder.is_queued_for_deletion():
		return "sprite não saiu depois do hide"
	return ""


func test_transicao_slide_personagem() -> String:
	var m := _make(Vector2i(2520, 1080))
	var st := _stage(m)
	st.show_character({"character": ALICE, "transition": {"kind": "slide_left", "duration": 1.0}})
	var holder := st.get_layer(VNLayers.CHARACTERS).get_node(ALICE) as Node2D
	if st.character_rect(ALICE).position.x < st.view_rect().end.x:
		return "slide_left não começou fora da tela, à direita: %s" % st.character_rect(ALICE)
	st.skip_transitions()
	if not _approx(holder.position, Vector2(960, 1080)):
		return "slide terminou em %s" % holder.position
	# Já no palco: desliza até a nova posição.
	st.show_character({"character": ALICE, "position": "left", "transition": {"kind": "slide_right", "duration": 1.0}})
	if not st.is_busy(StringName(ALICE)) or _approx(holder.position.x, 480.0):
		return "não deslizou"
	st.skip_transitions()
	if not _approx(holder.position, Vector2(480, 1080)):
		return "posição final %s" % holder.position
	st.hide_character({"character": ALICE, "transition": {"kind": "slide_left", "duration": 1.0}})
	st.skip_transitions()
	if st.character_rect_of(holder).end.x > st.view_rect().position.x:
		return "slide_left do hide não saiu pela esquerda"
	return ""


func test_transicao_cenario_fade() -> String:
	var m := _make()
	var st := _stage(m)
	st.set_background({"asset": "bg/train_beach"})
	var old := _bg_view(st)
	st.set_background({"asset": "bg/train_evening", "transition": {"kind": "fade", "duration": 1.0}})
	var new_view := _bg_view(st)
	if not st.is_busy(&"background") or new_view == old or new_view.modulate.a != 0.0:
		return "fade do cenário não começou"
	st.skip_transitions()
	if not old.is_queued_for_deletion() or new_view.modulate.a != 1.0:
		return "fade não terminou"
	if st.snapshot().background != "bg/train_evening":
		return "snapshot %s" % st.snapshot()
	return ""


func test_transicao_cenario_dissolve_e_slide() -> String:
	var m := _make()
	var st := _stage(m)
	st.set_background({"asset": "bg/train_beach", "transition": {"kind": "dissolve", "duration": 0.5}})
	st.skip_transitions()
	var old := _bg_view(st)
	if old.modulate.a != 1.0:
		return "primeiro cenário com dissolve"
	st.set_background({"asset": "bg/onsen_night", "transition": {"kind": "slide_left", "duration": 0.5}})
	var nv := _bg_view(st)
	if not _approx(nv.position.x, 1920.0):
		return "slide_left do cenário não entra pela direita: %s" % nv.position
	st.skip_transitions()
	if not _approx(nv.position.x, 0.0) or not old.is_queued_for_deletion():
		return "slide não terminou"
	return ""


func test_novo_comando_termina_transicao() -> String:
	var m := _make()
	var st := _stage(m)
	st.show_character({"character": ALICE, "transition": {"kind": "fade", "duration": 5.0}})
	st.show_character({"character": ALICE, "expression": "sad"})
	if st.is_busy(StringName(ALICE)):
		return "continuou ocupado"
	var holder := st.get_layer(VNLayers.CHARACTERS).get_node(ALICE) as Node2D
	if holder.modulate.a != 1.0 or _sprite(st, ALICE).texture != (m.assets as FakeAssets).resources["char/alice/sad"]:
		return "estado final errado"
	return ""


func test_reduce_motion_corta_seco() -> String:
	var m := _make()
	var st := _stage(m)
	(m.ui as FakeUIManager).settings["reduce_motion"] = true
	var done: Array = []
	st.transition_finished.connect(func(t): done.append(t))
	st.set_background({"asset": "bg/train_beach", "transition": {"kind": "fade", "duration": 1.0}})
	st.show_character({"character": ALICE, "transition": {"kind": "slide_left", "duration": 1.0}})
	if st.is_busy(&"background") or st.is_busy(StringName(ALICE)):
		return "transição com reduce_motion"
	if done != [&"background", StringName(ALICE)]:
		return "transition_finished %s" % [done]
	if _bg_view(st).modulate.a != 1.0 or not _approx(st.character_rect(ALICE).get_center().x, 960.0):
		return "corte seco não deixou o estado final"
	(m.ui as FakeUIManager).settings["reduce_motion"] = false
	st.hide_character({"character": ALICE, "transition": {"kind": "fade", "duration": 1.0}})
	if not st.is_busy(StringName(ALICE)):
		return "sem reduce_motion a transição volta"
	return ""


## O set da demo (cena do dia tranquilo), parado: camadas na ordem, a lâmpada na
## posição com pivô central e o estado "on".
func test_set_parado_com_estado() -> String:
	var m := _make()
	var st := _stage(m)
	st.reduce_motion_override = true
	_run_nodes(st, _demo_stage_nodes("scenes/ch01/scene_quiet_day.json"))
	var view := _bg_view(st)
	var names := view.get_children().map(func(c): return String(c.name))
	if names != ["sky", "sea", "lamp", "shell"]:
		return "camadas %s" % [names]
	var lamp := view.get_node("lamp") as Sprite2D
	if not _approx(lamp.position, Vector2(0.8 * 1920 - 110, 0.62 * 1080 - 210)):
		return "lâmpada em %s" % lamp.position
	var snap := st.snapshot()
	if snap.background != null or snap.set != "beach_title" or snap.set_states != {}:
		return "snapshot do set %s" % snap
	st.restore({"background": null, "set": "beach_title", "set_states": {"lamp": "on", "sky": "night"}, "characters": []})
	view = _bg_view(st)
	var fa := m.assets as FakeAssets
	if (view.get_node("lamp") as Sprite2D).texture != fa.resources["obj/lamp_on"] or (view.get_node("sky") as Sprite2D).texture != fa.resources["bg/sky_night"]:
		return "estado das camadas não aplicado"
	return ""


func test_snapshot_e_restore() -> String:
	var m := _make()
	var st := _stage(m)
	st.set_background({"asset": "bg/train_beach"})
	st.show_character({"character": PROBE, "expression": "tall", "position": 0.3})
	st.show_character({"character": ALICE, "expression": "happy", "position": "right"})
	var snap := st.snapshot()
	var m2 := _make()
	var st2 := _stage(m2)
	st2.restore(snap)
	if st2.snapshot() != snap:
		return "restore → snapshot difere: %s" % st2.snapshot()
	if st2.character_order() != PackedStringArray([PROBE, ALICE]):
		return "ordem restaurada %s" % st2.character_order()
	if not _approx(st2.character_rect(ALICE).get_center().x, 1440.0):
		return "posição restaurada"
	if st2.is_busy(StringName(ALICE)) or st2.is_busy(&"background"):
		return "restore com transição"
	return ""


func test_modo_stream_resolve_assets() -> String:
	var m := _make()
	var st := _stage(m)
	var fa := m.assets as FakeAssets
	st.set_background({"asset": "test/bg_hidden"})
	st.show_character({"character": PROBE, "expression": "hot", "position": 0.5})
	st.show_character({"character": ALICE, "expression": "neutral"})
	fa.set_content_filter(true)
	st.set_content_filter(true)
	# replace_with usa a substituta com a âncora e a escala dela.
	if _sprite(st, PROBE) == null or _sprite(st, PROBE).texture != fa.resources["test/tall"]:
		return "substituta não desenhada"
	if not _approx(st.character_rect(PROBE), Rect2(960, 980, 50, 200)):
		return "âncora/escala da substituta: %s" % st.character_rect(PROBE)
	# hide no cenário: placeholder do projeto.
	if (_bg_view(st).get_node("Image") as Sprite2D).texture != fa.resources["test/placeholder"]:
		return "placeholder"
	# O estado guarda os ids originais.
	var snap := st.snapshot()
	if snap.background != "test/bg_hidden" or snap.characters[0].expression != "hot":
		return "snapshot com ids trocados: %s" % snap
	st.show_character({"character": PROBE, "expression": "hidden"})
	if _sprite(st, PROBE) != null:
		return "sprite com hide desenhado"
	return ""


func test_conteudo_sensivel() -> String:
	var m := _make()
	var st := _stage(m)
	st.set_background({"asset": "bg/train_beach"})
	if st.is_showing_sensitive():
		return "nada sensível"
	st.set_background({"asset": "bg/train_evening"})
	if not st.is_showing_sensitive():
		return "cenário com censored"
	st.set_content_filter(true)
	if st.is_showing_sensitive():
		return "com o modo ligado"
	return ""


func test_clear_e_detach() -> String:
	var m := _make()
	var st := _stage(m)
	st.set_background({"asset": "bg/train_beach", "transition": {"kind": "fade", "duration": 1.0}})
	st.show_character({"character": ALICE})
	st.clear()
	if st.is_busy(&"background") or st.snapshot() != {"background": null, "characters": []}:
		return "clear %s" % st.snapshot()
	st.set_textbox_hidden(true)
	if st.get_layer(VNLayers.TEXTBOX).visible:
		return "vn_hide"
	st.show_character({"character": ALICE})
	st.detach()
	if st.get_layer(VNLayers.BACKGROUND) != null or _host.get_child_count() != 0:
		return "detach deixou nós"
	st.attach(_host)
	if _screen_rect(st, ALICE) == Rect2() or not _approx(_screen_rect(st, ALICE).get_center().x, 960.0):
		return "attach de novo não redesenhou o palco"
	return ""
