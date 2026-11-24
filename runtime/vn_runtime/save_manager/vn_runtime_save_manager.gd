class_name VNRuntimeSaveManager
extends VNSaveManager
## Save Manager do runtime (RT §8): slots, Continuar, autosave, assinatura e
## perfil, sempre pelo [VNStorage] do registro.
##
## Configuração do build (BS §4.4): lê [code]SAVE_KEY[/code],
## [code]SAVE_TAMPER_POLICY[/code], [code]DEBUG_BUILD[/code] e
## [code]RUNTIME_VERSION[/code] de [code]res://vn_runtime/build_config.gd[/code]
## quando ele existe. Sem ele (editor, [code]--vn-bundle[/code], testes), usa a
## chave fixa de debug e a política [code]flag[/code] (RT §2.1, BS §11.1).
## [method configure] troca esses valores (Preview, testes).
##
## Specs: RT §3.0 passo 4, §3.4, §8.1–§8.5; BS §8.3, §11.1; save.schema.json;
## Plugin SDK §9.1. Tarefa: M2-10 (M2-11 refina o perfil e a migração; M2-13 a
## galeria; M3-06 os recordes).

const SAVE_FORMAT := "1.0.0"
const SUPPORTED_SAVE_MAJOR := 1
const DEFAULT_RUNTIME_VERSION := "1.0.0"
const PROFILE_PATH := "profile.json"
const PROFILE_REJECTED_PATH := "profile.rejected.json"
const BUILD_CONFIG_PATH := "res://vn_runtime/build_config.gd"
const THUMBNAIL_SIZE := Vector2i(320, 180)

## Políticas de [code]build.protection.save_tamper[/code] (BS §8.3).
const TAMPER_IGNORE := &"ignore"
const TAMPER_FLAG := &"flag"
const TAMPER_REJECT := &"reject"

## Mensagens do BS §13.1 mostradas pelo Save Manager.
const MESSAGE_SAVE_REJECTED := "runtime/message/g003"
const MESSAGE_SAVE_INCOMPATIBLE := "runtime/message/g004"
const MESSAGE_PROFILE_REJECTED := "runtime/message/g006"

## Valores de [code]project.settings.autosave[/code].
const AUTOSAVE_OFF := "off"
const AUTOSAVE_AT_SCENE_START := "scene_start"
const AUTOSAVE_AT_SELECTION := "selection_point"

## Quadros de recordes sem declaração (M3-06 passa a usar o manifesto).
const DEFAULT_RECORD_KEEP := 10

var _save_key: PackedByteArray = VNCanonicalJson.debug_key()
var _tamper_policy: StringName = TAMPER_FLAG
var _debug_build: bool = true
var _runtime_version: String = DEFAULT_RUNTIME_VERSION

var _project_id: String = ""
var _project_version: String = "0.0.0"
var _content_hash: String = ""
var _autosave_setting: String = AUTOSAVE_AT_SELECTION

var _profile: Dictionary = {}
var _profile_loaded: bool = false
var _profile_dirty: bool = false
var _profile_modified: bool = false
var _save_modified: bool = false
var _record_boards: Dictionary = {}   # "<ns>/<board>" → { order, keep }
var _engine_ref: WeakRef = null   # Engine ligado ao debounce do perfil


func _init() -> void:
	_profile = _empty_profile()
	_read_build_config()


## Troca a configuração do build: [code]save_key[/code] (PackedByteArray ou
## base64), [code]save_tamper[/code] ([code]ignore[/code]/[code]flag[/code]/[code]reject[/code]),
## [code]debug_build[/code] e [code]runtime_version[/code]. Em build de debug a
## política vale sempre [code]flag[/code] (BS §11.1).
func configure(options: Dictionary) -> void:
	if options.has("save_key"):
		var key: Variant = options.save_key
		_save_key = Marshalls.base64_to_raw(key) if key is String else PackedByteArray(key)
	if options.has("save_tamper"):
		_tamper_policy = StringName(options.save_tamper)
	if options.has("debug_build"):
		_debug_build = bool(options.debug_build)
	if options.has("runtime_version"):
		_runtime_version = String(options.runtime_version)


