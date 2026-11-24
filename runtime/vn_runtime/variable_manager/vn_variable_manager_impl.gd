class_name VNVariableManagerImpl
extends VNVariableManager
## Variable Manager real (tarefa M1-05): escopos, defaults, derivadas e [code]sys.*[/code].
##
## Implementa o contrato [VNVariableManager] (M0-07). Lê do bundle (RT §2,
## [code]bundle.schema.json[/code]):
## [br]- [code]variables[/code]: escopo de jogo ([code]global.*[/code],
##   [code]character.<p>.*[/code] já instanciadas com [code]initial_values[/code],
##   [code]plugin.<ns>.*[/code]);
## [br]- [code]chapters[<id>].variables[/code] e [code]scenes[<id>].variables[/code]:
##   listas de definições de [code]chapter.*[/code] e [code]scene.*[/code];
## [br]- [code]aliases[/code]: os [code]renamed_from[/code] reunidos pelo compilador
##   (só as chaves com forma de variável são usadas). Os [code]renamed_from[/code]
##   de [code]chapter.*[/code]/[code]scene.*[/code] são lidos das próprias definições;
## [br]- [code]project.endings[/code], [code]project.gallery[/code] e
##   [code]project.default_locale[/code], para as variáveis [code]sys.*[/code].
##
## [b]Variáveis de sistema[/b] (DM §4.3): todas são somente leitura para o
## conteúdo e mantidas pelo runtime por [method store] (via
## [method VNStateManager.set_system_value]). [code]sys.selection_count[/code],
## [code]sys.scenes.<cena>.plays[/code], [code]sys.scenes.<cena>.last_selection[/code]
## e [code]sys.chapters.<cap>.completed[/code] são lidas do histórico do Scene
## Scheduler ([code]modules().scheduler[/code]), que é o dono delas; sem
## Scheduler no registro, valem os valores gravados por [method store].
## [method enter_chapter], [method exit_chapter], [method enter_scene] e
## [method exit_scene] atualizam [code]sys.chapter.id[/code] e [code]sys.scene.id[/code]
## (RT §3.2 passo 3, §5.1 passo 1). As variáveis de interface que dependem de
## outros módulos ([code]sys.ui.has_save[/code], [code]sys.ui.in_game[/code]…)
## começam no padrão do tipo e são preenchidas pelo boot (RT §3.0 passo 6).
##
## [b]Derivadas[/b] (DM §4.5): recalculadas a cada leitura pelo Condition
## Evaluator ([code]modules().conditions.evaluate_expression[/code]). Um ciclo
## entre derivadas (o validador já o recusa) é acusado no [method load_bundle]
## e a leitura delas devolve o [code]fallback[/code].
##
## [b]Save carregado[/b] (RT §8.3, §8.4): [method restore_save_values] reinicia o
## escopo de jogo (defaults, perfil na memória, depois o save). Os valores de
## [code]chapter.*[/code] e [code]scene.*[/code] do save valem para o capítulo e a
## cena ativos; se ainda não houver, ficam pendentes e são aplicados sobre os
## defaults no próximo [method enter_chapter]/[method enter_scene]. Para
## recomeçar a cena com [code]scene.*[/code] zeradas (RT §8.4, nó inexistente),
## chame [method exit_scene] antes, que descarta os pendentes.

## Maior inteiro aceito (RT §12.1): ±(2^53 − 1).
const INT_LIMIT := 9007199254740991

const SCOPE_GLOBAL := &"global"
const SCOPE_CHARACTER := &"character"
const SCOPE_CHAPTER := &"chapter"
const SCOPE_SCENE := &"scene"
const SCOPE_PLUGIN := &"plugin"
const SCOPE_SYS := &"sys"

## sys.* fixas (DM §4.3): id → tipo.
const SYS_FIXED := {
	"sys.chapter.id": &"string",
	"sys.locale": &"string",
	"sys.save_modified": &"boolean",
	"sys.scene.id": &"string",
	"sys.selection_count": &"integer",
	"sys.ui.activity": &"boolean",
	"sys.ui.activity_skippable": &"boolean",
	"sys.ui.content_filter": &"boolean",
	"sys.ui.content_filter_available": &"boolean",
	"sys.ui.gallery_endings": &"boolean",
	"sys.ui.gallery_images": &"boolean",
	"sys.ui.gallery_music": &"boolean",
	"sys.ui.has_gallery": &"boolean",
	"sys.ui.has_minigames": &"boolean",
	"sys.ui.has_save": &"boolean",
	"sys.ui.in_game": &"boolean",
	"sys.ui.last_activity_outcome": &"string",
	"sys.ui.last_record_rank": &"integer",
	"sys.ui.platform": &"string",
}

