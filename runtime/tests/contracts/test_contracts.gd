extends SceneTree
## Teste de fumaça dos contratos do runtime (tarefa M0-07).
##
##   godot --headless --path runtime --script res://tests/contracts/test_contracts.gd
##
## Confere que cada módulo do RT §1 tem contrato e dublê, que o dublê cumpre o
## contrato, que as constantes batem com as specs e que os dublês funcionam
## juntos no caminho básico (escrita, eventos, seleção, save e load, palco,
## telas, atividade). Sai com 1 se algo falhar.

var _passed := 0
var _failed := 0


func _init() -> void:
	for t in [
		"registro_completo", "dubles_cumprem_contratos", "camadas_rt_1_1",
		"fases_iguais_ao_protocolo", "codigos_de_erro_rt_6_2", "estado_escrita_e_transacao",
		"eventos_fila_fifo", "scheduler_selecao", "storage_caminhos", "save_e_load",
		"stage_camadas", "ui_acoes", "atividade_de_plugin", "assets_modo_stream", "audio_canais",
	]:
		_run(t)
	print("%d/%d testes de contrato passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	var err: String = call("test_" + test)
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Estrutura --------------------------------------------------------------

const CONTRACTS := {
	&"engine": ["res://vn_runtime/narrative_engine/vn_narrative_engine.gd", "res://tests/fakes/narrative_engine/fake_narrative_engine.gd"],
	&"scheduler": ["res://vn_runtime/scheduler/vn_scene_scheduler.gd", "res://tests/fakes/scheduler/fake_scene_scheduler.gd"],
	&"conditions": ["res://vn_runtime/condition_evaluator/vn_condition_evaluator.gd", "res://tests/fakes/condition_evaluator/fake_condition_evaluator.gd"],
	&"state": ["res://vn_runtime/state_manager/vn_state_manager.gd", "res://tests/fakes/state_manager/fake_state_manager.gd"],
	&"variables": ["res://vn_runtime/variable_manager/vn_variable_manager.gd", "res://tests/fakes/variable_manager/fake_variable_manager.gd"],
	&"events": ["res://vn_runtime/event_bus/vn_event_bus.gd", "res://tests/fakes/event_bus/fake_event_bus.gd"],
	&"plugins": ["res://vn_runtime/plugin_host/vn_plugin_host.gd", "res://tests/fakes/plugin_host/fake_plugin_host.gd"],
	&"saves": ["res://vn_runtime/save_manager/vn_save_manager.gd", "res://tests/fakes/save_manager/fake_save_manager.gd"],
	&"storage": ["res://vn_runtime/storage/vn_storage.gd", "res://tests/fakes/storage/fake_storage.gd"],
	&"stage": ["res://vn_runtime/stage/vn_stage.gd", "res://tests/fakes/stage/fake_stage.gd"],
	&"audio": ["res://vn_runtime/audio/vn_audio_manager.gd", "res://tests/fakes/audio/fake_audio_manager.gd"],
	&"ui": ["res://vn_runtime/ui_manager/vn_ui_manager.gd", "res://tests/fakes/ui_manager/fake_ui_manager.gd"],
	&"assets": ["res://vn_runtime/assets/vn_assets.gd", "res://tests/fakes/assets/fake_assets.gd"],
}


func test_registro_completo() -> String:
	var m := VNFakeModules.create()
	if not m.missing().is_empty():
		return "faltam módulos: %s" % m.missing()
	if CONTRACTS.size() != VNModules.MODULE_IDS.size():
		return "CONTRACTS e VNModules.MODULE_IDS diferem"
	for id in VNModules.MODULE_IDS:
		var mod := m.get_module(id)
		if mod.module_id() != id:
			return "%s.module_id() = %s" % [id, mod.module_id()]
		if mod.modules() != m:
			return "%s não está ligado ao registro" % id
	return ""


func test_dubles_cumprem_contratos() -> String:
	for id in CONTRACTS:
		var base: GDScript = load(CONTRACTS[id][0])
		var fake: GDScript = load(CONTRACTS[id][1])
		if base == null or fake == null:
			return "%s: script não carregou" % id
		if not base.is_abstract():
			return "%s: o contrato deveria ser @abstract" % id
		if fake.is_abstract() or fake.get_base_script() != base:
			return "%s: o dublê deve estender o contrato diretamente e ser concreto" % id
		var inst = fake.new()
		if not (inst is VNModule):
			return "%s: o dublê não é um VNModule" % id
		# Todo método do contrato existe no dublê com o mesmo número de argumentos.
		var fake_methods := {}
		for meth in fake.get_script_method_list():
			fake_methods[meth.name] = meth.args.size()
		for meth in base.get_script_method_list():
			if not meth.name.begins_with("_") and fake_methods.get(meth.name, -1) != meth.args.size():
				return "%s: %s ausente ou com outra assinatura no dublê" % [id, meth.name]
		if base.get_script_signal_list().size() > fake.get_script_signal_list().size():
			return "%s: sinais do contrato faltando no dublê" % id
	return ""


func test_camadas_rt_1_1() -> String:
	var expected := [0, 10, 15, 20, 30, 40, 50, 60, 100]
	if VNLayers.ALL != expected:
		return "VNLayers.ALL = %s" % [VNLayers.ALL]
	if VNLayers.THUMBNAIL_MAX != VNLayers.PLUGIN_OVERLAYS:
		return "a miniatura vai até a camada 20 (RT §8.5)"
	return ""


func test_fases_iguais_ao_protocolo() -> String:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/specs/schemas/preview-protocol.schema.json")
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return "schema do protocolo não encontrado em %s" % path
	var enum_list: Variant = _find_key(JSON.parse_string(text), "phase")
	if not enum_list is Dictionary or not enum_list.has("enum"):
		return "phase sem enum no schema"
	var from_schema: Array = enum_list["enum"]
	var ours: Array = VNPhase.ALL.map(func(p): return String(p))
	if from_schema != ours:
		return "VNPhase.ALL %s ≠ schema %s" % [ours, from_schema]
	return ""


func test_codigos_de_erro_rt_6_2() -> String:
	var expected := ["WRONG_THREAD", "INVALID_STATE", "VARIABLE_NOT_FOUND", "READ_ONLY", "SCOPE_INACTIVE",
		"PERMISSION_DENIED", "TYPE_MISMATCH", "OUT_OF_RANGE", "CONSTRAINT_VIOLATION", "CONFLICT"]
	if VNErrors.WRITE_CHECK_ORDER.map(func(e): return String(e)) != expected:
		return "ordem das verificações difere do RT §6.2"
	if VNErrors.is_content_error(VNErrors.CONSTRAINT_VIOLATION):
		return "CONSTRAINT_VIOLATION não é erro de conteúdo (DM §6.2)"
	return ""


# --- Comportamento dos dublês juntos ----------------------------------------

func test_estado_escrita_e_transacao() -> String:
	var m := VNFakeModules.create()
	var vars: FakeVariableManager = m.variables
	vars.define("global.money", &"integer", 30)
	vars.define("sys.selection_count", &"integer", 0)
	var emitted := []
	m.state.state_changed.connect(func(ch): emitted.append(ch))
	var r := m.state.write(&"add", "global.money", 100)
	if not r.ok or vars.read("global.money") != 130 or r.changes != [{"variable": "global.money", "old": 30, "new": 130}]:
		return "add falhou: %s %s" % [r.error, r.changes]
	if emitted.size() != 1:
		return "state_changed deve sair uma vez por operação"
	r = m.state.write(&"set", "sys.selection_count", 3)
	if r.ok or r.error != VNErrors.READ_ONLY:
		return "sys.* deveria ser READ_ONLY"
	var tx := m.state.begin_transaction(VNStateManager.plugin_caller(&"fishing"))
	r = tx.add("global.money", 1).expect("global.money", 999).commit()
	if r.ok or r.error != VNErrors.CONFLICT or vars.read("global.money") != 130:
		return "expect deveria dar CONFLICT sem aplicar nada"
	if tx.commit().ok:
		return "commit duplo deveria falhar"
	if VNStateManager.caller_plugin(tx.caller) != &"fishing":
		return "caller_plugin errado"
	r = m.state.apply_effects([{"op": "subtract", "variable": "global.money", "value": {"var": "global.money"}}])
	if not r.ok or vars.read("global.money") != 0:
		return "apply_effects com {var} falhou"
	return ""


func test_eventos_fila_fifo() -> String:
	var m := VNFakeModules.create()
	var got := []
	m.events.on("story.*", func(n, _p, s): got.append([n, s]))
	m.events.emit("story.a", {}, VNEventBus.SOURCE_STORY)
	m.events.emit("sys.scene_started", {"scene": "x", "chapter": "c"}, VNEventBus.SOURCE_SYS)
	m.events.emit("story.b")
	if not got.is_empty():
		return "emit não pode entregar na mesma pilha (RT §7.2)"
	if m.events.drain() != 3 or got != [["story.a", "story"], ["story.b", "story"]]:
		return "drain fora de ordem: %s" % [got]
	if m.scheduler.events_since_selection() != PackedStringArray(["story.a", "story.b"]):
		return "events_since_selection não pode ter sys.*: %s" % m.scheduler.events_since_selection()
	if not VNEventBus.SYS_EVENTS.has("sys.content_filter_changed") or VNEventBus.SYS_EVENTS.size() != 13:
		return "tabela sys.* incompleta (RT §7.1)"
	return ""


func test_scheduler_selecao() -> String:
	var m := VNFakeModules.create()
	var sched: FakeSceneScheduler = m.scheduler
	sched.decisions = [{"action": VNSceneScheduler.ACTION_START_SCENE, "chosen": "s1", "reason": "priority"}]
	var seen := []
	sched.evaluated.connect(func(ev): seen.append(ev))
	var ev := sched.select()
	if ev.action != VNSceneScheduler.ACTION_START_SCENE or sched.selection_count() != 1 or seen.size() != 1:
		return "select não registrou a seleção"
	if sched.select().action != VNSceneScheduler.ACTION_END_GAME:
		return "sem decisões o dublê deve devolver end_game"
	sched.complete_scene("s1")
	if sched.get_history().scenes.s1.plays != 1:
		return "complete_scene não contou plays"
	return ""


func test_storage_caminhos() -> String:
	for bad in ["", "/abs", "../x", "a/../b", "C:/x", "a\\b", "a//b"]:
		if VNStorage.is_valid_path(bad):
			return "caminho inválido aceito: %s" % bad
	var s := FakeStorage.new()
	if s.write_json("saves/slot_1.json", {"a": 1}) != OK or s.read_json("saves/slot_1.json").get("a") != 1.0:
		return "write/read json"
	if s.write_bytes("../fora", PackedByteArray()) == OK:
		return "deveria recusar caminho inválido"
	if s.list("saves") != PackedStringArray(["saves/slot_1.json"]):
		return "list: %s" % s.list("saves")
	return ""


func test_save_e_load() -> String:
	var m := VNFakeModules.create()
	var vars: FakeVariableManager = m.variables
	vars.define("global.money", &"integer", 0)
	m.state.write(&"set", "global.money", 42)
	var eng: FakeNarrativeEngine = m.engine
	eng.chapter = "ch1"
	eng.set_phase(VNPhase.SCENE_RUNNING)
	eng.goto_node("s1", "n3")
	m.stage.show_character({"character": "alice", "expression": "smile", "position": "center"})
	m.audio.run_audio_node({"action": "play", "channel": "music", "asset": "bgm"})
	var slot := VNSaveManager.manual_slot(1)
	if not m.saves.save(slot).ok:
		return "save recusado"
	var data: Dictionary = m.storage.read_json(VNSaveManager.slot_path(slot))
	if data.state.variables.keys() != ["global.money"] or data.state.variables["global.money"] != 42.0 or data.state.scene.node != "n3" or not data.state.scene.stage.audio.has("music"):
		return "save sem as partes dos módulos: %s" % data.state
	m.state.write(&"set", "global.money", 0)
	eng.return_to_title()
	if not m.saves.load_slot(slot).ok or vars.read("global.money") != 42 or eng.current_node() != "n3":
		return "load não restaurou"
	if m.saves.latest_slot() != slot or not m.saves.has_save():
		return "latest_slot/has_save"
	m.saves.mark_text_seen("scene/x/line/1")
	if not m.saves.is_text_seen("scene/x/line/1"):
		return "seen_text"
	return ""


func test_stage_camadas() -> String:
	var m := VNFakeModules.create()
	var root := Node.new()
	m.attach_all(root)
	for layer in [VNLayers.BACKGROUND, VNLayers.CHARACTERS, VNLayers.TEXTBOX]:
		var cl := m.stage.get_layer(layer)
		if cl == null or cl.layer != layer:
			m.detach_all()
			root.free()
			return "camada %d ausente" % layer
	var picked := []
	m.stage.option_selected.connect(func(o): picked.append(o))
	(m.stage as FakeStage).select_option("opt_a")
	m.detach_all()
	root.free()
	if picked != ["opt_a"]:
		return "option_selected"
	return ""


func test_ui_acoes() -> String:
	var m := VNFakeModules.create()
	(m.variables as FakeVariableManager).define("global.flag", &"boolean", false)
	var r := m.ui.run_actions([
		{"do": "effects", "effects": [{"op": "toggle", "variable": "global.flag"}]},
		{"do": "open_screen", "screen": "settings"},
	])
	if not r.ok or m.variables.read("global.flag") != true:
		return "effects da tela deve passar pelo State Manager"
	if (m.state as FakeStateManager).count_calls(&"apply_effects") != 1:
		return "a ação effects não chamou o State Manager"
	if m.ui.screen_stack() != PackedStringArray(["settings"]):
		return "pilha de telas"
	m.ui.set_setting(&"text_speed", 60)
	if m.storage.read_json("settings.json").get("text_speed") != 60.0:
		return "settings.json deve ir pelo VNStorage"
	return ""


func test_atividade_de_plugin() -> String:
	var m := VNFakeModules.create()
	var host: FakePluginHost = m.plugins
	host.load_plugins({"plugins": {"fishing": {}}})
	var ended := []
	host.activity_ended.connect(func(s, o, p): ended.append([s, o, p]))
	if not host.start_activity(&"fishing.fishing_game", {"duration_seconds": 60}).ok:
		return "start_activity recusado"
	if host.start_activity(&"fishing.fishing_game", {}).ok:
		return "só uma atividade por vez"
	host.finish_activity(VNPluginHost.STATUS_COMPLETED, &"won", {"score": 3})
	if ended != [[VNPluginHost.STATUS_COMPLETED, &"won", {"score": 3}]]:
		return "activity_ended: %s" % [ended]
	for i in VNPluginHost.FAULT_THRESHOLD:
		host.report_error(&"fishing", "erro")
	if not host.is_faulted(&"fishing") or host.start_activity(&"fishing.fishing_game", {}).ok:
		return "plugin faulted deveria recusar atividades"
	return ""


func test_assets_modo_stream() -> String:
	var a := FakeAssets.new()
	a.load_bundle({"assets": {"bg/beach": "res://vn_content/assets/bg/beach.png", "bg/safe": "res://vn_content/assets/bg/safe.png"}})
	a.censored = {"bg/beach": {"replace_with": "bg/safe"}, "cg/x": {"hide": true}}
	if a.resolve_id("bg/beach") != "bg/beach":
		return "sem modo stream o id não muda"
	a.set_content_filter(true)
	if a.resolve_id("bg/beach") != "bg/safe" or a.resolve_id("cg/x") != "":
		return "replace_with/hide"
	a.set_assets_base("vnpreview://localhost/project/assets/")
	if a.resolve_path("bg/beach") != "vnpreview://localhost/project/assets/bg/beach.png":
		return "assets_base: %s" % a.resolve_path("bg/beach")
	return ""


func test_audio_canais() -> String:
	var au := FakeAudioManager.new()
	if VNAudioManager.CHANNELS != [&"music", &"ambient", &"sfx", &"voice"]:
		return "canais diferem de scene.schema.json"
	au.run_audio_node({"action": "play", "channel": "ambient", "asset": "waves", "loop": true})
	var snap := au.snapshot()
	au.stop_all()
	au.restore(snap)
	if au.snapshot() != snap:
		return "snapshot/restore"
	return ""


static func _find_key(o: Variant, key: String) -> Variant:
	if o is Dictionary:
		if o.has(key):
			return o[key]
		for v in o.values():
			var r: Variant = _find_key(v, key)
			if r != null:
				return r
	elif o is Array:
		for v in o:
			var r: Variant = _find_key(v, key)
			if r != null:
				return r
	return null
