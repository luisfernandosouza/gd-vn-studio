extends SceneTree
## Testes dos métodos do Preview (tarefa M4-05; Preview Protocol §3, §5, §6).
##
##   python3 runtime/tests/fixtures/generate.py && godot --headless --path runtime --import
##   godot --headless --path runtime --script res://tests/preview/test_preview_methods.gd
##
## Cada método roda pela [VNPreviewSession] (sem transporte) sobre os dublês de [VNFakeModules] e o
## bundle da fixture [code]choice[/code]. Sai com 1 se algo falhar.

const BUNDLE := "res://tests/fixtures/bundles/choice/"
const ASSETS := "/projeto/assets/"

var _passed := 0
var _failed := 0


## Narrative Engine com o que o Preview pede além do contrato do M0-07.
class PreviewEngine extends FakeNarrativeEngine:
	var started_at: Array = []
	func preview_start_at(p_chapter: String, p_scene: String, p_node: String) -> void:
		started_at = [p_chapter, p_scene, p_node]
		chapter = p_chapter
		scene = p_scene
		node = p_node
		set_phase(VNPhase.SCENE_RUNNING)
	func new_game() -> void:
		super.new_game()
		set_phase(VNPhase.SCENE_RUNNING)

## Plugin Host com manifesto e conclusão de atividade.
class PreviewHost extends FakePluginHost:
	var manifests: Dictionary = {}
	var reloaded: Array = []
	func manifest(plugin: StringName) -> Dictionary:
		return manifests.get(String(plugin), {})
	func activity_token() -> int:
		return 1
	func complete_activity(_token: int, outcome: StringName, payload: Dictionary = {}) -> void:
		finish_activity(VNPluginHost.STATUS_COMPLETED, outcome, payload)
	func reload_plugins(ids: Array) -> void:
		reloaded = ids


