class_name VNPluginHostImpl
extends VNPluginHost
## Plugin Host do runtime (tarefa M3-01): carregamento, permissões e ciclo de
## vida dos plugins, conforme o contrato [VNPluginHost].
##
## [b]Carga[/b] (RT §3.0 passo 5; Plugin SDK §5.1). [method load_plugins] lê o
## [code]plugins.json[/code] do bundle ([code]bundle-plugins.schema.json[/code])
## e, para cada plugin, o [code]plugin.json[/code] da pasta dele em
## [code]res://vn_plugins/<namespace>/[/code] (entrypoint, versões e
## dependências; o bundle não as repete). Confere namespace, caminho, faixas de
## [code]compatibility.runtime[/code], [code]sdk.runtime[/code] e
## [code]compatibility.godot[/code], dependências e ciclos; ordena em ordem
## topológica com empate pela ordem lexicográfica do id; instancia o
## entrypoint, chama [code]_vn_init(ctx)[/code] em todos e depois
## [code]_vn_ready()[/code] em todos. Um plugin que falha (manifesto, versão,
## script, dependência que falhou) fica de fora e o jogo segue sem ele (RT §9);
## a falha sai em [signal plugin_load_failed] e em [method load_failures], e o
## boot decide se é erro bloqueante (debug e Preview) ou só log (release).
##
## [b]Confiança[/b] (Plugin SDK §4.3; RT §2.1). Plugins sem [code]trust[/code]
## no bundle (o caso de [code]res://vn_plugins/[/code] no desenvolvimento, sem
## lock) valem como [code]local[/code]. O runtime executa os três níveis: a
## confirmação de um plugin [code]local[/code] é do Studio, antes do build.
## A confiança não amplia nada: as concessões vêm sempre de [code]plugins.json[/code].
##
## [b]Permissões[/b] (Plugin SDK §4; DM §4.6). Capacidades efetivas são as do
## bundle (pedido ∩ concessão, com prefixo [code]runtime:[/code]). As
## consultas do contrato respondem a permissão efetiva; os métodos
## [code]plugin_*[/code] são a porta que as fachadas do Runtime SDK (M3-02)
## usam: conferem a capacidade, recusam com [constant VNErrors.PERMISSION_DENIED]
## (ou [constant VNErrors.WRONG_THREAD] fora da thread principal), contam o
## erro para o estado [i]faulted[/i] e mandam a operação ao módulo dono.
##
## [b]Erros[/b] (RT §9). Contam por sessão: erros de script reportados pelo
## motor (um [Logger] atribui cada erro ao plugin pelo caminho do script),
## [code]fail[/code] de atividade, timeout e chamadas recusadas com
## [code]PERMISSION_DENIED[/code] ou [code]WRONG_THREAD[/code]. No
## [constant VNPluginHost.FAULT_THRESHOLD]º, o plugin fica [i]faulted[/i]: os
## ouvintes saem do Event Bus, a atividade em curso termina como
## [code]failed[/code], novas atividades são recusadas (o Narrative Engine segue
## [code]on_error[/code]) e ele não recebe mais chamadas de ciclo de vida, salvo
## [code]_vn_shutdown[/code].
##
## Atividades e saves têm aqui o caminho básico do contrato; o resto é das
## tarefas M3-04 (handle, pulo, pausa, timeout) e M3-05 (migração e perfil).

## Um plugin não carregou (manifesto, versão, script ou dependência). O jogo
## segue sem ele; em debug e no Preview o boot mostra como erro bloqueante (RT §9).
signal plugin_load_failed(plugin: StringName, error: String)

const Semver := preload("res://vn_runtime/plugin_host/vn_plugin_semver.gd")
const ErrorLogger := preload("res://vn_runtime/plugin_host/vn_plugin_error_logger.gd")
const HostBridge := preload("res://vn_runtime/plugin_host/vn_plugin_host_bridge.gd")

## Versão do runtime, conferida contra [code]compatibility.runtime[/code].
const RUNTIME_VERSION := "1.0.0"
## Versão do Runtime SDK embutido, conferida contra [code]sdk.runtime[/code].
const SDK_RUNTIME_VERSION := "1.0.0"

const TRUST_OFFICIAL := &"official"
const TRUST_REVIEWED := &"reviewed"
const TRUST_LOCAL := &"local"

## Namespaces reservados (Data Model §3; Plugin SDK §3).
const RESERVED_NAMESPACES: Array[String] = [
	"sys", "story", "vn", "global", "character", "chapter", "scene", "plugin",
]

## Pasta dos plugins no jogo (Plugin SDK §2.4). Os testes trocam por outra.
var plugins_root := "res://vn_plugins/"

## Monta o contexto passado a [code]_vn_init[/code]:
## [code]func(host: VNPluginHostImpl, info: Dictionary) -> Object[/code], com
## [code]info = { id, namespace, version, trust, config, capabilities }[/code].
## Vazio: usa [code]VNPluginContext.create(bridge, id, namespace, config)[/code]
## do Runtime SDK com a ponte de [method make_sdk_bridge], se o addon estiver no
## projeto; senão, um contexto mínimo só com identidade e configuração.
var context_factory: Callable

## Cria o [code]VNActivityHandle[/code] de uma atividade:
## [code]func(host: VNPluginHostImpl, activity: Dictionary) -> Object[/code],
## com [code]activity = { activity, mode, params, skippable }[/code]. O handle
## termina a atividade com [method complete_activity] ou [method fail_activity]
## e responde [code]is_active()[/code] com [method is_activity_active]. Vazio:
## usa o [code]VNActivityHandle[/code] do Runtime SDK, se o addon estiver no
## projeto; sem ele, [method start_activity] recusa.
var handle_factory: Callable

