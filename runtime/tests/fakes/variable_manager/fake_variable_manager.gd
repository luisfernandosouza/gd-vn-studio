class_name FakeVariableManager
extends VNVariableManager
## Dublê do Variable Manager: um dicionário. Defina variáveis com [method define].

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

## id → { type, default, persistence, read_only }
var definitions: Dictionary = {}
var values: Dictionary = {}
var aliases: Dictionary = {}
var chapter_active: bool = false
var scene_active: bool = false


## Define uma variável (atalho para testes).
func define(id: String, type: StringName, default_value: Variant, persistence: StringName = &"save", read_only: bool = false) -> void:
	definitions[id] = {"type": type, "default": default_value, "persistence": persistence, "read_only": read_only or id.begins_with("sys.")}
	values[id] = default_value


func has(id: String) -> bool:
	return definitions.has(id)


func get_definition(id: String) -> Dictionary:
	return definitions.get(id, {})


func ids() -> PackedStringArray:
	var out := PackedStringArray(definitions.keys())
	out.sort()
	return out


func resolve_alias(id: String) -> String:
	return aliases.get(id, id)


func is_read_only(id: String) -> bool:
	return definitions.get(id, {}).get("read_only", false)


func is_scope_active(id: String) -> bool:
	if id.begins_with("chapter."):
		return chapter_active
	if id.begins_with("scene."):
		return scene_active
	return true


func read(id: String, fallback: Variant = null) -> Variant:
	if not has(id) or not is_scope_active(id):
		return fallback
	return values.get(id, fallback)


func store(id: String, value: Variant) -> void:
	_rec(&"store", [id, value])
	if not definitions.has(id):
		define(id, &"string" if value is String else &"integer", value, &"session", id.begins_with("sys."))
	values[id] = value


func is_default(id: String) -> bool:
	return has(id) and values.get(id) == definitions[id].default


func reset_game() -> void:
	_rec(&"reset_game")
	for id in definitions:
		if definitions[id].persistence != &"profile":
			values[id] = definitions[id].default


func apply_profile(p_values: Dictionary) -> void:
	_rec(&"apply_profile", [p_values])
	for id in p_values:
		values[resolve_alias(id)] = p_values[id]


func enter_chapter(chapter_id: String) -> void:
	_rec(&"enter_chapter", [chapter_id])
	chapter_active = true
	for id in definitions:
		if id.begins_with("chapter."):
			values[id] = definitions[id].default


func exit_chapter() -> void:
	_rec(&"exit_chapter")
	chapter_active = false


func enter_scene(scene_id: String) -> void:
	_rec(&"enter_scene", [scene_id])
	scene_active = true
	for id in definitions:
		if id.begins_with("scene."):
			values[id] = definitions[id].default


func exit_scene() -> void:
	_rec(&"exit_scene")
	scene_active = false


func save_values() -> Dictionary:
	var out := {}
	for id in ids():
		if definitions[id].persistence == &"save" and not is_read_only(id) and is_scope_active(id):
			out[id] = values[id]
	return out


func profile_values() -> Dictionary:
	var out := {}
	for id in ids():
		if definitions[id].persistence == &"profile":
			out[id] = values[id]
	return out


func restore_save_values(p_values: Dictionary) -> PackedStringArray:
	_rec(&"restore_save_values", [p_values])
	var warnings := PackedStringArray()
	for key in p_values:
		var id := resolve_alias(key)
		if has(id):
			var v: Variant = p_values[key]
			# JSON não distingue 2 de 2.0 (spec 08 §2.1): o tipo vem da definição.
			values[id] = int(v) if definitions[id].type == &"integer" and v is float else v
		else:
			warnings.append("variável descartada: %s" % key)
	return warnings