class Rig:
	var session: VNPreviewSession
	var methods: VNPreviewMethods
	var modules: VNModules
	var out: Array = []
	var engine: PreviewEngine
	var host: PreviewHost
	var next_id := 1

	func _init() -> void:
		modules = VNFakeModules.create()
		engine = PreviewEngine.new()
		host = PreviewHost.new()
		modules.engine = engine
		modules.plugins = host
		modules.bind_all()
		session = VNPreviewSession.new(VNPreviewSession.Transport.PANEL)
		session.outgoing.connect(func(t): out.append(JSON.parse_string(t)))
		methods = VNPreviewMethods.install(session, modules)
		session.open()
		(modules.variables as FakeVariableManager).define("global.money", &"integer", 0)
		(modules.variables as FakeVariableManager).define("sys.locale", &"string", "en")

	func call_method(method: String, params: Dictionary = {}) -> Dictionary:
		var id := next_id
		next_id += 1
		out.clear()
		await session.receive(JSON.stringify({"jsonrpc": "2.0", "id": id, "method": method, "params": params}))
		for m in out:
			if m is Dictionary and m.get("id") == id:
				return m
		return {}

	func hello() -> void:
		await call_method("session.hello", {"protocol": "1.0"})

	func load_bundle(extra: Dictionary = {}) -> Dictionary:
		var p := {"bundle_path": BUNDLE, "assets_base": ASSETS}
		p.merge(extra, true)
		return await call_method("preview.load", p)


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	for t in ["load", "load_erros", "start_e_estados", "start_erros", "pause_step_stop", "get_state",
			"set_variables", "input_basico", "input_atividades", "reload_incremental", "reload_erros",
			"reload_completo", "reload_plugins", "set_setting_locale_screen", "explain_selection"]:
		var err: String = await call("test_" + t)
		if err.is_empty():
			_passed += 1
			print("ok      ", t)
		else:
			_failed += 1
			print("FALHOU  ", t, ": ", err)
	print("%d/%d testes dos métodos do Preview passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _ready_rig() -> Rig:
	var rig := Rig.new()
	await rig.hello()
	return rig


func _err(resp: Dictionary) -> String:
	return String(resp.get("error", {}).get("data", {}).get("code", ""))


func _first_scene(rig: Rig) -> String:
	return String(rig.methods.bundle.scenes.keys()[0])


func test_load() -> String:
	var rig := await _ready_rig()
	var r := await rig.load_bundle()
	if not r.has("result"):
		return "load falhou: %s" % r
	var bundle: Dictionary = rig.methods.bundle
	if r.result.content_hash != bundle.content_hash or r.result.chapters != bundle.chapters.size() or r.result.scenes != bundle.scenes.size():
		return "resultado do load não confere: %s" % r.result
	if rig.session.state() != VNPreviewSession.LOADED:
		return "estado deveria ser LOADED"
	var assets := rig.modules.assets as FakeAssets
	if assets.assets_base != ASSETS:
		return "assets_base não chegou ao VNAssets: %s" % assets.assets_base
	if not assets.paths.has(bundle.assets.keys()[0]):
		return "bundle não chegou aos módulos"
	if rig.modules.storage.kind() != VNStorage.KIND_MEMORY:
		return "padrão deveria ser armazenamento em memória"
	var r2 := await rig.load_bundle({"user_data": "project", "user_files": {"settings.json": Marshalls.raw_to_base64("{}".to_utf8_buffer())}})
	if not r2.has("result") or rig.modules.storage.kind() != VNStorage.KIND_FOLDER or not rig.modules.storage.exists("settings.json"):
		return "user_data project com user_files: %s" % r2
	return ""


func test_load_erros() -> String:
	var rig := await _ready_rig()
	var r := await rig.call_method("preview.load", {"bundle_path": BUNDLE})
	if r.get("error", {}).get("code") != -32602:
		return "sem assets_base deveria ser -32602: %s" % r
	r = await rig.call_method("preview.load", {"bundle_path": "res://nao_existe/", "assets_base": ASSETS})
	if _err(r) != "BUNDLE_INVALID":
		return "bundle ausente deveria ser BUNDLE_INVALID: %s" % r
	r = await rig.call_method("preview.load", {"bundle_path": BUNDLE, "bundle_url": "x", "assets_base": ASSETS})
	if r.get("error", {}).get("code") != -32602:
		return "bundle_path e bundle_url juntos: %s" % r
	r = await rig.call_method("preview.load", {"bundle_path": BUNDLE, "assets_base": ASSETS, "user_files": {}})
	if r.get("error", {}).get("code") != -32602:
		return "user_files sem user_data project: %s" % r
	return ""


func test_start_e_estados() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	var r := await rig.call_method("preview.start")
	if not r.has("result") or r.result.preview != "RUNNING" or rig.session.state() != VNPreviewSession.RUNNING:
		return "start: %s" % r
	if rig.engine.count_calls(&"new_game") != 1:
		return "start sem scene deveria chamar new_game"
	await rig.call_method("preview.stop")
	if rig.session.state() != VNPreviewSession.LOADED:
		return "stop deveria voltar a LOADED"
	var scene := _first_scene(rig)
	var node: String = rig.methods.bundle.scenes[scene].nodes[0].id
	r = await rig.call_method("preview.start", {"scene": scene, "node": node, "paused": true, "variables": {"global.money": 7}})
	if not r.has("result"):
		return "start com cena: %s" % r
	if r.result.preview != "PAUSED" or rig.session.state() != VNPreviewSession.PAUSED:
		return "paused:true deveria dar PAUSED"
	if rig.engine.started_at[1] != scene or rig.engine.started_at[2] != node:
		return "start_at: %s" % [rig.engine.started_at]
	if r.result.variables.get("global.money") != 7:
		return "variables do start não aplicadas: %s" % r.result.get("variables")
	return ""


func test_start_erros() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	var r := await rig.call_method("preview.start", {"scene": "019a7a00-0000-7000-8000-000000000000"})
	if _err(r) != "NOT_FOUND" or r.error.data.kind != "scene":
		return "cena inexistente: %s" % r
	r = await rig.call_method("preview.start", {"node": "x"})
	if r.get("error", {}).get("code") != -32602:
		return "node sem scene: %s" % r
	r = await rig.call_method("preview.start", {"seed": "zz"})
	if r.get("error", {}).get("code") != -32602:
		return "seed inválida: %s" % r
	r = await rig.call_method("preview.start", {"scene": _first_scene(rig), "node": "nao-existe"})
	if _err(r) != "NOT_FOUND" or r.error.data.kind != "node":
		return "nó inexistente: %s" % r
	return ""


func test_pause_step_stop() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	await rig.call_method("preview.start")
	var r := await rig.call_method("preview.pause")
	if not r.has("result") or rig.session.state() != VNPreviewSession.PAUSED or not rig.engine.paused:
		return "pause: %s" % r
	rig.engine.goto_node("s", "n1")
	r = await rig.call_method("preview.step", {"until": "blocking"})
	if not r.has("result") or r.result.phase != "SCENE_RUNNING" or rig.engine.count_calls(&"advance") != 1:
		return "step: %s" % r
	if rig.session.state() != VNPreviewSession.PAUSED:
		return "step continua PAUSED"
	r = await rig.call_method("preview.resume")
	if not r.has("result") or rig.session.state() != VNPreviewSession.RUNNING or rig.engine.paused:
		return "resume: %s" % r
	r = await rig.call_method("preview.step")
	if _err(r) != "INVALID_PREVIEW_STATE":
		return "step em RUNNING: %s" % r
	r = await rig.call_method("preview.stop")
	if not r.has("result") or rig.engine.count_calls(&"return_to_title") < 1 or rig.host.count_calls(&"notify_game_ended") != 1:
		return "stop: %s" % r
	return ""


func test_get_state() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	var scene := _first_scene(rig)
	await rig.call_method("preview.start", {"scene": scene})
	var r := await rig.call_method("preview.get_state", {"include": ["variables"]})
	if not r.has("result") or not r.result.has("variables") or r.result.has("history") or r.result.scene != scene:
		return "include variables: %s" % r
	r = await rig.call_method("preview.get_state")
	for k in ["variables", "history", "stage", "backlog", "plugins"]:
		if not r.result.has(k):
			return "faltou %s no GameState completo" % k
	r = await rig.call_method("preview.get_state", {"include": ["xx"]})
	if r.get("error", {}).get("code") != -32602:
		return "include inválido: %s" % r
	return ""


func test_set_variables() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	await rig.call_method("preview.start", {"paused": true})
	var r := await rig.call_method("preview.set_variables", {"variables": {"global.money": 50}})
	if not r.has("result") or r.result.changes.size() != 1 or r.result.changes[0].new != 50:
		return "set_variables: %s" % r
	if rig.modules.state.count_calls(&"commit_transaction") < 1 or rig.modules.state.calls[-1].args[1] != VNStateManager.CALLER_PREVIEW:
		return "a origem deveria ser preview"
	r = await rig.call_method("preview.set_variables", {"variables": {"global.nao_existe": 1}})
	if _err(r) != "NOT_FOUND":
		return "variável inexistente: %s" % r
	r = await rig.call_method("preview.set_variables", {"variables": {"sys.locale": "pt"}})
	if _err(r) != "STATE_REJECTED" or r.error.data.vn_code != "READ_ONLY":
		return "sys.* deveria dar READ_ONLY: %s" % r
	return ""


func test_input_basico() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	await rig.call_method("preview.start")
	var r := await rig.call_method("preview.input", {"action": "advance"})
	if r.get("result", {}).get("accepted") != true or rig.engine.count_calls(&"advance") != 1:
		return "advance: %s" % r
	rig.engine.set_phase(VNPhase.TITLE)
	r = await rig.call_method("preview.input", {"action": "choose", "option": "019a7a00-0000-7000-8000-000000000001"})
	if r.get("result", {}).get("accepted") != false:
		return "choose fora de cena deveria ser recusado: %s" % r
	rig.engine.set_phase(VNPhase.SCENE_RUNNING)
	r = await rig.call_method("preview.input", {"action": "choose", "option": "019a7a00-0000-7000-8000-000000000001"})
	if r.get("result", {}).get("accepted") != true or rig.engine.count_calls(&"choose") != 2:
		return "choose: %s" % r
	r = await rig.call_method("preview.input", {"action": "click", "hotspot": "019a7a00-0000-7000-8000-000000000002"})
	if r.get("result", {}).get("accepted") != true:
		return "click: %s" % r
	r = await rig.call_method("preview.input", {"action": "choose"})
	if r.get("error", {}).get("code") != -32602:
		return "choose sem option: %s" % r
	return ""


func test_input_atividades() -> String:
	var rig := await _ready_rig()
	rig.host.manifests["probe"] = {"activities": [
		{"id": "run", "outcomes": ["win", "lose"], "free_play": {"params": {"level": 1}}},
		{"id": "story_only", "outcomes": ["win"]}]}
	await rig.load_bundle()
	rig.host.plugins = PackedStringArray(["probe"])
	# play_activity em LOADED: modo livre, params de free_play sobrepostos.
	var r := await rig.call_method("preview.input", {"action": "play_activity", "activity": "probe.run", "params": {"level": 3, "x": 1}})
	if r.get("result", {}).get("accepted") != true:
		return "play_activity: %s" % r
	var c: Dictionary = rig.host.calls.filter(func(x): return x.method == &"start_activity")[0]
	if float(c.args[1].get("level", 0)) != 3.0 or not c.args[1].has("x") or c.args[2] != VNPluginHost.MODE_FREE_PLAY:
		return "params/mode do play_activity: %s" % [c.args]
	if rig.session.state() != VNPreviewSession.LOADED:
		return "play_activity mantém LOADED"
	# skip_activity: do modo livre não é aceito; cancel_activity sai com cancelled.
	r = await rig.call_method("preview.input", {"action": "skip_activity"})
	if r.get("result", {}).get("accepted") != false:
		return "skip no modo livre deveria recusar: %s" % r
	r = await rig.call_method("preview.input", {"action": "cancel_activity"})
	if r.get("result", {}).get("accepted") != true or not rig.host.activity.is_empty():
		return "cancel_activity: %s" % r
	# Sem free_play (P020), play recusa.
	r = await rig.call_method("preview.input", {"action": "play_activity", "activity": "probe.story_only"})
	if r.get("result", {}).get("accepted") != false:
		return "sem free_play: %s" % r
	# complete_activity com outcome declarado e não declarado.
	await rig.call_method("preview.input", {"action": "play_activity", "activity": "probe.run"})
	r = await rig.call_method("preview.input", {"action": "complete_activity", "outcome": "nope"})
	if r.get("result", {}).get("accepted") != false:
		return "outcome não declarado: %s" % r
	r = await rig.call_method("preview.input", {"action": "complete_activity", "outcome": "win", "payload": {"score": 3}})
	if r.get("result", {}).get("accepted") != true or not rig.host.activity.is_empty():
		return "complete_activity: %s" % r
	r = await rig.call_method("preview.input", {"action": "complete_activity", "outcome": "win"})
	if r.get("result", {}).get("accepted") != false:
		return "complete sem atividade: %s" % r
	# skip na história: só se a atividade for skippable.
	rig.host.activity = {"activity": &"probe.run", "mode": VNPluginHost.MODE_STORY, "params": {}, "skippable": true}
	await rig.call_method("preview.start")
	r = await rig.call_method("preview.input", {"action": "skip_activity"})
	if r.get("result", {}).get("accepted") != true or rig.host.count_calls(&"cancel_activity") < 2:
		return "skip na história: %s" % r
	return ""


func test_reload_incremental() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	var scene := _first_scene(rig)
	await rig.call_method("preview.start", {"scene": scene})
	var before: Dictionary = rig.methods.bundle.duplicate(true)
	var hash_before: String = before.content_hash
	var new_scene: Dictionary = before.scenes[scene].duplicate(true)
	new_scene["title"] = "Trocada"
	var r := await rig.call_method("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/scenes/" + scene, "value": new_scene}]})
	if not r.has("result") or r.result.has("content_hash") or r.result.resumed != "node":
		return "patch de cena: %s" % r
	var after: Dictionary = rig.methods.bundle
	if after.scenes[scene] != new_scene:
		return "a cena do patch não foi trocada"
	# Só a entidade do patch muda: o resto do bundle é igual ao de antes.
	for k in before:
		if k == "scenes":
			for s in before.scenes:
				if s != scene and before.scenes[s] != after.scenes[s]:
					return "outra cena mudou: %s" % s
		elif before[k] != after[k]:
			return "%s mudou sem estar no patch" % k
	if after.content_hash != hash_before:
		return "content_hash não é recalculado na recarga incremental"
	# Asset: invalida só o id do patch.
	var assets := rig.modules.assets as FakeAssets
	assets.calls.clear()
	var asset_id: String = before.assets.keys()[0]
	r = await rig.call_method("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/assets/" + asset_id.replace("/", "~1"), "value": before.assets[asset_id]}]})
	var inv := assets.calls.filter(func(c): return c.method == &"invalidate")
	if not r.has("result") or inv.size() != 1 or inv[0].args[0] != asset_id:
		return "assets: %s / %s" % [r, inv]
	# Entidade removida: a cena atual sumiu → ponto de seleção.
	r = await rig.call_method("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/scenes/" + scene}]})
	if r.get("result", {}).get("resumed") != "selection_point" or rig.methods.bundle.scenes.has(scene):
		return "cena removida: %s" % r
	# Só ui/ → ui_only.
	var ui_id: String = rig.methods.bundle.ui.keys()[0]
	r = await rig.call_method("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/ui/" + ui_id, "value": rig.methods.bundle.ui[ui_id]}]})
	if r.get("result", {}).get("resumed") != "ui_only":
		return "ui_only: %s" % r
	if rig.methods.patches_since_full() != 4:
		return "contagem de patches: %d" % rig.methods.patches_since_full()
	return ""