var _plugins: Dictionary = {}          # namespace → registro (ver _new_record)
var _ids: Dictionary = {}              # id → namespace
var _order: PackedStringArray = []     # namespaces carregados, na ordem do _vn_init
var _failures: Array[Dictionary] = []  # [{ plugin, id, error }]
var _activity: Dictionary = {}
var _activity_token := 0
var _foreign_saves: Dictionary = {}    # state.plugins de plugins ausentes, preservados
var _last_saves: Dictionary = {}       # último state.plugins de cada plugin
var _bundle: Dictionary = {}
var _logger: Logger = null
var _container: Node = null
var _parent: Node = null
var _init_ns: StringName = &""         # plugin em _vn_init (erro de script = falha de carga)
var _init_failed := false
var _sdk_scripts: Dictionary = {}       # class_name → Script ou null
var _adapter_script: GDScript = null

## Subclasse de VNPluginBridge que repassa tudo para vn_plugin_host_bridge.gd.
const _ADAPTER_SOURCE := """extends VNPluginBridge
var _core
func _bind(core) -> void:
	_core = core
	_core.state_changed.connect(func(c): state_changed.emit(c))
func has_capability(capability: StringName) -> bool: return _core.has_capability(capability)
func can_read_variable(variable: String) -> bool: return _core.can_read_variable(variable)
func can_emit(event_name: String) -> bool: return _core.can_emit(event_name)
func can_subscribe(pattern: String) -> bool: return _core.can_subscribe(pattern)
func can_request_scene(scene_id: String) -> bool: return _core.can_request_scene(scene_id)
func permission_denied(capability: StringName, call: String) -> void: _core.permission_denied(capability, call)
func report_error(error: StringName, message: String) -> void: _core.report_error(error, message)
func write_log(level: StringName, message: String) -> void: _core.write_log(level, message)
func variable_exists(variable: String) -> bool: return _core.variable_exists(variable)
func read_value(variable: String, fallback: Variant = null) -> Variant: return _core.read_value(variable, fallback)
func get_definition(variable: String) -> Dictionary: return _core.get_definition(variable)
func commit(ops: Array[Dictionary], expectations: Array[Dictionary]) -> VNResult: return _core.commit(ops, expectations)
func emit_event(name: String, payload: Dictionary) -> VNResult: return _core.emit_event(name, payload)
func subscribe(pattern: String, callback: Callable) -> int: return _core.subscribe(pattern, callback)
func unsubscribe(subscription_id: int) -> void: _core.unsubscribe(subscription_id)
func request_scene(scene_id: String) -> VNResult: return _core.request_scene(scene_id)
"""


# --- Módulo ------------------------------------------------------------------

func load_bundle(bundle: Dictionary) -> void:
	_bundle = bundle


func attach(parent: Node) -> void:
	_parent = parent
	_container = Node.new()
	_container.name = "VNPlugins"
	parent.add_child(_container)
	for ns in _order:
		var inst = _plugins[ns].instance
		if inst is Node and (inst as Node).get_parent() == null:
			_container.add_child(inst)
	if parent.is_inside_tree():
		var tree := parent.get_tree()
		if not tree.process_frame.is_connected(_drain_script_errors):
			tree.process_frame.connect(_drain_script_errors)


func detach() -> void:
	if _parent != null and _parent.is_inside_tree():
		var tree := _parent.get_tree()
		if tree.process_frame.is_connected(_drain_script_errors):
			tree.process_frame.disconnect(_drain_script_errors)
	if _container != null:
		for child in _container.get_children():
			_container.remove_child(child)
		_container.queue_free()
	_container = null
	_parent = null


# --- Carga e ciclo de vida -----------------------------------------------------

func load_plugins(plugins: Dictionary) -> void:
	if not _plugins.is_empty():
		shutdown()
	_install_logger()
	var entries: Dictionary = plugins.get("plugins", {})
	var ids := entries.keys()
	ids.sort()

	# 1. Registro e manifesto de cada plugin.
	var candidates := {}  # id → true (runtime, sem falha até aqui)
	for id in ids:
		var rec := _new_record(String(id), entries[id])
		var ns: String = rec.namespace
		if ns.is_empty():
			_record_failure(StringName(id), String(id), "entrada sem namespace")
			continue
		if _plugins.has(ns):
			_record_failure(StringName(ns), String(id), "namespace '%s' já usado por %s (P001)" % [ns, _plugins[ns].id])
			continue
		_plugins[ns] = rec
		_ids[rec.id] = ns
		var err := _check_entry(rec)
		if err.is_empty():
			err = _read_manifest(rec)
		if not err.is_empty():
			_fail(ns, err)
			continue
		if not rec.manifest.get("targets", []).has("runtime"):
			rec.status = &"editor_only"
			continue
		candidates[rec.id] = true

	# 2. Dependências: presença, faixa de versão e falhas em cascata.
	var deps := {}  # id → ids de que depende (obrigatórias e opcionais presentes)
	for id in candidates:
		deps[id] = []
	var changed := true
	while changed:
		changed = false
		for id in candidates.keys():
			if not candidates.has(id):
				continue
			var err := _resolve_dependencies(id, candidates, deps)
			if not err.is_empty():
				candidates.erase(id)
				_fail(_ids[id], err)
				changed = true

	# 3. Ordem topológica; empate pela ordem lexicográfica do id (SDK §5.1).
	var order := _topological_order(candidates, deps)
	for id in candidates:
		if not order.has(id):
			_fail(_ids[id], "ciclo de dependências")

	# 4. _vn_init em todos, na ordem.
	for id in order:
		var ns: String = _ids[id]
		var rec: Dictionary = _plugins[ns]
		var failed_dep := ""
		for d in deps[id]:
			if _plugins.has(_ids.get(d, "")) and _plugins[_ids[d]].status == &"failed":
				if rec.manifest.get("dependencies", {}).has(d):
					failed_dep = d
					break
		if not failed_dep.is_empty():
			_fail(ns, "dependência %s não carregou" % failed_dep)
			continue
		_instantiate(rec)

	# 5. _vn_ready em todos.
	for ns in _order:
		_invoke(StringName(ns), &"_vn_ready")


