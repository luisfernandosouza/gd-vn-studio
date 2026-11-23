class_name VNStateTransaction
extends RefCounted
## Transação do State Manager (RT §6.1; Plugin SDK §5.3).
##
## Só acumula operações; quem valida e aplica é
## [method VNStateManager.commit_transaction], no [method commit]. Operações
## relativas ([code]add[/code], [code]subtract[/code], [code]multiply[/code],
## [code]toggle[/code]) são calculadas sobre o valor no momento do commit;
## [code]set[/code] sobrescreve. [method expect] protege contra condição de
## corrida: se o valor no commit for outro, o commit falha com
## [code]CONFLICT[/code] e nada é aplicado.
##
## O [code]VNTransaction[/code] do Runtime SDK (M3-02) é uma fachada sobre
## esta classe, com o atalho [code]~chave[/code] já traduzido.

var caller: StringName = &"content"    ## quem escreve (ver VNStateManager.CALLER_*)
var ops: Array[Dictionary] = []        ## [{ op, variable, value? }], na ordem (DM §6.2)
var expectations: Array[Dictionary] = []  ## [{ variable, value }]
var finished: bool = false             ## commit ou rollback já chamados
var _manager_ref: WeakRef = null


func _init(manager: VNStateManager = null, p_caller: StringName = &"content") -> void:
	if manager != null:
		_manager_ref = weakref(manager)
	caller = p_caller


func set_value(id: String, value: Variant) -> VNStateTransaction:
	return _add(&"set", id, value)


func add(id: String, amount: Variant) -> VNStateTransaction:
	return _add(&"add", id, amount)


func subtract(id: String, amount: Variant) -> VNStateTransaction:
	return _add(&"subtract", id, amount)


func multiply(id: String, factor: Variant) -> VNStateTransaction:
	return _add(&"multiply", id, factor)


func toggle(id: String) -> VNStateTransaction:
	return _add(&"toggle", id, null)


func reset(id: String) -> VNStateTransaction:
	return _add(&"reset", id, null)


## Acrescenta um efeito no formato do DM §6.2 ([code]{ op, variable, value? }[/code]).
## [code]value[/code] já deve estar avaliado (literal), não uma expressão.
func effect(e: Dictionary) -> VNStateTransaction:
	return _add(StringName(e.get("op", "")), String(e.get("variable", "")), e.get("value"))


## Pré-condição (compare-and-set): no commit, [param id] deve valer [param value].
func expect(id: String, value: Variant) -> VNStateTransaction:
	if not finished:
		expectations.append({"variable": id, "value": value})
	return self


## Tudo ou nada. Depois do commit, a transação não aceita mais operações.
func commit() -> VNResult:
	if finished:
		return VNResult.failure(VNErrors.INVALID_STATE, "transação já encerrada")
	finished = true
	var manager: VNStateManager = null if _manager_ref == null else _manager_ref.get_ref()
	if manager == null:
		return VNResult.failure(VNErrors.INVALID_STATE, "transação sem State Manager")
	return manager.commit_transaction(self)


## Descarta as operações sem aplicar nada.
func rollback() -> void:
	finished = true
	ops.clear()
	expectations.clear()


func _add(op: StringName, id: String, value: Variant) -> VNStateTransaction:
	if not finished:
		var entry := {"op": op, "variable": id}
		if op not in [&"toggle", &"reset"]:
			entry["value"] = value
		ops.append(entry)
	return self