## A política efetiva de assinatura inválida.
func tamper_policy() -> StringName:
	return TAMPER_FLAG if _debug_build else _tamper_policy


## O último save carregado ou o perfil tinham assinatura inválida ([code]sys.save_modified[/code]).
func is_modified() -> bool:
	return _save_modified or _profile_modified


func _read_build_config() -> void:
	if not ResourceLoader.exists(BUILD_CONFIG_PATH):
		return
	var script: Script = load(BUILD_CONFIG_PATH)
	if script == null:
		return
	var c := script.get_script_constant_map()
	var options := {}
	if c.has("SAVE_KEY"):
		options.save_key = c.SAVE_KEY
	if c.has("SAVE_TAMPER_POLICY"):
		options.save_tamper = c.SAVE_TAMPER_POLICY
	if c.has("DEBUG_BUILD"):
		options.debug_build = c.DEBUG_BUILD
	if c.has("RUNTIME_VERSION"):
		options.runtime_version = c.RUNTIME_VERSION
	configure(options)


func bind(p_modules: VNModules) -> void:
	super.bind(p_modules)
	# Debounce do perfil (RT §8.5): grava em cada ponto de seleção, ao fim do jogo e no título.
	var engine := p_modules.engine if p_modules != null else null
	var previous: VNNarrativeEngine = _engine_ref.get_ref() if _engine_ref != null else null
	if engine == previous:
		return
	if previous != null and previous.phase_changed.is_connected(_on_phase_changed):
		previous.phase_changed.disconnect(_on_phase_changed)
	_engine_ref = weakref(engine) if engine != null else null
	if engine != null:
		engine.phase_changed.connect(_on_phase_changed)


func load_bundle(bundle: Dictionary) -> void:
	var project: Dictionary = bundle.get("project", {})
	_project_id = String(project.get("id", ""))
	_project_version = String(project.get("version", "0.0.0"))
	_content_hash = String(bundle.get("content_hash", ""))
	var settings: Dictionary = project.get("settings", {})
	_autosave_setting = String(settings.get("autosave", AUTOSAVE_AT_SELECTION))
	_profile.project_id = _project_id


func _on_phase_changed(phase: StringName, _previous: StringName) -> void:
	if _profile_dirty and phase in [VNPhase.SELECTION_POINT, VNPhase.GAME_END, VNPhase.TITLE]:
		flush_profile()


# --- Slots --------------------------------------------------------------------

## O slot é um nome aceito: [constant QUICK], [code]slot_1[/code]…[code]slot_99[/code] ou [code]auto_1[/code]…[code]auto_3[/code].
static func is_valid_slot(slot: StringName) -> bool:
	return _slot_order(slot) >= 0


## Posição do slot na ordem das telas (rápido, manuais, autosaves); −1 se inválido.
static func _slot_order(slot: StringName) -> int:
	var s := String(slot)
	if s == String(QUICK):
		return 0
	for kind in [["slot_", MAX_MANUAL_SLOTS, 0], ["auto_", AUTOSAVE_SLOTS, MAX_MANUAL_SLOTS]]:
		if s.begins_with(kind[0]):
			var n := s.substr(kind[0].length())
			if n.is_valid_int() and not n.begins_with("0") and int(n) >= 1 and int(n) <= kind[1]:
				return kind[2] + int(n)
	return -1


static func _is_auto_slot(slot: StringName) -> bool:
	return String(slot).begins_with("auto_")


func _storage() -> VNStorage:
	return modules().storage if modules() != null else null


