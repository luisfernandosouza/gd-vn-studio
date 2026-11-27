extends SceneTree
## Testes do UI Manager (tarefa M2-06; UI Spec §2–§4, §8, §12).
##
##   python3 docs/specs/tools/compile_bundle.py docs/specs/examples/demo-project <saída> docs/specs/examples/fishing-plugin
##   godot --headless --path runtime --script res://tests/ui_manager/test_ui_manager.gd -- --bundle <saída>
##
## Usa as telas title, settings, credits e extras da demo (critério de aceite
## da issue), mais telas pequenas montadas aqui para as ações do UI Spec §4. Os
## outros módulos são os dublês de tests/fakes/, com um avaliador de condições
## que entende as condições simples do Data Model §5. Sai com 1 se algo falhar.

var _passed := 0
var _failed := 0
var _bundle_dir := ""
var _bundle: Dictionary = {}
var _strings: Dictionary = {}   # idioma → strings
var _licenses: Dictionary = {}
var _host: Node


## Avaliador com as condições simples { variable, operator, value } do Data
## Model §5.1, lidas do Variable Manager do registro.
class SimpleConditions extends FakeConditionEvaluator:
	func evaluate_conditions(conditions: Variant, bindings: Dictionary = {}) -> VNEvalResult:
		_rec(&"evaluate_conditions", [conditions, bindings])
		for c in conditions:
			var id := String(c.get("variable", ""))
			if not modules().variables.has(id):
				return VNEvalResult.failure(VNErrors.VARIABLE_NOT_FOUND, id)
			var v: Variant = modules().variables.read(id)
			var want: Variant = c.get("value")
			var ok: bool
			match String(c.get("operator", "equals")):
				"equals": ok = v == want
				"not_equals": ok = v != want
				"greater_than": ok = v > want
				"less_than": ok = v < want
				_: ok = false
			if not ok:
				return VNEvalResult.of(false, &"boolean")
		return VNEvalResult.of(true, &"boolean")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--bundle")
	if i < 0 or i + 1 >= args.size():
		printerr("uso: -- --bundle <pasta do bundle compilado da demo>")
		quit(2)
		return
	_bundle_dir = args[i + 1]
	_bundle = JSON.parse_string(FileAccess.get_file_as_string(_bundle_dir.path_join("bundle.json")))
	for lang in ["pt-BR", "en"]:
		_strings[lang] = JSON.parse_string(FileAccess.get_file_as_string(_bundle_dir.path_join("locales/%s.json" % lang))).strings
	_licenses = JSON.parse_string(FileAccess.get_file_as_string(_bundle_dir.path_join("licenses.json")))
	_main.call_deferred()


func _main() -> void:
	for t in [
		"contrato", "titulo_condicoes", "titulo_novo_jogo", "titulo_continuar", "titulo_foco_teclado",
		"titulo_on_open_set", "titulo_sair_confirma", "pilha_e_voltar", "settings_controles",
		"settings_arquivo_invalido", "settings_sobrevivem_reinicio", "settings_legado_fullscreen",
		"fps_novel_e_atividade", "settings_traducao", "credits_licencas", "extras_modo_livre",
		"extras_recusado_no_jogo", "acoes_if_else", "acoes_confirm_then_else", "acoes_effects_titulo",
		"acoes_effects_e_emit_no_jogo", "acoes_elementos", "pausa_pausa_o_engine", "hud_durante_atividade",
		"textos_interpolacao", "reset_profile",
	]:
		await _run(t)
	print("%d/%d testes do UI Manager passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_host)
	var err: String = await call("test_" + test)
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)
	_host.queue_free()
	await process_frame


# --- Montagem ---------------------------------------------------------------

func _setup(extra_ui: Dictionary = {}) -> Array:
	var m := VNFakeModules.create()
	m.conditions = SimpleConditions.new()
	var ui := VNRuntimeUIManager.new()
	ui.auto_quit = false
	m.ui = ui
	m.bind_all()
	var vars: FakeVariableManager = m.variables
	for id in ["sys.ui.has_save", "sys.ui.in_game", "sys.ui.activity", "sys.ui.activity_skippable",
			"sys.ui.has_minigames", "sys.ui.has_gallery", "sys.ui.gallery_endings", "sys.ui.gallery_images",
			"sys.ui.gallery_music", "sys.ui.content_filter", "sys.ui.content_filter_available", "sys.endings.festival_ending"]:
		vars.define(id, &"boolean", false)
	vars.define("sys.ui.platform", &"string", "linux")
	vars.define("sys.ui.last_activity_outcome", &"string", "")
	vars.define("global.player_money", &"integer", 30)
	vars.define("global.flag", &"boolean", false)
	vars.define("global.endings_seen", &"integer", 0, &"profile")
	var b: Dictionary = _bundle.duplicate(true)
	for k in extra_ui:
		b.ui[k] = extra_ui[k]
	m.load_bundle(b)
	ui.settings_model().system_locale = "pt-BR"
	ui.set_locale_strings(_strings["pt-BR"], "pt-BR")
	ui.set_licenses(_licenses)
	ui.load_settings()
	m.attach_all(_host)
	(m.plugins as FakePluginHost).load_plugins({"plugins": {"fishing": {}}})
	return [m, ui]


