class_name VNSdkTest
extends RefCounted
## Base mínima dos testes do addon: cada método [code]test_*[/code] é um caso.

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func eq(got: Variant, want: Variant, what: String) -> void:
	if typeof(got) != typeof(want) or got != want:
		failures.append("%s: esperado %s (%s), veio %s (%s)" % [what, var_to_str(want), type_string(typeof(want)), var_to_str(got), type_string(typeof(got))])
