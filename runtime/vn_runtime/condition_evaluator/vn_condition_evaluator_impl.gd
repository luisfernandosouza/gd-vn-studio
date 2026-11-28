class_name VNConditionEvaluatorImpl
extends VNConditionEvaluator
## Condition Evaluator real (tarefas M1-03 e a parte de M1-04 de que as expressões dependem).
##
## Expressões de valor (DM §6.1) e funções (DM §6.1.1): literal, [code]{"var"}[/code],
## [code]{"fn","args"}[/code], [code]{"if","then","else"}[/code] e [code]{"result"}[/code].
## A aritmética e as comparações vêm de [VNValue] (M1-02), na mesma ordem de verificações de
## [code]docs/specs/tools/conformance.py[/code].
##
## [b]Escolhas onde a spec é omissa[/b] (também listadas no PR do M1-03):
## [br]- Aridade errada ou função desconhecida: [code]TYPE_MISMATCH[/code] (é o T007 do validador;
##   o runtime só tem os códigos do RT §6.2), checada antes de avaliar os argumentos.
## [br]- [code]random_int[/code] sem [param allow_random] (condição, derivada): [code]TYPE_MISMATCH[/code]
##   (T008 no validador). Com [code]min > max[/code]: [code]OUT_OF_RANGE[/code]. O RNG é o comum do
##   motor; o PCG32 reproduzível é o M1-08.
## [br]- Variável de escopo inativo ([code]chapter.*[/code]/[code]scene.*[/code]): [code]SCOPE_INACTIVE[/code].
## [br]- Forma de expressão desconhecida (objeto sem [code]var[/code]/[code]fn[/code]/[code]if[/code]/
##   [code]result[/code], ou lista): [code]TYPE_MISMATCH[/code].
## [br]- [code]{"result"}[/code] sem [code]bindings.result[/code] ou fora de [code]on_result[/code]:
##   usa o [code]default[/code] ou o padrão do tipo de destino, como num campo ausente.
## [br]Condições (DM §5) ficam no mínimo que o [code]if[/code] precisa; os vetores e o detalhe são do M1-04.

const _ARITY := {
	&"add": [2, 2], &"sub": [2, 2], &"mul": [2, 2], &"div": [2, 2], &"mod": [2, 2],
	&"min": [2, 8], &"max": [2, 8], &"clamp": [3, 3],
	&"round": [1, 1], &"floor": [1, 1], &"ceil": [1, 1], &"abs": [1, 1],
	&"concat": [1, 8], &"random_int": [2, 2],
}

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


# --- API ----------------------------------------------------------------------

func evaluate_expression(expr: Variant, bindings: Dictionary = {}, target_type: StringName = &"", allow_random: bool = false) -> VNEvalResult:
	if typeof(expr) == TYPE_ARRAY:
		return _mismatch("lista não é expressão de valor")
	if typeof(expr) != TYPE_DICTIONARY:
		return VNValue.from_literal(expr)
	var e: Dictionary = expr
	if e.has("var"):
		return _read_var(String(e["var"]))
	if e.has("if"):
		var c := _cond(e["if"], bindings)
		if not c.ok:
			return c
		if not e.has("then") or not e.has("else"):
			return _mismatch("if exige then e else")
		return evaluate_expression(e["then"] if c.value else e["else"], bindings, target_type, allow_random)
	if e.has("fn"):
		return _call(StringName(String(e["fn"])), e.get("args", []), bindings, target_type, allow_random)
	if e.has("result"):
		return _result(e, bindings, target_type)
	return _mismatch("forma de expressão desconhecida")


func evaluate_conditions(conditions: Variant, bindings: Dictionary = {}) -> VNEvalResult:
	return _cond(conditions, bindings)


func explain_conditions(conditions: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := _cond(conditions, {})
	if r.ok and r.value:
		return out
	_explain(conditions, "conditions", out)
	return out


# --- Expressões ---------------------------------------------------------------

func _read_var(id: String) -> VNEvalResult:
	var vars := _variables()
	if vars == null:
		return VNEvalResult.failure(VNErrors.VARIABLE_NOT_FOUND, "sem Variable Manager: %s" % id)
	if not vars.has(id):
		return VNEvalResult.failure(VNErrors.VARIABLE_NOT_FOUND, id)
	if not vars.is_scope_active(id):
		return VNEvalResult.failure(VNErrors.SCOPE_INACTIVE, id)
	var type: StringName = vars.get_definition(id).get("type", &"")
	return VNValue.typed(vars.read(id), type)


func _call(fn: StringName, args: Variant, bindings: Dictionary, target_type: StringName, allow_random: bool) -> VNEvalResult:
	if not _ARITY.has(fn):
		return _mismatch("função desconhecida %s" % fn)
	if typeof(args) != TYPE_ARRAY:
		return _mismatch("%s: args deve ser lista" % fn)
	var arity: Array = _ARITY[fn]
	if args.size() < arity[0] or args.size() > arity[1]:
		return _mismatch("%s: aridade (%d argumentos)" % [fn, args.size()])
	if fn == &"random_int" and not allow_random:
		return _mismatch("random_int só vale em efeitos e payloads de emit (T008)")
	var vs: Array[VNEvalResult] = []
	for a in args:
		var v := evaluate_expression(a, bindings, target_type, allow_random)
		if not v.ok:
			return v
		vs.append(v)
	match fn:
		&"add", &"sub", &"mul", &"div", &"mod":
			return VNValue.arith(fn, vs[0], vs[1])
		&"min", &"max":
			return VNValue.min_max(fn, vs)
		&"clamp":
			return VNValue.clamp_value(vs[0], vs[1], vs[2])
		&"round", &"floor", &"ceil", &"abs":
			return VNValue.unary(fn, vs[0])
		&"concat":
			var s := ""
			for v in vs:
				s += VNValue.to_text(v)
			return VNValue.string(s)
		&"random_int":
			return _random_int(vs[0], vs[1])
	return _mismatch("função desconhecida %s" % fn)


func _random_int(lo: VNEvalResult, hi: VNEvalResult) -> VNEvalResult:
	if lo.type != VNValue.INTEGER or hi.type != VNValue.INTEGER:
		return _mismatch("random_int exige inteiros")
	if lo.value > hi.value:
		return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "random_int com min > max")
	return VNValue.integer(_rng.randi_range(lo.value, hi.value))


