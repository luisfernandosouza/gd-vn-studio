class_name FakePluginHost
extends VNPluginHost
## Dublê do Plugin Host: sem plugins de verdade. As permissões vêm de
## [member capabilities], [member readable], [member writable] e
## [member scene_grants]; a atividade termina quando o teste chama
## [method finish_activity].

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var plugins: PackedStringArray = []
var faulted: Dictionary = {}           # namespace → true
var errors: Dictionary = {}            # namespace → contagem
var capabilities: Dictionary = {}      # namespace → Array[StringName]
var readable: Dictionary = {}          # namespace → Array[String] de variáveis
var writable: Dictionary = {}          # namespace → Array[String] de variáveis
var scene_grants: Dictionary = {}      # namespace → Array[String] de cenas
var plugin_saves: Dictionary = {}      # state.plugins que save_data() devolve
var activity: Dictionary = {}


func load_plugins(p_plugins: Dictionary) -> void:
	_rec(&"load_plugins", [p_plugins])
	var ids := PackedStringArray(p_plugins.get("plugins", {}).keys())
	ids.sort()
	plugins = ids


func loaded_plugins() -> PackedStringArray:
	return plugins


func is_loaded(plugin: StringName) -> bool:
	return plugins.has(String(plugin)) and not is_faulted(plugin)


func is_faulted(plugin: StringName) -> bool:
	return faulted.has(plugin)


func report_error(plugin: StringName, error: String) -> void:
	_rec(&"report_error", [plugin, error])
	errors[plugin] = errors.get(plugin, 0) + 1
	if errors[plugin] >= FAULT_THRESHOLD and not faulted.has(plugin):
		faulted[plugin] = true
		plugin_faulted.emit(plugin, error)


func notify_game_started(is_new_game: bool) -> void:
	_rec(&"notify_game_started", [is_new_game])


func notify_game_ended() -> void:
	_rec(&"notify_game_ended")


func shutdown() -> void:
	_rec(&"shutdown")


func has_capability(plugin: StringName, capability: StringName) -> bool:
	return capabilities.get(plugin, []).has(capability)


func can_read_variable(plugin: StringName, variable: String) -> bool:
	return variable.begins_with("plugin.%s." % plugin) or readable.get(plugin, []).has(variable)


func can_write_variable(plugin: StringName, variable: String) -> bool:
	return variable.begins_with("plugin.%s." % plugin) or writable.get(plugin, []).has(variable)


func can_request_scene(plugin: StringName, scene_id: String) -> bool:
	return scene_grants.get(plugin, []).has(scene_id)


func can_emit(plugin: StringName, event_name: String) -> bool:
	return event_name.begins_with("%s." % plugin)


func start_activity(p_activity: StringName, params: Dictionary, mode: StringName = MODE_STORY) -> VNResult:
	_rec(&"start_activity", [p_activity, params, mode])
	if not activity.is_empty():
		return VNResult.failure(VNErrors.INVALID_STATE, "já há atividade")
	var ns := StringName(String(p_activity).get_slice(".", 0))
	if not is_loaded(ns):
		return VNResult.failure(VNErrors.INVALID_STATE, "plugin não carregado")
	activity = {"activity": p_activity, "mode": mode, "params": params, "skippable": false}
	return VNResult.success()


func cancel_activity(status: StringName) -> void:
	_rec(&"cancel_activity", [status])
	finish_activity(status)


func current_activity() -> Dictionary:
	return activity


## Termina a atividade em curso como o plugin terminaria (atalho para testes).
func finish_activity(status: StringName, outcome: StringName = &"", payload: Dictionary = {}) -> void:
	if activity.is_empty():
		return
	activity = {}
	activity_ended.emit(status, outcome, payload)


func save_data() -> Dictionary:
	return plugin_saves.duplicate(true)


func load_data(plugins_state: Dictionary) -> void:
	_rec(&"load_data", [plugins_state])
	plugin_saves = plugins_state.duplicate(true)