func loaded_plugins() -> PackedStringArray:
	return _order.duplicate()


func is_loaded(plugin: StringName) -> bool:
	var rec: Dictionary = _plugins.get(String(plugin), {})
	return rec.get("status", &"") == &"loaded" and not rec.faulted


func is_faulted(plugin: StringName) -> bool:
	return _plugins.get(String(plugin), {}).get("faulted", false)


func report_error(plugin: StringName, error: String) -> void:
	var rec: Dictionary = _plugins.get(String(plugin), {})
	if rec.is_empty() or rec.status != &"loaded" or rec.faulted:
		return
	rec.errors += 1
	rec.last_error = error
	push_warning("[vn_plugin %s] erro %d/%d: %s" % [plugin, rec.errors, FAULT_THRESHOLD, error])
	if rec.errors >= FAULT_THRESHOLD:
		_set_faulted(plugin, error)


func notify_game_started(is_new_game: bool) -> void:
	for ns in _order:
		_invoke(StringName(ns), &"_vn_game_started", [is_new_game])


func notify_game_ended() -> void:
	for ns in _order:
		_invoke(StringName(ns), &"_vn_game_ended")


func shutdown() -> void:
	if not _activity.is_empty():
		cancel_activity(STATUS_CANCELLED)
	for ns in _order:
		_invoke(StringName(ns), &"_vn_shutdown", [], true)
	for ns in _order:
		_free_instance(_plugins[ns])
	_drain_script_errors()
	_remove_logger()
	_plugins.clear()
	_ids.clear()
	_order = PackedStringArray()
	_failures.clear()


## Falhas de carga desta sessão: [code][{ plugin, id, error }][/code].
func load_failures() -> Array[Dictionary]:
	return _failures.duplicate(true)


## Confiança do plugin ([constant TRUST_OFFICIAL], [constant TRUST_REVIEWED]
## ou [constant TRUST_LOCAL]); [code]&""[/code] se ele não está no bundle.
func plugin_trust(plugin: StringName) -> StringName:
	return _plugins.get(String(plugin), {}).get("trust", &"")


## Id do plugin ([code]vnstudio.fishing[/code]) a partir do namespace.
func plugin_id(plugin: StringName) -> String:
	return _plugins.get(String(plugin), {}).get("id", "")


## Erros contados nesta sessão.
func error_count(plugin: StringName) -> int:
	return _plugins.get(String(plugin), {}).get("errors", 0)


## A instância do entrypoint do plugin, ou [code]null[/code].
func plugin_instance(plugin: StringName) -> Object:
	return _plugins.get(String(plugin), {}).get("instance", null)


## O [code]plugin.json[/code] lido na carga, ou vazio.
func manifest(plugin: StringName) -> Dictionary:
	return _plugins.get(String(plugin), {}).get("manifest", {})


# --- Permissões -------------------------------------------------------------

func has_capability(plugin: StringName, capability: StringName) -> bool:
	var rec: Dictionary = _plugins.get(String(plugin), {})
	if rec.is_empty():
		return false
	var cap := String(capability)
	if not cap.contains(":"):
		cap = "runtime:" + cap
	return rec.capabilities.has(cap)


func can_read_variable(plugin: StringName, variable: String) -> bool:
	var rec: Dictionary = _plugins.get(String(plugin), {})
	if rec.is_empty():
		return false
	if _is_own_variable(rec, variable):
		return true
	if not has_capability(plugin, &"variables.read"):
		return false
	if _matches_any(variable, rec.read):
		return true
	var owner := _variable_plugin_ns(variable)
	if not owner.is_empty():
		# Variável de outro plugin: só com dependência declarada e leitura pedida (DM §4.6).
		var other: Dictionary = _plugins.get(owner, {})
		if other.is_empty():
			return false
		var m: Dictionary = rec.manifest
		var declared: bool = m.get("dependencies", {}).has(other.id) or m.get("optional_dependencies", {}).has(other.id)
		return declared and _matches_any(variable, m.get("variable_permissions", {}).get("read", []))
	return _variable_access(variable).get("plugins_read", "none") == "all"


func can_write_variable(plugin: StringName, variable: String) -> bool:
	var rec: Dictionary = _plugins.get(String(plugin), {})
	if rec.is_empty():
		return false
	if _is_own_variable(rec, variable):
		return true
	if not _variable_plugin_ns(variable).is_empty():
		return false  # variáveis de outro plugin nunca são graváveis (P017)
	return has_capability(plugin, &"variables.write") and _matches_any(variable, rec.write)


func can_request_scene(plugin: StringName, scene_id: String) -> bool:
	var rec: Dictionary = _plugins.get(String(plugin), {})
	return not rec.is_empty() and has_capability(plugin, &"scenes.request") and rec.scenes.has(scene_id)


func can_emit(plugin: StringName, event_name: String) -> bool:
	var rec: Dictionary = _plugins.get(String(plugin), {})
	if rec.is_empty() or not event_name.begins_with(String(plugin) + "."):
		return false
	for e in rec.manifest.get("events", {}).get("emits", []):
		if e is Dictionary and e.get("name", "") == event_name:
			return true
	return false


