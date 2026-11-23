class_name FakeSaveManager
extends VNSaveManager
## Dublê do Save Manager: monta um save simplificado com as partes dos outros
## módulos e o grava em JSON no VNStorage do registro, sem assinatura nem
## validação. O perfil fica na memória.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var profile_data: Dictionary = {}
var profile_dirty: bool = false
var _auto_next: int = 1


func _init() -> void:
	profile_data = _empty_profile()


func save(slot: StringName, label: String = "") -> VNResult:
	_rec(&"save", [slot, label])
	if modules().engine != null and not modules().engine.can_save():
		return VNResult.failure(VNErrors.INVALID_STATE)
	modules().storage.write_json(slot_path(slot), build_save(label))
	saved.emit(slot, false)
	return VNResult.success()


func autosave(reason: StringName) -> VNResult:
	_rec(&"autosave", [reason])
	var slot := auto_slot(_auto_next)
	_auto_next = _auto_next % AUTOSAVE_SLOTS + 1
	modules().storage.write_json(slot_path(slot), build_save(String(reason)))
	saved.emit(slot, true)
	return VNResult.success()


func load_slot(slot: StringName) -> VNResult:
	_rec(&"load_slot", [slot])
	var data: Variant = modules().storage.read_json(slot_path(slot))
	if not data is Dictionary:
		return VNResult.failure(VNErrors.VARIABLE_NOT_FOUND, "save não existe")
	var state: Dictionary = data.state
	modules().variables.restore_save_values(state.get("variables", {}))
	modules().scheduler.restore_history(state.get("history", {}))
	modules().plugins.load_data(state.get("plugins", {}))
	modules().engine.resume_from_save(state)
	return VNResult.success()


func latest_slot() -> StringName:
	var latest := &""
	var latest_at := ""
	for path in modules().storage.list("saves"):
		if path.ends_with(".json"):
			var at: String = modules().storage.read_json(path).get("created_at", "")
			if at >= latest_at:
				latest_at = at
				latest = StringName(path.get_file().get_basename())
	return latest


func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in modules().storage.list("saves"):
		if path.ends_with(".json"):
			var d: Dictionary = modules().storage.read_json(path)
			out.append({"slot": StringName(path.get_file().get_basename()), "label": d.get("label", ""), "created_at": d.get("created_at", "")})
	return out


func delete_slot(slot: StringName) -> Error:
	return modules().storage.delete(slot_path(slot))


func has_save() -> bool:
	return not list_slots().is_empty()


func build_save(label: String = "") -> Dictionary:
	var m := modules()
	var engine_part := m.engine.snapshot()
	var scene: Variant = engine_part.get("scene")
	if scene is Dictionary:
		scene["stage"] = m.stage.snapshot()
		scene.stage["audio"] = m.audio.snapshot()
	return {
		"save_format": "1.0",
		"created_at": Time.get_datetime_string_from_system(true),
		"label": label,
		"state": {
			"variables": m.variables.save_values(),
			"chapter": engine_part.get("chapter"),
			"scene": scene,
			"history": m.scheduler.get_history(),
			"plugins": m.plugins.save_data(),
			"backlog": engine_part.get("backlog", []),
		},
	}


func load_profile() -> VNResult:
	_rec(&"load_profile")
	var data: Variant = modules().storage.read_json("profile.json")
	profile_data = data if data is Dictionary else _empty_profile()
	return VNResult.success()


func profile() -> Dictionary:
	return profile_data


func flush_profile() -> Error:
	_rec(&"flush_profile")
	profile_dirty = false
	return modules().storage.write_json("profile.json", profile_data)


func mark_profile_dirty() -> void:
	profile_dirty = true
	profile_changed.emit()


func reset_profile() -> VNResult:
	_rec(&"reset_profile")
	profile_data = _empty_profile()
	modules().storage.delete("profile.json")
	return VNResult.success()


func record_ending(ending_id: String) -> void:
	_add_unique("endings", ending_id)


func mark_text_seen(text_path: String) -> void:
	_add_unique("seen_text", text_path.sha256_text().left(16))


func is_text_seen(text_path: String) -> bool:
	return profile_data.seen_text.has(text_path.sha256_text().left(16))


func mark_asset_seen(asset_id: String) -> void:
	_add_unique("seen_assets", asset_id)


func get_plugin_profile_data(plugin: StringName) -> Variant:
	return profile_data.plugins.get(plugin, {}).get("data")


func set_plugin_profile_data(plugin: StringName, data: Variant) -> VNResult:
	profile_data.plugins.get_or_add(plugin, {})["data"] = data
	mark_profile_dirty()
	return VNResult.success()


func submit_record(plugin: StringName, board: StringName, score: float, meta: Dictionary = {}) -> int:
	_rec(&"submit_record", [plugin, board, score, meta])
	var records: Dictionary = profile_data.plugins.get_or_add(plugin, {}).get_or_add("records", {})
	var entries: Array = records.get_or_add(board, [])
	entries.append({"score": score, "at": Time.get_datetime_string_from_system(true), "meta": meta})
	mark_profile_dirty()
	return entries.size()


func get_records(plugin: StringName, board: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(profile_data.plugins.get(plugin, {}).get("records", {}).get(board, []))
	return out


func _add_unique(key: String, value: String) -> void:
	var arr: Array = profile_data[key]
	if not arr.has(value):
		arr.append(value)
		arr.sort()
		mark_profile_dirty()


static func _empty_profile() -> Dictionary:
	return {"variables": {}, "endings": [], "seen_text": [], "seen_assets": [], "plugins": {}}
