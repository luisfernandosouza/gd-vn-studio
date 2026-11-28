extends VNCaseAdapter
## [code]expression[/code] (spec 08 §2.2; DM §6.1, §6.1.1; RT §12.1): avalia [code]expr[/code] no
## Condition Evaluator com as [code]variables[/code] do caso. Resultado [code]{type, value}[/code] ou
## [code]{error}[/code].


func kinds() -> PackedStringArray:
	return ["expression"]


func run(c: Dictionary) -> Dictionary:
	var missing := require([&"conditions"])
	if not missing.is_empty():
		return missing
	var m := modules.create(true)
	if c.has("rng_state"):
		m.rng.set_state_hex(String(c["rng_state"]))   # random_int sorteia por modules().rng (M1-08)
	var bundle := VNCaseModules.empty_bundle()
	var vars: Dictionary = c.get("variables", {})
	var err := VNCaseModules.add_variables(bundle, vars, "", "")
	if err != "":
		return result({"setup_error": err})
	VNCaseModules.load_state(m, bundle, vars, "", "")
	var r := m.conditions.evaluate_expression(c["expr"], {}, &"", false)
	if r == null:
		return result({"module_error": "o módulo não devolveu resultado (erro de script?)"})
	if not r.ok:
		return result({"error": r.error})
	return result({"type": r.type, "value": r.value})