## Definições do escopo de jogo e de sys.*: id → definição resolvida.
var _defs: Dictionary = {}
## Valores do escopo de jogo e de sys.*.
var _values: Dictionary = {}
## Capítulo → { id qualificado → definição }.
var _chapter_defs: Dictionary = {}
## Cena → { id qualificado → definição }.
var _scene_defs: Dictionary = {}
## chapter.<key> e scene.<key> declaradas em algum capítulo/cena → true.
var _scoped_ids: Dictionary = {}
## id antigo → id atual.
var _aliases: Dictionary = {}

var _chapter_id: String = ""
var _chapter_active: bool = false
var _chapter_values: Dictionary = {}
var _scene_id: String = ""
var _scene_active: bool = false
var _scene_values: Dictionary = {}

## Valores de chapter.*/scene.* de um save, à espera do capítulo/da cena.
var _pending_chapter: Dictionary = {}
var _pending_scene: Dictionary = {}

## Derivadas presas num ciclo (acusadas no load_bundle).
var _cyclic: Dictionary = {}
## Derivadas em cálculo, para não entrar em recursão.
var _evaluating: Dictionary = {}

## Erros e avisos registrados (os mais recentes por último), para a UI de
## debug e os testes. Com [member quiet], não vão para o log do Godot.
var diagnostics := PackedStringArray()
var quiet := false

var _ids_cache := PackedStringArray()
var _ids_dirty := true


# --- Bundle -----------------------------------------------------------------

func load_bundle(bundle: Dictionary) -> void:
	_defs.clear()
	_values.clear()
	_chapter_defs.clear()
	_scene_defs.clear()
	_scoped_ids.clear()
	_aliases.clear()
	_cyclic.clear()
	_evaluating.clear()
	_clear_scopes()

	var vars: Dictionary = bundle.get("variables", {})
	for id in _sorted_keys(vars):
		_defs[id] = _resolve_definition(id, vars[id])

	for cid in _sorted_keys(bundle.get("chapters", {})):
		_chapter_defs[cid] = _scoped_definitions(SCOPE_CHAPTER, bundle.chapters[cid].get("variables", []))
	for sid in _sorted_keys(bundle.get("scenes", {})):
		_scene_defs[sid] = _scoped_definitions(SCOPE_SCENE, bundle.scenes[sid].get("variables", []))

	var aliases: Dictionary = bundle.get("aliases", {})
	for old in aliases:
		var new_id := String(aliases[old])
		if _looks_like_variable(new_id):
			_aliases[String(old)] = new_id

	_define_sys(bundle)
	_ids_dirty = true
	_check_derived_cycles()

	for id in _defs:
		_values[id] = _defs[id].get("default")


func _resolve_definition(id: String, src: Dictionary) -> Dictionary:
	var d: Dictionary = src.duplicate(true)
	var type := StringName(d.get("type", "string"))
	d["type"] = type
	d["scope"] = _scope_of(id)
	if d.has("derived"):
		d.erase("default")
		d.erase("persistence")
		return d
	d["persistence"] = StringName(d.get("persistence", "save"))
	d["default"] = _normalize(type, d["default"]) if d.has("default") else _type_default(type, d.get("constraints", {}))
	return d


func _scoped_definitions(scope: StringName, list: Array) -> Dictionary:
	var out := {}
	for src in list:
		var qid := "%s.%s" % [scope, src.get("key", "")]
		out[qid] = _resolve_definition(qid, src)
		_scoped_ids[qid] = true
		for old in src.get("renamed_from", []):
			_aliases["%s.%s" % [scope, old]] = qid
	return out


func _define_sys(bundle: Dictionary) -> void:
	var project: Dictionary = bundle.get("project", {})
	for id in SYS_FIXED:
		_def_sys(id, SYS_FIXED[id])
	_defs["sys.locale"]["default"] = String(project.get("default_locale", ""))
	_defs["sys.ui.platform"]["default"] = platform_name()
	var sections: Array = project.get("gallery", {}).get("sections", [])
	_defs["sys.ui.has_gallery"]["default"] = project.has("gallery")
	for s in ["endings", "images", "music"]:
		_defs["sys.ui.gallery_" + s]["default"] = sections.has(s)
	for sid in _scene_defs:
		_def_sys("sys.scenes.%s.plays" % sid, &"integer")
		_def_sys("sys.scenes.%s.last_selection" % sid, &"integer", -1)
	for cid in _chapter_defs:
		_def_sys("sys.chapters.%s.completed" % cid, &"boolean")
	for e in project.get("endings", []):
		_def_sys("sys.endings.%s" % e.get("id", ""), &"boolean")