func save(slot: StringName, label: String = "") -> VNResult:
	if not is_valid_slot(slot) or _is_auto_slot(slot):
		return VNResult.failure(VNErrors.INVALID_STATE, "slot inválido para save manual: %s" % slot)
	var engine := modules().engine
	if engine != null and not engine.can_save(VNNarrativeEngine.SAVE_MANUAL):
		return VNResult.failure(VNErrors.INVALID_STATE, "não é possível salvar agora (RT §8.1)")
	return _write_save(slot, label, false)


func autosave(reason: StringName) -> VNResult:
	var kind := VNNarrativeEngine.SAVE_MANUAL
	match reason:
		AUTOSAVE_ACTIVITY:
			kind = VNNarrativeEngine.SAVE_ACTIVITY
		AUTOSAVE_SCENE_START:
			if _autosave_setting != AUTOSAVE_AT_SCENE_START:
				return VNResult.success()
			kind = VNNarrativeEngine.SAVE_SCENE_START
		AUTOSAVE_SETTINGS:
			if _autosave_setting != AUTOSAVE_AT_SELECTION:
				return VNResult.success()
		_:
			return VNResult.failure(VNErrors.INVALID_STATE, "motivo de autosave desconhecido: %s" % reason)
	var engine := modules().engine
	if engine != null and not engine.can_save(kind):
		return VNResult.failure(VNErrors.INVALID_STATE, "não é possível salvar agora (RT §8.1)")
	return _write_save(_next_auto_slot(), "", true)


## Rodízio: o primeiro autosave vazio; senão, o mais antigo.
func _next_auto_slot() -> StringName:
	var oldest := auto_slot(1)
	var oldest_at := INF
	for n in range(1, AUTOSAVE_SLOTS + 1):
		var slot := auto_slot(n)
		var data: Variant = _read_save(slot)
		if not data is Dictionary:
			return slot
		var at := _timestamp(String(data.get("created_at", "")))
		if at < oldest_at:
			oldest_at = at
			oldest = slot
	return oldest


func _write_save(slot: StringName, label: String, is_autosave: bool) -> VNResult:
	var storage := _storage()
	var data := build_save(label)
	var stage := modules().stage
	if stage != null:
		var image := stage.capture_thumbnail()
		if image != null and not image.is_empty():
			image = image.duplicate()
			if image.get_size() != THUMBNAIL_SIZE:
				image.resize(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, Image.INTERPOLATE_BILINEAR)
			if storage.write_bytes(thumbnail_path(slot), image.save_png_to_buffer()) == OK:
				data.thumbnail = thumbnail_path(slot)
		if stage.is_showing_sensitive():
			data.thumbnail_sensitive = true
	if not data.has("thumbnail") and storage.exists(thumbnail_path(slot)):
		storage.delete(thumbnail_path(slot))
	var err := _write_signed(slot_path(slot), data)
	if err != OK:
		return VNResult.failure(VNErrors.INVALID_STATE, "não gravou %s: %s" % [slot_path(slot), error_string(err)])
	saved.emit(slot, is_autosave)
	return VNResult.success()


## Assina e grava em JSON canônico (a forma que a assinatura cobre).
func _write_signed(path: String, data: Dictionary) -> Error:
	var stable: Dictionary = VNCanonicalJson.stabilize(data)
	stable.erase("integrity")
	stable.integrity = VNCanonicalJson.signature(stable, _save_key)
	return _storage().write_text(path, VNCanonicalJson.stringify(stable))


## O save lido, [code]null[/code] se não existe e [code]false[/code] se não é JSON.
func _read_save(slot: StringName) -> Variant:
	var storage := _storage()
	if storage == null or not storage.exists(slot_path(slot)):
		return null
	return _read_json_quiet(slot_path(slot))


## JSON do arquivo sem registrar erro no log (arquivo corrompido não é erro do
## runtime); [code]false[/code] se não é JSON.
func _read_json_quiet(path: String) -> Variant:
	var json := JSON.new()
	if json.parse(_storage().read_text(path)) != OK:
		return false
	return json.data