## [code]{"result": "a.b", "default": x}[/code] (DM §6.1): campo do payload de
## [code]bindings.result[/code]; ausente ou de tipo diferente do de destino vale o
## [code]default[/code] ou o padrão do tipo.
func _result(e: Dictionary, bindings: Dictionary, target_type: StringName) -> VNEvalResult:
	var type := target_type if target_type != &"" else VNValue.STRING
	var cur: Variant = bindings.get("result", null)
	for part in String(e["result"]).split("."):
		cur = cur.get(part, null) if typeof(cur) == TYPE_DICTIONARY else null
	if cur != null:
		var r := VNValue.typed(cur, type)
		if r.ok:
			return r
	if e.has("default"):
		return VNValue.from_literal(e["default"], type)
	return VNValue.typed(VNValue.default_of(type), type)


# --- Condições (mínimo para o if; M1-04 completa) -----------------------------

func _cond(c: Variant, bindings: Dictionary) -> VNEvalResult:
	if typeof(c) == TYPE_ARRAY:
		for x in c:
			var r := _cond(x, bindings)
			if not r.ok or not r.value:
				return r
		return VNValue.boolean(true)
	if typeof(c) != TYPE_DICTIONARY:
		return _mismatch("condição inválida")
	var d: Dictionary = c
	if d.has("all"):
		return _cond(d["all"], bindings)
	if d.has("any"):
		for x in d["any"]:
			var r := _cond(x, bindings)
			if not r.ok or r.value:
				return r
		return VNValue.boolean(false)
	if d.has("not"):
		var r := _cond(d["not"], bindings)
		return r if not r.ok else VNValue.boolean(not r.value)
	if d.has("event_since_last_selection"):
		var m := modules()
		var seen := m != null and m.scheduler != null \
			and String(d["event_since_last_selection"]) in m.scheduler.events_since_selection()
		return VNValue.boolean(seen)
	if d.has("variable"):
		return _leaf(d, bindings)
	return _mismatch("condição desconhecida")


func _leaf(d: Dictionary, bindings: Dictionary) -> VNEvalResult:
	var id := String(d["variable"])
	var a := _read_var(id)
	if not a.ok:
		return a
	var op := StringName(String(d.get("operator", "")))
	if op == &"is_default":
		return VNValue.boolean(_variables().is_default(id))
	if not d.has("value"):
		return _mismatch("%s exige value" % op)
	if op == &"in" or op == &"not_in":
		if typeof(d["value"]) != TYPE_ARRAY:
			return _mismatch("%s exige lista" % op)
		var cands: Array[VNEvalResult] = []
		for x in d["value"]:
			var lit := VNValue.from_literal(x)
			if not lit.ok:
				return lit
			cands.append(lit)
		var r := VNValue.is_in(a, cands)
		if not r.ok or op == &"in":
			return r
		return VNValue.boolean(not r.value)
	var b := evaluate_expression(d["value"], bindings)
	if not b.ok:
		return b
	return VNValue.compare(op, a, b)


## Uma entrada por folha falsa que decidiu o resultado (Preview Protocol §4.3): [code]all[/code] e
## listas mostram a primeira falsa (curto-circuito); [code]any[/code] mostra todas as alternativas.
func _explain(c: Variant, path: String, out: Array[Dictionary]) -> void:
	if typeof(c) == TYPE_ARRAY:
		for i in c.size():
			var r := _cond(c[i], {})
			if not r.ok or not r.value:
				_explain(c[i], "%s[%d]" % [path, i], out)
				return
		return
	if typeof(c) != TYPE_DICTIONARY:
		out.append({"path": path})
		return
	var d: Dictionary = c
	if d.has("all"):
		_explain(d["all"], path + ".all", out)
	elif d.has("any"):
		for i in d["any"].size():
			_explain(d["any"][i], "%s.any[%d]" % [path, i], out)
	elif d.has("not"):
		_explain_leaf(d["not"], path + ".not", out)
	elif d.has("event_since_last_selection"):
		out.append({"path": path, "event": String(d["event_since_last_selection"])})
	else:
		_explain_leaf(d, path, out)


func _explain_leaf(d: Variant, path: String, out: Array[Dictionary]) -> void:
	if typeof(d) != TYPE_DICTIONARY or not d.has("variable"):
		out.append({"path": path})
		return
	var entry := {"path": path, "variable": String(d["variable"]), "operator": String(d.get("operator", ""))}
	if d.has("value"):
		var exp: Variant = d["value"]
		if typeof(exp) == TYPE_DICTIONARY:
			var ev := evaluate_expression(exp)
			exp = ev.value if ev.ok else null
		entry["expected"] = exp
	var vars := _variables()
	if vars != null and vars.has(String(d["variable"])):
		entry["actual"] = vars.read(String(d["variable"]))
	out.append(entry)


# --- Internos -----------------------------------------------------------------

func _variables() -> VNVariableManager:
	var m := modules()
	return m.variables if m != null else null


static func _mismatch(message: String) -> VNEvalResult:
	return VNEvalResult.failure(VNErrors.TYPE_MISMATCH, message)