func _to_title(m: VNModules) -> void:
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.TITLE)


func _to_game(m: VNModules) -> void:
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.NEW_GAME)
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.SCENE_RUNNING)


func _press(ui: VNRuntimeUIManager, action: StringName) -> bool:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ui.handle_input(ev)


func _click(ui: VNRuntimeUIManager, element: String) -> String:
	var s := ui.top_screen()
	if s == null or not s.elements.has(element):
		return "elemento %s não está na tela do topo" % element
	if not s.is_element_enabled(element):
		return "elemento %s desabilitado" % element
	var fc := VNUIElements.focus_control(s.elements[element])
	if fc is BaseButton:
		fc.pressed.emit()
	else:
		s.activate(element)
	return ""


func _focused() -> String:
	var f := root.gui_get_focus_owner()
	return String(f.get_meta(&"vn_id", f.get_parent().get_meta(&"vn_id", ""))) if f != null else ""


func _vis(ui: VNRuntimeUIManager, element: String) -> bool:
	return ui.top_screen().is_element_visible(element)


# --- Testes -----------------------------------------------------------------

func test_contrato() -> String:
	var base: GDScript = load("res://vn_runtime/ui_manager/vn_ui_manager.gd")
	var impl: GDScript = load("res://vn_runtime/ui_manager/vn_runtime_ui_manager.gd")
	if impl.get_base_script() != base or impl.is_abstract():
		return "VNRuntimeUIManager deve estender VNUIManager e ser concreto"
	var x := VNRuntimeUIManager.new()
	if x.module_id() != &"ui":
		return "module_id"
	return ""


func test_titulo_condicoes() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	await process_frame
	if ui.screen_stack() != PackedStringArray(["title"]):
		return "a fase TITLE deve abrir a tela title: %s" % ui.screen_stack()
	if _vis(ui, "btn_continue"):
		return "Continuar sem save deveria estar oculto"
	if ui.top_screen().is_element_enabled("btn_load"):
		return "Carregar sem save deveria estar desabilitado"
	if _vis(ui, "btn_extras"):
		return "Minijogos só aparece depois do final do festival"
	if not _vis(ui, "btn_quit") or not _vis(ui, "btn_new_game") or not _vis(ui, "btn_credits"):
		return "botões fixos do título"
	m.state.set_system_value("sys.ui.has_save", true)
	m.state.set_system_value("sys.endings.festival_ending", true)
	m.state.set_system_value("sys.ui.platform", "web")
	ui.refresh()
	if not _vis(ui, "btn_continue") or not ui.top_screen().is_element_enabled("btn_load"):
		return "Continuar/Carregar com save"
	if not _vis(ui, "btn_extras"):
		return "Minijogos depois do final"
	if _vis(ui, "btn_quit"):
		return "Sair escondido no Web"
	var btn: Button = ui.top_screen().elements["btn_new_game"]
	if btn.text != "Novo jogo":
		return "texto do botão: %s" % btn.text
	var cred: Button = ui.top_screen().elements["btn_credits"]
	if cred.tooltip_text != "Créditos":
		return "tooltip do botão de créditos"
	return ""


func test_titulo_novo_jogo() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	var e := _click(ui, "btn_new_game")
	if not e.is_empty():
		return e
	if (m.engine as FakeNarrativeEngine).count_calls(&"new_game") != 1:
		return "new_game não chamou o Narrative Engine"
	if not ui.screen_stack().is_empty():
		return "o título deve fechar: %s" % ui.screen_stack()
	if not ui.is_hud_visible():
		return "a hud deve aparecer no jogo"
	# new_game fora do título é recusado.
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.SCENE_RUNNING)
	if ui.run_actions([{"do": "new_game"}]).ok:
		return "new_game durante o jogo deveria ser recusado"
	return ""


func test_titulo_continuar() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	m.storage.write_json("saves/auto_1.json", {"created_at": "2026-11-01T00:00:00Z", "state": {"chapter": {"id": "c"}, "scene": {"id": "s", "node": "n"}}})
	m.storage.write_json("saves/slot_2.json", {"created_at": "2026-11-20T00:00:00Z", "state": {"chapter": {"id": "c"}, "scene": {"id": "s2", "node": "n2"}}})
	_to_title(m)
	ui.refresh_sys_ui()
	if m.variables.read("sys.ui.has_save") != true:
		return "refresh_sys_ui deveria ligar sys.ui.has_save"
	var e := _click(ui, "btn_continue")
	if not e.is_empty():
		return e
	var loads := (m.saves as FakeSaveManager).calls.filter(func(c): return c.method == &"load_slot")
	if loads.size() != 1 or loads[0].args[0] != &"slot_2":
		return "Continuar deve abrir o save mais recente: %s" % [loads]
	if (m.engine as FakeNarrativeEngine).current_scene() != "s2" or not ui.screen_stack().is_empty():
		return "depois de Continuar a pilha fica vazia e o jogo retoma"
	return ""


