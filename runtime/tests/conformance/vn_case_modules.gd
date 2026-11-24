class_name VNCaseModules
extends RefCounted
## Monta o estado mínimo de um caso de conformidade (spec 08 §4): um [VNModules] com os módulos reais
## que já existem em [code]res://vn_runtime/[/code] e dublês ([code]tests/fakes/[/code]) no lugar dos
## que ainda não existem, mais um bundle mínimo com as variáveis, o capítulo e as cenas do caso.
##
## **Como um módulo real é encontrado.** Toda classe com [code]class_name[/code], não abstrata, num
## arquivo de [code]res://vn_runtime/[/code], que estende o contrato de um módulo (a classe base do
## M0-07, ex.: [VNConditionEvaluator]) é a implementação real dele. A tarefa que implementa um módulo
## não precisa mexer no executor: assim que a classe existe, os casos que dependem dela deixam de ser
## pulados. Com mais de uma implementação do mesmo contrato, vale a primeira em ordem de nome e o
## executor avisa no cabeçalho.

## Contrato de cada módulo de [constant VNModules.MODULE_IDS].
const CONTRACTS := {
	&"engine": &"VNNarrativeEngine",
	&"scheduler": &"VNSceneScheduler",
	&"conditions": &"VNConditionEvaluator",
	&"state": &"VNStateManager",
	&"variables": &"VNVariableManager",
	&"events": &"VNEventBus",
	&"plugins": &"VNPluginHost",
	&"saves": &"VNSaveManager",
	&"storage": &"VNStorage",
	&"stage": &"VNStage",
	&"audio": &"VNAudioManager",
	&"ui": &"VNUIManager",
	&"assets": &"VNAssets",
}

## Tarefa do backlog que entrega cada módulo, para as mensagens de caso pulado.
const TASKS := {
	&"engine": "M1-11",
	&"scheduler": "M1-10",
	&"conditions": "M1-03/M1-04",
	&"state": "M1-06",
	&"variables": "M1-05",
	&"events": "M1-09",
	&"plugins": "M3-01",
	&"saves": "M2-10",
	&"storage": "M2-10",
	&"stage": "M2-02",
	&"audio": "M2-05",
	&"ui": "M2-06",
	&"assets": "M4-07",
}

const RUNTIME_ROOT := "res://vn_runtime/"

## id do módulo → [Script] da implementação real.
var implementations: Dictionary = {}
## Avisos da descoberta (mais de uma implementação para o mesmo contrato).
var warnings: PackedStringArray = []


## Usa [param impls] (id → [Script]) no lugar da descoberta; o autoteste do executor liga dublês
## como se fossem módulos reais.
static func with(impls: Dictionary) -> VNCaseModules:
	var out := VNCaseModules.new()
	out.implementations = impls.duplicate()
	return out


## Procura as implementações reais em [param root].
static func discover(root: String = RUNTIME_ROOT) -> VNCaseModules:
	var out := VNCaseModules.new()
	var classes := {}
	for c in ProjectSettings.get_global_class_list():
		classes[c["class"]] = c
	var names := classes.keys()
	names.sort_custom(func(a, b): return String(a) < String(b))
	var found := {}  # id → [class_name, …]
	for name in names:
		var info: Dictionary = classes[name]
		if info.get("is_abstract", false) or not String(info["path"]).begins_with(root):
			continue
		var id := _contract_of(name, classes)
		if id != &"":
			found.get_or_add(id, []).append(name)
	for id in found:
		var list: Array = found[id]
		if list.size() > 1:
			out.warnings.append("mais de uma implementação de %s (%s); usando %s" % [CONTRACTS[id], ", ".join(list), list[0]])
		out.implementations[id] = load(classes[list[0]]["path"])
	return out


static func _contract_of(name: StringName, classes: Dictionary) -> StringName:
	var contract_ids := {}
	for id in CONTRACTS:
		contract_ids[CONTRACTS[id]] = id
	if contract_ids.has(name):
		return &""  # o próprio contrato
	var cur: StringName = name
	var guard := 0
	while classes.has(cur) and guard < 64:
		cur = classes[cur]["base"]
		if contract_ids.has(cur):
			return contract_ids[cur]
		guard += 1
	return &""


func has_real(id: StringName) -> bool:
	return implementations.has(id)


