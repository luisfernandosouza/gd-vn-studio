class_name FakePluginBridge
extends VNPluginBridge
## Ponte de teste: permissões configuráveis, variáveis num dicionário e registro
## de todas as chamadas. Simula a validação do State Manager na ordem do RT §6.2
## só no que os testes precisam (existência, permissão, tipo, expect).

var capabilities: Array[StringName] = []
var readable: Array[String] = []
var writable: Array[String] = []
var emits: Array[String] = []
var subscribes: Array[String] = []          # vazio = qualquer padrão
var scene_grants: Array[String] = []
var values: Dictionary = {}                  # id → valor
var definitions: Dictionary = {}             # id → definição

var denied: Array[Dictionary] = []           # [{ capability, call }]
var errors: Array[Dictionary] = []           # [{ error, message }]
var logs: Array[Dictionary] = []             # [{ level, message }]
var commits: Array[Dictionary] = []          # [{ ops, expectations }]
var emitted: Array[Dictionary] = []          # [{ name, payload }]
var requests: Array[String] = []
var subscriptions: Dictionary = {}           # id → { pattern, callback }
var _next_sub := 1


func has_capability(capability: StringName) -> bool:
	return capabilities.has(capability)


func can_read_variable(variable: String) -> bool:
	return readable.has(variable)


func can_emit(event_name: String) -> bool:
	return emits.has(event_name)


func can_subscribe(pattern: String) -> bool:
	return subscribes.is_empty() or subscribes.has(pattern)


func can_request_scene(scene_id: String) -> bool:
	return scene_grants.has(scene_id)


func permission_denied(capability: StringName, call: String) -> void:
	denied.append({"capability": capability, "call": call})


func report_error(error: StringName, message: String) -> void:
	errors.append({"error": error, "message": message})


func write_log(level: StringName, message: String) -> void:
	logs.append({"level": level, "message": message})


func variable_exists(variable: String) -> bool:
	return values.has(variable)


func read_value(variable: String, fallback: Variant = null) -> Variant:
	return values.get(variable, fallback)


func get_definition(variable: String) -> Dictionary:
	return definitions.get(variable, {})


func commit(ops: Array[Dictionary], expectations: Array[Dictionary]) -> VNResult:
	commits.append({"ops": ops, "expectations": expectations})
	var next := values.duplicate(true)
	var changes: Array[Dictionary] = []
	for op in ops:
		var id: String = op.variable
		if not next.has(id):
			return VNResult.failure(VNRuntimeSDK.VARIABLE_NOT_FOUND, id)
		if not id.begins_with("plugin.") and not writable.has(id):
			return VNResult.failure(VNRuntimeSDK.PERMISSION_DENIED, id)
		var old: Variant = next[id]
		match op.op:
			&"set": next[id] = op.value
			&"add": next[id] = old + op.value
			&"subtract": next[id] = old - op.value
			&"toggle":
				if typeof(old) != TYPE_BOOL:
					return VNResult.failure(VNRuntimeSDK.TYPE_MISMATCH, id)
				next[id] = not old
			&"reset": next[id] = definitions.get(id, {}).get("default")
		changes.append({"variable": id, "old": old, "new": next[id]})
	for e in expectations:
		if values.get(e.variable) != e.value:
			return VNResult.failure(VNRuntimeSDK.CONFLICT, e.variable)
	values = next
	state_changed.emit(changes)
	return VNResult.success(changes)


func emit_event(name: String, payload: Dictionary) -> VNResult:
	emitted.append({"name": name, "payload": payload})
	return VNResult.success()


func subscribe(pattern: String, callback: Callable) -> int:
	var id := _next_sub
	_next_sub += 1
	subscriptions[id] = {"pattern": pattern, "callback": callback}
	return id


func unsubscribe(subscription_id: int) -> void:
	subscriptions.erase(subscription_id)


## Entrega um evento como o Event Bus entregaria (para os testes).
func deliver(name: String, payload: Dictionary, source: String) -> void:
	for id in subscriptions.keys():
		var s: Dictionary = subscriptions[id]
		if VNRuntimeSDK.event_matches(s.pattern, name):
			s.callback.call(name, payload, source)


func request_scene(scene_id: String) -> VNResult:
	requests.append(scene_id)
	return VNResult.success()
