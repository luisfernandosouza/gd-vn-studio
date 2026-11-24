extends SceneTree
## Testes do Plugin Host (tarefa M3-01): carga, ordem, permissões, erros e
## ciclo de vida, contra os dublês dos outros módulos (M0-07).
##
##   godot --headless --path runtime --script res://tests/plugin_host/test_plugin_host.gd
##
## Os plugins de teste são gravados em user:// a cada execução (o Plugin Host
## aceita outra raiz em plugins_root): assim um plugin com erro de sintaxe não
## entra no import do projeto. Alguns testes provocam erros de script de
## propósito, então o log tem "SCRIPT ERROR"; o resultado é o código de saída.

const ROOT := "user://plugin_host_test/vn_plugins/"
const Semver := preload("res://vn_runtime/plugin_host/vn_plugin_semver.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	for t in [
		"semver", "ordem_topologica_e_ciclo_de_vida", "falhas_de_carga_e_jogo_segue",
		"confianca", "capacidades_e_variaveis", "permission_denied_e_jogo_segue",
		"faulted_apos_cinco_erros", "erro_de_script_conta", "eventos_e_cenas",
		"atividade_basica", "saves_ordem_do_load", "shutdown",
	]:
		_run(t)
	print("%d/%d testes do Plugin Host passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	_log().clear()
	var err: String = call("test_" + test)
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Apoio ------------------------------------------------------------------

## Log compartilhado pelos plugins de teste: ["<ns>:<método>", …].
func _log() -> Array:
	if not Engine.has_meta("vn_test_log"):
		Engine.set_meta("vn_test_log", [])
	return Engine.get_meta("vn_test_log")


const PLUGIN_SRC := """extends RefCounted
var ctx
var saved = {}
var loaded = "unset"
func _l(m): Engine.get_meta("vn_test_log").append("%s:%s" % [ctx.plugin_namespace if ctx else "?", m])
func _vn_init(c):
	ctx = c
	_l("init")
func _vn_ready(): _l("ready")
func _vn_game_started(is_new): _l("started_%s" % is_new)
func _vn_game_ended(): _l("ended")
func _vn_shutdown(): _l("shutdown")
func _vn_save():
	_l("save")
	return saved
func _vn_load(data):
	loaded = data
	_l("load_%s" % ("null" if data == null else "data"))
func _vn_migrate_save_data(data, from_version):
	_l("migrate_%d" % from_version)
	var d = data.duplicate()
	d["v"] = from_version + 1
	return d
func _vn_start_activity(activity_id, params, handle):
	_l("start_%s" % activity_id)
	match params.get("mode", ""):
		"win": handle.complete(&"won", {"score": 1})
		"bad": handle.complete(&"bogus", {})
		"fail": handle.fail("pedido")
		"crash":
			var n = null
			n.boom()
func _vn_cancel_activity(handle): _l("cancel_%s" % handle.is_active())
func crash():
	var n = null
	n.boom()
"""


## Grava um plugin de teste e devolve a entrada de plugins.json.
func _plugin(ns: String, extra_manifest: Dictionary = {}, entry: Dictionary = {}, source := PLUGIN_SRC) -> Dictionary:
	var id := "test.%s" % ns
	var dir := ROOT + ns + "/"
	DirAccess.make_dir_recursive_absolute(dir + "runtime/src")
	var m := {
		"manifest_version": 1, "id": id, "namespace": ns, "name": ns, "version": "1.0.0",
		"default_locale": "en", "license": "MIT", "sdk": {"runtime": "^1.0.0"},
		"compatibility": {"runtime": "^1.0.0", "godot": ">=4.7.0 <5.0.0"},
		"targets": ["runtime"], "entrypoints": {"runtime": "runtime/src/main.gd"},
		"events": {"emits": [{"name": "%s.done" % ns}]},
		"activities": [{"id": "game", "outcomes": ["won", "lost"], "skippable": true, "default_outcome": "lost"}],
	}
	m.merge(extra_manifest, true)
	var f := FileAccess.open(dir + "plugin.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(m))
	f.close()
	f = FileAccess.open(dir + "runtime/src/main.gd", FileAccess.WRITE)
	f.store_string(source)
	f.close()
	var e := {
		"id": id, "namespace": ns, "version": m.version, "path": dir, "trust": "official",
		"capabilities": [], "variables": {"read": [], "write": []}, "scenes": [], "config": {},
	}
	e.merge(entry, true)
	return e


func _bundle(entries: Array) -> Dictionary:
	var plugins := {}
	for e in entries:
		plugins[e.id] = e
	return {"plugins": plugins}


func _host(modules: VNModules = null) -> VNPluginHostImpl:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var m := modules if modules != null else VNFakeModules.create()
	var h := VNPluginHostImpl.new()
	h.plugins_root = ROOT
	m.plugins = h
	m.bind_all()
	h.set_meta("modules", m)  # mantém o registro vivo (o módulo guarda só referência fraca)
	return h


func _clean() -> void:
	_rm(ProjectSettings.globalize_path("user://plugin_host_test"))


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(path.path_join(sub))
	DirAccess.remove_absolute(path)


# --- Testes -----------------------------------------------------------------

func test_semver() -> String:
	var cases := [
		["1.0.0", "^1.0.0", true], ["1.9.3", "^1.0.0", true], ["2.0.0", "^1.0.0", false],
		["0.2.5", "^0.2.0", true], ["0.3.0", "^0.2.0", false], ["1.2.9", "~1.2.0", true],
		["1.3.0", "~1.2.0", false], ["4.7.2", ">=4.7.0 <5.0.0", true], ["5.0.0", ">=4.7.0 <5.0.0", false],
		["1.4.0", "1.x", true], ["2.0.0", "1.x || 2.x", true], ["3.0.0", "1.x || 2.x", false],
		["1.0.0", "*", true], ["1.0.0-beta.1", "^1.0.0", false], ["1.0.0", "1.0.0", true],
		["1.2.0", "1.0.0 - 1.4.0", true], ["1.5.0", "1.0.0 - 1.4.0", false], ["1.0.1", ">1.0.0", true],
	]
	for c in cases:
		if Semver.satisfies(c[0], c[1]) != c[2]:
			return "%s em '%s' deveria ser %s" % c
	if Semver.compare("1.0.0-beta", "1.0.0") != -1 or Semver.compare("1.10.0", "1.9.0") != 1:
		return "compare"
	if Semver.is_valid_range("^banana"):
		return "faixa ilegível aceita"
	return ""


func test_ordem_topologica_e_ciclo_de_vida() -> String:
	_clean()
	var h := _host()
	# alpha depende de gamma; beta e gamma não dependem de ninguém; delta tem
	# dependência opcional em beta. Ordem esperada: beta, delta, gamma, alpha.
	var b := _bundle([
		_plugin("alpha", {"dependencies": {"test.gamma": "^1.0.0"}}),
		_plugin("gamma"), _plugin("beta"),
		_plugin("delta", {"optional_dependencies": {"test.beta": "^1.0.0", "test.nada": "^1.0.0"}}),
	])
	h.load_plugins(b)
	var order := h.loaded_plugins()
	if order != PackedStringArray(["beta", "delta", "gamma", "alpha"]):
		return "ordem %s" % order
	var expected := ["beta:init", "delta:init", "gamma:init", "alpha:init", "beta:ready", "delta:ready", "gamma:ready", "alpha:ready"]
	if _log() != expected:
		return "init/ready %s" % [_log()]
	_log().clear()
	h.notify_game_started(true)
	h.notify_game_ended()
	if _log().slice(0, 4) != ["beta:started_true", "delta:started_true", "gamma:started_true", "alpha:started_true"]:
		return "game_started %s" % [_log()]
	if _log().slice(4) != ["beta:ended", "delta:ended", "gamma:ended", "alpha:ended"]:
		return "game_ended %s" % [_log()]
	var ctx = h.plugin_instance(&"alpha").ctx
	if ctx.plugin_id != &"test.alpha" or ctx.plugin_namespace != &"alpha":
		return "contexto sem identidade"
	h.shutdown()
	return ""


func test_falhas_de_carga_e_jogo_segue() -> String:
	_clean()
	var h := _host()
	var failed := []
	h.plugin_load_failed.connect(func(p, _e): failed.append(String(p)))
	var nomani := _plugin("nomani")
	DirAccess.remove_absolute(ROOT + "nomani/plugin.json")
	var entries := [
		_plugin("good"),
		nomani,
		_plugin("oldrt", {"compatibility": {"runtime": "^2.0.0"}}),
		_plugin("oldsdk", {"sdk": {"runtime": "^0.9.0"}}),
		_plugin("godot3", {"compatibility": {"runtime": "^1.0.0", "godot": "^3.5.0"}}),
		_plugin("syntax", {}, {}, "extends RefCounted\nfunc _vn_init(c)\n\tpass\n"),
		_plugin("initcrash", {}, {}, "extends RefCounted\nfunc _vn_init(c):\n\tvar n = null\n\tn.boom()\n"),
		_plugin("needsbad", {"dependencies": {"test.syntax": "^1.0.0"}}),
		_plugin("needsnone", {"dependencies": {"test.missing": "^1.0.0"}}),
		_plugin("needsnew", {"dependencies": {"test.good": "^2.0.0"}}),
		_plugin("cyca", {"dependencies": {"test.cycb": "^1.0.0"}}),
		_plugin("cycb", {"dependencies": {"test.cyca": "^1.0.0"}}),
		_plugin("badpath", {}, {"path": "res://outro/"}),
		_plugin("badentry", {"entrypoints": {"runtime": "../../fora.gd"}}),
	]
	var sys_entry := _plugin("sysx")
	sys_entry.namespace = "sys"
	entries.append(sys_entry)
	var dup := _plugin("dup1")
	dup.id = "test.zdup"
	dup.namespace = "good"
	entries.append(dup)
	var b := _bundle(entries)
	h.load_plugins(b)
	if h.loaded_plugins() != PackedStringArray(["good"]):
		return "carregados %s" % h.loaded_plugins()
	var expected := ["nomani", "oldrt", "oldsdk", "godot3", "syntax", "initcrash", "needsbad",
		"needsnone", "needsnew", "cyca", "cycb", "badpath", "badentry", "sys"]
	for ns in expected:
		if not failed.has(ns):
			return "%s deveria falhar; falhas: %s" % [ns, h.load_failures()]
	if failed.size() != expected.size() + 1:  # + namespace duplicado
		return "falhas inesperadas: %s" % [h.load_failures()]
	if h.is_loaded(&"syntax") or h.is_loaded(&"initcrash"):
		return "plugin com falha ficou carregado"
	# O jogo segue: o plugin bom funciona e atividade do que falhou é recusada (on_error).
	h.notify_game_started(true)
	if not _log().has("good:started_true"):
		return "plugin bom não recebeu game_started"
	h.handle_factory = func(_h, _a): return null
	if h.start_activity(&"initcrash.game", {}).ok:
		return "atividade de plugin que não carregou foi aceita"
	h.shutdown()
	return ""


func test_confianca() -> String:
	_clean()
	var h := _host()
	var local_entry := _plugin("dev")
	local_entry.erase("trust")  # res://vn_plugins/ em desenvolvimento, sem lock (RT §2.1)
	h.load_plugins(_bundle([local_entry, _plugin("off"), _plugin("bad", {}, {"trust": "verified"})]))
	if h.plugin_trust(&"dev") != VNPluginHostImpl.TRUST_LOCAL:
		return "sem trust deveria ser local: %s" % h.plugin_trust(&"dev")
	if h.plugin_trust(&"off") != VNPluginHostImpl.TRUST_OFFICIAL:
		return "official"
	if not h.is_loaded(&"dev"):
		return "plugin local deveria executar"
	if h.is_loaded(&"bad"):
		return "confiança desconhecida aceita"
	h.shutdown()
	return ""


func test_capacidades_e_variaveis() -> String:
	_clean()
	var m := VNFakeModules.create()
	var fv := m.variables as FakeVariableManager
	fv.definitions["global.public"] = {"type": "integer", "default": 0, "access": {"plugins_read": "all"}}
	fv.definitions["global.money"] = {"type": "integer", "default": 0, "access": {"plugins_read": "granted", "plugins_write": "granted"}}
	fv.definitions["global.secret"] = {"type": "integer", "default": 0}
	var h := _host(m)
	h.load_plugins(_bundle([
		_plugin("reader", {"dependencies": {"test.owner": "^1.0.0"}, "variable_permissions": {"read": ["plugin.owner.score"]}},
			{"capabilities": ["runtime:variables.read", "runtime:variables.write", "editor:panels"],
			"variables": {"read": ["global.money", "character.*.affection"], "write": ["global.money"]}}),
		_plugin("owner", {}, {"capabilities": ["runtime:scenes.request"], "scenes": ["scene_a"]}),
		_plugin("nocaps", {}, {"variables": {"read": ["global.money"], "write": ["global.money"]}}),
	]))
	var checks := [
		[h.has_capability(&"reader", &"variables.read"), true, "cap sem prefixo"],
		[h.has_capability(&"reader", &"runtime:variables.write"), true, "cap com prefixo"],
		[h.has_capability(&"reader", &"panels"), false, "cap de editor não vale no runtime"],
		[h.can_read_variable(&"reader", "global.money"), true, "leitura concedida"],
		[h.can_read_variable(&"reader", "character.alice.affection"), true, "curinga"],
		[h.can_read_variable(&"reader", "character.alice.mood"), false, "fora do curinga"],
		[h.can_read_variable(&"reader", "global.public"), true, "plugins_read all"],
		[h.can_read_variable(&"reader", "global.secret"), false, "sem concessão"],
		[h.can_read_variable(&"reader", "plugin.owner.score"), true, "de dependência declarada"],
		[h.can_read_variable(&"reader", "plugin.owner.other"), false, "de dependência, não pedida"],
		[h.can_read_variable(&"owner", "plugin.owner.anything"), true, "próprio namespace"],
		[h.can_write_variable(&"owner", "plugin.owner.anything"), true, "próprio, escrita"],
		[h.can_write_variable(&"reader", "plugin.owner.score"), false, "de outro plugin nunca gravável"],
		[h.can_write_variable(&"reader", "global.money"), true, "escrita concedida"],
		[h.can_write_variable(&"reader", "global.public"), false, "escrita não concedida"],
		[h.can_read_variable(&"nocaps", "global.money"), false, "concessão sem capacidade"],
		[h.can_write_variable(&"nocaps", "global.money"), false, "escrita sem capacidade"],
		[h.can_read_variable(&"nocaps", "global.public"), false, "all sem variables.read"],
		[h.can_request_scene(&"owner", "scene_a"), true, "cena concedida"],
		[h.can_request_scene(&"owner", "scene_b"), false, "cena não concedida"],
		[h.can_request_scene(&"reader", "scene_a"), false, "cena sem capacidade"],
		[h.can_emit(&"owner", "owner.done"), true, "evento declarado"],
		[h.can_emit(&"owner", "owner.other"), false, "evento não declarado"],
		[h.can_emit(&"owner", "reader.done"), false, "namespace de outro"],
		[h.has_capability(&"ghost", &"variables.read"), false, "plugin desconhecido"],
	]
	for c in checks:
		if c[0] != c[1]:
			return c[2]
	h.shutdown()
	return ""


## State Manager de teste com a verificação 6 do RT §6.2 (a do dublê não confere permissão).
class PermStateManager:
	extends FakeStateManager
	func write(op: StringName, id: String, value: Variant = null, caller: StringName = CALLER_CONTENT) -> VNResult:
		var ns := caller_plugin(caller)
		if ns != &"" and modules().variables.has(id) and not modules().plugins.can_write_variable(ns, id):
			return VNResult.failure(VNErrors.PERMISSION_DENIED, id)
		return super.write(op, id, value, caller)


func test_permission_denied_e_jogo_segue() -> String:
	_clean()
	var m := VNFakeModules.create()
	m.state = PermStateManager.new()
	var fv := m.variables as FakeVariableManager
	fv.define("global.money", &"integer", 10)
	fv.define("global.other", &"integer", 0)
	fv.define("plugin.thief.loot", &"integer", 0)
	fv.reset_game()
	var h := _host(m)
	h.load_plugins(_bundle([
		_plugin("thief"),
		_plugin("banker", {}, {"capabilities": ["runtime:variables.write"], "variables": {"read": [], "write": ["global.money"]}}),
	]))
	var denied := []
	h.permission_denied.connect(func(p, cap, call): denied.append([String(p), String(cap), call]))
	# Sem variables.write: PERMISSION_DENIED, nada aplicado, recusa registrada.
	var r := h.plugin_write(&"thief", &"set", "global.money", 999)
	if r.ok or r.error != VNErrors.PERMISSION_DENIED:
		return "esperava PERMISSION_DENIED, veio %s" % r.error
	if fv.read("global.money") != 10:
		return "valor mudou sem permissão"
	if denied.size() != 1 or denied[0][0] != "thief" or denied[0][1] != "variables.write":
		return "sinal permission_denied: %s" % [denied]
	if h.error_count(&"thief") != 1:
		return "recusa não contou para faulted"
	# Leitura sem variables.read devolve o fallback.
	if h.plugin_read(&"thief", "global.money", -1) != -1:
		return "leitura sem permissão devolveu valor"
	# Com capacidade mas variável não concedida: recusa vem do State Manager (verificação 6).
	r = h.plugin_write(&"banker", &"set", "global.other", 5)
	if r.error != VNErrors.PERMISSION_DENIED or h.error_count(&"banker") != 1:
		return "recusa da verificação 6 não contou: %s / %d" % [r.error, h.error_count(&"banker")]
	# O jogo segue: escritas permitidas funcionam e o plugin continua carregado.
	r = h.plugin_write(&"banker", &"add", "global.money", 5)
	if not r.ok or fv.read("global.money") != 15:
		return "escrita concedida falhou: %s" % r.error
	r = h.plugin_write(&"thief", &"set", "plugin.thief.loot", 3)
	if not r.ok:
		return "variável própria não exige capacidade: %s" % r.error
	if not h.is_loaded(&"thief") or h.is_faulted(&"thief"):
		return "plugin deveria seguir carregado"
	h.notify_game_started(true)
	if not _log().has("thief:started_true"):
		return "ciclo de vida parou"
	h.shutdown()
	return ""


func test_faulted_apos_cinco_erros() -> String:
	_clean()
	var m := VNFakeModules.create()
	var h := _host(m)
	h.load_plugins(_bundle([_plugin("noisy"), _plugin("calm")]))
	var faulted := []
	h.plugin_faulted.connect(func(p, e): faulted.append([String(p), e]))
	var fb := m.events as FakeEventBus
	h.plugin_on(&"noisy", "noisy.*", func(_n, _p, _s): pass)
	h.plugin_on(&"calm", "calm.*", func(_n, _p, _s): pass)
	for i in VNPluginHost.FAULT_THRESHOLD - 1:
		h.plugin_emit(&"noisy", "noisy.done")  # sem events.emit
	if h.is_faulted(&"noisy"):
		return "faulted antes do limite"
	h.plugin_emit(&"noisy", "noisy.done")
	if not h.is_faulted(&"noisy") or faulted.size() != 1 or faulted[0][0] != "noisy":
		return "não ficou faulted no 5º erro: %s" % [faulted]
	if h.is_loaded(&"noisy"):
		return "faulted não deveria contar como carregado"
	for s in fb._subs.values():
		if s.owner == &"noisy":
			return "ouvintes do plugin faulted não saíram"
	if fb._subs.size() != 1:
		return "ouvinte de outro plugin saiu"
	h.handle_factory = func(_h, _a): return null
	if h.start_activity(&"noisy.game", {}).ok:
		return "atividade de plugin faulted aceita"
	_log().clear()
	h.notify_game_started(true)
	if _log() != ["calm:started_true"]:
		return "faulted ainda recebe ciclo de vida: %s" % [_log()]
	h.report_error(&"noisy", "mais um")  # depois de faulted, não emite de novo
	if faulted.size() != 1:
		return "plugin_faulted emitido duas vezes"
	h.shutdown()
	if not _log().has("noisy:shutdown"):
		return "_vn_shutdown deveria chegar ao faulted"
	return ""


func test_erro_de_script_conta() -> String:
	_clean()
	var h := _host()
	h.load_plugins(_bundle([_plugin("buggy"), _plugin("clean")]))
	h.plugin_instance(&"buggy").crash()
	h._drain_script_errors()  # o que o process_frame faz com o host anexado
	if h.error_count(&"buggy") != 1 or h.error_count(&"clean") != 0:
		return "erro de script não atribuído: buggy=%d clean=%d" % [h.error_count(&"buggy"), h.error_count(&"clean")]
	h.shutdown()
	return ""


func test_eventos_e_cenas() -> String:
	_clean()
	var m := VNFakeModules.create()
	var h := _host(m)
	h.load_plugins(_bundle([
		_plugin("talker", {}, {"capabilities": ["runtime:events.emit", "runtime:scenes.request"], "scenes": ["scene_x"]}),
		_plugin("listener", {}, {"capabilities": ["runtime:events.subscribe"]}),
	]))
	var fb := m.events as FakeEventBus
	var r := h.plugin_emit(&"talker", "talker.done", {"a": 1})
	if not r.ok or fb._queue.back().source != "test.talker":
		return "emit concedido falhou ou source errado"
	if h.plugin_emit(&"talker", "talker.undeclared").error != VNErrors.PERMISSION_DENIED:
		return "evento não declarado aceito"
	if h.plugin_on(&"talker", "story.*", func(_n, _p, _s): pass) != -1:
		return "assinatura sem events.subscribe aceita"
	if h.plugin_on(&"talker", "talker.*", func(_n, _p, _s): pass) < 0:
		return "assinatura do próprio namespace recusada"
	if h.plugin_on(&"listener", "sys.*", func(_n, _p, _s): pass) < 0:
		return "assinatura concedida recusada"
	if not h.plugin_request_scene(&"talker", "scene_x").ok:
		return "pedido de cena concedido falhou"
	if h.plugin_request_scene(&"talker", "scene_y").error != VNErrors.PERMISSION_DENIED:
		return "cena não concedida aceita"
	h.shutdown()
	return ""


class TestHandle:
	extends RefCounted
	var host: VNPluginHostImpl
	var token: int
	func complete(outcome: StringName, payload: Dictionary = {}) -> void:
		host.complete_activity(token, outcome, payload)
	func fail(reason: String) -> void:
		host.fail_activity(token, reason)
	func is_active() -> bool:
		return host.is_activity_active(token)


func test_atividade_basica() -> String:
	_clean()
	var h := _host()
	h.load_plugins(_bundle([_plugin("game")]))
	var ended := []
	h.activity_ended.connect(func(s, o, p): ended.append([s, o, p]))
	if h.start_activity(&"game.game", {}).ok:
		return "sem handle_factory deveria recusar"
	h.handle_factory = func(host, _a):
		var hd := TestHandle.new()
		hd.host = host
		hd.token = host.activity_token()
		return hd
	if not h.start_activity(&"game.game", {"mode": "win"}).ok or ended.back() != [&"completed", &"won", {"score": 1}]:
		return "complete: %s" % [ended]
	if h.start_activity(&"game.nada", {}).ok:
		return "atividade não declarada aceita"
	h.start_activity(&"game.game", {"mode": "bad"})
	if ended.back()[0] != &"failed" or h.error_count(&"game") != 1:
		return "outcome desconhecido deveria falhar e contar"
	h.start_activity(&"game.game", {"mode": "fail"})
	if ended.back()[0] != &"failed" or h.error_count(&"game") != 2:
		return "fail deveria contar"
	h.start_activity(&"game.game", {"mode": "crash"})
	if ended.back()[0] != &"failed" or h.error_count(&"game") != 3:
		return "erro de script na atividade: %s / %d" % [ended.back(), h.error_count(&"game")]
	h.start_activity(&"game.game", {"mode": "wait"})
	if h.current_activity().get("skippable") != true:
		return "current_activity"
	if h.start_activity(&"game.game", {}).ok:
		return "segunda atividade simultânea aceita"
	_log().clear()
	h.cancel_activity(VNPluginHost.STATUS_SKIPPED)
	if ended.back() != [&"skipped", &"lost", {}] or not _log().has("game:cancel_false"):
		return "pulo: %s %s" % [ended.back(), _log()]
	h.shutdown()
	return ""


func test_saves_ordem_do_load() -> String:
	_clean()
	var h := _host()
	h.load_plugins(_bundle([
		_plugin("keeper", {"save": {"data_version": 3}}, {"capabilities": ["runtime:save.data"]}),
		_plugin("plain"),
	]))
	h.plugin_instance(&"keeper").saved = {"fish": 2}
	var s := h.save_data()
	if s.keys() != ["keeper"] or s.keeper != {"plugin_version": "1.0.0", "data_version": 3, "data": {"fish": 2}}:
		return "save_data sem save.data deveria ficar de fora: %s" % s
	_log().clear()
	h.load_data({
		"keeper": {"plugin_version": "1.0.0", "data_version": 1, "data": {"fish": 1}},
		"gone": {"plugin_version": "2.0.0", "data_version": 1, "data": 7},
	})
	var expected := ["keeper:started_false", "keeper:migrate_1", "keeper:migrate_2", "keeper:load_data",
		"plain:started_false", "plain:load_null"]
	if _log() != expected:
		return "ordem do load %s" % [_log()]
	if h.plugin_instance(&"keeper").loaded != {"fish": 1, "v": 3}:
		return "migração em cadeia: %s" % h.plugin_instance(&"keeper").loaded
	if h.save_data().get("gone", {}).get("data") != 7:
		return "dados de plugin ausente não foram preservados"
	h.shutdown()
	return ""


func test_shutdown() -> String:
	_clean()
	var h := _host()
	h.load_plugins(_bundle([_plugin("a"), _plugin("b")]))
	_log().clear()
	h.shutdown()
	if _log() != ["a:shutdown", "b:shutdown"]:
		return "shutdown %s" % [_log()]
	if not h.loaded_plugins().is_empty() or h.is_loaded(&"a"):
		return "plugins continuam carregados"
	# Recarregar depois do shutdown (Preview: reload_plugins) funciona.
	h.load_plugins(_bundle([_plugin("a")]))
	if h.loaded_plugins() != PackedStringArray(["a"]):
		return "recarga"
	h.shutdown()
	_clean()
	return ""