func _def_sys(id: String, type: StringName, default_value: Variant = null) -> void:
	_defs[id] = {
		"key": id.trim_prefix("sys."), "type": type, "scope": SCOPE_SYS, "persistence": &"session",
		"default": _type_default(type, {}) if typeof(default_value) == TYPE_NIL else default_value,
	}


## Nome da plataforma para [code]sys.ui.platform[/code] (DM §4.3).
static func platform_name() -> String:
	match OS.get_name():
		"Windows": return "windows"
		"macOS": return "macos"
		"Web": return "web"
	return "linux"


# --- Definições -------------------------------------------------------------

func has(id: String) -> bool:
	return _defs.has(id) or _scoped_ids.has(id)


func get_definition(id: String) -> Dictionary:
	var d := _find_definition(id)
	return d.duplicate(true)


func ids() -> PackedStringArray:
	if _ids_dirty:
		var all := {}
		for id in _defs:
			all[id] = true
		for id in _scoped_ids:
			all[id] = true
		_ids_cache = PackedStringArray(all.keys())
		_ids_cache.sort()
		_ids_dirty = false
	return _ids_cache


func resolve_alias(id: String) -> String:
	var seen := {}
	var cur := id
	while _aliases.has(cur) and not seen.has(cur):
		seen[cur] = true
		cur = _aliases[cur]
	return cur


func is_read_only(id: String) -> bool:
	if id.begins_with("sys."):
		return true
	return _find_definition(id).has("derived")


func is_scope_active(id: String) -> bool:
	if id.begins_with("chapter."):
		return _chapter_active and _chapter_defs.get(_chapter_id, {}).has(id)
	if id.begins_with("scene."):
		return _scene_active and _scene_defs.get(_scene_id, {}).has(id)
	return true


## Definição vigente: a do capítulo/da cena ativos ou, com o escopo inativo, a
## primeira (por id do capítulo/da cena) que a declara.
func _find_definition(id: String) -> Dictionary:
	if _defs.has(id):
		return _defs[id]
	var table := _chapter_defs if id.begins_with("chapter.") else (_scene_defs if id.begins_with("scene.") else {})
	if table.is_empty():
		return {}
	var active := _chapter_id if id.begins_with("chapter.") else _scene_id
	if table.get(active, {}).has(id):
		return table[active][id]
	for owner in table:
		if table[owner].has(id):
			return table[owner][id]
	return {}


# --- Valores ----------------------------------------------------------------

func read(id: String, fallback: Variant = null) -> Variant:
	if not has(id) or not is_scope_active(id):
		return fallback
	var d := _find_definition(id)
	if d.has("derived"):
		return _read_derived(id, d, fallback)
	if d.scope == SCOPE_SYS:
		return _read_sys(id, d)
	return _store_for(id).get(id, fallback)


func store(id: String, value: Variant) -> void:
	if id.begins_with("sys."):
		if not _defs.has(id):
			# sys.* de entidade criada depois do bundle (ex.: cena nova no Preview).
			_def_sys(id, _type_of_value(value))
			_ids_dirty = true
		_values[id] = _normalize(_defs[id].type, value)
		return
	if not has(id):
		_log_error("VNVariableManager.store: variável inexistente: %s" % id)
		return
	var d := _find_definition(id)
	if d.has("derived"):
		_log_error("VNVariableManager.store: variável derivada é somente leitura: %s" % id)
		return
	if not is_scope_active(id):
		_log_error("VNVariableManager.store: escopo inativo: %s" % id)
		return
	_store_for(id)[id] = _normalize(d.type, value)


func is_default(id: String) -> bool:
	if not has(id) or not is_scope_active(id):
		return false
	var d := _find_definition(id)
	if d.has("derived"):
		return false
	return _same(read(id), d.get("default"))


func _store_for(id: String) -> Dictionary:
	if id.begins_with("chapter."):
		return _chapter_values
	if id.begins_with("scene."):
		return _scene_values
	return _values