func test_reload_erros() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	var scene := _first_scene(rig)
	var snapshot: Dictionary = rig.methods.bundle.duplicate(true)
	var r := await rig.call_method("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/project", "value": {}}]})
	if _err(r) != "BUNDLE_INVALID" or r.error.data.detail != "full_reload_required":
		return "/project: %s" % r
	r = await rig.call_method("preview.reload", {"patch": [
		{"file": "bundle.json", "pointer": "/scenes/" + scene},
		{"file": "bundle.json", "pointer": "/variables/global.money", "value": {}}]})
	if _err(r) != "BUNDLE_INVALID" or r.error.data.path != "/patch/1":
		return "erro na 2ª troca: %s" % r
	if rig.methods.bundle != snapshot:
		return "nada deveria ser aplicado quando uma troca falha"
	r = await rig.call_method("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/scenes/" + scene + "/title", "value": "x"}]})
	if _err(r) != "BUNDLE_INVALID":
		return "pointer abaixo da entidade: %s" % r
	r = await rig.call_method("preview.reload", {"patch": [], "changed": []})
	if r.get("error", {}).get("code") != -32602:
		return "patch vazio com changed: %s" % r
	r = await rig.call_method("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/scenes/" + scene}]})
	if r.get("result", {}).get("resumed") != "not_running":
		return "fora de partida: %s" % r
	return ""