## Recusa uma chamada por falta de permissão (Plugin SDK §5.2): registra no
## log do plugin, emite [signal VNPluginHost.permission_denied] (para o
## Preview, [code]plugin.permission_denied[/code]), conta para [i]faulted[/i]
## e devolve [constant VNErrors.PERMISSION_DENIED]. As fachadas que devolvem
## [code]null[/code], [code]fallback[/code] ou [code]false[/code] descartam o resultado.
func deny(plugin: StringName, capability: StringName, call: String) -> VNResult:
	if not _on_main_thread():
		_deny_deferred.call_deferred(plugin, capability, call)
		return VNResult.failure(VNErrors.PERMISSION_DENIED, "%s exige %s" % [call, capability])
	_deny_deferred(plugin, capability, call)
	return VNResult.failure(VNErrors.PERMISSION_DENIED, "%s exige %s" % [call, capability])


## Confere o resultado de uma operação feita por um plugin em outro módulo:
## [code]PERMISSION_DENIED[/code] (verificação 6 do RT §6.2) e
## [code]WRONG_THREAD[/code] contam para [i]faulted[/i]. Devolve [param result].
func track_result(plugin: StringName, result: VNResult, call: String, capability: StringName = &"") -> VNResult:
	if result == null or result.ok:
		return result
	if result.error == VNErrors.PERMISSION_DENIED:
		if _on_main_thread():
			_deny_deferred(plugin, capability, call)
		else:
			_deny_deferred.call_deferred(plugin, capability, call)
	elif result.error == VNErrors.WRONG_THREAD:
		_report_wrong_thread(plugin, call)
	return result


## Leitura de variável por um plugin ([code]variables.get_value[/code]).
## Sem [code]variables.read[/code] (fora do próprio namespace), devolve
## [param fallback] e conta o erro. A permissão por variável é conferida pelo
## State Manager, que chama [method can_read_variable].
func plugin_read(plugin: StringName, id: String, fallback: Variant = null) -> Variant:
	if not _on_main_thread():
		_report_wrong_thread(plugin, "variables.get_value")
		return fallback
	var rec: Dictionary = _plugins.get(String(plugin), {})
	if rec.is_empty():
		return fallback
	if not _is_own_variable(rec, id) and not has_capability(plugin, &"variables.read"):
		deny(plugin, &"variables.read", "variables.get_value(%s)" % id)
		return fallback
	if not _is_own_variable(rec, id) and not can_read_variable(plugin, id):
		deny(plugin, &"variables.read", "variables.get_value(%s)" % id)
		return fallback
	return modules().state.read_value(id, fallback, VNStateManager.plugin_caller(plugin))


## Escrita de variável por um plugin ([code]set_value[/code], [code]add_value[/code]…):
## [param op] é a operação do State Manager ([code]&"set"[/code], [code]&"add"[/code]…).
func plugin_write(plugin: StringName, op: StringName, id: String, value: Variant = null) -> VNResult:
	var call := "variables.%s(%s)" % [op, id]
	if not _on_main_thread():
		_report_wrong_thread(plugin, call)
		return VNResult.failure(VNErrors.WRONG_THREAD, call)
	var rec: Dictionary = _plugins.get(String(plugin), {})
	if rec.is_empty():
		return VNResult.failure(VNErrors.INVALID_STATE, "plugin desconhecido: %s" % plugin)
	if not _is_own_variable(rec, id) and not has_capability(plugin, &"variables.write"):
		return deny(plugin, &"variables.write", call)
	var result := modules().state.write(op, id, value, VNStateManager.plugin_caller(plugin))
	return track_result(plugin, result, call, &"variables.write")


## Emissão de evento por um plugin (Plugin SDK §5.4, §7): exige
## [code]events.emit[/code], o próprio namespace e o evento em [code]events.emits[/code].
func plugin_emit(plugin: StringName, event_name: String, payload: Dictionary = {}) -> VNResult:
	var call := "events.emit(%s)" % event_name
	if not _on_main_thread():
		_report_wrong_thread(plugin, call)
		return VNResult.failure(VNErrors.WRONG_THREAD, call)
	if not has_capability(plugin, &"events.emit") or not can_emit(plugin, event_name):
		return deny(plugin, &"events.emit", call)
	return modules().events.emit(event_name, payload, plugin_id(plugin))


## Assinatura de eventos por um plugin. Os do próprio namespace não pedem
## capacidade; os outros exigem [code]events.subscribe[/code]. Devolve o id da
## assinatura, ou [code]-1[/code] se recusada.
func plugin_on(plugin: StringName, pattern: String, callback: Callable) -> int:
	var call := "events.on(%s)" % pattern
	if not _on_main_thread():
		_report_wrong_thread(plugin, call)
		return -1
	if not is_loaded(plugin):
		return -1
	var own := pattern.begins_with(String(plugin) + ".")
	if not own and not has_capability(plugin, &"events.subscribe"):
		deny(plugin, &"events.subscribe", call)
		return -1
	return modules().events.on(pattern, callback, plugin)


## Pedido de cena por um plugin (Plugin SDK §5.5): exige
## [code]scenes.request[/code] e a cena em [code]grants.scenes[/code].
func plugin_request_scene(plugin: StringName, scene_id: String) -> VNResult:
	var call := "scenes.request(%s)" % scene_id
	if not _on_main_thread():
		_report_wrong_thread(plugin, call)
		return VNResult.failure(VNErrors.WRONG_THREAD, call)
	if not can_request_scene(plugin, scene_id):
		return deny(plugin, &"scenes.request", call)
	return modules().scheduler.request(scene_id, plugin)


# --- Atividades (caminho básico; M3-04 completa) -----------------------------