func _read_sys(id: String, d: Dictionary) -> Variant:
	var sched := _scheduler()
	if sched != null:
		if id == "sys.selection_count":
			return sched.selection_count()
		var parts := id.split(".")
		if parts.size() == 4 and parts[1] == "scenes" and (parts[3] == "plays" or parts[3] == "last_selection"):
			var h: Dictionary = sched.get_history().get("scenes", {}).get(parts[2], {})
			return int(h.get(parts[3], d.default))
		if parts.size() == 4 and parts[1] == "chapters" and parts[3] == "completed":
			var h: Dictionary = sched.get_history().get("chapters", {}).get(parts[2], {})
			return bool(h.get("completed", false))
	return _values.get(id, d.default)


func _read_derived(id: String, d: Dictionary, fallback: Variant) -> Variant:
	if _cyclic.has(id):
		return fallback
	if _evaluating.has(id):
		_log_error("VNVariableManager: ciclo entre derivadas em %s" % id)
		return fallback
	var m := modules()
	if m == null or m.conditions == null:
		_log_error("VNVariableManager: sem Condition Evaluator para calcular %s" % id)
		return fallback
	_evaluating[id] = true
	var r: VNEvalResult = m.conditions.evaluate_expression(d.derived, {}, d.type, false)
	_evaluating.erase(id)
	if not r.ok:
		_log_error("VNVariableManager: derivada %s falhou: %s %s" % [id, r.error, r.message])
		return fallback
	return _normalize(d.type, r.value)


func _scheduler() -> VNSceneScheduler:
	var m := modules()
	return null if m == null else m.scheduler


# --- Ciclo de vida por escopo (RT §6.5) -------------------------------------

func reset_game() -> void:
	for id in _defs:
		var d: Dictionary = _defs[id]
		if d.has("derived"):
			continue
		if d.scope == SCOPE_SYS:
			if _is_progress_sys(id):
				_values[id] = d.default
		elif d.persistence != &"profile":
			_values[id] = d.default
	_clear_scopes()


func apply_profile(values: Dictionary) -> void:
	for key in _sorted_keys(values):
		var id := resolve_alias(String(key))
		var d: Dictionary = _defs.get(id, {})
		if d.is_empty() or d.has("derived") or d.get("persistence") != &"profile":
			_log_warning("VNVariableManager: variável de perfil descartada: %s" % key)
			continue
		var c := _coerce(id, d, values[key])
		if c.warning != "":
			_log_warning(c.warning)
		_values[id] = c.value


func enter_chapter(chapter_id: String) -> void:
	_chapter_id = chapter_id
	_chapter_active = true
	_chapter_values = _defaults_of(_chapter_defs.get(chapter_id, {}))
	_apply_pending(_pending_chapter, _chapter_defs.get(chapter_id, {}), _chapter_values)
	_pending_chapter.clear()
	_values["sys.chapter.id"] = chapter_id


func exit_chapter() -> void:
	_chapter_id = ""
	_chapter_active = false
	_chapter_values.clear()
	_pending_chapter.clear()
	_values["sys.chapter.id"] = ""


func enter_scene(scene_id: String) -> void:
	_scene_id = scene_id
	_scene_active = true
	_scene_values = _defaults_of(_scene_defs.get(scene_id, {}))
	_apply_pending(_pending_scene, _scene_defs.get(scene_id, {}), _scene_values)
	_pending_scene.clear()
	_values["sys.scene.id"] = scene_id


func exit_scene() -> void:
	_scene_id = ""
	_scene_active = false
	_scene_values.clear()
	_pending_scene.clear()
	_values["sys.scene.id"] = ""


func _clear_scopes() -> void:
	_chapter_id = ""
	_chapter_active = false
	_chapter_values.clear()
	_scene_id = ""
	_scene_active = false
	_scene_values.clear()
	_pending_chapter.clear()
	_pending_scene.clear()
	if _defs.has("sys.chapter.id"):
		_values["sys.chapter.id"] = ""
		_values["sys.scene.id"] = ""


## sys.* que pertencem à partida e voltam ao padrão em novo jogo. Os finais
## (perfil), o idioma e as de interface ficam.
static func _is_progress_sys(id: String) -> bool:
	return id == "sys.chapter.id" or id == "sys.scene.id" or id == "sys.selection_count" \
		or id.begins_with("sys.scenes.") or id.begins_with("sys.chapters.")


func _defaults_of(defs: Dictionary) -> Dictionary:
	var out := {}
	for id in defs:
		if not defs[id].has("derived"):
			out[id] = defs[id].default
	return out