func build_save(label: String = "") -> Dictionary:
	var m := modules()
	var engine_part: Dictionary = m.engine.snapshot() if m.engine != null else {}
	var scene: Variant = engine_part.get("scene")
	if scene is Dictionary:
		scene = scene.duplicate(true)
		var stage_part: Dictionary = m.stage.snapshot().duplicate(true) if m.stage != null else {}
		if m.audio != null:
			stage_part["audio"] = m.audio.snapshot()
		scene["stage"] = stage_part
	var state := {
		"variables": m.variables.save_values() if m.variables != null else {},
		"chapter": engine_part.get("chapter"),
		"scene": scene,
		"history": m.scheduler.get_history() if m.scheduler != null else {"selection_count": 0, "scenes": {}},
		"plugins": m.plugins.save_data() if m.plugins != null else {},
		"backlog": engine_part.get("backlog", []),
	}
	# O RNG reproduzível (RT §12.2) não tem módulo próprio no contrato: vem do Engine, se houver.
	if engine_part.get("rng") is Dictionary:
		state["rng"] = engine_part.rng
	var project := {"id": _project_id, "version": _project_version}
	if not _content_hash.is_empty():
		project["content_hash"] = _content_hash
	return {
		"save_format": SAVE_FORMAT,
		"project": project,
		"runtime_version": _runtime_version,
		"created_at": _now_iso(),
		"label": label,
		"state": state,
	}


# --- Carregamento (RT §8.3) ---------------------------------------------------

func load_slot(slot: StringName) -> VNResult:
	if not is_valid_slot(slot):
		return VNResult.failure(VNErrors.INVALID_STATE, "slot inválido: %s" % slot)
	var data: Variant = _read_save(slot)
	if data == null:
		return VNResult.failure(VNErrors.INVALID_STATE, "save não existe: %s" % slot)
	return load_save_data(data, slot)


## Carrega um save já lido (o [code]load_slot[/code] sem o arquivo; o Preview usa).
func load_save_data(data: Variant, slot: StringName = &"") -> VNResult:
	var m := modules()
	# 1. Valida e confere a assinatura.
	var problem := validate_save(data)
	if not problem.is_empty():
		push_warning("Save %s recusado: %s" % [slot, problem])
		_show_message(MESSAGE_SAVE_INCOMPATIBLE)
		return VNResult.failure(VNErrors.INVALID_STATE, problem)
	var doc: Dictionary = data
	var valid := VNCanonicalJson.verify(doc, _save_key)
	var policy := tamper_policy()
	if not valid and policy == TAMPER_REJECT:
		push_warning("Save %s recusado: assinatura inválida (save_tamper: reject)" % slot)
		_show_message(MESSAGE_SAVE_REJECTED)
		return VNResult.failure(VNErrors.INVALID_STATE, "assinatura inválida")
	if not valid and policy == TAMPER_FLAG:
		push_warning("Save %s com assinatura inválida: sys.save_modified ligado (BS §8.3)" % slot)
	_save_modified = not valid and policy == TAMPER_FLAG
	var state: Dictionary = doc.state

	# 2. Jogo em andamento: _vn_game_ended() nos plugins.
	if m.engine != null and VNPhase.is_in_game(m.engine.phase()) and m.plugins != null:
		m.plugins.notify_game_ended()

	# 3. Defaults → perfil → variáveis do save (com chapter.*/scene.* ativas).
	var warnings := PackedStringArray()
	if m.variables != null:
		m.variables.reset_game()
		m.variables.apply_profile(_profile.get("variables", {}))
		var chapter: Variant = state.get("chapter")
		if chapter is Dictionary:
			m.variables.enter_chapter(String(chapter.id))
		var scene: Variant = state.get("scene")
		if scene is Dictionary:
			m.variables.enter_scene(String(scene.id))
		warnings = m.variables.restore_save_values(state.get("variables", {}))
		for w in warnings:
			push_warning("Save %s: %s" % [slot, w])
	if m.state != null:
		m.state.set_system_value("sys.save_modified", is_modified())

	# 4. Histórico (o capítulo e o RNG seguem no state para o Engine).
	if m.scheduler != null:
		m.scheduler.restore_history(state.get("history", {}))

	# 5. Plugins: _vn_game_started(false), migração, _vn_load.
	if m.plugins != null:
		m.plugins.load_data(state.get("plugins", {}))

	# 6. Eventos.
	if m.events != null:
		m.events.emit("sys.game_started", {"new_game": false}, VNEventBus.SOURCE_SYS)
		m.events.emit("sys.game_loaded", {"slot": String(slot)}, VNEventBus.SOURCE_SYS)
		m.events.drain()

	# 7. Palco e retomada.
	var scene_state: Variant = state.get("scene")
	if scene_state is Dictionary:
		var stage_state: Dictionary = scene_state.get("stage", {})
		if m.stage != null:
			m.stage.restore(stage_state)
		if m.audio != null:
			m.audio.restore(stage_state.get("audio", {}))
	else:
		if m.stage != null:
			m.stage.clear()
		if m.audio != null:
			m.audio.stop_all()
	if m.engine != null:
		m.engine.resume_from_save(state)
	var result := VNResult.success()
	result.message = "\n".join(warnings)
	return result


