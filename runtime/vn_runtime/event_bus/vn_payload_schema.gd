class_name VNPayloadSchema
extends RefCounted
## Validação de payload de evento (RT §7.2, Plugin SDK §7).
##
## Confere que um valor só tem tipos JSON e o valida contra um subconjunto do
## JSON Schema 2020-12, o bastante para os schemas declarados em
## [code]project.json → events[].payload[/code] e
## [code]plugin.json → events.emits[].payload[/code]: [code]type[/code],
## [code]enum[/code], [code]const[/code], [code]properties[/code],
## [code]required[/code], [code]additionalProperties[/code],
## [code]minProperties[/code]/[code]maxProperties[/code], [code]items[/code],
## [code]prefixItems[/code], [code]minItems[/code]/[code]maxItems[/code],
## [code]uniqueItems[/code], [code]minimum[/code]/[code]maximum[/code],
## [code]exclusiveMinimum[/code]/[code]exclusiveMaximum[/code],
## [code]multipleOf[/code], [code]minLength[/code]/[code]maxLength[/code],
## [code]pattern[/code], [code]allOf[/code], [code]anyOf[/code],
## [code]oneOf[/code] e [code]not[/code]. Palavras-chave fora dessa lista
## (inclusive [code]$ref[/code]) são ignoradas, como manda o JSON Schema para
## anotações desconhecidas.
##
## Números: [code]integer[/code] aceita [code]float[/code] com parte
## fracionária zero ([code]3.0[/code]), porque o JSON lido pelo Godot dá
## [code]float[/code] para todo número (mesma regra do RT §5.3, passo 6).
## [StringName] conta como string.

static var _regex_cache: Dictionary = {}


## Caminho e motivo do primeiro tipo não JSON em [param value], ou vazio se
## tudo é JSON (null, bool, int, float finito, String, Array, Dictionary com
## chaves String).
static func json_type_error(value: Variant, path: String = "") -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return ""
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return "%s: número não finito" % _p(path)
			return ""
		TYPE_ARRAY:
			for i in value.size():
				var err := json_type_error(value[i], "%s/%d" % [path, i])
				if not err.is_empty():
					return err
			return ""
		TYPE_DICTIONARY:
			for k in value:
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
					return "%s: chave %s não é string" % [_p(path), var_to_str(k)]
				var err := json_type_error(value[k], "%s/%s" % [path, k])
				if not err.is_empty():
					return err
			return ""
	return "%s: %s não é tipo JSON" % [_p(path), type_string(typeof(value))]


