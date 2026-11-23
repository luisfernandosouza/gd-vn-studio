class_name FakeStateManager
extends VNStateManager
## Dublê do State Manager. Aplica set/add/subtract/multiply/toggle/reset no
## Variable Manager do registro, confere só existência, somente leitura e
## expect, e emite state_changed uma vez por operação ou transação.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

## Se preenchido, toda escrita falha com este código e nada é aplicado.
var fail_with: StringName = &""
var evaluating: bool = false


func read_value(id: String, fallback: Variant = null, caller: StringName = CALLER_CONTENT) -> Variant:
	_rec(&"read_value", [id, fallback, caller])
	return _vars().read(id, fallback)


func write(op: StringName, id: String, value: Variant = null, caller: StringName = CALLER_CONTENT) -> VNResult:
	_rec(&"write", [op, id, value, caller])
	var tx := begin_transaction(caller)
	tx.ops.append({"op": op, "variable": id, "value": value})
	return tx.commit()


func commit_transaction(tx: VNStateTransaction) -> VNResult:
	_rec(&"commit_transaction", [tx.ops.duplicate(true), tx.caller])
	return _apply(tx.ops, tx.expectations)


func apply_effects(effects: Array, bindings: Dictionary = {}, caller: StringName = CALLER_CONTENT, extra: Array[Dictionary] = []) -> VNResult:
	_rec(&"apply_effects", [effects, bindings, caller, extra])
	var ops: Array[Dictionary] = []
	for e in effects:
		var op: Dictionary = e.duplicate()
		if op.has("value"):
			var ev := modules().conditions.evaluate_expression(op.value, bindings, &"", true)
			if not ev.ok:
				return VNResult.failure(ev.error, ev.message)
			op.value = ev.value
		ops.append(op)
	ops.append_array(extra)
	return _apply(ops, [])


func set_system_value(id: String, value: Variant) -> void:
	_rec(&"set_system_value", [id, value])
	_vars().store(id, value)


func set_evaluating(p_evaluating: bool) -> void:
	evaluating = p_evaluating


func _vars() -> VNVariableManager:
	return modules().variables


func _apply(ops: Array[Dictionary], expectations: Array[Dictionary]) -> VNResult:
	if fail_with != &"":
		return VNResult.failure(fail_with)
	if evaluating:
		return VNResult.failure(VNErrors.INVALID_STATE)
	var vars := _vars()
	var pending := {}
	var changes: Array[Dictionary] = []
	for op in ops:
		var id := String(op.variable)
		if not vars.has(id):
			return VNResult.failure(VNErrors.VARIABLE_NOT_FOUND, id)
		if vars.is_read_only(id):
			return VNResult.failure(VNErrors.READ_ONLY, id)
		var old: Variant = pending.get(id, vars.read(id))
		var new_value: Variant
		match StringName(op.op):
			&"set": new_value = op.value
			&"add": new_value = old + op.value
			&"subtract": new_value = old - op.value
			&"multiply": new_value = old * op.value
			&"toggle": new_value = not old
			&"reset": new_value = vars.get_definition(id).get("default")
			_: return VNResult.failure(VNErrors.TYPE_MISMATCH, String(op.op))
		pending[id] = new_value
		if new_value != old:
			changes.append({"variable": id, "old": old, "new": new_value})
	for x in expectations:
		if vars.read(String(x.variable)) != x.value:
			return VNResult.failure(VNErrors.CONFLICT, String(x.variable))
	for id in pending:
		vars.store(id, pending[id])
	if not changes.is_empty():
		state_changed.emit(changes)
	return VNResult.success(changes)