## Confere o save contra o essencial de [code]save.schema.json[/code] e a
## compatibilidade (RT §8.3 passo 1). Devolve o problema, ou vazio.
func validate_save(data: Variant) -> String:
	if not data is Dictionary:
		return "não é um objeto JSON"
	var doc: Dictionary = data
	for key in ["save_format", "project", "runtime_version", "created_at", "state"]:
		if not doc.has(key):
			return "falta %s" % key
	if not doc.save_format is String or not _is_semver(doc.save_format):
		return "save_format inválido"
	if int(String(doc.save_format).get_slice(".", 0)) != SUPPORTED_SAVE_MAJOR:
		return "save_format %s não suportado" % doc.save_format
	if not doc.project is Dictionary or not doc.project.get("id") is String or not doc.project.get("version") is String:
		return "project inválido"
	if not _project_id.is_empty() and doc.project.id != _project_id:
		return "save de outro projeto (%s)" % doc.project.id
	if not doc.runtime_version is String or not doc.created_at is String:
		return "runtime_version ou created_at inválidos"
	if doc.has("integrity") and not doc.integrity is String:
		return "integrity inválido"
	if doc.has("label") and not doc.label is String:
		return "label inválido"
	var state: Variant = doc.state
	if not state is Dictionary:
		return "state inválido"
	for key in ["variables", "chapter", "history"]:
		if not state.has(key):
			return "falta state.%s" % key
	if not state.variables is Dictionary:
		return "state.variables inválido"
	if state.chapter != null and not (state.chapter is Dictionary and state.chapter.get("id") is String):
		return "state.chapter inválido"
	var scene: Variant = state.get("scene")
	if scene != null and not (scene is Dictionary and scene.get("id") is String and scene.get("node") is String):
		return "state.scene inválido"
	if scene is Dictionary and scene.has("stage") and not scene.stage is Dictionary:
		return "state.scene.stage inválido"
	var history: Variant = state.history
	if not history is Dictionary or not _is_number(history.get("selection_count")) or not history.get("scenes") is Dictionary:
		return "state.history inválido"
	if state.has("plugins"):
		if not state.plugins is Dictionary:
			return "state.plugins inválido"
		for ns in state.plugins:
			var p: Variant = state.plugins[ns]
			if not p is Dictionary or not p.has("data") or not _is_number(p.get("data_version")) or not p.get("plugin_version") is String:
				return "state.plugins.%s inválido" % ns
	if state.has("backlog") and not state.backlog is Array:
		return "state.backlog inválido"
	return ""


