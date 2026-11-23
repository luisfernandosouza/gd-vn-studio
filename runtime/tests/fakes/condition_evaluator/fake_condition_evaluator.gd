class_name FakeConditionEvaluator
extends VNConditionEvaluator
## Dublê do Condition Evaluator. Literais e {"var"} são resolvidos de verdade
## (pelo Variable Manager do registro); o resto devolve os valores programados.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

## Valor de toda condição não vazia.
var condition_result: bool = true
## Valor de expressões que não são literal nem {"var"}.
var expression_result: Variant = 0
## Se preenchido, toda avaliação falha com este código.
var fail_with: StringName = &""


func evaluate_conditions(conditions: Variant, bindings: Dictionary = {}) -> VNEvalResult:
	_rec(&"evaluate_conditions", [conditions, bindings])
	if fail_with != &"":
		return VNEvalResult.failure(fail_with)
	if conditions is Array and conditions.is_empty():
		return VNEvalResult.of(true, &"boolean")
	return VNEvalResult.of(condition_result, &"boolean")


func evaluate_expression(expr: Variant, bindings: Dictionary = {}, target_type: StringName = &"", allow_random: bool = false) -> VNEvalResult:
	_rec(&"evaluate_expression", [expr, bindings, target_type, allow_random])
	if fail_with != &"":
		return VNEvalResult.failure(fail_with)
	if expr is Dictionary and expr.has("var"):
		var m := modules()
		var id := String(expr["var"])
		if m == null or m.variables == null or not m.variables.has(id):
			return VNEvalResult.failure(VNErrors.VARIABLE_NOT_FOUND, id)
		return _typed(m.variables.read(id))
	if expr is Dictionary or expr is Array:
		return _typed(expression_result)
	return _typed(expr)


func explain_conditions(conditions: Variant) -> Array[Dictionary]:
	_rec(&"explain_conditions", [conditions])
	return []


static func _typed(v: Variant) -> VNEvalResult:
	match typeof(v):
		TYPE_BOOL: return VNEvalResult.of(v, &"boolean")
		TYPE_INT: return VNEvalResult.of(v, &"integer")
		TYPE_FLOAT: return VNEvalResult.of(v, &"number")
	return VNEvalResult.of(v, &"string")
