class_name VNPreviewMethods
extends RefCounted
## Métodos [code]preview.*[/code] do Preview (Preview Protocol §3; tarefa M4-05).
##
## Registra os handlers numa [VNPreviewSession] e os liga aos módulos do runtime
## ([VNModules]). A sessão cuida de estados, [code]BUSY[/code] e [code]seq[/code]; aqui
## fica o que cada método faz.
##
## Escolhas onde a spec é omissa (também descritas no PR):
## [br]- [code]preview.start[/code] com [code]scene[/code]/[code]node[/code] chama
##   [code]engine.preview_start_at(chapter, scene, node)[/code] se o Narrative Engine o tiver
##   (o contrato do M0-07 não o prevê); sem esse método devolve [code]INTERNAL[/code];
## [br]- [code]preview.step[/code] com [code]until[/code] diferente de [code]node[/code]
##   avança por [code]engine.advance()[/code] até a condição, no máximo [constant MAX_STEPS] vezes;
## [br]- [code]plugins[/code] do [code]preview.load[/code] são os namespaces carregados pelo Plugin Host.

const MAX_STEPS := 10000
const ASSET_PREFIX := "res://vn_content/assets/"
const UI_ONLY_ENTITIES: Array[String] = ["ui", "sets", "theme"]

var session: VNPreviewSession
var modules: VNModules
## Carregador do bundle (injetável nos testes). Recebe o diretório e devolve um [VNBundleLoader].
var loader_factory: Callable = func(dir: String) -> VNBundleLoader: return VNBundleLoader.new(dir)

var bundle: Dictionary = {}
var plugins_doc: Dictionary = {}
var licenses_doc: Dictionary = {}
var locales: Dictionary = {}          # idioma → strings (só os já pedidos)
var locale: String = ""
var assets_base: String = ""
var user_data: String = "memory"
var bundle_dir: String = ""
var _patches_since_full := 0


static func install(p_session: VNPreviewSession, p_modules: VNModules) -> VNPreviewMethods:
	var m := VNPreviewMethods.new()
	m.session = p_session
	m.modules = p_modules
	p_session.modules = p_modules
	for method in ["preview.load", "preview.start", "preview.stop", "preview.pause", "preview.resume",
			"preview.step", "preview.input", "preview.set_variables", "preview.get_state",
			"preview.explain_selection", "preview.reload", "preview.reload_plugins",
			"preview.show_screen", "preview.set_setting", "preview.set_locale"]:
		p_session.register(method, Callable(m, "_" + method.trim_prefix("preview.")))
	return m


# --- load -------------------------------------------------------------------

func _load(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["bundle_path", "bundle_url", "assets_base", "locale", "user_data", "user_files"])
	if bad != null:
		return bad
	if not p.get("assets_base") is String or String(p["assets_base"]).is_empty():
		return VNPreviewError.invalid_params("assets_base é obrigatório")
	if p.has("bundle_path") == p.has("bundle_url"):
		return VNPreviewError.invalid_params("passe bundle_path ou bundle_url, e só um")
	var ud: Variant = p.get("user_data", "memory")
	if not ud in ["memory", "project"]:
		return VNPreviewError.invalid_params("user_data deve ser memory ou project")
	if p.has("user_files") and not (p["user_files"] is Dictionary and ud == "project"):
		return VNPreviewError.invalid_params("user_files só vale com user_data \"project\"")
	if p.has("bundle_url"):
		return VNPreviewError.bundle_invalid("bundle_url", "bundle_url só existe no painel Web (runtime nativo usa bundle_path)") \
			if not OS.has_feature("web") else await _load_web(p)
	var dir := String(p["bundle_path"])
	var loader: VNBundleLoader = loader_factory.call(dir)
	loader.allow_json = true   # o Preview lê a forma canônica (RT §2)
	if not loader.load_all():
		return VNPreviewError.bundle_invalid(dir, "%s: %s" % [loader.error_code, loader.error_detail])
	return _apply_loaded(loader, p)


func _load_web(_p: Dictionary) -> Variant:
	# O painel lê os arquivos pelo fetch da página (PP §1.3). A leitura é feita pela ponte Web
	# e entregue em [code]loader_factory[/code]; sem ela, não há como ler a URL.
	return VNPreviewError.bundle_invalid("bundle_url", "leitura por fetch ainda não ligada neste build")


