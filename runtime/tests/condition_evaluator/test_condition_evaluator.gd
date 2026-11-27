extends SceneTree
## Testes unitários do Condition Evaluator real (tarefa M1-03): o que os vetores de
## conformidade não cobrem (DM §6.1: {"result"}, {"if"}, escopo; DM §6.1.1: aridade,
## random_int, T007/T008). Sai com 1 se algo falhar.
##
##   godot --headless --path runtime --script res://tests/condition_evaluator/test_condition_evaluator.gd

var _passed := 0
var _failed := 0
var _reg: Array[VNModules] = []


func _init() -> void:
	for m in get_script().get_script_method_list():
		var n: String = m.name
		if not n.begins_with("test_"):
			continue
		var err: String = call(n)
		if err.is_empty():
			_passed += 1
			print("ok      ", n.trim_prefix("test_"))
		else:
			_failed += 1
			print("FALHOU  ", n.trim_prefix("test_"), ": ", err)
	print("%d/%d testes do Condition Evaluator passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 or _passed == 0 else 0)


func _ev() -> VNConditionEvaluatorImpl:
	var m := VNFakeModules.create()
	var vm := VNVariableManagerImpl.new()
	vm.quiet = true
	var ce := VNConditionEvaluatorImpl.new()
	m.variables = vm
	m.conditions = ce
	m.bind_all()
	vm.load_bundle({"project": {"default_locale": "pt-BR"}, "variables": {
		"global.money": {"key": "money", "type": "integer", "default": 5, "persistence": "save"},
		"global.mood": {"key": "mood", "type": "enum", "persistence": "save", "constraints": {"values": ["calm", "angry"]}},
	}, "aliases": {}, "chapters": {}, "scenes": {}})
	vm.reset_game()
	_reg.append(m)
	return ce


static func _chk(label: String, r: VNEvalResult, type: Variant, value: Variant = null) -> String:
	if type is StringName and type != &"integer" and type != &"number" and type != &"string" and type != &"boolean" and type != &"enum":
		return "" if (not r.ok and r.error == type) else "%s: esperava erro %s, veio ok=%s %s %s" % [label, type, r.ok, r.error, r.value]
	if not r.ok:
		return "%s: erro inesperado %s %s" % [label, r.error, r.message]
	if r.type != type or typeof(r.value) != typeof(value) or r.value != value:
		return "%s: esperava %s %s, veio %s %s" % [label, type, value, r.type, r.value]
	return ""


func test_aridade_e_funcao_desconhecida() -> String:
	var ce := _ev()
	for expr in [{"fn": "add", "args": [1]}, {"fn": "round", "args": []}, {"fn": "min", "args": [1]},
			{"fn": "concat", "args": [1, 2, 3, 4, 5, 6, 7, 8, 9]}, {"fn": "nope", "args": [1]}, {"fn": "add", "args": 3}]:
		var e := _chk(JSON.stringify(expr), ce.evaluate_expression(expr), VNErrors.TYPE_MISMATCH)
		if e != "":
			return e
	return ""


func test_args_avaliados_e_erro_propaga() -> String:
	var ce := _ev()
	var e := _chk("var ausente em arg", ce.evaluate_expression({"fn": "add", "args": [1, {"var": "global.nada"}]}), VNErrors.VARIABLE_NOT_FOUND)
	if e != "":
		return e
	e = _chk("escopo inativo", ce.evaluate_expression({"var": "scene.x"}), VNErrors.VARIABLE_NOT_FOUND)
	return e


func test_enum_e_variavel() -> String:
	var ce := _ev()
	var e := _chk("enum", ce.evaluate_expression({"var": "global.mood"}), &"enum", "calm")
	if e != "":
		return e
	return _chk("integer", ce.evaluate_expression({"fn": "mul", "args": [{"var": "global.money"}, 2]}), &"integer", 10)


func test_random_int() -> String:
	var ce := _ev()
	var e := _chk("sem allow_random", ce.evaluate_expression({"fn": "random_int", "args": [1, 3]}), VNErrors.TYPE_MISMATCH)
	if e != "":
		return e
	for i in 50:
		var r := ce.evaluate_expression({"fn": "random_int", "args": [1, 3]}, {}, &"", true)
		if not r.ok or r.type != &"integer" or r.value < 1 or r.value > 3:
			return "random_int fora de [1,3]: %s" % r.value
	e = _chk("inclusivo igual", ce.evaluate_expression({"fn": "random_int", "args": [4, 4]}, {}, &"", true), &"integer", 4)
	if e != "":
		return e
	e = _chk("min > max", ce.evaluate_expression({"fn": "random_int", "args": [5, 1]}, {}, &"", true), VNErrors.OUT_OF_RANGE)
	if e != "":
		return e
	return _chk("tipos", ce.evaluate_expression({"fn": "random_int", "args": [1.5, 3]}, {}, &"", true), VNErrors.TYPE_MISMATCH)


func test_result() -> String:
	var ce := _ev()
	var b := {"result": {"score": 42, "a": {"b": 1.5}, "name": "x"}}
	var checks := [
		["campo", {"result": "score"}, &"integer", &"integer", 42],
		["caminho a.b", {"result": "a.b"}, &"number", &"number", 1.5],
		["ausente com default", {"result": "nada", "default": 7}, &"integer", &"integer", 7],
		["ausente sem default", {"result": "nada"}, &"integer", &"integer", 0],
		["ausente number", {"result": "nada"}, &"number", &"number", 0.0],
		["tipo errado vira default", {"result": "name", "default": 3}, &"integer", &"integer", 3],
		["tipo errado vira padrão", {"result": "name"}, &"boolean", &"boolean", false],
	]
	for c in checks:
		var e := _chk(c[0], ce.evaluate_expression(c[1], b, c[2]), c[3], c[4])
		if e != "":
			return e
	return _chk("sem bindings", ce.evaluate_expression({"result": "score", "default": 9}, {}, &"integer"), &"integer", 9)


func test_if_aninhado_e_forma_invalida() -> String:
	var ce := _ev()
	var expr := {"if": [{"variable": "global.money", "operator": "equals", "value": 5}],
		"then": {"if": [], "then": "a", "else": "b"}, "else": "c"}
	var e := _chk("if aninhado", ce.evaluate_expression(expr), &"string", "a")
	if e != "":
		return e
	e = _chk("if com erro", ce.evaluate_expression({"if": [{"variable": "global.nada", "operator": "equals", "value": 1}], "then": 1, "else": 2}), VNErrors.VARIABLE_NOT_FOUND)
	if e != "":
		return e
	e = _chk("objeto estranho", ce.evaluate_expression({"foo": 1}), VNErrors.TYPE_MISMATCH)
	if e != "":
		return e
	return _chk("lista", ce.evaluate_expression([1, 2]), VNErrors.TYPE_MISMATCH)


func test_explain() -> String:
	var ce := _ev()
	var cond := [{"variable": "global.money", "operator": "equals", "value": 5},
		{"any": [{"variable": "global.money", "operator": "greater_than", "value": 10},
			{"variable": "global.money", "operator": "less_than", "value": 1}]}]
	var out := ce.explain_conditions(cond)
	if out.size() != 2 or out[0].path != "conditions[1].any[0]" or out[0].actual != 5 or out[0].expected != 10 or out[1].path != "conditions[1].any[1]":
		return "explain: %s" % [out]
	if not ce.explain_conditions([]).is_empty():
		return "condição verdadeira não explica nada"
	return ""
