extends SceneTree
## Testes do laço de nós do Narrative Engine (tarefa M1-11; RT §3.1–§3.4, §5.1–§5.4; DM §8.2).
##
##   godot --headless --path runtime --script res://tests/narrative_engine/test_narrative_engine.gd
##
## Usa o [VNRuntimeNarrativeEngine] real com os dublês dos outros módulos ([code]tests/fakes/[/code]) e
## um avaliador de condições que entende as condições simples do DM §5.1. Os casos [code]flow.json[/code]
## reais ficam para o M1-12. Sai com 1 se algo falhar.

var _passed := 0
var _failed := 0
var _errors: Array[String] = []


## Avaliador com as condições simples { variable, operator, value } e o [code]{"result": campo}[/code] do on_result.
class SimpleConditions extends FakeConditionEvaluator:
	func evaluate_conditions(conditions: Variant, bindings: Dictionary = {}) -> VNEvalResult:
		_rec(&"evaluate_conditions", [conditions, bindings])
		var list: Array = conditions if conditions is Array else [conditions]
		for c in list:
			var id := String(c.get("variable", ""))
			if not modules().variables.has(id):
				return VNEvalResult.failure(VNErrors.VARIABLE_NOT_FOUND, id)
			var v: Variant = modules().variables.read(id)
			var want: Variant = c.get("value")
			var ok := false
			match String(c.get("operator", "equals")):
				"equals": ok = v == want
				"greater_than": ok = v > want
				"greater_than_or_equal": ok = v >= want
			if not ok:
				return VNEvalResult.of(false, &"boolean")
		return VNEvalResult.of(true, &"boolean")

	func evaluate_expression(expr: Variant, bindings: Dictionary = {}, target_type: StringName = &"", allow_random: bool = false) -> VNEvalResult:
		if expr is Dictionary and expr.has("result"):
			var payload: Dictionary = bindings.get("result", {})
			return _typed(payload.get(expr.result, expr.get("default", 0)))
		return super.evaluate_expression(expr, bindings, target_type, allow_random)


