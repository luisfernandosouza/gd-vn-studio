extends RefCounted
## SemVer mínimo do Plugin Host (Plugin SDK §11): compara versões e confere
## faixas no formato do npm, o mesmo dos manifestos ([code]^1.0.0[/code],
## [code]~1.2.0[/code], [code]>=4.7.0 <5.0.0[/code], [code]1.x[/code],
## [code]*[/code], [code]a || b[/code], [code]1.0.0 - 1.4.0[/code]).
##
## Sem [code]class_name[/code]: o Plugin Host carrega com [code]preload[/code],
## para não ocupar um nome global (Plugin SDK §2.4, nomes globais do Godot).
## Pré-lançamentos ([code]1.0.0-beta.1[/code]) ordenam antes da versão final e
## só casam com faixas que citam o mesmo [code]major.minor.patch[/code].


## [major, minor, patch, prerelease]; [code][][/code] se não é SemVer.
static func parse(version: String) -> Array:
	var v := version.strip_edges()
	if v.begins_with("v") or v.begins_with("="):
		v = v.substr(1)
	var pre := ""
	var cut := v.find("+")
	if cut >= 0:
		v = v.substr(0, cut)
	cut = v.find("-")
	if cut >= 0:
		pre = v.substr(cut + 1)
		v = v.substr(0, cut)
	var parts := v.split(".")
	if parts.size() != 3:
		return []
	var out := []
	for p in parts:
		if not p.is_valid_int() or int(p) < 0:
			return []
		out.append(int(p))
	out.append(pre)
	return out


## -1, 0 ou 1. Versões inválidas comparam como iguais.
static func compare(a: String, b: String) -> int:
	return _cmp(parse(a), parse(b))


## A versão satisfaz a faixa. Faixa vazia ou [code]*[/code] aceita tudo.
static func satisfies(version: String, range_expr: String) -> bool:
	var v := parse(version)
	if v.is_empty():
		return false
	for alt in range_expr.split("||"):
		if _satisfies_set(v, alt.strip_edges()):
			return true
	return false


## A faixa é legível (para dar erro claro em vez de recusar calado).
static func is_valid_range(range_expr: String) -> bool:
	for alt in range_expr.split("||"):
		if _comparators(alt.strip_edges()) == null:
			return false
	return true


static func _cmp(a: Array, b: Array) -> int:
	if a.is_empty() or b.is_empty():
		return 0
	for i in 3:
		if a[i] != b[i]:
			return -1 if a[i] < b[i] else 1
	var pa: String = a[3]
	var pb: String = b[3]
	if pa == pb:
		return 0
	if pa.is_empty():
		return 1
	if pb.is_empty():
		return -1
	return -1 if pa < pb else 1


static func _satisfies_set(v: Array, expr: String) -> bool:
	var comps = _comparators(expr)
	if comps == null:
		return false
	var allows_pre := false
	for c in comps:
		var cv: Array = c[1]
		if not String(cv[3]).is_empty() and cv[0] == v[0] and cv[1] == v[1] and cv[2] == v[2]:
			allows_pre = true
		if not _test(v, c[0], cv):
			return false
	return String(v[3]).is_empty() or allows_pre


static func _test(v: Array, op: String, cv: Array) -> bool:
	var c := _cmp(v, cv)
	match op:
		">=": return c >= 0
		">": return c > 0
		"<=": return c <= 0
		"<": return c < 0
		_: return c == 0


## Lista de [op, versão]; [code]null[/code] se a faixa não é legível.
static func _comparators(expr: String):
	var out := []
	if expr.is_empty() or expr == "*" or expr == "x" or expr == "X":
		return out
	var hy := expr.find(" - ")
	if hy >= 0:
		var lo = _partial(expr.substr(0, hy).strip_edges())
		var hi = _partial(expr.substr(hy + 3).strip_edges())
		if lo == null or hi == null:
			return null
		out.append([">=", _fill(lo)])
		_upper(out, hi, "<=")
		return out
	for raw in expr.split(" ", false):
		var op := ""
		var tok: String = raw
		for candidate in [">=", "<=", ">", "<", "=", "^", "~"]:
			if tok.begins_with(candidate):
				op = candidate
				tok = tok.substr(candidate.length())
				break
		var p = _partial(tok)
		if p == null:
			return null
		match op:
			"^":
				var lo: Array = _fill(p)
				out.append([">=", lo])
				if p[0] == null:
					continue
				if p[0] > 0 or p[1] == null:
					out.append(["<", [p[0] + 1, 0, 0, ""]])
				elif p[1] > 0 or p[2] == null:
					out.append(["<", [0, p[1] + 1, 0, ""]])
				else:
					out.append(["<", [0, 0, p[2] + 1, ""]])
			"~":
				out.append([">=", _fill(p)])
				if p[0] == null:
					continue
				if p[1] == null:
					out.append(["<", [p[0] + 1, 0, 0, ""]])
				else:
					out.append(["<", [p[0], p[1] + 1, 0, ""]])
			">=", ">", "<=", "<":
				if op == ">" and p[2] == null and p[0] != null:
					out.append([">=", _bump(p)])
				elif op == "<=" and p[2] == null and p[0] != null:
					out.append(["<", _bump(p)])
				else:
					out.append([op, _fill(p)])
			_:
				if p[0] == null:
					continue
				if p[2] != null:
					out.append(["=", _fill(p)])
				else:
					out.append([">=", _fill(p)])
					out.append(["<", _bump(p)])
	return out


## [major|null, minor|null, patch|null, pre]; null se ilegível.
static func _partial(tok: String):
	if tok.is_empty():
		return null
	var pre := ""
	var cut := tok.find("+")
	if cut >= 0:
		tok = tok.substr(0, cut)
	cut = tok.find("-")
	if cut >= 0:
		pre = tok.substr(cut + 1)
		tok = tok.substr(0, cut)
	if tok.begins_with("v"):
		tok = tok.substr(1)
	var parts := tok.split(".")
	if parts.size() > 3:
		return null
	var out := [null, null, null, pre]
	for i in parts.size():
		var s := parts[i]
		if s in ["x", "X", "*"]:
			break
		if not s.is_valid_int() or int(s) < 0:
			return null
		out[i] = int(s)
	return out


static func _fill(p: Array) -> Array:
	return [p[0] if p[0] != null else 0, p[1] if p[1] != null else 0, p[2] if p[2] != null else 0, p[3]]


## A menor versão acima da faixa parcial (1.2 → 1.3.0, 1 → 2.0.0).
static func _bump(p: Array) -> Array:
	if p[1] == null:
		return [p[0] + 1, 0, 0, ""]
	return [p[0], p[1] + 1, 0, ""]


static func _upper(out: Array, p: Array, op: String) -> void:
	if p[0] == null:
		return
	if p[2] != null:
		out.append([op, _fill(p)])
	else:
		out.append(["<", _bump(p)])