## Os módulos de [param ids] sem implementação real, no formato da mensagem de pulado.
func missing(ids: Array) -> String:
	var out := PackedStringArray()
	for id in ids:
		if not has_real(id):
			out.append("%s (%s)" % [CONTRACTS[id], TASKS[id]])
	return ", ".join(out)


## Descrição de uma linha para o cabeçalho do executor.
func describe() -> String:
	if implementations.is_empty():
		return "módulos reais: nenhum ainda (todos os módulos são dublês)"
	var parts := PackedStringArray()
	for id in VNModules.MODULE_IDS:
		if implementations.has(id):
			var s: Script = implementations[id]
			parts.append("%s=%s" % [id, s.get_global_name() if s.get_global_name() != &"" else s.resource_path])
	return "módulos reais: " + ", ".join(parts)


## Um registro novo: dublês em tudo, os módulos reais por cima e, se [param fake_engine], o Narrative
## Engine sempre dublê (os casos sem cena inteira só precisam de capítulo e fase).
func create(fake_engine: bool = false) -> VNModules:
	var m := VNFakeModules.create()
	for id in implementations:
		if fake_engine and id == &"engine":
			continue
		var s: Script = implementations[id]
		m.set(id, s.new())
	m.bind_all()
	return m


# --- Bundle mínimo ----------------------------------------------------------------------------

## Um bundle vazio no formato de [code]bundle.schema.json[/code], com os padrões do compilador
## ([code]tools/compile_bundle.py[/code]) onde os módulos leem configuração.
static func empty_bundle() -> Dictionary:
	return {
		"bundle_version": "1.0.0",
		"format_version": "1.0.0",
		"content_hash": "",
		"project": {
			"id": "conformance",
			"settings": {"reproducible_rng": false, "number_formats": {}},
			"scheduler": {"tie_breaker": "deterministic", "include_global_scenes": true},
			"exclusive_groups": [],
			"chapters": [],
			"endings": [],
			"events": [],
		},
		"variables": {},
		"aliases": {},
		"characters": {},
		"chapters": {},
		"scenes": {},
		"theme": {},
		"ui": {},
		"sets": {},
		"assets": {},
	}


## Valor com o tipo da variável: [code]number[/code] vira float; [code]integer[/code] vira int.
static func typed_value(type: String, v: Variant) -> Variant:
	if type == "number" and typeof(v) == TYPE_INT:
		return float(v)
	if type == "integer" and typeof(v) == TYPE_FLOAT and v == floorf(v):
		return int(v)
	return v


## Põe as variáveis do caso (spec 08 §2.1: id → [code]{type, value, default?, constraints?}[/code]) no
## [param bundle] como definições ([code]VariableDefinition[/code]). [code]chapter.*[/code] vai para o
## capítulo [param chapter_id] e [code]scene.*[/code] para a cena [param scene_id], que são criados se
## faltarem. Devolve uma mensagem de erro ou vazio.
static func add_variables(bundle: Dictionary, variables: Dictionary, chapter_id: String, scene_id: String) -> String:
	for id in variables:
		var spec: Dictionary = variables[id]
		var qid := String(id)
		var parts := qid.split(".")
		var type := String(spec.get("type", ""))
		var def := {"key": parts[parts.size() - 1], "type": type, "persistence": "save"}
		if spec.has("default"):
			def["default"] = typed_value(type, spec["default"])
		if spec.has("constraints"):
			def["constraints"] = spec["constraints"]
		match parts[0]:
			"global", "character", "plugin":
				bundle["variables"][qid] = def
			"chapter":
				ensure_chapter(bundle, {"id": chapter_id})["variables"].append(def)
			"scene":
				ensure_scene(bundle, {"id": scene_id, "chapter": chapter_id})["variables"].append(def)
			_:
				return "variável de escopo que o executor não monta: %s" % qid
	return ""


