extends VNCaseAdapter
## [code]condition[/code] (spec 08 §2.2; DM §5, §5.1–§5.3): avalia [code]conditions[/code] no
## Condition Evaluator, com as [code]variables[/code] do caso e os [code]events[/code] registrados no
## Scheduler como eventos desde a última seleção. Resultado [code]{value}[/code] ou [code]{error}[/code].


func kinds() -> PackedStringArray:
	return ["condition"]


func run(c: Dictionary) -> Dictionary:
	var missing := require([&"conditions"])
	if not missing.is_empty():
		return missing
	var m := modules.create(true)
	var bundle := VNCaseModules.empty_bundle()
	var vars: Dictionary = c.get("variables", {})
	var err := VNCaseModules.add_variables(bundle, vars, "", "")
	if err != "":
		return result({"setup_error": err})
	VNCaseModules.load_state(m, bundle, vars, "", "")
	for e in c.get("events", []):
		m.scheduler.record_event(String(e))
	var r := m.conditions.evaluate_conditions(c["conditions"])
	if r == null:
		return result({"module_error": "o módulo não devolveu resultado (erro de script?)"})
	if not r.ok:
		return result({"error": r.error})
	return result({"value": r.value})