# --- Consulta -----------------------------------------------------------------

func latest_slot() -> StringName:
	var latest := &""
	var latest_at := -INF
	for entry in list_slots():
		var at := _timestamp(entry.created_at)
		if at > latest_at:
			latest_at = at
			latest = entry.slot
	return latest


func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var storage := _storage()
	if storage == null:
		return out
	for path in storage.list("saves"):
		if not path.ends_with(".json"):
			continue
		var slot := StringName(path.get_file().get_basename())
		if not is_valid_slot(slot):
			continue
		var data: Variant = _read_json_quiet(path)
		if not data is Dictionary:
			continue
		out.append({
			"slot": slot,
			"label": String(data.get("label", "")),
			"created_at": String(data.get("created_at", "")),
			"thumbnail": String(data.get("thumbnail", "")),
			"thumbnail_sensitive": bool(data.get("thumbnail_sensitive", false)),
		})
	out.sort_custom(func(a, b): return _slot_order(a.slot) < _slot_order(b.slot))
	return out


func delete_slot(slot: StringName) -> Error:
	if not is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var storage := _storage()
	if storage.exists(thumbnail_path(slot)):
		storage.delete(thumbnail_path(slot))
	return storage.delete(slot_path(slot))


func has_save() -> bool:
	var storage := _storage()
	if storage == null:
		return false
	for path in storage.list("saves"):
		if path.ends_with(".json") and is_valid_slot(StringName(path.get_file().get_basename())):
			return true
	return false


# --- Perfil (RT §3.0 passo 4, §8.5) -------------------------------------------

func load_profile() -> VNResult:
	var storage := _storage()
	_profile = _empty_profile()
	_profile_modified = false
	_profile_loaded = true
	var result := VNResult.success()
	if storage != null and storage.exists(PROFILE_PATH):
		var data: Variant = _read_json_quiet(PROFILE_PATH)
		var problem := _validate_profile(data)
		if not problem.is_empty():
			# Ilegível: guarda o arquivo e começa vazio, sem mensagem (RT §3.0).
			push_warning("profile.json ilegível (%s): guardado como %s" % [problem, PROFILE_REJECTED_PATH])
			_reject_profile_file()
			result = VNResult.failure(VNErrors.INVALID_STATE, "")
		elif not VNCanonicalJson.verify(data, _save_key) and tamper_policy() != TAMPER_IGNORE:
			if tamper_policy() == TAMPER_REJECT:
				push_warning("profile.json com assinatura inválida: guardado como %s (save_tamper: reject)" % PROFILE_REJECTED_PATH)
				_reject_profile_file()
				result = VNResult.failure(VNErrors.INVALID_STATE, MESSAGE_PROFILE_REJECTED)
			else:
				push_warning("profile.json com assinatura inválida: sys.save_modified ligado (BS §8.3)")
				_profile_modified = true
				_adopt_profile(data)
		else:
			_adopt_profile(data)
	var m := modules()
	if m != null and m.variables != null:
		m.variables.apply_profile(_profile.variables)
	if m != null and m.state != null:
		m.state.set_system_value("sys.save_modified", is_modified())
	return result


func _reject_profile_file() -> void:
	var storage := _storage()
	if storage.exists(PROFILE_REJECTED_PATH):
		storage.delete(PROFILE_REJECTED_PATH)
	storage.rename(PROFILE_PATH, PROFILE_REJECTED_PATH)


func _adopt_profile(data: Dictionary) -> void:
	var p := _empty_profile()
	for key in data:
		if key != "integrity":
			p[key] = data[key]
	p.project_id = _project_id if not _project_id.is_empty() else p.project_id
	for key in ["endings", "seen_text", "seen_assets"]:
		var arr: Array = p[key]
		arr.sort()
	_profile = p