func _apply_pending(pending: Dictionary, defs: Dictionary, target: Dictionary) -> void:
	for key in _sorted_keys(pending):
		var id := resolve_alias(key)
		var d: Dictionary = defs.get(id, {})
		if d.is_empty() or d.has("derived") or d.get("persistence") != &"save":
			_log_warning("VNVariableManager: variável do save descartada: %s" % key)
			continue
		var c := _coerce(id, d, pending[key])
		if c.warning != "":
			_log_warning(c.warning)
		target[id] = c.value


# --- Save e perfil (RT §8.2–§8.4) -------------------------------------------

func save_values() -> Dictionary:
	var out := {}
	for id in ids():
		var d := _find_definition(id)
		if d.has("derived") or d.get("scope") == SCOPE_SYS or d.get("persistence") != &"save":
			continue
		if not is_scope_active(id):
			continue
		out[id] = _store_for(id)[id]
	return out


func profile_values() -> Dictionary:
	var out := {}
	for id in ids():
		var d: Dictionary = _defs.get(id, {})
		if not d.has("derived") and d.get("persistence") == &"profile":
			out[id] = _values[id]
	return out


func restore_save_values(values: Dictionary) -> PackedStringArray:
	var warnings := PackedStringArray()
	# Passo 3 do RT §8.3: defaults → perfil (fica na memória) → save.
	for id in _defs:
		var d: Dictionary = _defs[id]
		if d.has("derived"):
			continue
		if (d.scope == SCOPE_SYS and _is_progress_sys(id)) or (d.scope != SCOPE_SYS and d.persistence != &"profile"):
			_values[id] = d.default
	if _chapter_active:
		_chapter_values = _defaults_of(_chapter_defs.get(_chapter_id, {}))
	if _scene_active:
		_scene_values = _defaults_of(_scene_defs.get(_scene_id, {}))
	_pending_chapter.clear()
	_pending_scene.clear()

	for key in _sorted_keys(values):
		var id := resolve_alias(String(key))
		var v: Variant = values[key]
		if id.begins_with("chapter.") or id.begins_with("scene."):
			var is_chapter := id.begins_with("chapter.")
			if (is_chapter and _chapter_active) or (not is_chapter and _scene_active):
				if not is_scope_active(id):
					warnings.append("variável descartada: %s (não existe mais)" % key)
					continue
			else:
				# Capítulo/cena ainda não restaurados: aplica no próximo enter_*.
				if not _scoped_ids.has(id):
					warnings.append("variável descartada: %s (não existe mais)" % key)
				else:
					(_pending_chapter if is_chapter else _pending_scene)[id] = v
				continue
		var d := _find_definition(id)
		if d.is_empty():
			warnings.append("variável descartada: %s (não existe mais)" % key)
			continue
		if d.has("derived") or d.scope == SCOPE_SYS:
			warnings.append("variável descartada: %s (somente leitura)" % key)
			continue
		if d.persistence != &"save":
			warnings.append("variável descartada: %s (persistence %s)" % [key, d.persistence])
			continue
		var c := _coerce(id, d, v)
		if c.warning != "":
			warnings.append(c.warning)
		_store_for(id)[id] = c.value
	return warnings


# --- Tipos e conversões -----------------------------------------------------

static func _type_default(type: StringName, constraints: Dictionary) -> Variant:
	match type:
		&"boolean": return false
		&"integer": return 0
		&"number": return 0.0
		&"enum":
			var values: Array = constraints.get("values", [])
			return String(values[0]) if not values.is_empty() else ""
	return ""


## JSON não distingue 2 de 2.0 (spec 08 §2.1): o tipo vem da definição.
static func _normalize(type: StringName, v: Variant) -> Variant:
	if type == &"integer" and v is float and is_finite(v) and v == floorf(v):
		return int(v)
	if type == &"number" and v is int:
		return float(v)
	return v


static func _type_of_value(v: Variant) -> StringName:
	match typeof(v):
		TYPE_BOOL: return &"boolean"
		TYPE_INT: return &"integer"
		TYPE_FLOAT: return &"number"
	return &"string"


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