func test_titulo_foco_teclado() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	await process_frame
	if _focused() != "btn_new_game":
		return "focus_start: foco em %s" % _focused()
	# Sem save, Carregar está desabilitado e o vn_down pula para a Galeria
	# (a demo tem galeria); Minijogos está oculto, então o próximo é Configurações.
	_press(ui, &"vn_down")
	if _focused() != "btn_gallery":
		return "vn_down: foco em %s" % _focused()
	_press(ui, &"vn_down")
	if _focused() != "btn_settings":
		return "vn_down 2: foco em %s" % _focused()
	_press(ui, &"vn_up")
	_press(ui, &"vn_up")
	if _focused() != "btn_new_game":
		return "vn_up: foco em %s" % _focused()
	_press(ui, &"vn_down")
	_press(ui, &"vn_down")
	_press(ui, &"vn_confirm")
	if ui.screen_stack() != PackedStringArray(["title", "settings"]):
		return "vn_confirm em Configurações: %s" % ui.screen_stack()
	await process_frame
	if _focused() != "sl_master":
		return "focus_start das configurações: %s" % _focused()
	_press(ui, &"vn_cancel")
	await process_frame
	if ui.screen_stack() != PackedStringArray(["title"]):
		return "vn_cancel fecha as configurações"
	if _focused() != "btn_settings":
		return "o foco volta para onde estava: %s" % _focused()
	_press(ui, &"vn_cancel")
	if ui.screen_stack() != PackedStringArray(["title"]):
		return "vn_cancel no título não faz nada"
	return ""


func test_titulo_on_open_set() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	var got := []
	ui.set_target_action.connect(func(scope, target, action, args): got.append([scope, target, action, args]))
	_to_title(m)
	if not got.is_empty():
		return "sem o final, o céu não muda"
	ui.close_all()
	m.state.set_system_value("sys.endings.festival_ending", true)
	ui.open_screen("title")
	if got != [[&"set", "sky", &"set_state", {"state": "night"}]]:
		return "on_open com set_state: %s" % [got]
	got.clear()
	var e := _click(ui, "shell")
	if not e.is_empty():
		return e
	if got.size() != 1 or got[0][2] != &"play_animation":
		return "hotspot da concha: %s" % [got]
	if (m.audio as FakeAudioManager).calls.filter(func(c): return c.method == &"play" and c.args[0] == "sfx/shell").size() != 1:
		return "play_sfx da concha"
	return ""


func test_titulo_sair_confirma() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	var quits := [0]
	ui.quit_requested.connect(func(): quits[0] += 1)
	_to_title(m)
	_click(ui, "btn_quit")
	if ui.open_dialogs().size() != 1 or quits[0] != 0:
		return "Sair pede confirmação antes"
	var text: String = ui.open_dialogs()[0].label.text
	if not text.contains("Sair"):
		return "texto da confirmação: %s" % text
	_press(ui, &"vn_cancel")
	if quits[0] != 0 or not ui.open_dialogs().is_empty():
		return "vn_cancel responde não"
	_click(ui, "btn_quit")
	ui.answer_dialog(true)
	if quits[0] != 1:
		return "Sim fecha o jogo"
	ui.platform = "web"
	if ui.run_actions([{"do": "quit", "confirm": false}]).ok:
		return "quit recusado no Web"
	return ""


func test_pilha_e_voltar() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	var changes := []
	ui.screens_changed.connect(func(s): changes.append(s))
	_click(ui, "btn_credits")
	if ui.screen_stack() != PackedStringArray(["title", "credits"]):
		return "créditos empilha sobre o título"
	_click(ui, "btn_back")
	if ui.screen_stack() != PackedStringArray(["title"]):
		return "back desempilha"
	if changes.size() != 2:
		return "screens_changed: %s" % [changes]
	if ui.open_screen("nao_existe").ok:
		return "tela inexistente deveria falhar"
	# Galeria: a demo tem galeria; o botão abre a tela.
	m.state.set_system_value("sys.ui.has_gallery", true)
	ui.refresh()
	_click(ui, "btn_gallery")
	if ui.screen_stack()[-1] != "gallery":
		return "galeria"
	ui.close_all()
	if not ui.screen_stack().is_empty():
		return "close_all"
	return ""