func _validate_profile(data: Variant) -> String:
	if not data is Dictionary:
		return "não é um objeto JSON"
	if not data.get("save_format") is String or int(String(data.save_format).get_slice(".", 0)) != SUPPORTED_SAVE_MAJOR:
		return "save_format inválido"
	if not data.get("project_id") is String:
		return "project_id inválido"
	if not _project_id.is_empty() and data.project_id != _project_id:
		return "perfil de outro projeto"
	if not data.get("variables") is Dictionary:
		return "variables inválido"
	for key in ["endings", "seen_text", "seen_assets"]:
		if data.has(key) and not data[key] is Array:
			return "%s inválido" % key
	if data.has("plugins") and not data.plugins is Dictionary:
		return "plugins inválido"
	return ""


func profile() -> Dictionary:
	return _profile


func flush_profile() -> Error:
	var storage := _storage()
	if storage == null:
		return ERR_UNCONFIGURED
	var m := modules()
	if _profile_loaded and m.variables != null:
		_profile.variables = m.variables.profile_values()
	_profile.project_id = _project_id
	_profile.save_format = SAVE_FORMAT
	var err := _write_signed(PROFILE_PATH, _profile)
	if err == OK:
		_profile_dirty = false
	return err


func mark_profile_dirty() -> void:
	_profile_dirty = true
	profile_changed.emit()


## Há mudanças do perfil ainda não gravadas.
func is_profile_dirty() -> bool:
	return _profile_dirty


func reset_profile() -> VNResult:
	var m := modules()
	if m.engine != null and VNPhase.is_in_game(m.engine.phase()):
		return VNResult.failure(VNErrors.INVALID_STATE, "reset_profile só fora de uma partida (U004)")
	var storage := _storage()
	if storage.exists(PROFILE_PATH):
		storage.delete(PROFILE_PATH)
	_profile = _empty_profile()
	_profile_dirty = false
	_profile_modified = false
	if m.variables != null:
		var defaults := {}
		for id in m.variables.ids():
			var def := m.variables.get_definition(id)
			if StringName(def.get("persistence", "")) == &"profile":
				defaults[id] = def.get("default")
		m.variables.apply_profile(defaults)
	if m.state != null:
		m.state.set_system_value("sys.save_modified", is_modified())
	if m.events != null:
		m.events.emit("sys.profile_reset", {}, VNEventBus.SOURCE_SYS)
	return VNResult.success()


func record_ending(ending_id: String) -> void:
	_add_sorted("endings", ending_id)


func mark_text_seen(text_path: String) -> void:
	_add_sorted("seen_text", _text_hash(text_path))


func is_text_seen(text_path: String) -> bool:
	var arr: Array = _profile.seen_text
	var h := _text_hash(text_path)
	var i := arr.bsearch(h)
	return i < arr.size() and arr[i] == h


func mark_asset_seen(asset_id: String) -> void:
	_add_sorted("seen_assets", asset_id)


static func _text_hash(text_path: String) -> String:
	return text_path.sha256_text().left(16)


func _add_sorted(key: String, value: String) -> void:
	var arr: Array = _profile[key]
	var i := arr.bsearch(value)
	if i < arr.size() and arr[i] == value:
		return
	arr.insert(i, value)
	mark_profile_dirty()


# --- Perfil de plugin (Plugin SDK §9.1) -----------------------------------------

func _plugin_entry(plugin: StringName) -> Dictionary:
	var plugins: Dictionary = _profile.plugins
	return plugins.get_or_add(String(plugin), {})


func get_plugin_profile_data(plugin: StringName) -> Variant:
	var plugins: Dictionary = _profile.plugins
	return plugins.get(String(plugin), {}).get("data")


func set_plugin_profile_data(plugin: StringName, data: Variant) -> VNResult:
	if JSON.stringify(data).to_utf8_buffer().size() > 64 * 1024:
		return VNResult.failure(VNErrors.OUT_OF_RANGE, "dados de perfil acima de 64 KB")
	_plugin_entry(plugin)["data"] = data
	mark_profile_dirty()
	return VNResult.success()