## Converte o valor de um save/perfil para a definição atual (RT §8.4):
## int↔number, bool↔int; senão default com aviso; fora das restrições, ajustado.
## Devolve [code]{ value, warning }[/code].
func _coerce(id: String, d: Dictionary, v: Variant) -> Dictionary:
	var type: StringName = d.type
	var default_value: Variant = d.default
	var out: Variant = null
	var warning := ""
	match type:
		&"boolean":
			if v is bool:
				out = v
			elif v is int or (v is float and v == floorf(v)):
				out = int(v) != 0
				warning = "variável %s: inteiro convertido para boolean" % id
		&"integer":
			if v is int:
				out = v
			elif v is float and is_finite(v):
				out = int(v)
				if v != floorf(v):
					warning = "variável %s: número %s convertido para inteiro" % [id, v]
			elif v is bool:
				out = 1 if v else 0
				warning = "variável %s: boolean convertido para inteiro" % id
		&"number":
			if v is float or v is int:
				out = float(v)
		&"string":
			if v is String:
				out = v
		&"enum":
			if v is String and Array(d.get("constraints", {}).get("values", [])).has(v):
				out = v
	if out == null or (out is float and not is_finite(out)):
		return {"value": default_value, "warning": "variável %s: valor %s incompatível com %s; usa o padrão" % [id, v, type]}
	# Restrições novas: ajusta (clamp), RT §8.4.
	var c: Dictionary = d.get("constraints", {})
	if type == &"integer" or type == &"number":
		var lo: Variant = c.get("min", -INT_LIMIT if type == &"integer" else null)
		var hi: Variant = c.get("max", INT_LIMIT if type == &"integer" else null)
		var adjusted: Variant = out
		if lo != null and adjusted < lo:
			adjusted = lo
		if hi != null and adjusted > hi:
			adjusted = hi
		adjusted = _normalize(type, int(adjusted) if type == &"integer" else float(adjusted))
		if not _same(adjusted, out):
			warning = "variável %s: %s fora das restrições, ajustado para %s" % [id, out, adjusted]
			out = adjusted
	elif type == &"string" and c.has("max_length") and String(out).length() > int(c.max_length):
		out = String(out).left(int(c.max_length))
		warning = "variável %s: texto cortado em %d caracteres" % [id, int(c.max_length)]
	return {"value": out, "warning": warning}


# --- Derivadas: ciclos ------------------------------------------------------

## Acusa ciclos entre derivadas (DM §4.5). O validador já os recusa; aqui é
## defesa contra bundle feito à mão.
func _check_derived_cycles() -> void:
	var graph := {}
	var all := _all_definitions()
	for id in all:
		var d: Dictionary = all[id]
		if d.has("derived"):
			var deps := {}
			_collect_refs(d.derived, deps)
			graph[id] = deps.keys()
	var state := {}  # 1 = visitando, 2 = pronto
	for id in _sorted_keys(graph):
		_visit(id, graph, state, [])


func _visit(id: String, graph: Dictionary, state: Dictionary, stack: Array) -> void:
	if state.get(id, 0) == 2:
		return
	if state.get(id, 0) == 1:
		var cycle := stack.slice(stack.find(id))
		for c in cycle:
			_cyclic[c] = true
		_log_error("VNVariableManager: ciclo entre derivadas: %s" % " → ".join(PackedStringArray(cycle + [id])))
		return
	state[id] = 1
	stack.append(id)
	for dep in graph[id]:
		if graph.has(dep):
			_visit(dep, graph, state, stack)
	stack.pop_back()
	state[id] = 2


func _all_definitions() -> Dictionary:
	var out := _defs.duplicate()
	for table in [_chapter_defs, _scene_defs]:
		for owner in table:
			for id in table[owner]:
				if not out.has(id):
					out[id] = table[owner][id]
	return out


## Referências a variáveis numa expressão ou condição: [code]{"var"}[/code] e
## [code]{"variable"}[/code].
static func _collect_refs(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		for k in node:
			if (k == "var" or k == "variable") and node[k] is String:
				out[node[k]] = true
			else:
				_collect_refs(node[k], out)
	elif node is Array:
		for item in node:
			_collect_refs(item, out)


# --- Utilidades -------------------------------------------------------------

func _log_error(msg: String) -> void:
	diagnostics.append("ERRO " + msg)
	if not quiet:
		push_error(msg)


func _log_warning(msg: String) -> void:
	diagnostics.append("AVISO " + msg)
	if not quiet:
		push_warning(msg)


static func _sorted_keys(d: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray()
	for k in d:
		keys.append(String(k))
	keys.sort()
	return keys


static func _looks_like_variable(id: String) -> bool:
	for p in ["global.", "character.", "chapter.", "scene.", "plugin."]:
		if id.begins_with(p):
			return true
	return false


static func _scope_of(id: String) -> StringName:
	return StringName(id.get_slice(".", 0))