## Valida [param value] contra [param schema]. Devolve o primeiro erro
## ("caminho: motivo") ou vazio. Não confere tipos JSON; use
## [method json_type_error] antes.
static func validate(value: Variant, schema: Variant, path: String = "") -> String:
	if schema is bool:
		return "" if schema else "%s: nenhum valor é aceito" % _p(path)
	if not schema is Dictionary:
		return ""
	var s: Dictionary = schema

	if s.has("type"):
		var types: Array = s.type if s.type is Array else [s.type]
		var ok := false
		for t in types:
			if is_type(value, String(t)):
				ok = true
				break
		if not ok:
			return "%s: esperava %s, veio %s" % [_p(path), " ou ".join(PackedStringArray(types)), json_type_name(value)]

	if s.has("const") and not json_equal(value, s.const):
		return "%s: esperava %s" % [_p(path), JSON.stringify(s.const)]
	if s.has("enum"):
		var found := false
		for e in s.enum:
			if json_equal(value, e):
				found = true
				break
		if not found:
			return "%s: %s fora de %s" % [_p(path), JSON.stringify(value), JSON.stringify(s.enum)]

	if _is_number(value):
		var n := float(value)
		if s.has("minimum") and n < float(s.minimum):
			return "%s: %s < minimum %s" % [_p(path), value, s.minimum]
		if s.has("maximum") and n > float(s.maximum):
			return "%s: %s > maximum %s" % [_p(path), value, s.maximum]
		if s.has("exclusiveMinimum") and n <= float(s.exclusiveMinimum):
			return "%s: %s <= exclusiveMinimum %s" % [_p(path), value, s.exclusiveMinimum]
		if s.has("exclusiveMaximum") and n >= float(s.exclusiveMaximum):
			return "%s: %s >= exclusiveMaximum %s" % [_p(path), value, s.exclusiveMaximum]
		if s.has("multipleOf") and float(s.multipleOf) > 0.0:
			var q := n / float(s.multipleOf)
			if not is_equal_approx(q, roundf(q)):
				return "%s: %s não é múltiplo de %s" % [_p(path), value, s.multipleOf]

	if value is String or value is StringName:
		var str_value := String(value)
		if s.has("minLength") and str_value.length() < int(s.minLength):
			return "%s: menos de %d caracteres" % [_p(path), int(s.minLength)]
		if s.has("maxLength") and str_value.length() > int(s.maxLength):
			return "%s: mais de %d caracteres" % [_p(path), int(s.maxLength)]
		if s.has("pattern"):
			var re := _regex(String(s.pattern))
			if re != null and re.search(str_value) == null:
				return "%s: \"%s\" não casa com %s" % [_p(path), str_value, s.pattern]

	if value is Array:
		var arr: Array = value
		if s.has("minItems") and arr.size() < int(s.minItems):
			return "%s: menos de %d itens" % [_p(path), int(s.minItems)]
		if s.has("maxItems") and arr.size() > int(s.maxItems):
			return "%s: mais de %d itens" % [_p(path), int(s.maxItems)]
		if s.get("uniqueItems", false):
			for i in arr.size():
				for j in range(i + 1, arr.size()):
					if json_equal(arr[i], arr[j]):
						return "%s: itens %d e %d repetidos" % [_p(path), i, j]
		var prefix: Array = s.get("prefixItems", [])
		for i in mini(prefix.size(), arr.size()):
			var err := validate(arr[i], prefix[i], "%s/%d" % [path, i])
			if not err.is_empty():
				return err
		if s.has("items"):
			for i in range(prefix.size(), arr.size()):
				var err := validate(arr[i], s.items, "%s/%d" % [path, i])
				if not err.is_empty():
					return err

	if value is Dictionary:
		var obj: Dictionary = value
		if s.has("minProperties") and obj.size() < int(s.minProperties):
			return "%s: menos de %d campos" % [_p(path), int(s.minProperties)]
		if s.has("maxProperties") and obj.size() > int(s.maxProperties):
			return "%s: mais de %d campos" % [_p(path), int(s.maxProperties)]
		for req in s.get("required", []):
			if not obj.has(String(req)) and not obj.has(StringName(req)):
				return "%s: falta o campo obrigatório \"%s\"" % [_p(path), req]
		var props: Dictionary = s.get("properties", {})
		for k in obj:
			var key := String(k)
			var sub_path := "%s/%s" % [path, key]
			if props.has(key):
				var err := validate(obj[k], props[key], sub_path)
				if not err.is_empty():
					return err
			elif s.has("additionalProperties"):
				var ap: Variant = s.additionalProperties
				if ap is bool and not ap:
					return "%s: campo \"%s\" não declarado" % [_p(path), key]
				var err := validate(obj[k], ap, sub_path)
				if not err.is_empty():
					return err

	for sub in s.get("allOf", []):
		var err := validate(value, sub, path)
		if not err.is_empty():
			return err
	if s.has("anyOf"):
		var any_ok := false
		for sub in s.anyOf:
			if validate(value, sub, path).is_empty():
				any_ok = true
				break
		if not any_ok:
			return "%s: nenhuma alternativa de anyOf aceita o valor" % _p(path)
	if s.has("oneOf"):
		var hits := 0
		for sub in s.oneOf:
			if validate(value, sub, path).is_empty():
				hits += 1
		if hits != 1:
			return "%s: %d alternativas de oneOf aceitam o valor (esperava 1)" % [_p(path), hits]
	if s.has("not") and validate(value, s.not, path).is_empty():
		return "%s: o valor casa com \"not\"" % _p(path)
	return ""


## [param value] é do tipo JSON Schema [param type]?
static func is_type(value: Variant, type: String) -> bool:
	match type:
		"null":
			return value == null
		"boolean":
			return value is bool
		"integer":
			return value is int or (value is float and is_finite(value) and value == floorf(value))
		"number":
			return value is int or (value is float and is_finite(value))
		"string":
			return value is String or value is StringName
		"array":
			return value is Array
		"object":
			return value is Dictionary
	return false


## Nome do tipo JSON de [param value], para mensagens.
static func json_type_name(value: Variant) -> String:
	for t in ["null", "boolean", "integer", "number", "string", "array", "object"]:
		if is_type(value, t):
			return t
	return type_string(typeof(value))


## Igualdade JSON: [code]1 == 1.0[/code], [StringName] igual à [String],
## arrays e objetos comparados por conteúdo.
static func json_equal(a: Variant, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		return float(a) == float(b)
	if (a is String or a is StringName) and (b is String or b is StringName):
		return String(a) == String(b)
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not json_equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			var key := String(k)
			var bk: Variant = key if b.has(key) else StringName(key)
			if not b.has(bk) or not json_equal(a[k], b[bk]):
				return false
		return true
	if a == null or b == null:
		return a == null and b == null
	if typeof(a) != typeof(b):
		return false
	return a == b


static func _is_number(v: Variant) -> bool:
	return (v is int or v is float) and not v is bool


static func _regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var re := RegEx.new()
		_regex_cache[pattern] = re if re.compile(pattern) == OK else null
	return _regex_cache[pattern]


static func _p(path: String) -> String:
	return "payload" if path.is_empty() else "payload" + path
