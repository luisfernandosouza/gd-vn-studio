extends SceneTree
## Autoteste do executor de conformidade (M1-01):
##   godot --headless --path runtime --script res://tests/conformance/test_runner.gd
##
## Confere o leitor de JSON (inteiro × float), a comparação, a descoberta dos módulos reais, o
## formato da saída e os códigos de saída: caso pulado nunca conta como passado, falha sai com 1,
## erro de uso sai com 2. Liga os dublês como se fossem módulos reais para exercitar cada adaptador.

const Runner := preload("res://tests/vn_test_runner.gd")
const CASES_DIR := "user://vn_test_runner_selftest"

var _fails := 0
var _checks := 0


func _init() -> void:
	_test_json()
	_test_compare()
	_test_discovery()
	_test_runner()
	_test_all_adapters_with_fakes()
	print("%d/%d verificações do executor passaram" % [_checks - _fails, _checks])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FALHOU autoteste: " + what)


func _test_json() -> void:
	var r := VNCaseJson.parse('{"a": [-7, 3, 2.0, 1e3, 9007199254740993, 0, -0], "s": "x\\u00e9\\ud83d\\ude00\\n", "b": true, "n": null}')
	_check(r.ok, "JSON válido é lido: " + r.error)
	var a: Array = r.value["a"]
	_check(typeof(a[0]) == TYPE_INT and a[0] == -7, "-7 é inteiro")
	_check(typeof(a[2]) == TYPE_FLOAT and a[2] == 2.0, "2.0 é float")
	_check(typeof(a[3]) == TYPE_FLOAT and a[3] == 1000.0, "1e3 é float")
	_check(typeof(a[4]) == TYPE_INT and a[4] == 9007199254740993, "inteiro acima de 2^53 fica exato")
	_check(typeof(a[6]) == TYPE_INT and a[6] == 0, "-0 é o inteiro 0")
	_check(r.value["s"] == "xé😀\n", "escapes e par substituto")
	_check(r.value["b"] == true and r.value["n"] == null, "true e null")
	_check(r.value.keys() == ["a", "s", "b", "n"], "ordem das chaves preservada")
	_check(typeof(VNCaseJson.parse("99999999999999999999").value) == TYPE_FLOAT, "inteiro fora do int64 vira float")
	for bad in ["{", "[1,]", "{\"a\" 1}", "01x", "\"\\q\"", "[1] 2", ""]:
		_check(not VNCaseJson.parse(bad).ok, "JSON inválido recusado: %s" % bad)


func _test_compare() -> void:
	_check(VNCaseCompare.same(2, 2.0), "2 confere com 2.0")
	_check(not VNCaseCompare.same(2, 3), "2 não confere com 3")
	_check(not VNCaseCompare.same(1, true), "1 não confere com true")
	_check(not VNCaseCompare.same(0.0, false), "0.0 não confere com false")
	_check(VNCaseCompare.same({"type": "integer"}, {&"type": &"integer"}), "StringName vale como String")
	_check(not VNCaseCompare.same({"a": 1}, {"a": 1, "b": 2}), "chave a mais não confere")
	_check(VNCaseCompare.same(["a", "b"], PackedStringArray(["a", "b"])), "PackedStringArray vale como Array")
	_check(not VNCaseCompare.same(null, ""), "null não confere com texto vazio")
	_check(VNCaseCompare.to_json({"v": 2, "f": 2.0, "s": "x"}) == '{"v": 2, "f": 2.0, "s": "x"}', "to_json mostra o tipo: " + VNCaseCompare.to_json({"v": 2, "f": 2.0, "s": "x"}))


func _test_discovery() -> void:
	var real := VNCaseModules.discover()
	for id in real.implementations:
		var s: Script = real.implementations[id]
		_check(s.resource_path.begins_with("res://vn_runtime/"), "implementação real fora de vn_runtime/: " + s.resource_path)
	var fakes := VNCaseModules.discover("res://tests/fakes/")
	_check(fakes.implementations.size() == VNModules.MODULE_IDS.size(), "a descoberta acha um dublê por contrato (%d)" % fakes.implementations.size())
	_check(fakes.implementations.get(&"conditions") == FakeConditionEvaluator, "dublê do Condition Evaluator achado pelo contrato")


func _write_cases(name: String, cases: Array) -> String:
	DirAccess.make_dir_recursive_absolute(CASES_DIR)
	var path := CASES_DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"title": "autoteste", "covers": [], "cases": cases}))
	f.close()
	return ProjectSettings.globalize_path(path)


func _run(target: String, impls: Variant) -> Array:
	var r = Runner.new()
	r.quiet = true
	r.implementations = impls
	var code: int = r.run(PackedStringArray(["--vn-test", target]))
	return [code, "\n".join(r.output)]