func start_activity(activity: StringName, params: Dictionary, mode: StringName = MODE_STORY) -> VNResult:
	if not _activity.is_empty():
		return VNResult.failure(VNErrors.INVALID_STATE, "já há atividade em curso: %s" % _activity.activity)
	var full := String(activity)
	var dot := full.find(".")
	if dot <= 0:
		return VNResult.failure(VNErrors.INVALID_STATE, "atividade sem namespace: %s" % full)
	var ns := StringName(full.substr(0, dot))
	var act := full.substr(dot + 1)
	if is_faulted(ns):
		return VNResult.failure(VNErrors.INVALID_STATE, "plugin %s está faulted" % ns)
	if not is_loaded(ns):
		return VNResult.failure(VNErrors.INVALID_STATE, "plugin %s não carregado" % ns)
	var decl := _activity_decl(ns, act)
	if decl.is_empty():
		return VNResult.failure(VNErrors.INVALID_STATE, "atividade não declarada: %s" % full)
	if mode == MODE_FREE_PLAY and not decl.has("free_play"):
		return VNResult.failure(VNErrors.INVALID_STATE, "atividade sem free_play: %s" % full)
	if not handle_factory.is_valid() and _sdk_script(&"VNActivityHandle") == null:
		return VNResult.failure(VNErrors.INVALID_STATE, "Runtime SDK ausente: sem VNActivityHandle")
	_activity_token += 1
	_activity = {
		"activity": activity, "mode": mode, "params": params,
		"skippable": bool(decl.get("skippable", false)), "min_fps": int(decl.get("min_fps", 0)),
		"plugin": ns, "id": StringName(act), "token": _activity_token,
		"outcomes": decl.get("outcomes", []), "default_outcome": decl.get("default_outcome", ""),
	}
	var handle = handle_factory.call(self, current_activity()) if handle_factory.is_valid() else _sdk_handle(ns, StringName(act), params, mode)
	if _activity.get("token", -1) == _activity_token:
		_activity.handle = handle
	var token := _activity_token
	_invoke(ns, &"_vn_start_activity", [StringName(act), params, handle])
	# Erro de script antes de complete/fail: a atividade falha (RT §5.3, on_error).
	if _activity.get("token", -1) == token and _activity.get("script_error", false):
		_end_activity(STATUS_FAILED, &"", {})
	return VNResult.success()


func cancel_activity(status: StringName) -> void:
	if _activity.is_empty():
		return
	var act := _activity
	_activity = {}  # o handle fica inativo antes de _vn_cancel_activity (SDK §6)
	if status == STATUS_FAILED:
		report_error(act.plugin, "timeout da atividade %s" % act.activity)
	_close_handle(act.get("handle"))
	_invoke(act.plugin, &"_vn_cancel_activity", [act.get("handle")])
	var outcome := StringName(act.default_outcome) if status == STATUS_SKIPPED else &""
	activity_ended.emit(status, outcome, {})


func current_activity() -> Dictionary:
	if _activity.is_empty():
		return {}
	return {
		"activity": _activity.activity, "mode": _activity.mode,
		"params": _activity.params, "skippable": _activity.skippable,
		"min_fps": _activity.get("min_fps", 0),
	}


## O handle de [param token] ainda é o da atividade em curso.
func is_activity_active(token: int) -> bool:
	return not _activity.is_empty() and _activity.token == token


## Token da atividade em curso (o handle guarda para as chamadas abaixo), ou -1.
func activity_token() -> int:
	return _activity.get("token", -1)


## [code]handle.complete(outcome, payload)[/code]. Outcome fora de
## [code]outcomes[/code] é erro do plugin e a atividade falha (RT §5.3 passo 6).
## Chamadas com handle inativo são ignoradas com aviso (SDK §6).
func complete_activity(token: int, outcome: StringName, payload: Dictionary = {}) -> void:
	if not is_activity_active(token):
		push_warning("[vn_plugin] complete com handle inativo ignorado")
		return
	if not _activity.outcomes.has(String(outcome)):
		var ns: StringName = _activity.plugin
		var act: StringName = _activity.activity
		_end_activity(STATUS_FAILED, &"", {})
		report_error(ns, "outcome desconhecido '%s' em %s" % [outcome, act])
		return
	_end_activity(STATUS_COMPLETED, outcome, payload)


## [code]handle.fail(reason)[/code]: conta como erro do plugin (RT §9).
func fail_activity(token: int, reason: String) -> void:
	if not is_activity_active(token):
		push_warning("[vn_plugin] fail com handle inativo ignorado")
		return
	var ns: StringName = _activity.plugin
	var act: StringName = _activity.activity
	_end_activity(STATUS_FAILED, &"", {})
	report_error(ns, "atividade %s falhou: %s" % [act, reason])


# --- Saves (caminho básico; M3-05 completa) --------------------------------

func save_data() -> Dictionary:
	var out := _foreign_saves.duplicate(true)
	for ns in _order:
		var rec: Dictionary = _plugins[ns]
		if not has_capability(StringName(ns), &"save.data"):
			continue
		if rec.faulted:
			if _last_saves.has(ns):
				out[ns] = _last_saves[ns].duplicate(true)
			continue
		if not _has_method(rec, &"_vn_save"):
			continue
		var data = _invoke(StringName(ns), &"_vn_save")
		var entry := {"plugin_version": rec.version, "data_version": _data_version(rec), "data": data}
		_last_saves[ns] = entry
		out[ns] = entry.duplicate(true)
	return out


