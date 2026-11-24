extends SceneTree
## Testes unitários do Event Bus (tarefa M1-09; RT §7, §7.1, §7.2).
##
##   godot --headless --path runtime --script res://tests/event_bus/test_event_bus.gd
##
## Usa o [VNRuntimeEventBus] real com os dublês dos outros módulos
## ([code]VNFakeModules[/code]). Lê os exemplos de [code]docs/specs/examples/[/code]
## para os schemas de [code]project.events[/code] e de [code]events.emits[/code].
## Sai com 1 se algo falhar.

var _passed := 0
var _failed := 0
var _buses: Array[VNRuntimeEventBus] = []


func _init() -> void:
	for t in [
		"cumpre_o_contrato", "tabela_sys_igual_ao_contrato", "tabela_sys_payloads_validos",
		"tabela_sys_payloads_invalidos", "sys_fora_de_events_since_selection",
		"emit_enfileira_e_drain_fifo", "ouvinte_que_emite_vai_para_o_fim", "drain_nao_reentrante",
		"limite_de_encadeados", "limite_conta_so_encadeados", "clear_queue_descarta_sem_registrar",
		"origens_e_namespaces", "nomes_malformados", "payload_so_tipos_json",
		"schema_story_do_bundle", "schema_de_plugin_declarado", "release_nao_valida_payload",
		"padroes_de_assinatura", "off_e_off_owner", "assinatura_durante_entrega",
		"callback_de_objeto_liberado", "payload_isolado_por_ouvinte", "event_delivered_antes_dos_ouvintes",
		"schema_subconjunto",
	]:
		_run(t)
	print("%d/%d testes do Event Bus passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	var err: String = call("test_" + test)
	for bus in _buses:   # desfaz os ciclos ouvinte → bus dos testes
		bus.off_all()
	_buses.clear()
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


## Registro de dublês com o bus real, validação de payload ligada.
func _setup() -> Array:
	var m := VNFakeModules.create()
	var bus := VNRuntimeEventBus.new()
	bus.validate_payloads = true
	bus.log_errors = false
	_buses.append(bus)
	m.events = bus
	m.bind_all()
	return [m, bus]


func _read_json(rel: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/specs/" + rel).simplify_path()
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)


## Payload válido de exemplo para cada evento sys.*.
const SYS_SAMPLES := {
	"sys.game_started": {"new_game": true},
	"sys.chapter_started": {"chapter": "019a7a00-0000-7000-8000-000000000001", "entries": 1},
	"sys.chapter_ended": {"chapter": "019a7a00-0000-7000-8000-000000000001"},
	"sys.scene_started": {"scene": "019a7a00-0000-7000-8000-000000000002", "chapter": "019a7a00-0000-7000-8000-000000000001"},
	"sys.scene_ended": {"scene": "019a7a00-0000-7000-8000-000000000002", "chapter": "019a7a00-0000-7000-8000-000000000001"},
	"sys.choice_made": {"scene": "s", "node": "n", "option": "o", "value": "brave"},
	"sys.activity_started": {"activity": "fishing.fishing_game", "scene": "s", "node": "n"},
	"sys.activity_completed": {"activity": "fishing.fishing_game", "outcome": "success", "skipped": false},
	"sys.game_saved": {"slot": "slot_3", "autosave": false},
	"sys.game_loaded": {"slot": "auto_1"},
	"sys.game_ended": {"ending": null},
	"sys.profile_reset": {},
	"sys.content_filter_changed": {"enabled": true},
}


# --- Contrato e tabela sys.* -------------------------------------------------

func test_cumpre_o_contrato() -> String:
	var script: GDScript = load("res://vn_runtime/event_bus/vn_runtime_event_bus.gd")
	if script.is_abstract() or script.get_base_script() != load("res://vn_runtime/event_bus/vn_event_bus.gd"):
		return "VNRuntimeEventBus deve estender VNEventBus e ser concreto"
	var s: Array = _setup()
	var m: VNModules = s[0]
	if m.events.module_id() != &"events" or m.events.modules() != m or not m.missing().is_empty():
		return "registro mal montado"
	return ""


func test_tabela_sys_igual_ao_contrato() -> String:
	if VNEventBus.SYS_EVENTS.size() != 13:
		return "RT §7.1 tem 13 eventos sys.*"
	if VNRuntimeEventBus.SYS_PAYLOAD_SCHEMAS.keys() != VNEventBus.SYS_EVENTS.keys():
		return "SYS_PAYLOAD_SCHEMAS e SYS_EVENTS diferem"
	for name in VNEventBus.SYS_EVENTS:
		var fields: Array = VNEventBus.SYS_EVENTS[name]
		var props: Dictionary = VNRuntimeEventBus.SYS_PAYLOAD_SCHEMAS[name]
		if props.keys() != fields:
			return "%s: campos %s, contrato %s" % [name, props.keys(), fields]
		if SYS_SAMPLES[name].keys() != fields:
			return "amostra de %s incompleta" % name
	return ""


func test_tabela_sys_payloads_validos() -> String:
	var s: Array = _setup()
	var m: VNModules = s[0]
	var bus: VNRuntimeEventBus = s[1]
	var got := []
	bus.on("sys.*", func(n, p, src): got.append([n, p, src]))
	for name in SYS_SAMPLES:
		var r := bus.emit(name, SYS_SAMPLES[name], VNEventBus.SOURCE_SYS)
		if not r.ok:
			return "%s recusado: %s" % [name, r.message]
	if bus.drain() != 13 or got.size() != 13:
		return "esperava 13 entregas, veio %d" % got.size()
	var i := 0
	for name in SYS_SAMPLES:
		if got[i] != [name, SYS_SAMPLES[name], "sys"]:
			return "entrega %d: %s" % [i, got[i]]
		i += 1
	# integer aceita 2.0 (JSON lido pelo Godot), ending aceita string
	for pair in [["sys.chapter_started", {"chapter": "c", "entries": 2.0}], ["sys.game_ended", {"ending": "good_end"}]]:
		if not bus.emit(pair[0], pair[1], VNEventBus.SOURCE_SYS).ok:
			return "%s %s deveria passar" % pair
	return ""


func test_tabela_sys_payloads_invalidos() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var wrong := {"boolean": "sim", "string": 1, "integer": 1.5, "string,null": 3}
	for name in SYS_SAMPLES:
		var sample: Dictionary = SYS_SAMPLES[name]
		for field in sample:
			var missing := sample.duplicate()
			missing.erase(field)
			if bus.emit(name, missing, VNEventBus.SOURCE_SYS).error != VNErrors.TYPE_MISMATCH:
				return "%s sem %s deveria ser recusado" % [name, field]
			var t: Variant = VNRuntimeEventBus.SYS_PAYLOAD_SCHEMAS[name][field].type
			var key := ",".join(PackedStringArray(t)) if t is Array else String(t)
			var bad := sample.duplicate()
			bad[field] = wrong[key]
			if bus.emit(name, bad, VNEventBus.SOURCE_SYS).ok:
				return "%s com %s = %s deveria ser recusado" % [name, field, bad[field]]
		var extra := sample.duplicate()
		extra["extra"] = 1
		if bus.emit(name, extra, VNEventBus.SOURCE_SYS).ok:
			return "%s com campo a mais deveria ser recusado" % name
	if bus.emit("sys.chapter_started", {"chapter": "c", "entries": 0}, VNEventBus.SOURCE_SYS).ok:
		return "entries começa em 1 (RT §3.2 passo 3)"
	if bus.pending_count() != 0:
		return "evento recusado não pode entrar na fila"
	return ""


func test_sys_fora_de_events_since_selection() -> String:
	var s: Array = _setup()
	var m: VNModules = s[0]
	var bus: VNRuntimeEventBus = s[1]
	bus.declare_plugin_events(&"vnstudio.fishing", [{"name": "fishing.completed"}])
	for name in SYS_SAMPLES:
		bus.emit(name, SYS_SAMPLES[name], VNEventBus.SOURCE_SYS)
	bus.emit("story.met_master", {}, VNEventBus.SOURCE_STORY)
	bus.emit("fishing.completed", {"fish_count": 1, "score": 10}, "vnstudio.fishing")
	bus.drain()
	var since := m.scheduler.events_since_selection()
	if since != PackedStringArray(["story.met_master", "fishing.completed"]):
		return "events_since_selection = %s" % since
	return ""


# --- Fila e drenagem ---------------------------------------------------------

func test_emit_enfileira_e_drain_fifo() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var got := []
	bus.on("story.*", func(n, _p, _s): got.append(n))
	for n in ["story.a", "story.b", "story.c"]:
		bus.emit(n)
	if not got.is_empty() or bus.pending_count() != 3:
		return "emit não pode entregar na mesma pilha (RT §7.2)"
	if bus.drain() != 3 or got != ["story.a", "story.b", "story.c"] or bus.pending_count() != 0:
		return "ordem: %s" % [got]
	if bus.drain() != 0:
		return "fila vazia deveria entregar 0"
	return ""


func test_ouvinte_que_emite_vai_para_o_fim() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var got := []
	bus.on("story.a", func(_n, _p, _s): bus.emit("story.from_a"))
	bus.on("story.*", func(n, _p, _s): got.append(n))
	bus.emit("story.a")
	bus.emit("story.b")
	if bus.drain() != 3 or got != ["story.a", "story.b", "story.from_a"]:
		return "ordem: %s" % [got]
	return ""


func test_drain_nao_reentrante() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var got := []
	var inner := []
	bus.on("story.*", func(n, _p, _s):
		got.append(n)
		if n == "story.a":
			bus.emit("story.c")
			inner.append(bus.drain())
			inner.append(bus.is_draining()))
	bus.emit("story.a")
	bus.emit("story.b")
	if bus.drain() != 3 or got != ["story.a", "story.b", "story.c"] or inner != [0, true]:
		return "got %s, inner %s" % [got, inner]
	if bus.is_draining():
		return "is_draining depois do fim"
	return ""


func test_limite_de_encadeados() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var failures := []
	bus.delivery_failed.connect(func(e): failures.append(e))
	bus.on("story.loop", func(_n, _p, _s): bus.emit("story.loop"))
	bus.emit("story.loop")
	var n := bus.drain()
	# 1 da fila inicial + 64 encadeados; o 65º é o erro
	if n != 1 + VNEventBus.MAX_CHAINED:
		return "entregou %d" % n
	if failures.size() != 1 or failures[0].error != VNRuntimeEventBus.CHAIN_LIMIT or bus.last_error != failures[0]:
		return "delivery_failed: %s" % [failures]
	if bus.pending_count() != 0 or bus.is_draining():
		return "a fila deveria ser descartada"
	# a próxima drenagem começa do zero
	bus.off_owner(&"")
	bus.emit("story.ok")
	if bus.drain() != 1:
		return "drenagem seguinte falhou"
	return ""


func test_limite_conta_so_encadeados() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var failures := []
	bus.delivery_failed.connect(func(e): failures.append(e))
	# 100 eventos já na fila não são encadeados
	for i in 100:
		bus.emit("story.x")
	if bus.drain() != 100 or not failures.is_empty():
		return "100 eventos da fila inicial não são ciclo"
	# exatamente 64 encadeados passam
	var left := [VNEventBus.MAX_CHAINED]
	bus.on("story.chain", func(_n, _p, _s):
		if left[0] > 0:
			left[0] -= 1
			bus.emit("story.chain"))
	bus.emit("story.chain")
	if bus.drain() != 1 + VNEventBus.MAX_CHAINED or not failures.is_empty():
		return "64 encadeados deveriam passar"
	return ""


func test_clear_queue_descarta_sem_registrar() -> String:
	var s: Array = _setup()
	var m: VNModules = s[0]
	var bus: VNRuntimeEventBus = s[1]
	var got := []
	bus.on("story.*", func(n, _p, _s): got.append(n))
	bus.emit("story.a")
	bus.clear_queue()
	if bus.pending_count() != 0 or bus.drain() != 0 or not got.is_empty():
		return "clear_queue deveria descartar"
	if not m.scheduler.events_since_selection().is_empty():
		return "evento descartado não entra em events_since_selection"
	# clear_queue dentro de um ouvinte para a drenagem
	bus.on("story.stop", func(_n, _p, _s): bus.clear_queue())
	bus.emit("story.stop")
	bus.emit("story.after")
	if bus.drain() != 1 or got != ["story.stop"]:
		return "clear_queue no ouvinte: %s" % [got]
	return ""


# --- Conferências do emit ----------------------------------------------------

func test_origens_e_namespaces() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var cases := [
		["sys.game_started", {"new_game": true}, "story", VNErrors.PERMISSION_DENIED],
		["sys.game_started", {"new_game": true}, "vnstudio.fishing", VNErrors.PERMISSION_DENIED],
		["sys.not_in_table", {}, "sys", VNErrors.TYPE_MISMATCH],
		["story.a", {}, "sys", VNErrors.PERMISSION_DENIED],
		["story.a", {}, "vnstudio.fishing", VNErrors.PERMISSION_DENIED],
		["fishing.completed", {}, "sys", VNErrors.PERMISSION_DENIED],
		["fishing.completed", {}, "story", VNErrors.PERMISSION_DENIED],
		["fishing.completed", {}, "", VNErrors.PERMISSION_DENIED],
	]
	for c in cases:
		var r := bus.emit(c[0], c[1], c[2])
		if r.ok or r.error != c[3]:
			return "%s de \"%s\": %s" % [c[0], c[2], r.error]
	for c in [["story.a", "story"], ["fishing.completed", "vnstudio.fishing"], ["sys.profile_reset", "sys"]]:
		var r := bus.emit(c[0], {}, c[1]) if c[0] != "fishing.completed" else bus.emit(c[0], {"fish_count": 1, "score": 2}, c[1])
		if not r.ok:
			return "%s de %s: %s" % [c[0], c[1], r.message]
	if bus.pending_count() != 3:
		return "só os 3 válidos entram na fila"
	return ""


func test_nomes_malformados() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	for n in ["", "story", "story.", ".a", "Story.a", "story.A", "story.a-b", "1x.a", "story.1a", "story a"]:
		var r := bus.emit(n)
		if r.ok or r.error != VNErrors.TYPE_MISMATCH:
			return "nome \"%s\" deveria ser recusado" % n
	for n in ["story.a", "story.a.b", "story.a_1", "x1.y_2.z"]:
		var src := "story" if n.begins_with("story.") else "p"
		if not bus.emit(n, {}, src).ok:
			return "nome \"%s\" deveria passar" % n
	return ""


func test_payload_so_tipos_json() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	for bad in [{"v": Vector2.ONE}, {"v": [1, Color.RED]}, {"v": {"x": NAN}}, {"v": INF}, {1: "chave int"}, {"v": RefCounted.new()}]:
		var r := bus.emit("story.a", bad)
		if r.ok or r.error != VNErrors.TYPE_MISMATCH:
			return "%s deveria ser recusado" % [bad]
	var good := {"n": null, "b": false, "i": 3, "f": 1.5, "s": "x", "sn": &"y", "a": [1, "2", [3]], "o": {"k": {"z": []}}}
	if not bus.emit("story.a", good).ok:
		return "payload só com tipos JSON deveria passar"
	return ""


func test_schema_story_do_bundle() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var project: Variant = _read_json("examples/demo-project/project.json")
	if not project is Dictionary:
		return "não li examples/demo-project/project.json"
	bus.load_bundle({"project": project})
	if not bus.emit("story.met_master", {"skill": 3}).ok:
		return "payload válido recusado"
	if bus.emit("story.met_master", {"skill": "alto"}).error != VNErrors.TYPE_MISMATCH:
		return "skill string deveria ser recusado"
	if not bus.emit("story.nao_declarado", {"qualquer": 1}).ok:
		return "evento não declarado só confere tipos (W015 é do validador)"
	# recarregar o bundle troca os schemas de story.*
	bus.load_bundle({"project": {"events": []}})
	if not bus.emit("story.met_master", {"skill": "alto"}).ok:
		return "schema antigo de story.* ficou depois de recarregar"
	return ""


func test_schema_de_plugin_declarado() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var manifest: Variant = _read_json("examples/fishing-plugin/plugin.json")
	if not manifest is Dictionary:
		return "não li examples/fishing-plugin/plugin.json"
	bus.declare_plugin_events(&"vnstudio.fishing", manifest.events.emits)
	var src := "vnstudio.fishing"
	if not bus.emit("fishing.completed", {"fish_count": 3, "score": 120}, src).ok:
		return "fishing.completed válido recusado"
	if not bus.emit("fishing.completed", {"fish_count": 3.0, "score": 120.0}, src).ok:
		return "integer deve aceitar 3.0"
	for bad in [{"fish_count": 3}, {"fish_count": 3, "score": 1.5}, {"fish_count": "3", "score": 1}]:
		if bus.emit("fishing.completed", bad, src).error != VNErrors.TYPE_MISMATCH:
			return "%s deveria ser recusado" % [bad]
	if bus.emit("fishing.rare_fish_caught", {}, src).ok:
		return "species é obrigatório"
	# o bundle não apaga os schemas de plugin
	bus.load_bundle({"project": {"events": []}})
	if bus.emit("fishing.rare_fish_caught", {}, src).ok:
		return "load_bundle apagou schema de plugin"
	# redeclarar troca
	bus.declare_plugin_events(&"vnstudio.fishing", [])
	if not bus.emit("fishing.rare_fish_caught", {}, src).ok:
		return "redeclarar deveria trocar os schemas"
	return ""


func test_release_nao_valida_payload() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	bus.validate_payloads = false
	if not bus.emit("sys.game_started", {}, VNEventBus.SOURCE_SYS).ok:
		return "em release o payload sys.* não é conferido"
	if not bus.emit("story.a", {"v": Vector2.ONE}).ok:
		return "em release os tipos não são conferidos"
	# o formato e as origens continuam conferidos
	if bus.emit("story", {}).ok or bus.emit("sys.game_started", {}, "story").ok:
		return "nome e origem são conferidos sempre"
	var dbg := VNRuntimeEventBus.new()
	if dbg.validate_payloads != OS.is_debug_build():
		return "padrão de validate_payloads deve seguir OS.is_debug_build()"
	return ""


# --- Assinaturas -------------------------------------------------------------

func test_padroes_de_assinatura() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var noop := func(_n, _p, _s): pass
	for p in ["*", "story", "story*", "story.**x", "*.a", "Story.*", ""]:
		if bus.on(p, noop) != 0:
			return "padrão \"%s\" deveria ser recusado" % p
	if bus.on("story.*", Callable()) != 0:
		return "callback inválido deveria ser recusado"
	var hits := {}
	for p in ["story.*", "story.a", "story.a.*", "sys.*", "sys.scene_ended", "fishing.*"]:
		var id := bus.on(p, func(n, _p, _s): hits[p] = hits.get(p, []) + [n])
		if id <= 0:
			return "padrão \"%s\" deveria valer" % p
	bus.emit("story.a")
	bus.emit("story.a.b")
	bus.emit("story.ab")
	bus.emit("sys.scene_ended", {"scene": "s", "chapter": "c"}, "sys")
	bus.emit("fishing.completed", {}, "p")
	bus.drain()
	var want := {
		"story.*": ["story.a", "story.a.b", "story.ab"],
		"story.a": ["story.a"],
		"story.a.*": ["story.a.b"],
		"sys.*": ["sys.scene_ended"],
		"sys.scene_ended": ["sys.scene_ended"],
		"fishing.*": ["fishing.completed"],
	}
	if hits != want:
		return "entregas: %s" % hits
	if not VNRuntimeEventBus.matches("story.*", "story.x") or VNRuntimeEventBus.matches("story.*", "story"):
		return "matches"
	return ""


func test_off_e_off_owner() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var got := []
	var a := bus.on("story.*", func(_n, _p, _s): got.append("a"))
	bus.on("story.*", func(_n, _p, _s): got.append("f1"), &"fishing")
	bus.on("sys.*", func(_n, _p, _s): got.append("f2"), &"fishing")
	bus.on("story.*", func(_n, _p, _s): got.append("o"), &"other")
	if a != 1 or bus.subscription_count() != 4 or bus.subscription_count(&"fishing") != 2:
		return "contagem inicial"
	bus.off(a)
	bus.off_owner(&"fishing")
	bus.off(999)
	if bus.subscription_count() != 1:
		return "sobrou %d" % bus.subscription_count()
	bus.emit("story.x")
	bus.emit("sys.profile_reset", {}, "sys")
	bus.drain()
	if got != ["o"]:
		return "entregas: %s" % [got]
	# ids não se repetem depois de off
	if bus.on("story.*", func(_n, _p, _s): pass) != 5:
		return "ids devem crescer"
	return ""


func test_assinatura_durante_entrega() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var got := []
	var late := [0]
	var victim := [0]
	bus.on("story.*", func(n, _p, _s):
		got.append("first:" + n)
		if n == "story.a":
			late[0] = bus.on("story.*", func(n2, _p2, _s2): got.append("late:" + n2))
			bus.off(victim[0]))
	victim[0] = bus.on("story.*", func(n, _p, _s): got.append("victim:" + n))
	bus.emit("story.a")
	bus.emit("story.b")
	bus.drain()
	if got != ["first:story.a", "first:story.b", "late:story.b"]:
		return "entregas: %s" % [got]
	return ""


class _Listener:
	extends Object
	var got := []
	func on_event(n: String, _p: Dictionary, _s: String) -> void:
		got.append(n)


func test_callback_de_objeto_liberado() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var l := _Listener.new()
	bus.on("story.*", l.on_event)
	bus.emit("story.a")
	bus.drain()
	if l.got != ["story.a"]:
		return "ouvinte não recebeu"
	l.free()
	bus.emit("story.b")
	bus.drain()
	if bus.subscription_count() != 0:
		return "assinatura de objeto liberado deveria sair"
	return ""


func test_payload_isolado_por_ouvinte() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var seen := []
	bus.on("story.*", func(_n, p, _s):
		seen.append(p.duplicate(true))
		p["list"].append(99)
		p["x"] = "mexido")
	bus.on("story.*", func(_n, p, _s): seen.append(p.duplicate(true)))
	var payload := {"x": 1, "list": [1]}
	bus.emit("story.a", payload)
	payload["x"] = 2   # mexer depois do emit não muda o evento
	bus.drain()
	var want := {"x": 1, "list": [1]}
	if seen != [want, want]:
		return "payloads: %s" % [seen]
	return ""


func test_event_delivered_antes_dos_ouvintes() -> String:
	var s: Array = _setup()
	var bus: VNRuntimeEventBus = s[1]
	var log := []
	bus.event_delivered.connect(func(n, p, src): log.append(["signal", n, p, src]))
	bus.on("story.*", func(n, _p, _s): log.append(["listener", n]))
	bus.emit("story.a", {"k": 1})
	bus.emit("sys.profile_reset", {}, "sys")
	bus.drain()
	var want := [["signal", "story.a", {"k": 1}, "story"], ["listener", "story.a"], ["signal", "sys.profile_reset", {}, "sys"]]
	if log != want:
		return "ordem: %s" % [log]
	return ""


# --- VNPayloadSchema ---------------------------------------------------------

func test_schema_subconjunto() -> String:
	var V := VNPayloadSchema
	var cases := [
		# [valor, schema, deve passar]
		[3.0, {"type": "integer"}, true],
		[3.5, {"type": "integer"}, false],
		[true, {"type": "integer"}, false],
		[1, {"type": "number"}, true],
		[null, {"type": ["string", "null"]}, true],
		["a", {"enum": ["a", "b"]}, true],
		["c", {"enum": ["a", "b"]}, false],
		[1.0, {"const": 1}, true],
		[5, {"minimum": 1, "maximum": 5}, true],
		[5, {"exclusiveMaximum": 5}, false],
		[0, {"exclusiveMinimum": 0}, false],
		[9, {"multipleOf": 3}, true],
		[10, {"multipleOf": 3}, false],
		["ab", {"minLength": 3}, false],
		["日本語", {"maxLength": 3}, true],
		["abc", {"pattern": "^a"}, true],
		["xabc", {"pattern": "^a"}, false],
		["xab", {"pattern": "b"}, true],
		[[1, 2], {"type": "array", "items": {"type": "integer"}, "minItems": 1, "maxItems": 2}, true],
		[[1, "2"], {"items": {"type": "integer"}}, false],
		[[1, 1.0], {"uniqueItems": true}, false],
		[["a", 1], {"prefixItems": [{"type": "string"}], "items": {"type": "integer"}}, true],
		[{"a": 1}, {"additionalProperties": false}, false],
		[{"a": 1}, {"additionalProperties": {"type": "string"}}, false],
		[{"a": 1}, {"properties": {"a": {"type": "integer"}}, "additionalProperties": false}, true],
		[{}, {"required": ["a"]}, false],
		[{"a": 1}, {"minProperties": 2}, false],
		[1, {"anyOf": [{"type": "string"}, {"type": "integer"}]}, true],
		[1, {"oneOf": [{"type": "number"}, {"type": "integer"}]}, false],
		[1, {"allOf": [{"type": "integer"}, {"minimum": 2}]}, false],
		[1, {"not": {"type": "string"}}, true],
		[1, true, true],
		[1, false, false],
		[{"a": {"b": [1, "x"]}}, {"properties": {"a": {"properties": {"b": {"items": {"type": "integer"}}}}}}, false],
		[1, {"$ref": "#/x", "description": "ignorado"}, true],
	]
	for c in cases:
		var err: String = V.validate(c[0], c[1])
		if err.is_empty() != c[2]:
			return "%s contra %s: %s" % [c[0], JSON.stringify(c[1]), err if not err.is_empty() else "passou"]
	var err := V.validate({"a": {"b": [1, "x"]}}, {"properties": {"a": {"properties": {"b": {"items": {"type": "integer"}}}}}})
	if not err.begins_with("payload/a/b/1"):
		return "caminho do erro: %s" % err
	return ""
