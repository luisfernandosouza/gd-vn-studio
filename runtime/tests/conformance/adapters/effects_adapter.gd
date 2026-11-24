extends VNCaseAdapter
## [code]effects[/code] (spec 08 §2.2; DM §6.2; RT §6.1–§6.4): aplica [code]effects[/code] como uma
## transação do State Manager, com o chamador [code]content[/code] e a cena em andamento. Resultado
## [code]{changes}[/code] ou [code]{error}[/code].
##
## Com erro, nenhuma variável pode mudar (spec 08 §2.2): o adaptador confere os valores depois e,
## se algum mudou, acrescenta [code]rollback_failed[/code] ao obtido, o que faz o caso falhar.


func kinds() -> PackedStringArray:
	return ["effects"]


func run(c: Dictionary) -> Dictionary:
	var missing := require([&"state", &"conditions"])
	if not missing.is_empty():
		return missing
	var m := modules.create(true)
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.SCENE_RUNNING)
	var bundle := VNCaseModules.empty_bundle()
	var vars: Dictionary = c.get("variables", {})
	var err := VNCaseModules.add_variables(bundle, vars, "", "")
	if err != "":
		return result({"setup_error": err})
	VNCaseModules.load_state(m, bundle, vars, "", "")
	var before := {}
	for id in vars:
		before[id] = m.variables.read(String(id))
	var r := m.state.apply_effects(c["effects"])
	if r == null:
		return result({"module_error": "o módulo não devolveu resultado (erro de script?)"})
	if r.ok:
		return result({"changes": r.changes})
	var out := {"error": r.error}
	var changed := []
	for id in before:
		if not VNCaseCompare.same(before[id], m.variables.read(String(id))):
			changed.append(id)
	if not changed.is_empty():
		out["rollback_failed"] = changed
	return result(out)