func _apply_loaded(loader: VNBundleLoader, p: Dictionary) -> Variant:
	bundle = loader.bundle
	plugins_doc = loader.plugins
	licenses_doc = loader.licenses
	bundle_dir = loader.dir
	assets_base = String(p["assets_base"])
	user_data = String(p.get("user_data", "memory"))
	_patches_since_full = 0
	locales.clear()
	if modules.engine != null and session.state() in [VNPreviewSession.RUNNING, VNPreviewSession.PAUSED]:
		modules.engine.return_to_title()
	if modules.assets != null:
		modules.assets.set_assets_base(assets_base)
	_install_storage(p)
	modules.load_bundle(bundle)
	var proj: Dictionary = bundle.get("project", {})
	var wanted := String(p.get("locale", proj.get("default_locale", "en")))
	var err := _use_locale(wanted, loader)
	if err != null:
		return err
	if modules.plugins != null:
		modules.plugins.load_plugins(plugins_doc)
	return {
		"content_hash": String(bundle.get("content_hash", "")),
		"format_version": String(bundle.get("format_version", "")),
		"chapters": bundle.get("chapters", {}).size(),
		"scenes": bundle.get("scenes", {}).size(),
		"plugins": Array(modules.plugins.loaded_plugins()) if modules.plugins != null else [],
	}


func _install_storage(p: Dictionary) -> void:
	# PP §1.4: padrão em memória; "project" grava na pasta do projeto (janela) ou avisa o Studio (painel).
	if user_data == "memory":
		modules.storage = VNMemoryStorage.new()
	else:
		var user_dir := _value_of_cmdline("--vn-user-dir")
		var fs := VNFolderStorage.new(user_dir)
		if fs.is_panel_mode():
			var files := {}
			for path: String in p.get("user_files", {}):
				if VNStorage.is_valid_path(path):
					files[path] = Marshalls.base64_to_raw(String(p["user_files"][path]))
			fs.seed_files(files)
		modules.storage = fs
	modules.storage.bind(modules)
	if modules.saves != null:
		modules.saves.bind(modules)


