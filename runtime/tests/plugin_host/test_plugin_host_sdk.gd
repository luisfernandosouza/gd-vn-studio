extends SceneTree
## Plugin Host com o Runtime SDK de verdade (tarefas M3-01 e M3-02): contexto,
## ponte, PERMISSION_DENIED pelas fachadas e atividade com VNActivityHandle.
##
## O addon ainda não faz parte do projeto do runtime (entra na integração), então
## este teste precisa dele copiado antes do import, sem a cópia de VNResult, que
## o runtime já tem em core/:
##
##   mkdir -p runtime/addons && cp -r sdk/runtime/addons/vn_runtime_sdk runtime/addons/
##   rm runtime/addons/vn_runtime_sdk/vn_result.gd*
##   godot --headless --path runtime --import
##   godot --headless --path runtime --script res://tests/plugin_host/test_plugin_host_sdk.gd
##
## Este script não cita classes do addon, para compilar também sem ele (o import
## das outras workflows); sem o addon, sai com 1 e avisa. Os plugins de teste
## (o probe das fixtures e um plugin sem permissões) são gravados em user://.

const ROOT := "user://plugin_host_sdk_test/vn_plugins/"
const PROBE_SRC := "res://tests/fixtures/src/projects/activity/plugins/probe/vn_plugins/probe/"

const GREEDY_SRC := """extends VNRuntimePlugin
var ctx: VNPluginContext
var results := {}
var heard := []
func _vn_init(c: VNPluginContext) -> void:
	ctx = c
	results.own_sub = ctx.narrative.events.on("greedy.*", func(n, p, s): heard.append(n))
	results.write = ctx.narrative.variables.set_value("global.money", 999)
	results.own = ctx.narrative.variables.set_value("~loot", 3)
	results.read = ctx.narrative.variables.get_value("global.money", -1)
	results.emit = ctx.narrative.events.emit("greedy.done", {})
	results.scene = ctx.scenes.request("scene_secret")
	results.sub = ctx.narrative.events.on("story.*", func(n, p, s): heard.append(n))
"""

const WAITER_SRC := """extends VNRuntimePlugin
var results := {}
func _vn_start_activity(activity_id: StringName, params: Dictionary, handle: VNActivityHandle) -> void:
	results.handle = handle
func _vn_cancel_activity(handle: VNActivityHandle) -> void:
	results.active_on_cancel = handle.is_active()
"""

var _passed := 0
var _failed := 0


