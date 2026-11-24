extends VNSdkTest
## Plugin SDK §5.1–§5.2: classe base, ciclo de vida e contexto.


class Probe extends VNRuntimePlugin:
	var calls: Array[String] = []
	var ctx: VNPluginContext
	func _vn_init(p_ctx: VNPluginContext) -> void:
		ctx = p_ctx
		calls.append("init")
	func _vn_ready() -> void:
		calls.append("ready")


func test_contexto_tem_todos_os_servicos() -> void:
	var b := FakePluginBridge.new()
	var ctx := VNPluginContext.create(b, &"vnstudio.fishing", &"fishing", {"rare_fish_chance": 0.1})
	eq(ctx.plugin_id, &"vnstudio.fishing", "plugin_id")
	eq(ctx.plugin_namespace, &"fishing", "plugin_namespace")
	eq(ctx.config, {"rare_fish_chance": 0.1}, "config")
	check(ctx.narrative is VNNarrativeAPI, "narrative")
	check(ctx.narrative.variables is VNVariableAPI, "narrative.variables")
	check(ctx.narrative.events is VNEventAPI, "narrative.events")
	check(ctx.scenes is VNSceneAPI, "scenes")
	check(ctx.characters is VNCharacterAPI, "characters")
	check(ctx.assets is VNAssetAPI, "assets")
	check(ctx.audio is VNAudioAPI, "audio")
	check(ctx.ui is VNUIAPI, "ui")
	check(ctx.profile is VNProfileAPI, "profile")
	check(ctx.rng is VNRandom, "rng")
	check(ctx.i18n is VNI18nAPI, "i18n")
	check(ctx.theme is VNThemeInfo, "theme")
	check(ctx.log is VNLogger, "log")
	eq(ctx.content_filter, false, "content_filter")


func test_classe_base_tem_o_ciclo_de_vida_da_spec() -> void:
	var p := Probe.new()
	for m in ["_vn_init", "_vn_ready", "_vn_game_started", "_vn_start_activity", "_vn_cancel_activity",
			"_vn_save", "_vn_load", "_vn_migrate_save_data", "_vn_migrate_profile_data", "_vn_game_ended", "_vn_shutdown"]:
		check(p.has_method(m), "VNRuntimePlugin.%s" % m)
	check(p is Node, "VNRuntimePlugin é Node")
	p._vn_init(VNPluginContext.create(FakePluginBridge.new(), &"x.probe", &"probe"))
	p._vn_ready()
	eq(p.calls, ["init", "ready"] as Array[String], "sobrescritas chamadas")
	eq(p._vn_save(), {}, "_vn_save padrão")
	eq(p._vn_migrate_save_data({"a": 1}, 1), {"a": 1}, "_vn_migrate_save_data padrão")
	eq(p._vn_migrate_profile_data([1], 1), [1], "_vn_migrate_profile_data padrão")
	p.free()


func test_logger_vai_para_a_ponte() -> void:
	var b := FakePluginBridge.new()
	var ctx := VNPluginContext.create(b, &"x.probe", &"probe")
	ctx.log.warn("recompensa não aplicada")
	ctx.log.error("x")
	eq(b.logs, [{"level": &"warn", "message": "recompensa não aplicada"}, {"level": &"error", "message": "x"}] as Array[Dictionary], "logs")


func test_handle_completa_uma_vez() -> void:
	var b := FakePluginBridge.new()
	var ended: Array = []
	var h := VNActivityHandle.new(&"fishing_game", {"target_fish": 3}, &"story", null,
		func(status, outcome, payload, reason): ended.append([status, outcome, payload, reason]), b)
	check(h.is_active(), "ativo no começo")
	h.complete(&"won", {"score": 10})
	h.complete(&"lost")
	h.fail("tarde")
	check(not h.is_active(), "inativo depois")
	eq(ended, [[&"completed", &"won", {"score": 10}, ""]], "uma única conclusão")
	eq(b.logs.size(), 2, "chamadas extras avisam")


func test_handle_fechado_pelo_host_ignora_complete() -> void:
	var ended: Array = []
	var h := VNActivityHandle.new(&"a", {}, &"free_play", null, func(s, o, p, r): ended.append(s))
	eq(h.mode, &"free_play", "mode")
	check(h.rng is VNRandom, "handle.rng")
	h.close()
	check(not h.is_active(), "close desativa")
	h.complete(&"won")
	eq(ended.size(), 0, "complete depois do close é ignorado")


func test_rng_com_semente_e_reproduzivel() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var c := RandomNumberGenerator.new()
	c.seed = 42
	var r1 := VNRandom.new(a)
	var r2 := VNRandom.new(c)
	eq(r1.randi_range(1, 1000), r2.randi_range(1, 1000), "randi_range")
	eq(r1.randf(), r2.randf(), "randf")
	var v := r1.randi_range(5, 5)
	eq(v, 5, "intervalo inclusivo")