func test_settings_controles() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	ui.open_screen("settings")
	await process_frame
	var s := ui.top_screen()
	var changed := []
	ui.setting_changed.connect(func(k, v): changed.append([k, v]))
	var master: HSlider = VNUIElements.focus_control(s.elements["sl_master"])
	if not is_equal_approx(master.value, 0.8):
		return "volume geral começa no padrão 0,8: %s" % master.value
	master.value = 0.5
	var saved: Dictionary = m.storage.read_json("settings.json")
	if saved.get("volume", {}).get("master") != 0.5:
		return "settings.json: %s" % saved
	# vn_right no slider muda o valor pelo step.
	master.grab_focus()
	_press(ui, &"vn_right")
	if not is_equal_approx(float(ui.get_setting(&"volume.master")), 0.55):
		return "vn_right no slider: %s" % ui.get_setting(&"volume.master")
	var music: HSlider = VNUIElements.focus_control(s.elements["sl_music"])
	music.value = 0.25
	if not is_equal_approx((m.audio as FakeAudioManager).get_channel_volume(VNAudioManager.MUSIC), 0.25):
		return "volume da música vai ao Audio Manager"
	var fps: OptionButton = VNUIElements.focus_control(s.elements["sel_fps_vn"])
	if fps.item_count != 5 or fps.get_item_text(fps.selected) != "60":
		return "FPS na história: %d opções, %s" % [fps.item_count, fps.get_item_text(fps.selected)]
	fps.select(4)
	fps.item_selected.emit(4)
	if ui.get_setting(&"fps_limit_vn") != 0:
		return "Sem limite = 0: %s" % ui.get_setting(&"fps_limit_vn")
	var loc: OptionButton = VNUIElements.focus_control(s.elements["sel_locale"])
	if loc.item_count != 2:
		return "idiomas do jogo: %d" % loc.item_count
	var mode: OptionButton = VNUIElements.focus_control(s.elements["sel_mode"])
	if mode.item_count != 3 or mode.get_item_text(0) != "Janela":
		return "modo de tela com textos do preset: %s" % mode.get_item_text(0)
	var cf: CheckButton = VNUIElements.focus_control(s.elements["tg_content_filter"])
	cf.button_pressed = true
	if ui.get_setting(&"content_filter") != true or not changed.has([&"content_filter", true]):
		return "modo stream: %s" % [changed]
	if ui.set_setting(&"volume.sfx", 2.0).ok or ui.set_setting(&"vsync", 1).ok or ui.set_setting(&"locale", "ja").ok:
		return "valores fora do schema devem dar TYPE_MISMATCH"
	if ui.set_setting(&"text_speed", "rápido").error != VNErrors.TYPE_MISMATCH:
		return "código do erro"
	# set_setting por ação atualiza o controle aberto.
	ui.run_actions([{"do": "set_setting", "setting": "volume.master", "value": 1}])
	if not is_equal_approx(master.value, 1.0):
		return "controle ligado acompanha a configuração"
	if _vis(ui, "sel_mode") == false:
		return "Modo de tela aparece fora do Web"
	m.state.set_system_value("sys.ui.platform", "web")
	ui.refresh()
	if _vis(ui, "sel_mode") or _vis(ui, "sel_fps_vn") or not _vis(ui, "tg_vsync"):
		return "controles escondidos no Web"
	saved = m.storage.read_json("settings.json")
	if saved.has("vsync") or saved.has("text_speed"):
		return "só o que o jogador mudou vai para settings.json: %s" % saved
	return ""


func test_settings_arquivo_invalido() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	m.storage.write_text("settings.json", "{ quebrado")
	ui.load_settings()
	if not m.storage.exists("settings.json.bad") or m.storage.exists("settings.json"):
		return "arquivo ilegível vira settings.json.bad"
	m.storage.write_json("settings.json", {"text_speed": -3})
	ui.load_settings()
	if not m.storage.exists("settings.json.bad") or ui.get_setting(&"text_speed") != 40.0:
		return "valor fora do schema: padrões"
	m.storage.write_json("settings.json", {"text_speed": 80, "volume": {"music": 0.1}, "locale": "en"})
	ui.load_settings()
	if ui.get_setting(&"text_speed") != 80.0 or ui.get_setting(&"volume.music") != 0.1 or ui.get_setting(&"locale") != "en":
		return "settings.json válido"
	if ui.get_setting(&"auto_delay") != 1.5 or ui.get_setting(&"fps_limit_activity") != 0 or ui.get_setting(&"display_mode") != "windowed":
		return "padrões do projeto"
	return ""


func test_settings_sobrevivem_reinicio() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	ui.set_setting(&"volume.music", 0.25)
	ui.set_setting(&"display_mode", "borderless")
	ui.set_setting(&"fps_limit_vn", 30)
	ui.set_setting(&"fps_limit_activity", 144)
	ui.set_setting(&"locale", "en")
	# Novo processo: outro UI Manager lendo o mesmo armazenamento.
	var r2 := _setup()
	var m2: VNModules = r2[0]
	var ui2: VNRuntimeUIManager = r2[1]
	m2.storage = m.storage
	ui2.load_settings()
	for pair in [["volume.music", 0.25], ["display_mode", "borderless"], ["fps_limit_vn", 30], ["fps_limit_activity", 144], ["locale", "en"]]:
		if ui2.get_setting(StringName(pair[0])) != pair[1]:
			return "%s não sobreviveu: %s" % [pair[0], ui2.get_setting(StringName(pair[0]))]
	if ui2.get_setting(&"volume.sfx") != 0.8 or ui2.get_setting(&"vsync") != true:
		return "o que o jogador não mudou continua com o padrão"
	var saved: Dictionary = m.storage.read_json("settings.json")
	return "" if saved.keys().size() == 4 + 1 and not saved.has("vsync") else "só o que mudou: %s" % saved