func test_reload_completo() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	await rig.call_method("preview.start", {"scene": _first_scene(rig)})
	var r := await rig.call_method("preview.reload", {"bundle_path": BUNDLE, "changed": ["scenes/a.json"]})
	if not r.has("result") or r.result.content_hash != rig.methods.bundle.content_hash or r.result.resumed != "node":
		return "reload completo: %s" % r
	r = await rig.call_method("preview.reload", {"bundle_path": BUNDLE, "changed": ["ui/title.json", "theme.json"]})
	if r.get("result", {}).get("resumed") != "ui_only":
		return "só ui: %s" % r
	r = await rig.call_method("preview.reload", {"bundle_path": "res://nao_existe/", "changed": ["x"]})
	if _err(r) != "BUNDLE_INVALID":
		return "bundle ausente: %s" % r
	return ""


func test_reload_plugins() -> String:
	var rig := await _ready_rig()
	rig.host.plugins = PackedStringArray(["probe"])
	await rig.load_bundle()
	rig.host.plugins = PackedStringArray(["probe"])
	var r := await rig.call_method("preview.reload_plugins", {"ids": ["probe"]})
	if not r.has("result") or r.result.reloaded != ["probe"] or r.result.activity_restarted != false or rig.host.reloaded != ["probe"]:
		return "reload_plugins: %s" % r
	rig.host.activity = {"activity": &"probe.run", "mode": VNPluginHost.MODE_FREE_PLAY, "params": {"a": 1}, "skippable": false}
	r = await rig.call_method("preview.reload_plugins", {"ids": ["probe"]})
	if r.get("result", {}).get("activity_restarted") != true or rig.host.activity.is_empty():
		return "atividade deveria reiniciar: %s" % r
	r = await rig.call_method("preview.reload_plugins", {"ids": ["fantasma"]})
	if _err(r) != "NOT_FOUND":
		return "plugin inexistente: %s" % r
	return ""