func _init() -> void:
	if not ClassDB.class_exists(&"Logger") or not _has_class(&"VNPluginBridge"):
		print("FALHOU  addon vn_runtime_sdk ausente em runtime/addons/ (veja o cabeçalho deste teste)")
		quit(1)
		return
	for t in ["contexto_e_ponte", "permission_denied_pelas_fachadas", "atividade_com_handle_do_sdk", "pulo_fecha_o_handle"]:
		_run(t)
	print("%d/%d testes do Plugin Host com o SDK passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	var ret: Variant = call("test_" + test)
	# Um erro de script no meio do teste devolve null: conta como falha.
	var err: String = ret if ret is String else "o teste parou num erro de script"
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


func _has_class(cls: StringName) -> bool:
	for c in ProjectSettings.get_global_class_list():
		if c.get("class", &"") == cls:
			return true
	return false


func _copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		var data := FileAccess.get_file_as_bytes(from.path_join(f))
		var out := FileAccess.open(to.path_join(f), FileAccess.WRITE)
		out.store_buffer(data)
		out.close()
	for d in DirAccess.get_directories_at(from):
		_copy_dir(from.path_join(d), to.path_join(d))


func _setup() -> VNPluginHostImpl:
	_copy_dir(PROBE_SRC, ROOT + "probe")
	# O probe das fixtures (M0-08) usa _ctx.events, que não existe no SDK §5.2: os
	# eventos ficam em ctx.narrative.events (§5.3). Corrigido só na cópia do teste.
	var probe_gd := ROOT + "probe/runtime/src/probe_plugin.gd"
	var src := FileAccess.get_file_as_string(probe_gd).replace("_ctx.events.", "_ctx.narrative.events.")
	var pf := FileAccess.open(probe_gd, FileAccess.WRITE)
	pf.store_string(src)
	pf.close()
	_write_plugin("greedy", GREEDY_SRC)
	_write_plugin("waiter", WAITER_SRC)

	var mods := VNFakeModules.create()
	mods.state = PermStateManager.new()
	var fv := mods.variables as FakeVariableManager
	fv.define("global.money", &"integer", 10)
	fv.define("plugin.greedy.loot", &"integer", 0)
	var h := VNPluginHostImpl.new()
	h.plugins_root = ROOT
	mods.plugins = h
	mods.bind_all()
	h.set_meta("modules", mods)
	var denied := []
	h.set_meta("denied", denied)
	h.permission_denied.connect(func(p, cap, call): denied.append([String(p), String(cap), call]))
	h.load_plugins({"plugins": {
		"fixture_activity.probe": {
			"id": "fixture_activity.probe", "namespace": "probe", "version": "1.0.0", "path": ROOT + "probe/",
			"trust": "local", "embedded": true, "capabilities": ["runtime:events.emit"],
			"variables": {"read": [], "write": []}, "scenes": [], "config": {"speed": 2},
		},
		"test.greedy": {
			"id": "test.greedy", "namespace": "greedy", "version": "1.0.0", "path": ROOT + "greedy/",
			"capabilities": [], "variables": {"read": [], "write": []}, "scenes": [], "config": {},
		},
		"test.waiter": {
			"id": "test.waiter", "namespace": "waiter", "version": "1.0.0", "path": ROOT + "waiter/",
			"capabilities": [], "variables": {"read": [], "write": []}, "scenes": [], "config": {},
		},
	}})
	return h


## State Manager de teste com a verificação 6 do RT §6.2 (o dublê não confere permissão).
class PermStateManager:
	extends FakeStateManager
	func commit_transaction(tx: VNStateTransaction) -> VNResult:
		var ns := caller_plugin(tx.caller)
		if ns != &"":
			for op in tx.ops:
				var id := String(op.variable)
				if modules().variables.has(id) and not modules().plugins.can_write_variable(ns, id):
					return VNResult.failure(VNErrors.PERMISSION_DENIED, id)
		return super.commit_transaction(tx)


func _write_plugin(ns: String, source: String) -> void:
	var dir := ROOT + ns + "/"
	DirAccess.make_dir_recursive_absolute(dir + "runtime/src")
	var m := {
		"manifest_version": 1, "id": "test." + ns, "namespace": ns, "name": ns, "version": "1.0.0",
		"default_locale": "en", "license": "MIT", "sdk": {"runtime": "^1.0.0"},
		"compatibility": {"runtime": "^1.0.0"}, "targets": ["runtime"],
		"entrypoints": {"runtime": "runtime/src/main.gd"},
		"events": {"emits": [{"name": ns + ".done"}]},
		"activities": [{"id": "wait", "outcomes": ["won", "lost"], "skippable": true, "default_outcome": "lost"}],
	}
	var f := FileAccess.open(dir + "plugin.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(m))
	f.close()
	f = FileAccess.open(dir + "runtime/src/main.gd", FileAccess.WRITE)
	f.store_string(source)
	f.close()


func test_contexto_e_ponte() -> String:
	var h := _setup()
	if h.loaded_plugins() != PackedStringArray(["probe", "greedy", "waiter"]):
		return "carregados %s; falhas %s" % [h.loaded_plugins(), h.load_failures()]
	var probe := h.plugin_instance(&"probe")
	if not probe is Node or probe.get_script().get_base_script().get_global_name() != &"VNRuntimePlugin":
		return "entrypoint não é VNRuntimePlugin"
	var ctx = probe.get(&"_ctx")
	if ctx == null or ctx.get_script().get_global_name() != &"VNPluginContext":
		return "contexto não é o VNPluginContext do SDK"
	if ctx.plugin_id != &"fixture_activity.probe" or ctx.plugin_namespace != &"probe" or ctx.config != {"speed": 2}:
		return "identidade/config do contexto"
	var bridge = ctx.narrative.get(&"_bridge")
	if not bridge.get_script().get_base_script().get_global_name() == &"VNPluginBridge":
		return "ponte não estende VNPluginBridge"
	if not bridge.has_capability(&"events.emit") or bridge.has_capability(&"variables.read"):
		return "capacidades da ponte"
	h.shutdown()
	return ""


func test_permission_denied_pelas_fachadas() -> String:
	var h := _setup()
	var mods: VNModules = h.get_meta("modules")
	var fv := mods.variables as FakeVariableManager
	var r: Dictionary = h.plugin_instance(&"greedy").results
	if r.write.ok or r.write.error != VNErrors.PERMISSION_DENIED:
		return "set_value sem permissão: %s" % r.write.error
	if fv.read("global.money") != 10:
		return "valor mudou sem permissão"
	if not r.own.ok or fv.read("plugin.greedy.loot") != 3:
		return "variável própria deveria ser gravável: %s" % r.own.error
	if r.read != -1:
		return "leitura sem permissão devolveu valor"
	if r.emit.error != VNErrors.PERMISSION_DENIED or r.scene.error != VNErrors.PERMISSION_DENIED:
		return "emit/scene sem capacidade: %s / %s" % [r.emit.error, r.scene.error]
	if r.sub != 0 or r.own_sub < 1:
		return "assinaturas: story.* %d, próprio %d" % [r.sub, r.own_sub]
	var denied: Array = h.get_meta("denied")
	var caps := denied.map(func(d): return d[1])
	for cap in ["variables.read", "events.emit", "scenes.request", "events.subscribe"]:
		if not caps.has(cap):
			return "permission_denied sem %s: %s" % [cap, denied]
	# A escrita foi recusada na verificação 6 do State Manager (RT §6.2) e a fachada
	# avisou a ponte com variables.write.
	if not caps.has("variables.write"):
		return "permission_denied sem variables.write: %s" % [denied]
	if h.error_count(&"greedy") != denied.size():
		return "erros contados %d, recusas %d" % [h.error_count(&"greedy"), denied.size()]
	# 5 recusas: faulted, e o jogo segue com o outro plugin.
	if denied.size() < VNPluginHost.FAULT_THRESHOLD:
		return "esperava ao menos %d recusas, houve %d" % [VNPluginHost.FAULT_THRESHOLD, denied.size()]
	if not h.is_faulted(&"greedy") or not h.is_loaded(&"probe"):
		return "faulted/jogo segue"
	h.shutdown()
	return ""


func test_atividade_com_handle_do_sdk() -> String:
	var h := _setup()
	var mods: VNModules = h.get_meta("modules")
	var fb := mods.events as FakeEventBus
	var ended := []
	h.activity_ended.connect(func(s, o, p): ended.append([s, o, p]))
	if not h.start_activity(&"probe.probe_game", {"mode": "win", "target": 3}).ok:
		return "start recusado"
	if ended.back() != [&"completed", &"won", {"won": true, "score": 3}]:
		return "win: %s" % [ended]
	if fb._queue.is_empty() or fb._queue.back().name != "probe.finished" or fb._queue.back().source != "fixture_activity.probe":
		return "evento do plugin pela ponte: %s" % [fb._queue]
	h.start_activity(&"probe.probe_game", {"mode": "lose"})
	if ended.back()[0] != &"completed" or ended.back()[1] != &"lost":
		return "lose: %s" % [ended.back()]
	h.start_activity(&"probe.probe_game", {"mode": "fail"})
	if ended.back()[0] != &"failed" or h.error_count(&"probe") != 1:
		return "fail: %s / %d" % [ended.back(), h.error_count(&"probe")]
	h.shutdown()
	return ""


func test_pulo_fecha_o_handle() -> String:
	var h := _setup()
	var ended := []
	h.activity_ended.connect(func(s, o, p): ended.append([s, o, p]))
	if not h.start_activity(&"waiter.wait", {}).ok:
		return "start recusado"
	var r: Dictionary = h.plugin_instance(&"waiter").results
	if not r.handle.is_active():
		return "handle inativo no início"
	h.cancel_activity(VNPluginHost.STATUS_SKIPPED)
	if r.get("active_on_cancel", true) != false:
		return "o handle deveria estar inativo em _vn_cancel_activity"
	if ended.back() != [&"skipped", &"lost", {}]:
		return "pulo: %s" % [ended.back()]
	r.handle.complete(&"won")  # depois do fim: ignorado com aviso
	if ended.size() != 1:
		return "complete depois do pulo foi aceito"
	h.shutdown()
	return ""