func test_settings_legado_fullscreen() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	m.storage.write_json("settings.json", {"fullscreen": true, "text_speed": 80})
	ui.load_settings()
	if m.storage.exists("settings.json.bad") or ui.get_setting(&"display_mode") != "fullscreen" or ui.get_setting(&"text_speed") != 80.0:
		return "fullscreen:true deveria virar display_mode fullscreen"
	var saved: Dictionary = m.storage.read_json("settings.json")
	if saved.has("fullscreen") or saved.get("display_mode") != "fullscreen":
		return "arquivo regravado no formato novo: %s" % saved
	m.storage.write_json("settings.json", {"fullscreen": true, "display_mode": "borderless"})
	ui.load_settings()
	if ui.get_setting(&"display_mode") != "borderless":
		return "display_mode gravado vence"
	m.storage.write_json("settings.json", {"fullscreen": false})
	ui.load_settings()
	return "" if ui.get_setting(&"display_mode") == "windowed" and not m.storage.read_json("settings.json").has("fullscreen") else "fullscreen:false"


func test_fps_novel_e_atividade() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	var model := ui.settings_model()
	# Padrões: 60 na novel, sem limite nas atividades.
	if ui.fps_limit_now() != 60 or model.activity_fps_limit(30) != 0:
		return "padrões 60 / 0"
	# Limite do padrão do projeto sobe até o min_fps; o do jogador vale como está.
	model.project = model.project.duplicate(true)
	model.project.settings.display["fps_limit_activity"] = 30
	if model.activity_fps_limit(60) != 60 or model.activity_fps_limit(0) != 30 or model.activity_fps_below_min(60):
		return "limite do projeto sobe até min_fps"
	ui.set_setting(&"fps_limit_activity", 30)
	if model.activity_fps_limit(60) != 30 or not model.activity_fps_below_min(60) or model.activity_fps_below_min(24):
		return "a escolha do jogador vence, com aviso"
	# A troca acompanha a fase do jogo.
	ui.set_setting(&"fps_limit_vn", 30)
	ui.set_setting(&"fps_limit_activity", 120)
	var e: FakeNarrativeEngine = m.engine
	e.set_phase(VNPhase.SCENE_RUNNING)
	if Engine.max_fps != 30:
		return "novel: %d" % Engine.max_fps
	e.set_phase(VNPhase.ACTIVITY)
	if Engine.max_fps != 120:
		return "atividade: %d" % Engine.max_fps
	e.set_phase(VNPhase.SCENE_RUNNING)
	return "" if Engine.max_fps == 30 else "volta à novel: %d" % Engine.max_fps


func test_settings_traducao() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	ui.open_screen("credits")
	var back: Button = ui.top_screen().elements["btn_back"]
	if back.text != "Voltar":
		return "pt-BR: %s" % back.text
	ui.set_locale_strings(_strings["en"], "en")
	back = ui.top_screen().elements["btn_back"]
	if back.text != "Back":
		return "trocar de idioma refaz as telas: %s" % back.text
	if ui.screen_stack() != PackedStringArray(["title", "credits"]):
		return "a pilha continua a mesma"
	return ""


func test_credits_licencas() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	ui.open_screen("credits")
	var s := ui.top_screen()
	var list: Control = s.elements["licenses"]
	if int(list.get_meta(&"vn_count", 0)) != 3:
		return "Godot, runtime e o plugin de pesca: %d" % list.get_meta(&"vn_count", 0)
	var text := ""
	for l in list.get_child(0).get_children():
		text += l.text
	if not text.contains("Godot Engine") or not text.contains("Fishing Minigame"):
		return "conteúdo da lista"
	var lbl: RichTextLabel = s.elements["text"]
	if lbl.text != "Roteiro: Seaside Team":
		return "label: %s" % lbl.text
	# Só engine: o aviso do motor aparece mesmo assim, o plugin não.
	var only := VNUIElements.build(s, {"id": "x", "type": "licenses_list", "include": ["fonts"]})
	if int(only.get_meta(&"vn_count")) != 2:
		return "include sem plugins: %d" % only.get_meta(&"vn_count")
	only.free()
	return ""