func test_set_setting_locale_screen() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	var r := await rig.call_method("preview.set_setting", {"setting": "content_filter", "value": true})
	if not r.has("result") or (rig.modules.ui as FakeUIManager).get_setting(&"content_filter") != true:
		return "set_setting: %s" % r
	r = await rig.call_method("preview.set_locale", {"locale": "xx"})
	if _err(r) != "NOT_FOUND":
		return "idioma inexistente: %s" % r
	r = await rig.call_method("preview.set_locale", {"locale": "en"})
	if not r.has("result") or rig.methods.locale != "en":
		return "set_locale: %s" % r
	var ui_id: String = rig.methods.bundle.ui.keys()[0]
	r = await rig.call_method("preview.show_screen", {"screen": ui_id, "simulate": {"has_save": true}})
	var ui := rig.modules.ui as FakeUIManager
	if not r.has("result") or not ui.stack.has(ui_id) or rig.modules.variables.read("sys.ui.has_save") != true:
		return "show_screen: %s" % r
	ui.close_screen()
	r = await rig.call_method("preview.show_screen", {"screen": "nao_existe"})
	if _err(r) != "NOT_FOUND":
		return "tela inexistente: %s" % r
	return ""


func test_explain_selection() -> String:
	var rig := await _ready_rig()
	await rig.load_bundle()
	await rig.call_method("preview.start")
	var r := await rig.call_method("preview.explain_selection")
	if not r.has("result") or rig.modules.scheduler.count_calls(&"explain") != 1:
		return "explain: %s" % r
	r = await rig.call_method("preview.explain_selection", {"scene": _first_scene(rig)})
	if rig.modules.scheduler.calls[-1].args[0] != _first_scene(rig):
		return "scene não chegou ao Scheduler"
	r = await rig.call_method("preview.explain_selection", {"scene": "019a7a00-0000-7000-8000-000000000000"})
	if _err(r) != "NOT_FOUND":
		return "cena inexistente: %s" % r
	return ""