## Declara um quadro de recordes ([code]order[/code] [code]desc[/code]/[code]asc[/code],
## [code]keep[/code]). O Plugin Host chama com o manifesto (M3-06); sem
## declaração, vale [code]desc[/code] e [constant DEFAULT_RECORD_KEEP].
func set_record_board(plugin: StringName, board: StringName, order: StringName, keep: int) -> void:
	_record_boards["%s/%s" % [plugin, board]] = {"order": order, "keep": maxi(1, keep)}


func submit_record(plugin: StringName, board: StringName, score: float, meta: Dictionary = {}) -> int:
	var cfg: Dictionary = _record_boards.get("%s/%s" % [plugin, board], {"order": &"desc", "keep": DEFAULT_RECORD_KEEP})
	var records: Dictionary = _plugin_entry(plugin).get_or_add("records", {})
	var entries: Array = records.get_or_add(String(board), [])
	var asc: bool = cfg.order == &"asc"
	# Empate fica com a mais antiga: a nova entra depois das iguais.
	var pos := entries.size()
	for i in entries.size():
		var s: float = entries[i].score
		if (asc and score < s) or (not asc and score > s):
			pos = i
			break
	if pos >= cfg.keep:
		return 0
	var entry := {"score": score, "at": _now_iso(false)}
	if not meta.is_empty():
		entry["meta"] = meta
	entries.insert(pos, entry)
	while entries.size() > cfg.keep:
		entries.pop_back()
	mark_profile_dirty()
	return pos + 1


func get_records(plugin: StringName, board: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var plugins: Dictionary = _profile.plugins
	out.assign(plugins.get(String(plugin), {}).get("records", {}).get(String(board), []))
	return out


# --- Utilidades ---------------------------------------------------------------

func _empty_profile() -> Dictionary:
	return {
		"save_format": SAVE_FORMAT, "project_id": _project_id, "variables": {},
		"endings": [], "seen_text": [], "seen_assets": [], "plugins": {},
	}


func _show_message(text_path: String) -> void:
	var m := modules()
	if m != null and m.ui != null:
		m.ui.show_message(text_path)


## Agora em UTC, RFC 3339; com milissegundos para ordenar saves do mesmo segundo.
static func _now_iso(with_ms: bool = true) -> String:
	var unix := Time.get_unix_time_from_system()
	var base := Time.get_datetime_string_from_unix_time(int(unix))
	if not with_ms:
		return base + "Z"
	return "%s.%03dZ" % [base, int((unix - floor(unix)) * 1000.0)]


## Segundos Unix de um date-time RFC 3339 ([code]-INF[/code] se inválido).
static func _timestamp(s: String) -> float:
	if s.length() < 19:
		return -INF
	var base := Time.get_unix_time_from_datetime_string(s.left(19))
	var rest := s.substr(19)
	var frac := 0.0
	if rest.begins_with("."):
		var digits := ""
		var i := 1
		while i < rest.length() and rest[i].is_valid_int():
			digits += rest[i]
			i += 1
		frac = ("0." + digits).to_float() if not digits.is_empty() else 0.0
		rest = rest.substr(i)
	var offset := 0
	if rest.length() == 6 and (rest[0] == "+" or rest[0] == "-"):
		offset = (rest.substr(1, 2).to_int() * 60 + rest.substr(4, 2).to_int()) * 60
		if rest[0] == "+":
			offset = -offset
	return float(base + offset) + frac


static func _is_semver(s: String) -> bool:
	var core := s.get_slice("-", 0).get_slice("+", 0)
	var parts := core.split(".")
	if parts.size() != 3:
		return false
	for p in parts:
		if not p.is_valid_int() or int(p) < 0:
			return false
	return true


static func _is_number(v: Variant) -> bool:
	return v is int or v is float