func load_data(plugins_state: Dictionary) -> void:
	_foreign_saves.clear()
	_last_saves.clear()
	for ns in plugins_state:
		if not _order.has(String(ns)):
			push_warning("[vn_plugin] dados de save do plugin ausente '%s' preservados" % ns)
			_foreign_saves[ns] = plugins_state[ns].duplicate(true)
	for ns in _order:
		var rec: Dictionary = _plugins[ns]
		if rec.faulted:
			if plugins_state.has(ns):
				_last_saves[ns] = plugins_state[ns].duplicate(true)
			continue
		_invoke(StringName(ns), &"_vn_game_started", [false])
		var entry: Dictionary = plugins_state.get(ns, {})
		if entry.is_empty():
			_invoke(StringName(ns), &"_vn_load", [null])
			continue
		var data = entry.get("data")
		var from := int(entry.get("data_version", 1))
		var current := _data_version(rec)
		if from > current:
			push_warning("[vn_plugin %s] data_version %d do save é maior que a do plugin (%d)" % [ns, from, current])
		while from < current and _has_method(rec, &"_vn_migrate_save_data"):
			data = _invoke(StringName(ns), &"_vn_migrate_save_data", [data, from])
			from += 1
		_last_saves[ns] = {"plugin_version": rec.version, "data_version": current, "data": data}
		_invoke(StringName(ns), &"_vn_load", [data])


# --- Interno: carga ----------------------------------------------------------

func _new_record(id: String, entry: Variant) -> Dictionary:
	var e: Dictionary = entry if entry is Dictionary else {}
	var caps := {}
	for c in e.get("capabilities", []):
		caps[String(c)] = true
	var vars: Dictionary = e.get("variables", {})
	var trust := StringName(e.get("trust", TRUST_LOCAL))
	return {
		"id": String(e.get("id", id)), "key": id, "namespace": String(e.get("namespace", "")),
		"version": String(e.get("version", "")), "path": String(e.get("path", "")),
		"trust": trust, "embedded": bool(e.get("embedded", false)),
		"capabilities": caps, "read": Array(vars.get("read", [])), "write": Array(vars.get("write", [])),
		"scenes": Array(e.get("scenes", [])), "config": Dictionary(e.get("config", {})),
		"manifest": {}, "instance": null, "status": &"pending",
		"errors": 0, "faulted": false, "last_error": "",
	}


func _check_entry(rec: Dictionary) -> String:
	var ns: String = rec.namespace
	if rec.id != rec.key:
		return "id '%s' difere da chave '%s' em plugins.json" % [rec.id, rec.key]
	if ns in RESERVED_NAMESPACES:
		return "namespace reservado: %s" % ns
	if not ns.is_valid_identifier() or ns != ns.to_lower():
		return "namespace inválido: %s" % ns
	var expected := plugins_root + ns + "/"
	if rec.path != expected:
		return "caminho '%s' deveria ser '%s' (Plugin SDK §2.4)" % [rec.path, expected]
	if not rec.trust in [TRUST_OFFICIAL, TRUST_REVIEWED, TRUST_LOCAL]:
		return "confiança desconhecida: %s" % rec.trust
	return ""


func _read_manifest(rec: Dictionary) -> String:
	var path: String = rec.path + "plugin.json"
	if not FileAccess.file_exists(path):
		return "plugin.json não encontrado em %s" % rec.path
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return "plugin.json ilegível em %s" % rec.path
	var m: Dictionary = parsed
	rec.manifest = m
	if m.get("id", "") != rec.id:
		return "plugin.json tem id '%s', esperado '%s'" % [m.get("id", ""), rec.id]
	if m.get("namespace", "") != rec.namespace:
		return "plugin.json tem namespace '%s', esperado '%s'" % [m.get("namespace", ""), rec.namespace]
	if not rec.version.is_empty() and m.get("version", "") != rec.version:
		return "plugin.json tem versão %s, o bundle pede %s" % [m.get("version", ""), rec.version]
	if rec.version.is_empty():
		rec.version = String(m.get("version", ""))
	if not m.get("targets", []).has("runtime"):
		return ""
	var compat: Dictionary = m.get("compatibility", {})
	var checks := [
		["compatibility.runtime", String(compat.get("runtime", "")), RUNTIME_VERSION, true],
		["sdk.runtime", String(m.get("sdk", {}).get("runtime", "")), SDK_RUNTIME_VERSION, true],
		["compatibility.godot", String(compat.get("godot", "")), _godot_version(), false],
	]
	for c in checks:
		if String(c[1]).is_empty():
			if c[3]:
				return "%s ausente" % c[0]
			continue
		if not Semver.is_valid_range(c[1]):
			return "%s ilegível: '%s'" % [c[0], c[1]]
		if not Semver.satisfies(c[2], c[1]):
			return "%s '%s' não aceita a versão %s" % [c[0], c[1], c[2]]
	var entry := String(m.get("entrypoints", {}).get("runtime", ""))
	if entry.is_empty():
		return "entrypoints.runtime ausente"
	if entry.begins_with("/") or entry.contains("://") or entry.contains("..") or not entry.ends_with(".gd"):
		return "entrypoints.runtime inválido: %s" % entry
	return ""


func _resolve_dependencies(id: String, candidates: Dictionary, deps: Dictionary) -> String:
	var m: Dictionary = _plugins[_ids[id]].manifest
	var out := []
	for kind in ["dependencies", "optional_dependencies"]:
		var required: bool = kind == "dependencies"
		var table = m.get(kind, {})
		if not table is Dictionary:
			continue
		for dep in table:
			var range_expr := String(table[dep])
			if not _ids.has(dep):
				if required:
					return "dependência %s ausente do jogo" % dep
				continue
			var other: Dictionary = _plugins[_ids[dep]]
			if not Semver.satisfies(other.version, range_expr):
				return "dependência %s %s não aceita a versão %s" % [dep, range_expr, other.version]
			if other.status == &"editor_only":
				continue
			if not candidates.has(dep):
				if required:
					return "dependência %s não carregou" % dep
				continue
			out.append(dep)
	deps[id] = out
	return ""


