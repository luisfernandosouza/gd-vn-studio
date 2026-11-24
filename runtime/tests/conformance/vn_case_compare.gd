class_name VNCaseCompare
extends RefCounted
## Comparação e impressão dos resultados dos vetores, com a mesma regra de [code]tools/conformance.py[/code]
## ([code]same()[/code]) e da spec 08 §2.1:
## - se um dos lados é [code]float[/code], os dois têm de ser números (não booleanos) e iguais por valor
##   ([code]2.0[/code] confere com [code]2[/code]; o tipo, quando importa, vem no campo [code]type[/code]);
## - inteiros comparam com inteiros; booleano nunca é número;
## - [StringName] vale como [String] e arrays empacotados como [Array];
## - objetos precisam ter o mesmo conjunto de chaves.


static func same(expected: Variant, got: Variant) -> bool:
	var a: Variant = normalize(expected)
	var b: Variant = normalize(got)
	var ta := typeof(a)
	var tb := typeof(b)
	if ta == TYPE_FLOAT or tb == TYPE_FLOAT:
		return _is_number(a) and _is_number(b) and float(a) == float(b)
	if ta == TYPE_DICTIONARY and tb == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k in da:
			if not db.has(k) or not same(da[k], db[k]):
				return false
		return true
	if ta == TYPE_ARRAY and tb == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not same(aa[i], ab[i]):
				return false
		return true
	return ta == tb and a == b


## Converte o resultado de um módulo em tipos JSON: [StringName] → [String], arrays empacotados →
## [Array], chaves de objeto → [String]. Inteiros e floats ficam como estão.
static func normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_STRING_NAME:
			return String(v)
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[String(k) if (k is String or k is StringName) else str(k)] = normalize(v[k])
			return out
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			var out := []
			for x in v:
				out.append(normalize(x))
			return out
	return v


## Texto JSON de um valor, em uma linha, para as mensagens de falha. Inteiros saem sem casa decimal e
## floats com ".0" quando inteiros, para que o esperado e o obtido mostrem o tipo.
static func to_json(v: Variant) -> String:
	var n: Variant = normalize(v)
	match typeof(n):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if n else "false"
		TYPE_INT:
			return str(n)
		TYPE_FLOAT:
			var f: float = n
			if is_nan(f) or is_inf(f):
				return str(f)
			if f == floorf(f) and absf(f) < 1e16:
				return "%d.0" % int(f)
			return String.num(f, 17) if str(f).to_float() != f else str(f)
		TYPE_STRING:
			return JSON.stringify(n)
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for x in n:
				parts.append(to_json(x))
			return "[" + ", ".join(parts) + "]"
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for k in n:
				parts.append("%s: %s" % [JSON.stringify(String(k)), to_json(n[k])])
			return "{" + ", ".join(parts) + "}"
	return JSON.stringify(str(n))


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