func test_extras_modo_livre() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	m.state.set_system_value("sys.endings.festival_ending", true)
	ui.refresh()
	_click(ui, "btn_extras")
	if ui.screen_stack() != PackedStringArray(["title", "extras"]):
		return "Minijogos abre extras: %s" % ui.screen_stack()
	var records: Control = ui.top_screen().elements["records"]
	var first: RichTextLabel = records.get_child(0).get_child(0)
	if first.text != "Nenhum recorde ainda.":
		return "empty_text: %s" % first.text
	var e := _click(ui, "btn_fishing_hard")
	if not e.is_empty():
		return e
	var host: FakePluginHost = m.plugins
	var starts := host.calls.filter(func(c): return c.method == &"start_activity")
	if starts.size() != 1 or starts[0].args != [&"fishing.fishing_game", {"difficulty": "hard"}, VNPluginHost.MODE_FREE_PLAY]:
		return "play_activity: %s" % [starts]
	m.saves.submit_record(&"fishing", &"high_scores", 1234.5)
	host.finish_activity(VNPluginHost.STATUS_COMPLETED, &"won")
	if m.variables.read("sys.ui.last_activity_outcome") != "won":
		return "last_activity_outcome: %s" % m.variables.read("sys.ui.last_activity_outcome")
	if ui.screen_stack() != PackedStringArray(["title", "extras"]):
		return "volta à tela que abriu"
	ui.close_screen()
	ui.open_screen("extras")
	records = ui.top_screen().elements["records"]
	if int(records.get_meta(&"vn_count")) != 1 or not records.get_child(0).get_child(0).text.contains("1.234,5"):
		return "recorde com número formatado: %s" % records.get_child(0).get_child(0).text
	# vn_menu no modo livre pergunta se sai do minijogo.
	_click(ui, "btn_fishing")
	ui.close_all()
	_press(ui, &"vn_menu")
	if ui.open_dialogs().size() != 1:
		return "vn_menu no modo livre pede confirmação"
	ui.answer_dialog(true)
	if m.variables.read("sys.ui.last_activity_outcome") != "cancelled":
		return "sair do minijogo: %s" % m.variables.read("sys.ui.last_activity_outcome")
	return ""


func test_extras_recusado_no_jogo() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_game(m)
	ui.open_screen("extras")
	var res := ui.run_actions([{"do": "play_activity", "activity": "fishing.fishing_game"}], {"screen": "extras"})
	if res.ok or (m.plugins as FakePluginHost).count_calls(&"start_activity") != 0:
		return "play_activity com partida em andamento é recusada"
	return ""


func test_acoes_if_else() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	var cond := [{"variable": "global.flag", "operator": "equals", "value": true}]
	ui.run_actions([
		{"do": "open_screen", "screen": "credits", "if": cond, "else": [{"do": "open_screen", "screen": "settings"}]},
	])
	if ui.screen_stack()[-1] != "settings":
		return "else com condição falsa"
	m.variables.store("global.flag", true)
	ui.run_actions([
		{"do": "open_screen", "screen": "credits", "if": cond, "else": [{"do": "open_screen", "screen": "settings"}]},
	])
	if ui.screen_stack()[-1] != "credits":
		return "if verdadeiro"
	# Ação recusada interrompe a lista.
	var res := ui.run_actions([{"do": "emit", "event": "story.x"}, {"do": "close_screen"}])
	if res.ok or ui.screen_stack()[-1] != "credits":
		return "emit no título é recusado e a lista para"
	return ""


func test_acoes_confirm_then_else() -> String:
	var custom := {"id": "probe", "kind": "custom", "elements": [
		{"id": "btn", "type": "button", "text": "x", "actions": [
			{"do": "confirm", "text": "Primeira?", "then": [{"do": "set_setting", "setting": "vsync", "value": false}],
			 "else": [{"do": "confirm", "text": "Segunda?", "then": [{"do": "set_setting", "setting": "skip_unread", "value": true}]}]},
			{"do": "set_setting", "setting": "reduce_motion", "value": true},
		]},
	]}
	var r := _setup({"probe": custom})
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	ui.set_locale_strings({"ui/probe/btn/confirm2": "Segunda traduzida?"}, "pt-BR")
	ui.open_screen("probe")
	_click(ui, "btn")
	if ui.get_setting(&"reduce_motion") != false:
		return "a lista espera a resposta da confirmação"
	if ui.open_dialogs()[0].label.text != "Primeira?":
		return "texto 1"
	ui.answer_dialog(false)
	if ui.open_dialogs().size() != 1 or ui.open_dialogs()[0].label.text != "Segunda traduzida?":
		return "else abre a segunda confirmação com o caminho confirm2"
	ui.answer_dialog(true)
	if ui.get_setting(&"skip_unread") != true or ui.get_setting(&"vsync") != true:
		return "then da segunda"
	if ui.get_setting(&"reduce_motion") != true:
		return "depois da confirmação a lista segue"
	return ""


func test_acoes_effects_titulo() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	var res := ui.run_actions([{"do": "effects", "effects": [{"op": "set", "variable": "global.player_money", "value": 5}]}])
	if res.ok or res.error != VNErrors.PERMISSION_DENIED or m.variables.read("global.player_money") != 30:
		return "no título, só variáveis profile: %s" % res.error
	res = ui.run_actions([{"do": "effects", "effects": [{"op": "add", "variable": "global.endings_seen", "value": 1}]}])
	if not res.ok or m.variables.read("global.endings_seen") != 1:
		return "profile no título"
	var call: Dictionary = (m.state as FakeStateManager).calls.filter(func(c): return c.method == &"apply_effects")[-1]
	if call.args[2] != VNStateManager.CALLER_UI:
		return "effects pelo State Manager com CALLER_UI"
	return ""


