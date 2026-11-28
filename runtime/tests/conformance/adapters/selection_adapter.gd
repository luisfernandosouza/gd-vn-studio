extends VNCaseAdapter
## [code]selection[/code] (spec 08 §2.3; RT §4.1–§4.4): monta o capítulo, as cenas, as variáveis e o
## histórico do caso, chama [method VNSceneScheduler.select] com o [code]content_request[/code] e
## compara com a decisão ([code]scheduler.evaluated[/code], PP §4.3) mais o histórico depois.
## [code]detail[/code] e [code]failed[/code] das candidatas são informativos e saem da comparação.


func kinds() -> PackedStringArray:
	return ["selection"]


func run(c: Dictionary) -> Dictionary:
	var missing := require([&"scheduler", &"conditions"])
	if not missing.is_empty():
		return missing
	var st: Dictionary = c.get("state", {})
	var m := modules.create(true)
	if st.has("rng_state"):
		# Sorteio ponderado (RT §4.3): o Scheduler sorteia por modules().rng, no estado do caso (M1-08).
		m.rng.set_state_hex(String(st["rng_state"]))
	var chapter: Dictionary = c["chapter"]
	var cid := String(chapter["id"])
	var bundle := VNCaseModules.empty_bundle()
	for g in c.get("project_groups", []):
		var gg := {"max_plays": 1}
		gg.merge(g, true)
		bundle["project"]["exclusive_groups"].append(gg)
	VNCaseModules.ensure_chapter(bundle, chapter)
	for s in c.get("scenes", []):
		VNCaseModules.ensure_scene(bundle, s)
	var vars: Dictionary = st.get("variables", {})
	var err := VNCaseModules.add_variables(bundle, vars, cid, "")
	if err != "":
		return result({"setup_error": err})
	VNCaseModules.load_state(m, bundle, vars, cid, "")

	var engine := m.engine as FakeNarrativeEngine
	engine.chapter = cid
	engine.set_phase(VNPhase.SELECTION_POINT)
	m.state.set_system_value("sys.chapter.id", cid)

	var history := {"selection_count": 0, "scenes": {}, "groups": {}, "chapters": {cid: {"entries": 1, "completed": false}},
		"events_since_selection": [], "pending_request": null, "fallback_streak": 0}
	history.merge(st.get("history", {}).duplicate(true), true)
	m.scheduler.restore_history(history)

	var request = c.get("content_request")
	var ev := m.scheduler.select("" if request == null else String(request))
	if ev == null or ev.is_empty():
		return result({"module_error": "select() não devolveu a avaliação (erro de script?)"})
	var after := m.scheduler.get_history()
	var candidates := []
	for cand in ev.get("candidates", []):
		var x: Dictionary = cand.duplicate()
		x.erase("detail")
		x.erase("failed")
		candidates.append(x)
	var chosen = ev.get("chosen")
	var out := {
		"action": ev.get("action"),
		"chosen": null if chosen == null or String(chosen) == "" else chosen,
		"reason": ev.get("reason"),
		"candidates": candidates,
		"selection_count_after": after.get("selection_count"),
		"fallback_streak_after": after.get("fallback_streak"),
	}
	if st.has("rng_state"):
		out["rng_state_after"] = m.rng.state_hex()
	if ev.has("request_refused") and ev["request_refused"] != null:
		out["request_refused"] = ev["request_refused"]
	return result(out)