## Garante o capítulo no bundle, com os campos que o compilador resolve (BS §5; compile_bundle.py).
static func ensure_chapter(bundle: Dictionary, src: Dictionary) -> Dictionary:
	var cid := String(src["id"])
	if bundle["chapters"].has(cid):
		return bundle["chapters"][cid]
	var c := src.duplicate(true)
	var sched: Dictionary = bundle["project"]["scheduler"].duplicate()
	if c.has("include_global_scenes"):
		sched["include_global_scenes"] = c["include_global_scenes"]
	sched.merge(c.get("scheduler", {}), true)
	c["scheduler"] = sched
	var completion := {"on_exhausted": "advance"}
	completion.merge(c.get("completion", {}), true)
	c["completion"] = completion
	var groups := []
	for g in c.get("exclusive_groups", []):
		var gg := {"max_plays": 1}
		gg.merge(g, true)
		groups.append(gg)
	c["exclusive_groups"] = groups
	var next := []
	for n in c.get("next", []):
		var nn := {"priority": 100}
		nn.merge(n, true)
		next.append(nn)
	c["next"] = next
	if not c.has("variables"):
		c["variables"] = []
	bundle["chapters"][cid] = c
	if not bundle["project"]["chapters"].has(cid):
		bundle["project"]["chapters"].append(cid)
	return c


## Garante a cena no bundle, com [code]scheduling[/code] e [code]start[/code] resolvidos como no
## compilador. Uma cena sem nós ganha um único nó [code]end[/code], para o bundle ficar completo.
static func ensure_scene(bundle: Dictionary, src: Dictionary) -> Dictionary:
	var sid := String(src["id"])
	if bundle["scenes"].has(sid):
		return bundle["scenes"][sid]
	var s := src.duplicate(true)
	var sc: Dictionary = s.get("scheduling", {})
	var sched := {
		"mode": sc.get("mode", "scheduled"),
		"priority": sc.get("priority", 100),
		"max_plays": sc.get("max_plays", 1),
		"cooldown": sc.get("cooldown", 0),
		"exclusive_groups": sc.get("exclusive_groups", []),
		"weight": sc.get("weight", 1),
	}
	if sc.has("order"):
		sched["order"] = sc["order"]
	if sc.has("conditions"):
		sched["conditions"] = sc["conditions"]
	s["scheduling"] = sched
	s["chapter"] = s.get("chapter")
	if not s.has("nodes") or s["nodes"].is_empty():
		s["nodes"] = [{"id": sid, "type": "end", "then": "schedule"}]
	if not s.has("start") or s["start"] == null:
		s["start"] = s["nodes"][0]["id"]
	if not s.has("variables"):
		s["variables"] = []
	bundle["scenes"][sid] = s
	return s


## Carrega o [param bundle] em todos os módulos, começa um jogo novo no Variable Manager, entra no
## capítulo e na cena se houver variáveis desses escopos e grava os valores atuais do caso.
static func load_state(m: VNModules, bundle: Dictionary, variables: Dictionary, chapter_id: String, scene_id: String) -> void:
	if m.variables is FakeVariableManager:
		_define_fake(m.variables as FakeVariableManager, bundle)
	m.load_bundle(bundle)
	m.variables.reset_game()
	var has_chapter_vars := false
	var has_scene_vars := false
	for id in variables:
		has_chapter_vars = has_chapter_vars or String(id).begins_with("chapter.")
		has_scene_vars = has_scene_vars or String(id).begins_with("scene.")
	if has_chapter_vars or has_scene_vars:
		m.variables.enter_chapter(chapter_id)
	if has_scene_vars:
		m.variables.enter_scene(scene_id)
	for id in variables:
		var spec: Dictionary = variables[id]
		m.variables.store(String(id), typed_value(String(spec.get("type", "")), spec.get("value")))


## O dublê do Variable Manager não lê o bundle: define as variáveis direto nele.
static func _define_fake(vars: FakeVariableManager, bundle: Dictionary) -> void:
	var defs := {}
	for id in bundle["variables"]:
		defs[id] = bundle["variables"][id]
	for cid in bundle["chapters"]:
		for d in bundle["chapters"][cid].get("variables", []):
			defs["chapter." + String(d["key"])] = d
	for sid in bundle["scenes"]:
		for d in bundle["scenes"][sid].get("variables", []):
			defs["scene." + String(d["key"])] = d
	for id in defs:
		var d: Dictionary = defs[id]
		var type := StringName(d.get("type", ""))
		vars.define(id, type, d.get("default", _type_default(type)), StringName(d.get("persistence", "save")))


static func _type_default(type: StringName) -> Variant:
	match type:
		&"integer": return 0
		&"number": return 0.0
		&"boolean": return false
	return ""
