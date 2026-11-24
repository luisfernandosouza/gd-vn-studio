class_name VNTransaction
extends VNPluginService
## Transação do plugin (Plugin SDK §5.3; RT §6.1): acumula operações e só valida
## e aplica no [method commit], tudo ou nada.
##
## Operações relativas ([code]add[/code], [code]subtract[/code],
## [code]toggle[/code]) são calculadas sobre o valor no momento do commit;
## [code]set_value[/code] sobrescreve. [method expect] é pré-condição
## (compare-and-set): se o valor no commit for outro, o commit falha com
## [code]CONFLICT[/code] e nada é aplicado.
##
## Diferença de nome em relação ao texto original da spec: a operação de
## atribuição é [method set_value], porque [code]set[/code] é método nativo de
## [Object] e não pode ser sobrescrito em GDScript (Plugin SDK §5.3).

var _allowed: bool = true
var _ops: Array[Dictionary] = []
var _expectations: Array[Dictionary] = []
var _finished: bool = false


func _init(bridge: VNPluginBridge = null, plugin_namespace: StringName = &"", allowed: bool = true) -> void:
	super(bridge, plugin_namespace)
	_allowed = allowed


func set_value(id: String, value: Variant) -> VNTransaction:
	return _add(&"set", id, value)


func add(id: String, amount: float) -> VNTransaction:
	return _add(&"add", id, VNRuntimeSDK.normalize_amount(amount))


func subtract(id: String, amount: float) -> VNTransaction:
	return _add(&"subtract", id, VNRuntimeSDK.normalize_amount(amount))


func toggle(id: String) -> VNTransaction:
	return _add(&"toggle", id, null)


func reset(id: String) -> VNTransaction:
	return _add(&"reset", id, null)


## Pré-condição: no commit, [param id] deve valer [param value].
func expect(id: String, value: Variant) -> VNTransaction:
	if not _finished:
		_expectations.append({"variable": VNRuntimeSDK.qualify(id, _ns), "value": value})
	return self


## Valida e aplica tudo ou nada. Depois do commit (ou do rollback), a transação
## não aceita mais operações, e um segundo commit devolve [code]INVALID_STATE[/code].
func commit() -> VNResult:
	if _finished:
		return VNResult.failure(VNRuntimeSDK.INVALID_STATE, "transação já encerrada")
	_finished = true
	if not _allowed:
		return VNResult.failure(VNRuntimeSDK.PERMISSION_DENIED, "begin_transaction requer transactions")
	if not _check_thread("transaction.commit"):
		return _wrong_thread("transaction.commit")
	var result := _bridge.commit(_ops.duplicate(true), _expectations.duplicate(true))
	if not result.ok and result.error == VNRuntimeSDK.PERMISSION_DENIED:
		_bridge.permission_denied(VNRuntimeSDK.CAP_VARIABLES_WRITE, "transaction.commit")
	return result


## Descarta as operações sem aplicar nada.
func rollback() -> void:
	_finished = true
	_ops.clear()
	_expectations.clear()


## Operações acumuladas, no formato do DM §6.2 (para testes e depuração).
func pending_ops() -> Array[Dictionary]:
	return _ops.duplicate(true)


func is_finished() -> bool:
	return _finished


func _add(op: StringName, id: String, value: Variant) -> VNTransaction:
	if not _finished:
		var entry := {"op": op, "variable": VNRuntimeSDK.qualify(id, _ns)}
		if op not in [&"toggle", &"reset"]:
			entry["value"] = value
		_ops.append(entry)
	return self
