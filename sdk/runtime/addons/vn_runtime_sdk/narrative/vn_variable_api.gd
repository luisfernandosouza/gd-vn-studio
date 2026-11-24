class_name VNVariableAPI
extends VNPluginService
## Variáveis do jogo vistas pelo plugin (Plugin SDK §5.3; RT §6).
##
## IDs são sempre totalmente qualificados ([code]global.player_money[/code]);
## [code]"~chave"[/code] é atalho para [code]plugin.<namespace>.chave[/code].
##
## [b]Leitura[/b]: variáveis do próprio namespace sempre; as outras com
## [code]variables.read[/code] e permissão efetiva da variável (Plugin SDK §4.1).
## Sem permissão, [method has] devolve [code]false[/code], [method get_value] o
## [code]fallback[/code] e [method get_definition] vazio, e a ponte é avisada.
##
## [b]Escrita[/b]: cada chamada vira uma transação de uma operação no State
## Manager, que valida na ordem do RT §6.2. A permissão de escrita (verificação 6,
## [code]variables.write[/code] ∩ concessão ∩ aceite) é conferida lá, para que
## [code]VARIABLE_NOT_FOUND[/code] e [code]READ_ONLY[/code] venham antes de
## [code]PERMISSION_DENIED[/code]; quando o resultado é
## [code]PERMISSION_DENIED[/code], a ponte é avisada aqui.

## Mudanças em variáveis que o plugin pode ler, uma vez por operação ou
## transação aplicada (RT §6.4). Cada item: [code]{ variable, old, new }[/code].
signal changed(changes: Array[Dictionary])


func _init(bridge: VNPluginBridge = null, plugin_namespace: StringName = &"") -> void:
	super(bridge, plugin_namespace)
	_bridge.state_changed.connect(_on_state_changed)


func has(id: String) -> bool:
	var qid := VNRuntimeSDK.qualify(id, _ns)
	if not _check_thread("variables.has"):
		return false
	if not _can_read(qid, "variables.has", true):
		return false
	return _bridge.variable_exists(qid)


func get_value(id: String, fallback: Variant = null) -> Variant:
	var qid := VNRuntimeSDK.qualify(id, _ns)
	if not _check_thread("variables.get_value"):
		return fallback
	if not _can_read(qid, "variables.get_value", true):
		return fallback
	return _bridge.read_value(qid, fallback)


## Tipo, restrições e default da variável, sem valores de outros escopos.
func get_definition(id: String) -> Dictionary:
	var qid := VNRuntimeSDK.qualify(id, _ns)
	if not _check_thread("variables.get_definition"):
		return {}
	if not _can_read(qid, "variables.get_definition", true):
		return {}
	return _bridge.get_definition(qid)


func set_value(id: String, value: Variant) -> VNResult:
	return _write(&"set", id, value, "variables.set_value")


func add_value(id: String, amount: float) -> VNResult:
	return _write(&"add", id, VNRuntimeSDK.normalize_amount(amount), "variables.add_value")


func subtract_value(id: String, amount: float) -> VNResult:
	return _write(&"subtract", id, VNRuntimeSDK.normalize_amount(amount), "variables.subtract_value")


func toggle(id: String) -> VNResult:
	return _write(&"toggle", id, null, "variables.toggle")


func reset(id: String) -> VNResult:
	return _write(&"reset", id, null, "variables.reset")


## O plugin pode ler [param qid] (já qualificado). Com [param report], uma recusa
## avisa a ponte.
func _can_read(qid: String, call: String, report: bool) -> bool:
	if VNRuntimeSDK.is_own_variable(qid, _ns):
		return true
	if not _bridge.has_capability(VNRuntimeSDK.CAP_VARIABLES_READ):
		if report:
			_bridge.permission_denied(VNRuntimeSDK.CAP_VARIABLES_READ, "%s(%s)" % [call, qid])
		return false
	if not _bridge.can_read_variable(qid):
		if report:
			_bridge.permission_denied(VNRuntimeSDK.CAP_VARIABLES_READ, "%s(%s)" % [call, qid])
		return false
	return true


func _write(op: StringName, id: String, value: Variant, call: String) -> VNResult:
	if not _check_thread(call):
		return _wrong_thread(call)
	var qid := VNRuntimeSDK.qualify(id, _ns)
	var entry := {"op": op, "variable": qid}
	if op not in [&"toggle", &"reset"]:
		entry["value"] = value
	var ops: Array[Dictionary] = [entry]
	var result := _bridge.commit(ops, [] as Array[Dictionary])
	if not result.ok and result.error == VNRuntimeSDK.PERMISSION_DENIED:
		_bridge.permission_denied(VNRuntimeSDK.CAP_VARIABLES_WRITE, "%s(%s)" % [call, qid])
	return result


func _on_state_changed(changes: Array[Dictionary]) -> void:
	var visible: Array[Dictionary] = []
	for c in changes:
		if _can_read(String(c.get("variable", "")), "", false):
			visible.append(c)
	if not visible.is_empty():
		changed.emit(visible)