func _topological_order(candidates: Dictionary, deps: Dictionary) -> PackedStringArray:
	var remaining := {}
	for id in candidates:
		remaining[id] = (deps[id] as Array).filter(func(d): return candidates.has(d)).size()
	var order := PackedStringArray()
	while true:
		var ready := PackedStringArray()
		for id in remaining:
			if remaining[id] == 0:
				ready.append(id)
		if ready.is_empty():
			break
		ready.sort()
		var next: String = ready[0]
		order.append(next)
		remaining.erase(next)
		for id in remaining:
			if (deps[id] as Array).has(next):
				remaining[id] -= 1
	return order


func _instantiate(rec: Dictionary) -> void:
	var ns: String = rec.namespace
	var script_path: String = rec.path + String(rec.manifest.entrypoints.runtime)
	if not ResourceLoader.exists(script_path):
		_fail(ns, "entrypoint não encontrado: %s" % script_path)
		return
	var script = load(script_path)
	_drain_script_errors()
	if not script is Script or not (script as Script).can_instantiate():
		_fail(ns, "script do entrypoint não compila: %s" % script_path)
		return
	var inst = (script as Script).new()
	if inst == null:
		_fail(ns, "não foi possível instanciar %s" % script_path)
		return
	rec.instance = inst
	if inst is Node:
		(inst as Node).name = ns
		if _container != null:
			_container.add_child(inst)
	var ctx := _make_context(rec)
	rec.context = ctx
	rec.status = &"loaded"  # _invoke só chama plugins carregados
	_init_ns = StringName(ns)
	_init_failed = false
	_invoke(StringName(ns), &"_vn_init", [ctx])
	_init_ns = &""
	if _init_failed:
		_fail(ns, "erro de script em _vn_init: %s" % rec.last_error)
		return
	_order.append(ns)


func _make_context(rec: Dictionary) -> Object:
	var info := {
		"id": StringName(rec.id), "namespace": StringName(rec.namespace), "version": rec.version,
		"trust": rec.trust, "config": rec.config.duplicate(true), "capabilities": rec.capabilities.keys(),
	}
	if context_factory.is_valid():
		return context_factory.call(self, info)
	var ctx_script := _sdk_script(&"VNPluginContext")
	var bridge := make_sdk_bridge(info.namespace)
	if ctx_script != null and bridge != null:
		return ctx_script.call(&"create", bridge, info.id, info.namespace, info.config)
	var ctx := BasicContext.new()
	ctx.plugin_id = info.id
	ctx.plugin_namespace = info.namespace
	ctx.config = info.config
	return ctx


## A [code]VNPluginBridge[/code] do Runtime SDK para o plugin, ligada aos
## módulos do M0-07 por [code]vn_plugin_host_bridge.gd[/code]; [code]null[/code]
## se o addon não está no projeto. Enquanto o addon não entra no runtime
## (integração), a subclasse de [code]VNPluginBridge[/code] é um adaptador
## compilado aqui, que só repassa as chamadas; o código da ponte é o do arquivo.
func make_sdk_bridge(plugin: StringName) -> Object:
	if _sdk_script(&"VNPluginBridge") == null:
		return null
	if _adapter_script == null:
		var s := GDScript.new()
		s.source_code = _ADAPTER_SOURCE
		if s.reload() != OK:
			push_warning("[vn_plugin] adaptador da VNPluginBridge não compilou")
			return null
		_adapter_script = s
	var core := HostBridge.new(self, plugin)
	var bridge: Object = _adapter_script.new()
	bridge.call(&"_bind", core)
	return bridge


## Script de uma classe global do Runtime SDK, ou [code]null[/code] se o addon
## não está no projeto.
func _sdk_script(cls_name: StringName) -> Script:
	if _sdk_scripts.has(cls_name):
		return _sdk_scripts[cls_name]
	var found: Script = null
	for cls in ProjectSettings.get_global_class_list():
		if cls.get("class", &"") == cls_name:
			var s = load(cls.path)
			if s is Script and (s as Script).can_instantiate():
				found = s
			break
	_sdk_scripts[cls_name] = found
	return found


func _sdk_handle(ns: StringName, act: StringName, params: Dictionary, mode: StringName) -> Object:
	var token := _activity_token
	var on_finish := func(status: StringName, outcome: StringName, payload: Dictionary, reason: String) -> void:
		if status == STATUS_COMPLETED:
			complete_activity(token, outcome, payload)
		else:
			fail_activity(token, reason)
	var rec: Dictionary = _plugins.get(String(ns), {})
	var ctx = rec.get("context")
	var bridge = null
	if ctx != null and "narrative" in ctx and ctx.narrative != null:
		bridge = ctx.narrative.get(&"_bridge")
	return _sdk_script(&"VNActivityHandle").new(act, params, mode, null, on_finish, bridge)


func _close_handle(handle: Variant) -> void:
	if handle is Object and is_instance_valid(handle) and (handle as Object).has_method(&"close"):
		(handle as Object).call(&"close")


func _fail(ns: String, error: String) -> void:
	var rec: Dictionary = _plugins.get(ns, {})
	var id := ns
	if not rec.is_empty():
		id = rec.id
		rec.status = &"failed"
		rec.last_error = error
		_free_instance(rec)
	if _order.has(ns):
		_order.remove_at(_order.find(ns))
	_record_failure(StringName(ns), id, error)


func _record_failure(ns: StringName, id: String, error: String) -> void:
	_failures.append({"plugin": ns, "id": id, "error": error})
	push_warning("[vn_plugin %s] não carregou: %s" % [id, error])
	plugin_load_failed.emit(ns, error)