func _init() -> void:
	for t in [
		"cumpre_o_contrato", "linhas_interpolacao_e_fim", "fim_do_grafo_sem_end", "backlog_e_seen_text",
		"escolha_visivel_habilitada_record", "escolha_recusas", "escolha_sem_opcao_visivel",
		"efeito_rejeitado_vai_para_on_fail", "branch_e_jump", "emit_ordem_dos_eventos", "laco_instantaneo",
		"plugin_resultado_e_outcome", "plugin_pulado_sem_efeitos", "plugin_falha_e_ausente",
		"plugin_autosave_e_fase", "then_end_chapter_e_proximo", "then_end_game_com_final", "then_pedido_de_cena",
		"novo_jogo_na_ordem", "entry_scene", "selecao_exit_chapter_e_end_game", "interact_once_e_exit",
		"modo_stream", "snapshot_e_can_save", "retomar_do_save", "retomar_no_no_inexistente",
		"voltar_ao_titulo_na_atividade", "pausa_e_espera",
	]:
		_run(t)
	print("%d/%d testes do Narrative Engine passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	_errors.clear()
	var err: String = call("test_" + test)
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Montagem -----------------------------------------------------------------------------------

## Registro com o engine real; [param scenes] (id → nós) ficam no capítulo "ch1".
func _setup(scenes: Dictionary, extra_vars: Dictionary = {}, chapter: Dictionary = {}) -> VNModules:
	var m := VNFakeModules.create()
	m.engine = VNRuntimeNarrativeEngine.new()
	m.conditions = SimpleConditions.new()
	m.bind_all()
	var bundle := VNCaseModules.empty_bundle()
	bundle.project["start_chapter"] = "ch1"
	bundle.project["endings"] = [{"id": "good"}]
	var ch := {"id": "ch1"}
	ch.merge(chapter, true)
	VNCaseModules.ensure_chapter(bundle, ch)
	for sid in scenes:
		VNCaseModules.ensure_scene(bundle, {"id": sid, "chapter": "ch1", "nodes": scenes[sid]})
	m.load_bundle(bundle)
	m.variables.define("global.money", &"integer", 30)
	m.variables.define("global.score", &"integer", 0)
	m.variables.define("global.won", &"boolean", false)
	m.variables.define("global.mood", &"string", "calm")
	for id in extra_vars:
		m.variables.define(id, &"integer", extra_vars[id])
	m.plugins.plugins = PackedStringArray(["fishing"])
	m.engine.content_error.connect(func(code, _msg, _ctx): _errors.append(String(code)))
	return m


## Começa o jogo na cena [param scene]: capítulo ch1 sem entry_scene e o Scheduler escolhe [param scene].
func _start(m: VNModules, scene := "s1", then_decisions: Array[Dictionary] = []) -> void:
	var d: Array[Dictionary] = [{"action": VNSceneScheduler.ACTION_START_SCENE, "chosen": scene}]
	d.append_array(then_decisions)
	(m.scheduler as FakeSceneScheduler).decisions = d
	m.engine.new_game()


func _names(m: VNModules) -> Array:
	return Array((m.events as FakeEventBus).delivered_names())


func _stage(m: VNModules) -> FakeStage:
	return m.stage as FakeStage


func _line(id: String, text: String) -> Dictionary:
	return {"id": id, "type": "line", "text": text}


func _end(id := "e", then: Variant = "schedule") -> Dictionary:
	return {"id": id, "type": "end", "then": then}


# --- Testes -------------------------------------------------------------------------------------

func test_cumpre_o_contrato() -> String:
	var e := VNRuntimeNarrativeEngine.new()
	if not (e is VNNarrativeEngine) or e.module_id() != &"engine":
		return "não é o módulo engine"
	if e.phase() != VNPhase.BOOT or e.is_paused() or not e.is_write_allowed():
		return "estado inicial errado"
	return ""


func test_linhas_interpolacao_e_fim() -> String:
	var m := _setup({"s1": [
		_line("a", "You have {global.money} coins."),
		{"id": "b", "type": "effects", "effects": [{"op": "add", "variable": "global.money", "value": 20}]},
		_line("c", "Now {global.money}. {{literal}}"), _end()]})
	_start(m)
	if m.engine.phase() != VNPhase.SCENE_RUNNING or m.engine.current_node() != "a":
		return "deveria parar na primeira fala"
	if _stage(m).line.text != "You have 30 coins.":
		return "texto 1: %s" % _stage(m).line.text
	_stage(m).press_advance()
	if _stage(m).line.text != "Now 50. {literal}":
		return "texto 2: %s" % _stage(m).line.text
	_stage(m).press_advance()
	var names := _names(m)
	if names != ["sys.game_started", "sys.chapter_started", "sys.scene_started", "sys.scene_ended", "sys.game_ended"]:
		return "eventos: %s" % [names]
	if m.scheduler.get_history().scenes.s1.plays != 1:
		return "complete_scene não foi chamado"
	if m.engine.phase() != VNPhase.TITLE:
		return "sem próxima seleção deveria voltar ao título, fase %s" % m.engine.phase()
	return ""


func test_fim_do_grafo_sem_end() -> String:
	var m := _setup({"s1": [_line("a", "{global.money}")]})
	_start(m)
	_stage(m).press_advance()
	return "" if "sys.scene_ended" in _names(m) else "cena sem end deveria concluir"


func test_backlog_e_seen_text() -> String:
	var m := _setup({"s1": [_line("a", "Money {global.money}"), _line("b", "two")]})
	_start(m)
	_stage(m).press_advance()
	var snap := m.engine.snapshot()
	if snap.backlog.size() != 2 or snap.backlog[0].path != "s1/a" or snap.backlog[0].vars != {"global.money": 30}:
		return "backlog: %s" % [snap.backlog]
	var seen: Array = (m.saves as FakeSaveManager).profile_data.seen_text
	return "" if seen.size() == 2 else "seen_text: %s" % [seen]


func test_escolha_visivel_habilitada_record() -> String:
	var m := _setup({"s1": [
		{"id": "c", "type": "choice", "record": "global.mood", "options": [
			{"id": "rich", "text": "Rich", "visible_if": [{"variable": "global.money", "operator": "greater_than", "value": 50}]},
			{"id": "happy", "text": "Happy", "value": "happy", "effects": [{"op": "set", "variable": "global.won", "value": true}], "goto": "z"},
			{"id": "locked", "text": "Locked", "enabled_if": [{"variable": "global.won", "operator": "equals", "value": true}]}]},
		_line("skipped", "skipped"), _end("z", "end_chapter")]})
	_start(m)
	var ids := _stage(m).choices.map(func(o): return "%s:%s" % [o.id, o.enabled])
	if ids != ["happy:true", "locked:false"]:
		return "opções mostradas: %s" % [ids]
	_stage(m).select_option("happy")
	if m.variables.read("global.won") != true or m.variables.read("global.mood") != "happy":
		return "efeitos e record não aplicados"
	if m.state.count_calls(&"apply_effects") != 1:
		return "efeitos e record numa transação só"
	var evs := (m.events as FakeEventBus).delivered.filter(func(e): return e.name == "sys.choice_made")
	if evs.size() != 1 or evs[0].payload != {"scene": "s1", "node": "c", "option": "happy", "value": "happy"}:
		return "sys.choice_made: %s" % [evs]
	return "" if "sys.scene_ended" in _names(m) else "goto não seguido"


func test_escolha_recusas() -> String:
	var m := _setup({"s1": [
		{"id": "c", "type": "choice", "options": [
			{"id": "a", "text": "A"}, {"id": "off", "text": "Off", "enabled_if": [{"variable": "global.won", "operator": "equals", "value": true}]}]},
		_end()]})
	if m.engine.choose("a").error != VNErrors.INVALID_STATE:
		return "fora de uma escolha deveria recusar"
	_start(m)
	if m.engine.choose("nope").error != VNErrors.INVALID_STATE:
		return "opção desconhecida"
	if m.engine.choose("off").error != VNErrors.INVALID_STATE:
		return "opção desabilitada"
	if m.engine.current_node() != "c":
		return "recusa não pode avançar"
	return "" if m.engine.choose("a").ok else "opção válida recusada"


func test_escolha_sem_opcao_visivel() -> String:
	var m := _setup({"s1": [
		{"id": "c", "type": "choice", "next": "z", "options": [{"id": "x", "text": "x", "visible_if": [{"variable": "global.won", "operator": "equals", "value": true}]}]},
		_line("never", "never"), _line("z", "Mood: {global.mood}")]})
	_start(m)
	return "" if m.engine.current_node() == "z" and _stage(m).line.text == "Mood: calm" else "deveria seguir next, nó %s" % m.engine.current_node()


func test_efeito_rejeitado_vai_para_on_fail() -> String:
	var m := _setup({"s1": [
		{"id": "f", "type": "effects", "effects": [{"op": "add", "variable": "global.money", "value": 500}], "on_fail": "bad"},
		_line("ok", "ok"), _line("bad", "Too much: {global.money}"), _end()]})
	(m.state as FakeStateManager).fail_with = VNErrors.CONSTRAINT_VIOLATION
	_start(m)
	if m.engine.current_node() != "bad" or not _errors.is_empty():
		return "restrição vai para on_fail sem erro de conteúdo (nó %s, erros %s)" % [m.engine.current_node(), _errors]
	return ""


func test_branch_e_jump() -> String:
	var m := _setup({"s1": [
		{"id": "br", "type": "branch", "cases": [{"conditions": [{"variable": "global.score", "operator": "greater_than_or_equal", "value": 2}], "goto": "done"}]},
		{"id": "add", "type": "effects", "effects": [{"op": "add", "variable": "global.score", "value": 1}]},
		{"id": "j", "type": "jump", "goto": "br"},
		_line("never", "never"), _end("done")]})
	_start(m)
	if m.variables.read("global.score") != 2 or not ("sys.scene_ended" in _names(m)):
		return "score %s" % m.variables.read("global.score")
	return ""


func test_emit_ordem_dos_eventos() -> String:
	var m := _setup({"s1": [
		{"id": "e1", "type": "emit", "event": "story.arrived", "payload": {"who": "alice"}},
		{"id": "c", "type": "choice", "options": [{"id": "go", "text": "Go", "effects": [{"op": "add", "variable": "global.score", "value": 1}]}]},
		{"id": "e2", "type": "emit", "event": "story.left"}, _end()]})
	_start(m)
	var names := _names(m)
	if names != ["sys.game_started", "sys.chapter_started", "sys.scene_started", "story.arrived"]:
		return "antes da escolha: %s" % [names]
	_stage(m).select_option("go")
	names = _names(m).slice(4)
	if names != ["sys.choice_made", "story.left", "sys.scene_ended", "sys.game_ended"]:
		return "depois da escolha: %s" % [names]
	var arrived := (m.events as FakeEventBus).delivered.filter(func(e): return e.name == "story.arrived")
	return "" if arrived[0].payload == {"who": "alice"} and arrived[0].source == "story" else "payload ou origem do emit"


func test_laco_instantaneo() -> String:
	var m := _setup({"s1": [{"id": "j", "type": "jump", "goto": "j"}]})
	_start(m)
	if not _errors.has("INSTANT_LOOP"):
		return "jump circular deveria ser erro de conteúdo"
	return "" if "sys.scene_ended" in _names(m) else "a cena deveria ser encerrada"


func _activity_scene(on_result := {}, extra := {}) -> Array:
	var p := {"id": "p", "type": "plugin", "activity": "fishing.fishing_game", "params": {"difficulty": "easy"}, "on_result": on_result}
	p.merge(extra, true)
	return [p, _line("lost", "lost"), _line("won", "won {global.money} {global.score}"), _end()]


func test_plugin_resultado_e_outcome() -> String:
	var m := _setup({"s1": _activity_scene({
		"effects": [{"op": "set", "variable": "global.won", "value": {"result": "won"}},
			{"op": "add", "variable": "global.money", "value": {"result": "coins", "default": 5}}],
		"outcomes": {"won": "won"}})})
	_start(m)
	if m.engine.phase() != VNPhase.ACTIVITY or m.plugins.current_activity().params != {"difficulty": "easy"}:
		return "deveria estar em ACTIVITY com os params"
	(m.plugins as FakePluginHost).finish_activity(VNPluginHost.STATUS_COMPLETED, &"won", {"won": true})
	if m.variables.read("global.won") != true or m.variables.read("global.money") != 35:
		return "on_result.effects: won=%s money=%s" % [m.variables.read("global.won"), m.variables.read("global.money")]
	var done := (m.events as FakeEventBus).delivered.filter(func(e): return e.name == "sys.activity_completed")
	if done[0].payload != {"activity": "fishing.fishing_game", "outcome": "won", "skipped": false}:
		return "sys.activity_completed: %s" % [done]
	return "" if m.engine.current_node() == "won" and m.engine.phase() == VNPhase.SCENE_RUNNING else "outcome não desviou, nó %s" % m.engine.current_node()


func test_plugin_pulado_sem_efeitos() -> String:
	var m := _setup({"s1": _activity_scene({
		"effects": [{"op": "set", "variable": "global.won", "value": {"result": "won"}}], "outcomes": {"lost": "lost"}})})
	_start(m)
	(m.plugins as FakePluginHost).finish_activity(VNPluginHost.STATUS_SKIPPED, &"lost")
	var done := (m.events as FakeEventBus).delivered.filter(func(e): return e.name == "sys.activity_completed")
	if m.variables.read("global.won") != false or done[0].payload.skipped != true:
		return "no pulo o on_result.effects não se aplica e skipped = true"
	return "" if m.engine.current_node() == "lost" else "desvio por outcome, nó %s" % m.engine.current_node()


func test_plugin_falha_e_ausente() -> String:
	var m := _setup({"s1": _activity_scene({}, {"on_error": "lost"})})
	_start(m)
	(m.plugins as FakePluginHost).finish_activity(VNPluginHost.STATUS_FAILED)
	if m.engine.current_node() != "lost" or not _errors.has("ACTIVITY_FAILED"):
		return "falha deveria seguir on_error com erro de conteúdo"
	var m2 := _setup({"s1": _activity_scene({}, {"on_error": "lost"})})
	m2.plugins.plugins = PackedStringArray()
	_start(m2)
	if m2.engine.current_node() != "lost" or m2.engine.phase() != VNPhase.SCENE_RUNNING:
		return "plugin ausente deveria seguir on_error"
	if (m2.saves as FakeSaveManager).calls.any(func(c): return c.method == &"autosave" and c.args[0] == VNSaveManager.AUTOSAVE_ACTIVITY):
		return "sem plugin não há autosave de atividade"
	return ""


func test_plugin_autosave_e_fase() -> String:
	var m := _setup({"s1": _activity_scene()})
	var saves := m.saves as FakeSaveManager
	_start(m)
	if saves.count_calls(&"autosave") < 2 or saves.calls.filter(func(c): return c.method == &"autosave").any(func(c): return c.args[0] == VNSaveManager.AUTOSAVE_ACTIVITY) == false:
		return "falta o autosave de segurança da atividade"
	return "" if not m.engine.can_save(VNNarrativeEngine.SAVE_MANUAL) else "can_save em ACTIVITY"


func test_then_end_chapter_e_proximo() -> String:
	var m := _setup({"s1": [_end("e", "end_chapter")]})
	(m.scheduler as FakeSceneScheduler).next_chapter_id = ""
	_start(m)
	var names := _names(m)
	if names.slice(3) != ["sys.scene_ended", "sys.chapter_ended", "sys.game_ended"]:
		return "sem próximo capítulo termina o jogo: %s" % [names]
	if not m.scheduler.get_history().chapters.ch1.completed:
		return "capítulo deveria ficar concluído"
	return ""


func test_then_end_game_com_final() -> String:
	var m2 := _setup({"s1": [{"id": "e", "type": "end", "then": "end_game", "ending": "good"}]})
	var phases: Array = []
	m2.engine.phase_changed.connect(func(p, _prev): phases.append(p))
	_start(m2)
	var saves := m2.saves as FakeSaveManager
	if saves.profile_data.endings != ["good"] or saves.count_calls(&"flush_profile") < 1:
		return "final não gravado no perfil na hora"
	var ended := (m2.events as FakeEventBus).delivered.filter(func(e): return e.name == "sys.game_ended")
	if ended[0].payload != {"ending": "good"} or m2.plugins.count_calls(&"notify_game_ended") != 1:
		return "sys.game_ended ou _vn_game_ended"
	if phases.slice(-2) != [VNPhase.GAME_END, VNPhase.TITLE]:
		return "fases: %s" % [phases]
	return ""


func test_then_pedido_de_cena() -> String:
	var m := _setup({"s1": [_end("e", {"scene": "s2"})], "s2": [_line("a", "second")]})
	_start(m, "s1", [{"action": VNSceneScheduler.ACTION_START_SCENE, "chosen": "s2"}])
	var sel := (m.scheduler as FakeSceneScheduler).calls.filter(func(c): return c.method == &"select")
	if sel.size() != 2 or sel[1].args != ["s2"]:
		return "o pedido deveria ir ao Scheduler: %s" % [sel]
	return "" if m.engine.current_scene() == "s2" else "cena atual %s" % m.engine.current_scene()


func test_novo_jogo_na_ordem() -> String:
	var m := _setup({"s1": [_line("a", "x")]})
	_start(m)
	var order := []
	for mod in [m.variables, m.scheduler, m.plugins]:
		order.append_array(mod.calls.map(func(c): return c.method))
	for need in [&"reset_game", &"apply_profile", &"enter_chapter", &"notify_game_started"]:
		if not need in order:
			return "faltou %s" % need
	var names := _names(m)
	if names.slice(0, 3) != ["sys.game_started", "sys.chapter_started", "sys.scene_started"]:
		return "ordem dos eventos: %s" % [names]
	var cs: Variant = (m.events as FakeEventBus).delivered[1].payload
	return "" if cs == {"chapter": "ch1", "entries": 1} else "sys.chapter_started: %s" % [cs]


func test_entry_scene() -> String:
	var m := _setup({"s1": [_line("a", "x")], "s2": [_line("a", "y")]}, {}, {"entry_scene": "s2"})
	_start(m, "s1")
	var sched := m.scheduler as FakeSceneScheduler
	if sched.count_calls(&"start_direct") != 1 or sched.count_calls(&"select") != 0:
		return "entry_scene é direta, sem passar pela seleção"
	return "" if m.engine.current_scene() == "s2" else "cena atual %s" % m.engine.current_scene()


func test_selecao_exit_chapter_e_end_game() -> String:
	var m := _setup({"s1": [_end()]})
	_start(m, "s1", [{"action": VNSceneScheduler.ACTION_EXIT_CHAPTER}])
	if not "sys.chapter_ended" in _names(m):
		return "exit_chapter deveria sair do capítulo"
	var m2 := _setup({"s1": [_end()]})
	_start(m2, "s1", [{"action": VNSceneScheduler.ACTION_END_GAME}])
	var ended := (m2.events as FakeEventBus).delivered.filter(func(e): return e.name == "sys.game_ended")
	return "" if ended.size() == 1 and ended[0].payload == {"ending": null} else "end_game sem final: %s" % [ended]


func test_interact_once_e_exit() -> String:
	var m := _setup({"s1": [
		{"id": "i", "type": "interact", "record": "global.mood", "hotspots": [
			{"id": "h1", "label": "Door", "once": true, "value": "door", "goto": "back"},
			{"id": "h2", "label": "Window"}], "exit": {"label": "Leave", "goto": "out"}},
		_line("never", "never"), {"id": "back", "type": "jump", "goto": "i"}, _end("out")]})
	_start(m)
	if _stage(m).hotspots.size() != 2 or _stage(m).hotspots[0].id != "h1":
		return "hotspots: %s" % [_stage(m).hotspots]
	_stage(m).select_option("h1")   # volta ao interact: h1 (once) some
	if _stage(m).hotspots.size() != 1 or _stage(m).hotspots[0].id != "h2":
		return "hotspot once deveria sumir: %s" % [_stage(m).hotspots]
	if m.variables.read("global.mood") != "door" or m.engine.snapshot().scene.used_hotspots != ["h1"]:
		return "record ou used_hotspots"
	_stage(m).select_option("exit")
	var made := (m.events as FakeEventBus).delivered.filter(func(e): return e.name == "sys.choice_made")
	return "" if made.size() == 1 and "sys.scene_ended" in _names(m) else "a saída não gera sys.choice_made e fecha por goto"


func test_modo_stream() -> String:
	var m := _setup({"s1": [
		{"id": "a", "type": "line", "text": "plain", "censored_text": "soft"},
		{"id": "b", "type": "line", "text": "only off", "censor": "skip"},
		{"id": "c", "type": "line", "text": "only on", "censor": "only"}, _end()]})
	m.engine.content_filter_changed(true)
	_start(m)
	if _stage(m).line.text != "soft":
		return "texto censurado: %s" % _stage(m).line.text
	_stage(m).press_advance()
	if m.engine.current_node() != "c":
		return "skip com o modo ligado pula o nó, está em %s" % m.engine.current_node()
	m.engine.content_filter_changed(false)
	if m.engine.snapshot().backlog.size() != 2:
		return "mudar o modo não duplica o backlog"
	return ""


func test_snapshot_e_can_save() -> String:
	var m := _setup({"s1": [_line("a", "x"), _end()]})
	if m.engine.can_save():
		return "sem jogo não salva"
	_start(m)
	if not m.engine.can_save() or m.engine.can_save(VNNarrativeEngine.SAVE_ACTIVITY):
		return "numa fala salva manual, mas não o autosave de atividade"
	var snap := m.engine.snapshot()
	if snap.chapter.id != "ch1" or snap.scene.id != "s1" or snap.scene.node != "a":
		return "snapshot: %s" % [snap]
	return ""


func test_retomar_do_save() -> String:
	var m := _setup({"s1": [_line("a", "one"), _line("b", "two {global.money}"), _end()]})
	m.engine.resume_from_save({
		"chapter": {"id": "ch1"}, "scene": {"id": "s1", "node": "b", "used_hotspots": []},
		"backlog": [{"path": "s1/a", "speaker": null, "vars": {}}]})
	if m.engine.phase() != VNPhase.SCENE_RUNNING or m.engine.current_node() != "b" or _stage(m).line.text != "two 30":
		return "deveria reexecutar o nó salvo"
	if m.engine.snapshot().backlog.size() != 1:
		return "a fala reexecutada não duplica o backlog"
	if "sys.chapter_started" in _names(m):
		return "carregar não emite sys.chapter_started"
	m.engine.resume_from_save({"chapter": {"id": "ch1"}, "scene": null})
	return "" if m.scheduler.count_calls(&"select") == 1 else "sem cena vai ao ponto de seleção"


func test_retomar_no_no_inexistente() -> String:
	var m := _setup({"s1": [_line("a", "one"), _end()]})
	m.engine.resume_from_save({"chapter": {"id": "ch1"}, "scene": {"id": "s1", "node": "gone"}})
	if m.engine.current_node() != "a" or m.variables.count_calls(&"enter_scene") != 1:
		return "nó inexistente recomeça a cena do início"
	(m.scheduler as FakeSceneScheduler).decisions = [{"action": VNSceneScheduler.ACTION_START_SCENE, "chosen": "s1"}]
	m.engine.resume_from_save({"chapter": {"id": "old"}, "scene": null})
	return "" if m.engine.current_chapter() == "ch1" and "sys.chapter_started" in _names(m) else "capítulo inexistente entra no start_chapter"


func test_voltar_ao_titulo_na_atividade() -> String:
	var m := _setup({"s1": _activity_scene()})
	_start(m)
	m.engine.return_to_title()
	if m.engine.phase() != VNPhase.TITLE or m.plugins.count_calls(&"cancel_activity") != 1:
		return "deveria cancelar a atividade e ir ao título"
	if "sys.activity_completed" in _names(m) or m.engine.current_scene() != "":
		return "cancelar não completa a atividade"
	return ""


func test_pausa_e_espera() -> String:
	var m := _setup({"s1": [_line("a", "x"), _line("b", "y")]})
	_start(m)
	m.engine.set_paused(true)
	_stage(m).press_advance()
	if m.engine.current_node() != "a":
		return "pausado não avança"
	if m.engine.choose("x").ok:
		return "pausado não escolhe"
	m.engine.set_paused(false)
	_stage(m).press_advance()
	return "" if m.engine.current_node() == "b" else "despausado avança"