func _test_runner() -> void:
	var vars := {"global.money": {"type": "integer", "value": 30, "default": 0}}
	var path := _write_cases("a.json", [
		{"id": "var_ok", "kind": "expression", "variables": vars, "expr": {"var": "global.money"}, "expect": {"type": "integer", "value": 30}},
		{"id": "var_wrong", "kind": "expression", "variables": vars, "expr": {"var": "global.money"}, "expect": {"type": "integer", "value": 31}},
		{"id": "missing_var", "kind": "expression", "expr": {"var": "global.nope"}, "expect": {"error": "VARIABLE_NOT_FOUND"}},
		{"id": "set_money", "kind": "effects", "variables": vars, "effects": [{"op": "set", "variable": "global.money", "value": 50}],
			"expect": {"changes": [{"variable": "global.money", "old": 30, "new": 50}]}},
		{"id": "texto", "kind": "text", "mode": "concat", "value": 1, "expect": {"text": "1"}},
	])
	# Sem módulos reais: tudo pulado, nada passa, sai com 0.
	var none := _run(path, {})
	_check(none[0] == 0, "sem módulos reais sai com 0")
	_check("0/0 (passaram/executados), 5 pulados" in none[1], "sem módulos reais tudo é pulado: " + none[1])

	var fakes := {&"conditions": FakeConditionEvaluator, &"state": FakeStateManager}
	var out := _run(path, fakes)
	_check(out[0] == 1, "falha sai com 1")
	_check("FALHOU a.json#var_wrong\n  esperado: {\"type\": \"integer\", \"value\": 31}\n  obtido:   {\"type\": \"integer\", \"value\": 30}" in out[1], "linha FALHOU com esperado e obtido: " + out[1])
	_check("FALHOU a.json#var_ok" not in out[1] and "FALHOU a.json#set_money" not in out[1] and "FALHOU a.json#missing_var" not in out[1], "casos certos passam")
	_check("3/4 (passaram/executados), 1 pulados" in out[1], "resumo N/M com pulados: " + out[1])
	_check("formatador de texto" in out[1], "motivo do pulado aparece")

	var one := _run(path + "#var_ok", fakes)
	_check(one[0] == 0 and "1/1 (passaram/executados), 0 pulados" in one[1], "arquivo#id roda um caso só: " + one[1])
	_check(_run(path + "#nao_existe", fakes)[0] == 2, "id inexistente é erro de uso")
	_check(_run(ProjectSettings.globalize_path(CASES_DIR.path_join("nada.json")), fakes)[0] == 2, "caminho inexistente é erro de uso")

	var unknown := _run(_write_cases("b.json", [{"id": "x", "kind": "desconhecido", "expect": {}}]), fakes)
	_check(unknown[0] == 1 and "FALHOU b.json#x" in unknown[1], "kind sem adaptador é falha, não pulado")
	var broken := _write_cases("c.json", [])
	var f := FileAccess.open(CASES_DIR.path_join("c.json"), FileAccess.WRITE)
	f.store_string("{\"cases\": [")
	f.close()
	_check(_run(broken, fakes)[0] == 1, "arquivo ilegível é falha")


## Todos os dublês ligados como reais, sobre os vetores de verdade: exercita a montagem de estado de
## cada adaptador. Os dublês não implementam a spec, então haverá falhas; o que importa é rodar até o
## fim sem erro de script e sem dar caso pulado por falta de módulo.
func _test_all_adapters_with_fakes() -> void:
	var fakes := VNCaseModules.discover("res://tests/fakes/").implementations
	var specs := ProjectSettings.globalize_path("res://").path_join("../docs/specs/conformance").simplify_path()
	# effects.json fica de fora: o dublê do State Manager dá erro de script com tipos errados (é o que
	# os casos testam), e o autoteste precisa rodar sem ERROR no log.
	var out := [0, ""]
	var total := 0
	for f in ["expressions.json", "conditions.json", "selection.json", "flow.json", "text.json"]:
		var r := _run(specs.path_join(f), fakes)
		out[0] = max(out[0], r[0])
		out[1] += r[1] + "\n"
		for line in r[1].split("\n"):
			if "(passaram/executados)" in line:
				total += int(line.get_slice("/", 1).get_slice(" ", 0))
	_check(out[0] == 1, "com dublês no lugar dos módulos reais os vetores falham (exit 1)")
	_check("sem implementação real" not in out[1], "com todos os módulos, nenhum caso é pulado por falta de módulo")
	_check(total == 69, "expressões, condições e seleção executadas (inclusive weighted, M1-08): %d" % total)