func _free_instance(rec: Dictionary) -> void:
	var inst = rec.get("instance")
	rec.instance = null
	rec.context = null
	if inst is Node:
		var n := inst as Node
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.free()
	elif inst is Object and not inst is RefCounted and is_instance_valid(inst):
		(inst as Object).free()


# --- Interno: chamadas e erros -------------------------------------------

func _has_method(rec: Dictionary, method: StringName) -> bool:
	var inst = rec.get("instance")
	return inst != null and is_instance_valid(inst) and inst.has_method(method)


## Chama um método do plugin, se ele existir, e atribui os erros de script.
func _invoke(ns: StringName, method: StringName, args: Array = [], even_faulted := false) -> Variant:
	var rec: Dictionary = _plugins.get(String(ns), {})
	if rec.is_empty() or rec.status != &"loaded" or (rec.faulted and not even_faulted):
		return null
	if not _has_method(rec, method):
		return null
	var result = rec.instance.callv(method, args)
	_drain_script_errors()
	return result


## Atribui os erros de script da fila a plugins pelo caminho do arquivo.
func _drain_script_errors() -> void:
	if _logger == null:
		return
	for e in _logger.take():
		var ns := _plugin_of_files(e.files)
		if ns.is_empty():
			continue
		var msg := "erro de script em %s:%d: %s" % [e.file, e.line, e.message]
		if ns == _init_ns:
			_init_failed = true
			_plugins[String(ns)].last_error = msg
			continue
		if not _activity.is_empty() and _activity.plugin == ns:
			_activity.script_error = true
		report_error(ns, msg)


func _plugin_of_files(files: PackedStringArray) -> StringName:
	for f in files:
		if not f.begins_with(plugins_root):
			continue
		var ns := f.substr(plugins_root.length()).get_slice("/", 0)
		if _plugins.has(ns):
			return StringName(ns)
	return &""


func _install_logger() -> void:
	if _logger == null:
		_logger = ErrorLogger.new()
		OS.add_logger(_logger)


func _remove_logger() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


func _set_faulted(plugin: StringName, error: String) -> void:
	var rec: Dictionary = _plugins[String(plugin)]
	rec.faulted = true
	push_warning("[vn_plugin %s] faulted: %s" % [rec.id, error])
	var m := modules()
	if m != null and m.events != null:
		m.events.off_owner(plugin)
	if not _activity.is_empty() and _activity.plugin == plugin:
		var act := _activity
		_activity = {}
		_close_handle(act.get("handle"))
		_invoke(plugin, &"_vn_cancel_activity", [act.get("handle")], true)
		activity_ended.emit(STATUS_FAILED, &"", {})
	plugin_faulted.emit(plugin, error)


func _deny_deferred(plugin: StringName, capability: StringName, call: String) -> void:
	push_warning("[vn_plugin %s] PERMISSION_DENIED: %s exige %s" % [plugin, call, capability])
	permission_denied.emit(plugin, capability, call)
	report_error(plugin, "PERMISSION_DENIED: %s" % call)


func _report_wrong_thread(plugin: StringName, call: String) -> void:
	if _on_main_thread():
		report_error(plugin, "WRONG_THREAD: %s" % call)
	else:
		report_error.call_deferred(plugin, "WRONG_THREAD: %s" % call)


func _end_activity(status: StringName, outcome: StringName, payload: Dictionary) -> void:
	_activity = {}
	activity_ended.emit(status, outcome, payload)


func _activity_decl(ns: StringName, act: String) -> Dictionary:
	for a in _plugins.get(String(ns), {}).get("manifest", {}).get("activities", []):
		if a is Dictionary and a.get("id", "") == act:
			return a
	return {}


func _data_version(rec: Dictionary) -> int:
	return int(rec.manifest.get("save", {}).get("data_version", 1))


# --- Interno: variáveis ----------------------------------------------------

func _is_own_variable(rec: Dictionary, variable: String) -> bool:
	return variable.begins_with("plugin.%s." % rec.namespace)


## Namespace do plugin dono de [code]plugin.<ns>.<chave>[/code], ou vazio.
func _variable_plugin_ns(variable: String) -> String:
	if not variable.begins_with("plugin."):
		return ""
	return variable.get_slice(".", 1)


## [code]access[/code] da definição da variável (DM §4.6), do Variable Manager
## ou, sem ele, do bundle.
func _variable_access(variable: String) -> Dictionary:
	var m := modules()
	var def: Dictionary = {}
	if m != null and m.variables != null:
		def = m.variables.get_definition(variable)
	if def.is_empty():
		def = _bundle.get("variables", {}).get(variable, {})
	return def.get("access", {})


## Casa o id com uma lista de concessões; [code]*[/code] vale um segmento inteiro.
static func _matches_any(variable: String, patterns: Array) -> bool:
	var parts := variable.split(".")
	for p in patterns:
		var pp := String(p).split(".")
		if pp.size() != parts.size():
			continue
		var ok := true
		for i in pp.size():
			if pp[i] != "*" and pp[i] != parts[i]:
				ok = false
				break
		if ok:
			return true
	return false


static func _on_main_thread() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()


static func _godot_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]


## Contexto mínimo enquanto o Runtime SDK (M3-02) não está no projeto: só a
## identidade do plugin e a configuração (Plugin SDK §5.2). O campo
## [code]namespace[/code] do SDK §5.2 não compila em GDScript (palavra
## reservada), então aqui ele é [code]plugin_namespace[/code].
class BasicContext:
	extends RefCounted
	var plugin_id: StringName
	var plugin_namespace: StringName  ## "namespace" é palavra reservada do GDScript
	var config: Dictionary