func test_acoes_effects_e_emit_no_jogo() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_game(m)
	var res := ui.run_actions([
		{"do": "effects", "effects": [{"op": "add", "variable": "global.player_money", "value": 100}]},
		{"do": "emit", "event": "story.map_opened", "payload": {"money": {"var": "global.player_money"}, "x": 2}},
	])
	if not res.ok or m.variables.read("global.player_money") != 130:
		return "effects no jogo: %s" % res.message
	var em: Dictionary = (m.events as FakeEventBus).calls.filter(func(c): return c.method == &"emit")[-1]
	if em.args != ["story.map_opened", {"money": 130, "x": 2}, VNEventBus.SOURCE_STORY]:
		return "emit: %s" % [em.args]
	if ui.run_actions([{"do": "emit", "event": "sys.game_saved"}]).error != VNErrors.PERMISSION_DENIED:
		return "emit só story.*"
	(m.state as FakeStateManager).fail_with = VNErrors.CONSTRAINT_VIOLATION
	if ui.run_actions([{"do": "effects", "effects": [{"op": "set", "variable": "global.flag", "value": true}]}]).ok:
		return "falha do State Manager volta como falha"
	return ""


func test_acoes_elementos() -> String:
	var custom := {"id": "probe", "kind": "custom", "modal": false, "elements": [
		{"id": "lbl", "type": "label", "text": "oi", "position": [0.1, 0.1], "pivot": [0, 0]},
		{"id": "img", "type": "image", "asset": "ui/logo", "position": [0.5, 0.5], "size": [200, 100]},
		{"id": "edge", "type": "button", "text": "E", "position": [0.96, 0.94], "anchor": "edge", "size": [80, 40]},
		{"id": "grid", "type": "container", "layout": "grid", "columns": 2, "children": [
			{"id": "a", "type": "button", "text": "A"}, {"id": "b", "type": "button", "text": "B", "focus": {"down": "a"}}]},
		{"id": "slots", "type": "slot_grid", "mode": "load", "columns": 2, "rows": 1},
		{"id": "gal", "type": "gallery_grid", "source": "endings"},
		{"id": "log", "type": "backlog_list"},
		{"id": "hs", "type": "hotspot", "area": {"polygon": [[0.1, 0.5], [0.2, 0.5], [0.15, 0.6]]}, "actions": []},
	]}
	var r := _setup({"probe": custom})
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	ui.open_screen("credits")
	ui.open_screen("probe")
	if ui.screen_stack() != PackedStringArray(["title", "probe"]):
		return "tela custom com modal: false substitui a do topo: %s" % ui.screen_stack()
	await process_frame
	var s := ui.top_screen()
	ui.run_actions([{"do": "hide", "target": "lbl"}], {"screen": "probe"})
	if s.elements["lbl"].visible:
		return "hide"
	ui.run_actions([{"do": "toggle_visible", "target": "lbl"}], {"screen": "probe"})
	if not s.elements["lbl"].visible:
		return "toggle_visible"
	if not ui.run_actions([{"do": "play_animation", "target": "img", "animation": {"kind": "pulse", "duration": 0.1}}], {"screen": "probe"}).ok:
		return "play_animation em elemento"
	var view := s.view_size()
	var origin := (view - Vector2(1920, 1080)) / 2.0
	var lbl: Control = s.elements["lbl"]
	if not lbl.position.is_equal_approx(origin + Vector2(192, 108)):
		return "posição com pivot [0,0]: %s" % lbl.position
	var img: Control = s.elements["img"]
	if not img.position.is_equal_approx(origin + Vector2(960 - 100, 540 - 50)):
		return "posição com size e pivot padrão: %s" % img.position
	var edge: Control = s.elements["edge"]
	var want := Vector2(view.x - 0.04 * 1920 - 40, view.y - 0.06 * 1080 - 20)
	if not edge.position.is_equal_approx(want):
		return "anchor edge: %s, esperado %s" % [edge.position, want]
	var slots: GridContainer = s.elements["slots"]
	if slots.get_child_count() != 2 or not (slots.get_child(0) as Button).disabled:
		return "slot_grid: slot vazio no modo load fica desabilitado"
	var gal: GridContainer = s.elements["gal"]
	if gal.get_child_count() != 1 or not (gal.get_child(0) as Button).disabled or gal.get_child(0).text != "???":
		return "gallery_grid: final não visto aparece bloqueado"
	var hs: VNUIHotspot = s.elements["hs"]
	if not hs.has_area() or not hs._has_point(Vector2(0.05 * 1920, 0.05 * 1080)):
		return "hotspot com polígono: %s %s" % [hs.position, hs.size]
	# Foco: vizinho declarado em focus.
	s.elements["b"].grab_focus()
	_press(ui, &"vn_down")
	if _focused() != "a":
		return "focus.down: %s" % _focused()
	return ""


