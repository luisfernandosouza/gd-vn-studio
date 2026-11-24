extends RefCounted
## A ponte de um plugin ([code]VNPluginBridge[/code] do Runtime SDK, M3-02)
## sobre os módulos do M0-07: permissões no Plugin Host, escrita e leitura no
## State Manager com [method VNStateManager.plugin_caller], eventos no Event
## Bus com o id do plugin como [code]source[/code] e o namespace como dono,
## pedidos de cena no [method VNSceneScheduler.request].
##
## Tem os mesmos métodos e o mesmo sinal da [code]VNPluginBridge[/code], mas não
## a estende: o addon ainda não faz parte do projeto do runtime (ele entra na
## integração, quando a cópia de [code]VNResult[/code] em [code]core/[/code]
## sai). Enquanto isso, o Plugin Host monta um adaptador que estende
## [code]VNPluginBridge[/code] e repassa cada chamada para cá, só quando a
## classe existe no projeto ([method VNPluginHostImpl.make_sdk_bridge]).
##
## Sem [code]class_name[/code]: carregado por [code]preload[/code] no Plugin Host.

signal state_changed(changes: Array[Dictionary])

var _host_ref: WeakRef
var _ns: StringName


func _init(host: VNPluginHost, plugin_namespace: StringName) -> void:
	_host_ref = weakref(host)
	_ns = plugin_namespace
	var m := _modules()
	if m != null and m.state != null:
		m.state.state_changed.connect(_on_state_changed)


func _host() -> VNPluginHost:
	return _host_ref.get_ref() as VNPluginHost


func _modules() -> VNModules:
	var h := _host()
	return null if h == null else h.modules()


func _caller() -> StringName:
	return VNStateManager.plugin_caller(_ns)


func _on_state_changed(changes: Array[Dictionary]) -> void:
	state_changed.emit(changes)


# --- Permissões --------------------------------------------------------------

func has_capability(capability: StringName) -> bool:
	var h := _host()
	return h != null and h.has_capability(_ns, capability)


func can_read_variable(variable: String) -> bool:
	var h := _host()
	return h != null and h.can_read_variable(_ns, variable)


func can_emit(event_name: String) -> bool:
	var h := _host()
	return h != null and h.can_emit(_ns, event_name)


## [code]events.subscribes[/code] do manifesto é informativo no v1 (o validador
## confere); o que barra é a capacidade [code]events.subscribe[/code], que a
## fachada confere antes.
func can_subscribe(_pattern: String) -> bool:
	return _host() != null


func can_request_scene(scene_id: String) -> bool:
	var h := _host()
	return h != null and h.can_request_scene(_ns, scene_id)


func permission_denied(capability: StringName, call: String) -> void:
	var h := _host()
	if h != null and h.has_method(&"deny"):
		h.deny(_ns, capability, call)


func report_error(error: StringName, message: String) -> void:
	var h := _host()
	if h == null:
		return
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		h.report_error(_ns, "%s: %s" % [error, message])
	else:
		h.report_error.call_deferred(_ns, "%s: %s" % [error, message])


func write_log(level: StringName, message: String) -> void:
	var line := "[vn_plugin %s] %s: %s" % [_ns, level, message]
	if level in [&"warn", &"error"]:
		push_warning(line)
	else:
		print(line)


# --- Variáveis ---------------------------------------------------------------

func variable_exists(variable: String) -> bool:
	var m := _modules()
	return m != null and m.variables != null and m.variables.has(variable)


func read_value(variable: String, fallback: Variant = null) -> Variant:
	var m := _modules()
	if m == null or m.state == null:
		return fallback
	return m.state.read_value(variable, fallback, _caller())


## Definição pública (Plugin SDK §5.3): sem [code]access[/code] nem valores.
func get_definition(variable: String) -> Dictionary:
	var m := _modules()
	if m == null or m.variables == null or not m.variables.has(variable):
		return {}
	var def := m.variables.get_definition(variable)
	var out := {"id": variable}
	for key in ["type", "default", "min", "max", "values", "max_length", "persistence"]:
		if def.has(key):
			out[key] = def[key]
	return out


func commit(ops: Array[Dictionary], expectations: Array[Dictionary]) -> VNResult:
	var m := _modules()
	if m == null or m.state == null:
		return VNResult.failure(VNErrors.INVALID_STATE, "sem jogo")
	var tx := m.state.begin_transaction(_caller())
	for op in ops:
		tx.effect(op)
	for e in expectations:
		tx.expect(String(e.get("variable", "")), e.get("value"))
	var result := tx.commit()
	if not result.ok and result.error == VNErrors.WRONG_THREAD:
		report_error(VNErrors.WRONG_THREAD, "commit fora da thread principal")
	return result


# --- Eventos -----------------------------------------------------------------

func emit_event(event_name: String, payload: Dictionary) -> VNResult:
	var m := _modules()
	var h := _host()
	if m == null or m.events == null or h == null:
		return VNResult.failure(VNErrors.INVALID_STATE, "sem jogo")
	var id := String(_ns)
	if h.has_method(&"plugin_id"):
		id = h.plugin_id(_ns)
	return m.events.emit(event_name, payload, id)


func subscribe(pattern: String, callback: Callable) -> int:
	var m := _modules()
	var h := _host()
	if m == null or m.events == null or h == null or h.is_faulted(_ns):
		return 0
	return m.events.on(pattern, callback, _ns)


func unsubscribe(subscription_id: int) -> void:
	var m := _modules()
	if m != null and m.events != null:
		m.events.off(subscription_id)


# --- Cenas -------------------------------------------------------------------

func request_scene(scene_id: String) -> VNResult:
	var m := _modules()
	if m == null or m.scheduler == null:
		return VNResult.failure(VNErrors.INVALID_STATE, "sem jogo")
	return m.scheduler.request(scene_id, _ns)