static func _value_of_cmdline(flag: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


func _use_locale(wanted: String, loader: VNBundleLoader = null) -> VNPreviewError:
	var strings: Variant = locales.get(wanted)
	if strings == null:
		var ld := loader
		if ld == null:
			ld = loader_factory.call(bundle_dir)
			ld.allow_json = true
			ld.form = VNBundleLoader.FORM_JSON
		strings = ld.load_locale(wanted)
		if strings == null:
			if ld.error_code != &"":
				return VNPreviewError.bundle_invalid("locales/%s" % wanted, String(ld.error_detail))
			return VNPreviewError.not_found("locale", wanted)
		locales[wanted] = strings
	locale = wanted
	if modules.ui != null and modules.ui.has_method("set_locale_strings"):
		modules.ui.call("set_locale_strings", strings, wanted)
	if modules.state != null:
		modules.state.set_system_value("sys.locale", wanted)
	return null


# --- start / stop / pause / resume / step -----------------------------------

func _start(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["chapter", "scene", "node", "variables", "profile", "content_filter", "seed", "paused"])
	if bad != null:
		return bad
	var chapters: Dictionary = bundle.get("chapters", {})
	var scenes: Dictionary = bundle.get("scenes", {})
	var chapter := String(p.get("chapter", ""))
	var scene := String(p.get("scene", ""))
	var node := String(p.get("node", ""))
	if not chapter.is_empty() and not chapters.has(chapter):
		return VNPreviewError.not_found("chapter", chapter)
	if not scene.is_empty() and not scenes.has(scene):
		return VNPreviewError.not_found("scene", scene)
	if not node.is_empty():
		if scene.is_empty():
			return VNPreviewError.invalid_params("node exige scene")
		if not _node_ids(scene).has(node):
			return VNPreviewError.not_found("node", node)
	if p.has("seed") and not (p["seed"] is String and VNPreviewSession._matches(p["seed"], "^[0-9a-f]{16}$")):
		return VNPreviewError.invalid_params("seed deve ter 16 dígitos hex")
	if p.has("variables") and not p["variables"] is Dictionary:
		return VNPreviewError.invalid_params("variables deve ser um objeto")
	if p.has("content_filter") and modules.ui != null:
		modules.ui.set_setting(&"content_filter", bool(p["content_filter"]))
	if p.has("profile") and modules.saves != null and modules.saves.has_method("set_session_profile"):
		modules.saves.call("set_session_profile", p["profile"])
	var engine := modules.engine
	if scene.is_empty():
		if not chapter.is_empty() and engine.has_method("preview_start_at"):
			engine.call("preview_start_at", chapter, "", "")
		else:
			engine.new_game()
	elif engine.has_method("preview_start_at"):
		if chapter.is_empty():
			chapter = String(scenes[scene].get("chapter", ""))
		engine.call("preview_start_at", chapter, scene, node)
	else:
		return VNPreviewError.internal("o Narrative Engine não implementa preview_start_at")
	if p.has("variables"):
		var r: Variant = _write_variables(p["variables"])
		if r is VNPreviewError:
			return r
	if bool(p.get("paused", false)):
		engine.set_paused(true)
	var state := _game_state(["variables", "history", "stage", "backlog", "plugins"])
	state["preview"] = "PAUSED" if bool(p.get("paused", false)) else "RUNNING"
	return state


func _stop(_p: Dictionary) -> Variant:
	modules.engine.return_to_title()
	if modules.plugins != null:
		modules.plugins.notify_game_ended()
	return {}


func _pause(_p: Dictionary) -> Variant:
	modules.engine.set_paused(true)
	return {"node": _or_null(modules.engine.current_node())}


func _resume(_p: Dictionary) -> Variant:
	modules.engine.set_paused(false)
	return {"node": _or_null(modules.engine.current_node())}


func _step(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["until"])
	if bad != null:
		return bad
	var until := String(p.get("until", "node"))
	if not until in ["node", "blocking", "scene_end", "selection"]:
		return VNPreviewError.invalid_params("until inválido: %s" % until)
	var engine := modules.engine
	var start_node := engine.current_node()
	var start_scene := engine.current_scene()
	var steps := 0
	engine.set_paused(false)
	while steps < MAX_STEPS:
		steps += 1
		engine.advance()
		match until:
			"node":
				if engine.current_node() != start_node:
					break
			"blocking":
				break
			"scene_end":
				if engine.current_scene() != start_scene or engine.phase() != VNPhase.SCENE_RUNNING:
					break
			"selection":
				if engine.phase() in [VNPhase.SELECTION_POINT, VNPhase.GAME_END, VNPhase.TITLE]:
					break
		if engine.phase() in [VNPhase.GAME_END, VNPhase.TITLE]:
			break
	engine.set_paused(true)
	return {"node": _or_null(engine.current_node()), "phase": String(engine.phase())}


# --- input ------------------------------------------------------------------

func _input(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["action", "option", "hotspot", "outcome", "payload", "activity", "params"])
	if bad != null:
		return bad
	var action := String(p.get("action", ""))
	var plugins := modules.plugins
	match action:
		"advance":
			modules.engine.advance()
			return {"accepted": true}
		"choose":
			if not p.get("option") is String:
				return VNPreviewError.invalid_params("choose exige option")
			return {"accepted": modules.engine.choose(String(p["option"])).ok}
		"click":
			if not p.get("hotspot") is String:
				return VNPreviewError.invalid_params("click exige hotspot")
			return {"accepted": modules.engine.choose(String(p["hotspot"])).ok}
		"skip_activity":
			var cur := plugins.current_activity()
			if cur.is_empty() or cur.get("mode") != VNPluginHost.MODE_STORY or not bool(cur.get("skippable", false)):
				return {"accepted": false}
			plugins.cancel_activity(VNPluginHost.STATUS_SKIPPED)
			return {"accepted": true}
		"cancel_activity":
			var cur2 := plugins.current_activity()
			if cur2.is_empty() or cur2.get("mode") != VNPluginHost.MODE_FREE_PLAY:
				return {"accepted": false}
			plugins.cancel_activity(VNPluginHost.STATUS_CANCELLED)
			return {"accepted": true}
		"complete_activity":
			return _complete_activity(p)
		"play_activity":
			return _play_activity(p)
	return VNPreviewError.invalid_params("action desconhecida: %s" % action)


func _complete_activity(p: Dictionary) -> Variant:
	if not p.get("outcome") is String:
		return VNPreviewError.invalid_params("complete_activity exige outcome")
	var plugins := modules.plugins
	var cur := plugins.current_activity()
	if cur.is_empty():
		return {"accepted": false}
	var decl := _activity_decl(String(cur.get("activity", "")))
	var outcomes: Array = decl.get("outcomes", [])
	if not outcomes.is_empty() and not outcomes.has(p["outcome"]):
		return {"accepted": false}
	if p.has("payload") and not p["payload"] is Dictionary:
		return VNPreviewError.invalid_params("payload deve ser um objeto")
	# Como se o plugin chamasse complete (Plugin SDK §6): pelo token da atividade em curso.
	if plugins.has_method("activity_token") and plugins.has_method("complete_activity"):
		plugins.call("complete_activity", plugins.call("activity_token"), StringName(p["outcome"]), p.get("payload", {}))
		return {"accepted": true}
	return VNPreviewError.internal("o Plugin Host não aceita complete_activity")


func _play_activity(p: Dictionary) -> Variant:
	if not p.get("activity") is String:
		return VNPreviewError.invalid_params("play_activity exige activity")
	var decl := _activity_decl(String(p["activity"]))
	if decl.is_empty() or not decl.has("free_play"):
		return {"accepted": false}   # sem free_play (P020)
	var params: Dictionary = decl["free_play"].get("params", {}).duplicate(true) if decl["free_play"] is Dictionary else {}
	params.merge(p.get("params", {}), true)
	return {"accepted": modules.plugins.start_activity(StringName(p["activity"]), params, VNPluginHost.MODE_FREE_PLAY).ok}


func _activity_decl(activity: String) -> Dictionary:
	## A declaração vem do [code]plugin.json[/code] lido pelo Plugin Host (activities é uma lista).
	var ns := activity.get_slice(".", 0)
	var name := activity.get_slice(".", 1)
	var host := modules.plugins
	if host == null or not host.has_method("manifest"):
		return {}
	var acts: Variant = host.call("manifest", StringName(ns)).get("activities", [])
	if acts is Array:
		for a in acts:
			if a is Dictionary and a.get("id") == name:
				return a
	return {}


# --- variáveis e estado -----------------------------------------------------

func _set_variables(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["variables"])
	if bad != null:
		return bad
	if not p.get("variables") is Dictionary:
		return VNPreviewError.invalid_params("variables deve ser um objeto")
	var r: Variant = _write_variables(p["variables"])
	if r is VNPreviewError:
		return r
	return {"changes": r}


## Uma transação com origem [code]preview[/code] (PP §3). Devolve as mudanças ou um erro.
func _write_variables(values: Dictionary) -> Variant:
	var tx := modules.state.begin_transaction(VNStateManager.CALLER_PREVIEW)
	for id in values:
		tx.ops.append({"op": "set", "variable": String(id), "value": values[id]})
	var r := tx.commit()
	if not r.ok:
		if r.error == VNErrors.VARIABLE_NOT_FOUND:
			return VNPreviewError.not_found("variable", _first_key(values))
		return VNPreviewError.state_rejected(r.error, r.message)
	return r.changes


func _get_state(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["include"])
	if bad != null:
		return bad
	var include: Array = p.get("include", ["variables", "history", "stage", "backlog", "plugins"])
	for x in include:
		if not x in ["variables", "history", "stage", "backlog", "plugins"]:
			return VNPreviewError.invalid_params("include inválido: %s" % x)
	return _game_state(include)


## [code]GameState[/code] (PP §5).
func _game_state(include: Array) -> Dictionary:
	var e := modules.engine
	var out := {
		"phase": String(e.phase()),
		"preview": "PAUSED" if session.state() == VNPreviewSession.PAUSED or e.is_paused() else "RUNNING",
		"chapter": _or_null(e.current_chapter()),
		"scene": _or_null(e.current_scene()),
		"node": _or_null(e.current_node()),
	}
	if "variables" in include and modules.variables != null:
		var vars := {}
		for id in modules.variables.ids():
			var v: Variant = modules.variables.read(id)
			if v is bool or v is int or v is float or v is String:
				vars[id] = v
		out["variables"] = vars
	if "history" in include and modules.scheduler != null:
		out["history"] = modules.scheduler.get_history()
	if "stage" in include and modules.stage != null:
		out["stage"] = modules.stage.snapshot()
	if "backlog" in include:
		var bl: Array = e.snapshot().get("backlog", [])
		out["backlog"] = bl.slice(maxi(0, bl.size() - 50))
	if "plugins" in include and modules.plugins != null:
		var pl := {}
		var cur := modules.plugins.current_activity()
		for ns in modules.plugins.loaded_plugins():
			pl[ns] = {"enabled": true, "faulted": modules.plugins.is_faulted(StringName(ns)),
				"activity": String(cur.get("activity", "")) if String(cur.get("activity", "")).begins_with(ns + ".") else null}
		out["plugins"] = pl
	return out


func _explain_selection(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["scene"])
	if bad != null:
		return bad
	var scene := String(p.get("scene", ""))
	if not scene.is_empty() and not bundle.get("scenes", {}).has(scene):
		return VNPreviewError.not_found("scene", scene)
	return modules.scheduler.explain(scene)


# --- reload -----------------------------------------------------------------

func _reload(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["patch", "bundle_path", "bundle_url", "changed"])
	if bad != null:
		return bad
	if p.has("patch"):
		if p.has("bundle_path") or p.has("bundle_url") or p.has("changed"):
			return VNPreviewError.invalid_params("patch não combina com bundle_path/bundle_url/changed")
		return _reload_patch(p["patch"])
	if p.has("bundle_path") and p.has("changed"):
		return _reload_full(p)
	return VNPreviewError.invalid_params("passe patch, ou bundle_path com changed")


func _reload_patch(patch: Variant) -> Variant:
	if not (patch is Array and not patch.is_empty()):
		return VNPreviewError.invalid_params("patch deve ser uma lista não vazia")
	# Aplica numa cópia: erro de uma troca não deixa nada aplicado (PP §3).
	var work_bundle := bundle.duplicate(false)
	var work_licenses := licenses_doc.duplicate(false)
	var work_locales := locales.duplicate(false)
	var touched: Dictionary = {}   # entidade → true
	var changed_assets: PackedStringArray = []
	var locale_changed := false
	for i in patch.size():
		var sw: Variant = patch[i]
		if not (sw is Dictionary and sw.get("file") is String and sw.get("pointer") is String):
			return VNPreviewError.bundle_invalid("/patch/%d" % i, "troca precisa de file e pointer")
		var file := String(sw["file"])
		var parts := _pointer_parts(String(sw["pointer"]))
		if parts.is_empty():
			return VNPreviewError.bundle_invalid("/patch/%d" % i, "pointer inválido")
		var has_value: bool = sw.has("value")
		if file == "bundle.json":
			var top := String(parts[0])
			if top in ["project", "variables", "aliases"] or top == "plugins":
				return VNPreviewError.bundle_invalid("/patch/%d" % i, "full_reload_required")
			if not top in ["scenes", "chapters", "characters", "ui", "sets", "assets", "theme"]:
				return VNPreviewError.bundle_invalid("/patch/%d" % i, "entidade desconhecida: %s" % top)
			if top == "theme":
				if parts.size() != 1 or not has_value:
					return VNPreviewError.bundle_invalid("/patch/%d" % i, "theme só é trocado inteiro")
				work_bundle["theme"] = sw["value"]
			else:
				if parts.size() != 2:
					return VNPreviewError.bundle_invalid("/patch/%d" % i, "pointer deve ir até uma entidade inteira")
				var coll: Dictionary = work_bundle.get(top, {}).duplicate(false)
				if has_value:
					coll[parts[1]] = sw["value"]
				else:
					coll.erase(parts[1])
				work_bundle[top] = coll
				if top == "assets":
					changed_assets.append(String(parts[1]))
			touched[top] = true
		elif file == "licenses.json":
			if parts != PackedStringArray(["entries"]) or not has_value:
				return VNPreviewError.bundle_invalid("/patch/%d" % i, "licenses.json: só /entries")
			work_licenses["entries"] = sw["value"]
		elif file.begins_with("locales/"):
			var lang := file.trim_prefix("locales/").trim_suffix(".json")
			if parts[0] != "strings" or parts.size() != 2:
				return VNPreviewError.bundle_invalid("/patch/%d" % i, "idioma: só /strings/<caminho>")
			var strings: Dictionary = work_locales.get(lang, {}).duplicate(false)
			if has_value:
				strings[parts[1]] = sw["value"]
			else:
				strings.erase(parts[1])
			work_locales[lang] = strings
			locale_changed = locale_changed or lang == locale
	var scene_before := modules.engine.current_scene()
	var node_before := modules.engine.current_node()
	bundle = work_bundle
	licenses_doc = work_licenses
	locales = work_locales
	_patches_since_full += 1
	for id in changed_assets:
		if modules.assets != null:
			modules.assets.invalidate(id)
	modules.load_bundle(bundle)
	if modules.ui != null and modules.ui.has_method("set_licenses"):
		modules.ui.call("set_licenses", licenses_doc)
	if locale_changed and locales.has(locale):
		_use_locale(locale)
	return {"resumed": _resume_kind(touched.keys(), scene_before, node_before)}


func _reload_full(p: Dictionary) -> Variant:
	var changed: Variant = p.get("changed")
	if not (changed is Array):
		return VNPreviewError.invalid_params("changed deve ser uma lista")
	var scene_before := modules.engine.current_scene()
	var node_before := modules.engine.current_node()
	var dir := String(p["bundle_path"])
	var loader: VNBundleLoader = loader_factory.call(dir)
	loader.allow_json = true
	if not loader.load_all():
		return VNPreviewError.bundle_invalid(dir, "%s: %s" % [loader.error_code, loader.error_detail])
	var old_assets: Dictionary = bundle.get("assets", {})
	bundle = loader.bundle
	plugins_doc = loader.plugins
	licenses_doc = loader.licenses
	bundle_dir = loader.dir
	locales.clear()
	_patches_since_full = 0
	for id in old_assets:
		if bundle.get("assets", {}).get(id) != old_assets[id] and modules.assets != null:
			modules.assets.invalidate(String(id))
	modules.load_bundle(bundle)
	if modules.ui != null and modules.ui.has_method("set_licenses"):
		modules.ui.call("set_licenses", licenses_doc)
	var err := _use_locale(locale if not locale.is_empty() else String(bundle.get("project", {}).get("default_locale", "en")), loader)
	if err != null:
		return err
	var only_ui: bool = not changed.is_empty()
	for c in changed:
		if not (String(c).begins_with("ui/") or String(c).begins_with("sets/") or String(c) == "theme.json"):
			only_ui = false
	var kind := "ui_only" if only_ui else _resume_kind(["scenes"], scene_before, node_before)
	return {"content_hash": String(bundle.get("content_hash", "")), "resumed": kind}


## Onde o jogo continua depois da recarga (PP §3).
func _resume_kind(touched: Array, scene_before: String, node_before: String) -> String:
	if not session.state() in [VNPreviewSession.RUNNING, VNPreviewSession.PAUSED]:
		return "not_running"
	if not touched.is_empty() and touched.all(func(t): return t in UI_ONLY_ENTITIES):
		return "ui_only"
	if scene_before.is_empty():
		return "selection_point"
	if not bundle.get("scenes", {}).has(scene_before):
		return "selection_point"
	if not node_before.is_empty() and not _node_ids(scene_before).has(node_before):
		return "scene_restarted"
	return "node"


## Quantas recargas incrementais desde a última completa (o Studio confere o estado a cada 50).
func patches_since_full() -> int:
	return _patches_since_full


func _reload_plugins(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["ids"])
	if bad != null:
		return bad
	if not (p.get("ids") is Array and not p["ids"].is_empty()):
		return VNPreviewError.invalid_params("ids deve ser uma lista não vazia")
	var host := modules.plugins
	for id in p["ids"]:
		if not host.is_loaded(StringName(id)) and not host.loaded_plugins().has(String(id)):
			return VNPreviewError.not_found("plugin", String(id))
	var cur := host.current_activity()
	var restarted := false
	var params: Dictionary = {}
	var activity := StringName(String(cur.get("activity", "")))
	var mode: StringName = cur.get("mode", VNPluginHost.MODE_STORY)
	if not cur.is_empty() and String(cur["activity"]).get_slice(".", 0) in p["ids"]:
		params = cur.get("params", {})
		host.cancel_activity(VNPluginHost.STATUS_CANCELLED)
		restarted = true
	if host.has_method("reload_plugins"):
		host.call("reload_plugins", p["ids"])
	else:
		host.load_plugins(plugins_doc)
	if restarted:
		restarted = host.start_activity(activity, params, mode).ok
	return {"reloaded": p["ids"].map(func(i): return String(i)), "activity_restarted": restarted}


# --- telas e configurações --------------------------------------------------

func _show_screen(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["screen", "simulate"])
	if bad != null:
		return bad
	var screen := String(p.get("screen", ""))
	if not bundle.get("ui", {}).has(screen):
		return VNPreviewError.not_found("screen", screen)
	var sim: Variant = p.get("simulate", {})
	if not sim is Dictionary:
		return VNPreviewError.invalid_params("simulate deve ser um objeto")
	var map := {"has_save": "sys.ui.has_save", "in_game": "sys.ui.in_game", "platform": "sys.ui.platform",
		"content_filter": "sys.ui.content_filter", "content_filter_available": "sys.ui.content_filter_available",
		"last_activity_outcome": "sys.ui.last_activity_outcome", "last_record_rank": "sys.ui.last_record_rank"}
	var saved := {}
	for key in sim:
		if map.has(key):
			saved[map[key]] = modules.variables.read(map[key])
			modules.state.set_system_value(map[key], sim[key])
		elif key == "endings":
			for ending in sim["endings"]:
				var id := "sys.endings.%s" % ending
				saved[id] = modules.variables.read(id)
				modules.state.set_system_value(id, true)
		elif not key in ["seen_assets", "gallery_unlock_all"]:
			return VNPreviewError.invalid_params("simulate: campo desconhecido: %s" % key)
	modules.ui.open_screen(screen)
	# Os valores fingidos valem só enquanto a tela está aberta (PP §3).
	if not saved.is_empty():
		var ui := modules.ui
		var restore := func():
			if not ui.screen_stack().has(screen):
				for id in saved:
					modules.state.set_system_value(id, saved[id])
		ui.screens_changed.connect(func(_s): restore.call())
	return {}


func _set_setting(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["setting", "value"])
	if bad != null:
		return bad
	if not p.get("setting") is String or not p.has("value"):
		return VNPreviewError.invalid_params("setting e value são obrigatórios")
	var r := modules.ui.set_setting(StringName(p["setting"]), p["value"])
	if not r.ok:
		return VNPreviewError.invalid_params("%s: %s" % [r.error, r.message])
	return {}


func _set_locale(p: Dictionary) -> Variant:
	var bad := _check_keys(p, ["locale"])
	if bad != null:
		return bad
	if not p.get("locale") is String:
		return VNPreviewError.invalid_params("locale é obrigatório")
	var err := _use_locale(String(p["locale"]))
	return err if err != null else {}


# --- auxiliares -------------------------------------------------------------

func _node_ids(scene_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var scene: Variant = bundle.get("scenes", {}).get(scene_id)
	if scene is Dictionary:
		var nodes: Variant = scene.get("nodes")
		if nodes is Array:
			for n in nodes:
				if n is Dictionary:
					out.append(String(n.get("id", "")))
		elif nodes is Dictionary:
			out.append_array(PackedStringArray(nodes.keys()))
	return out


static func _pointer_parts(pointer: String) -> PackedStringArray:
	if not pointer.begins_with("/"):
		return PackedStringArray()
	var out := PackedStringArray()
	for raw in pointer.substr(1).split("/"):
		if raw.is_empty():
			return PackedStringArray()
		out.append(raw.replace("~1", "/").replace("~0", "~"))
	return out


static func _check_keys(p: Dictionary, allowed: Array) -> VNPreviewError:
	for key in p:
		if not String(key) in allowed:
			return VNPreviewError.invalid_params("campo desconhecido: %s" % key)
	return null


static func _or_null(s: String) -> Variant:
	return null if s.is_empty() else s


static func _first_key(d: Dictionary) -> String:
	return String(d.keys()[0]) if not d.is_empty() else ""