func test_pausa_pausa_o_engine() -> String:
	var r := _setup()
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_game(m)
	var eng: FakeNarrativeEngine = m.engine
	if not ui.is_hud_visible() or eng.is_paused():
		return "no jogo, a hud aparece e o engine roda"
	if not _press(ui, &"vn_menu") or ui.screen_stack() != PackedStringArray(["pause"]):
		return "vn_menu abre a pausa: %s" % ui.screen_stack()
	if not eng.is_paused():
		return "a pausa pausa o Narrative Engine"
	await process_frame
	if _focused() != "btn_resume":
		return "foco na pausa: %s" % _focused()
	if _vis(ui, "btn_skip_activity"):
		return "Pular minijogo só com atividade pulável"
	_click(ui, "btn_settings")
	_press(ui, &"vn_cancel")
	_press(ui, &"vn_cancel")
	if not ui.screen_stack().is_empty() or eng.is_paused():
		return "fechar tudo despausa: %s" % ui.screen_stack()
	ui.open_screen("pause")
	_click(ui, "btn_title")
	if ui.open_dialogs().is_empty():
		return "voltar ao título pede confirmação"
	ui.answer_dialog(true)
	if eng.phase() != VNPhase.TITLE or ui.screen_stack() != PackedStringArray(["title"]) or ui.is_hud_visible():
		return "volta ao título: %s %s" % [eng.phase(), ui.screen_stack()]
	return ""


func test_hud_durante_atividade() -> String:
	var hud := {"id": "hud", "kind": "hud", "elements": [
		{"id": "btn_menu", "type": "button", "text": "M", "during_activity": true, "shortcut": "vn_quick_save", "actions": [{"do": "open_screen", "screen": "pause"}]},
		{"id": "btn_skip", "type": "button", "text": "S", "actions": [{"do": "toggle_skip"}]},
	]}
	var r := _setup({"hud": hud})
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_game(m)
	var host: FakePluginHost = m.plugins
	host.start_activity(&"fishing.fishing_game", {})
	host.activity["input_capture"] = true
	host.activity["skippable"] = true
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.ACTIVITY)
	var h := ui.get_screen("hud")
	var skip: Button = VNUIElements.focus_control(h.elements["btn_skip"])
	var menu: Button = VNUIElements.focus_control(h.elements["btn_menu"])
	if skip.mouse_filter != Control.MOUSE_FILTER_IGNORE or menu.mouse_filter != Control.MOUSE_FILTER_STOP:
		return "só during_activity recebe input"
	if not _press(ui, &"vn_quick_save") or ui.screen_stack() != PackedStringArray(["pause"]):
		return "atalho do botão da hud: %s" % ui.screen_stack()
	if not _vis(ui, "btn_skip_activity"):
		return "Pular minijogo com atividade pulável"
	_click(ui, "btn_skip_activity")
	if host.calls.filter(func(c): return c.method == &"cancel_activity" and c.args[0] == VNPluginHost.STATUS_SKIPPED).size() != 1:
		return "skip_activity"
	if not ui.screen_stack().is_empty():
		return "pular fecha a pausa"
	return ""


func test_textos_interpolacao() -> String:
	var t := VNUIText.new()
	t.locale = "pt-BR"
	t.reader = func(id): return {"a": 1234567.5, "b": 3, "c": "[x]", "d": 1.005}.get(id)
	var got := t.interpolate("{a}|{b}|{c}|{{lit}}|{d}")
	if got != "1.234.567,5|3|[[x]]|{lit}|1,01":
		return "interpolação: %s" % got
	t.locale = "es"
	if t.interpolate("{b}") != "3" or t.format_number(1234) != "1234" or t.format_number(12345) != "12.345":
		return "es agrupa só a partir de 5 dígitos"
	if VNUIText.to_bbcode("[b]oi[/b] [pause=0.5][[x]]") != "[b]oi[/b] [lb]x[rb]":
		return "marcação: %s" % VNUIText.to_bbcode("[b]oi[/b] [pause=0.5][[x]]")
	if VNUIText.strip_markup("[color=#ff0000]Sim[/color] [[1]]") != "Sim [1]":
		return "strip_markup"
	return ""


func test_reset_profile() -> String:
	var custom := {"id": "probe", "kind": "custom", "elements": [
		{"id": "btn", "type": "button", "text": "x", "actions": [{"do": "reset_profile"}]}]}
	var r := _setup({"probe": custom})
	var m: VNModules = r[0]
	var ui: VNRuntimeUIManager = r[1]
	_to_title(m)
	ui.open_screen("probe")
	_click(ui, "btn")
	if ui.open_dialogs().is_empty() or not ui.open_dialogs()[0].label.text.begins_with("Apagar"):
		return "reset_profile confirma com runtime/confirm/reset_profile"
	ui.answer_dialog(true)
	if (m.saves as FakeSaveManager).count_calls(&"reset_profile") != 1:
		return "Save Manager não apagou o perfil"
	if not (m.events as FakeEventBus).calls.any(func(c): return c.args[0] == "sys.profile_reset"):
		return "sys.profile_reset"
	_to_game(m)
	if ui.run_actions([{"do": "reset_profile"}]).ok:
		return "reset_profile no jogo é recusado"
	return ""
