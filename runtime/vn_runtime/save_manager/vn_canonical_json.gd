class_name VNCanonicalJson
extends RefCounted
## JSON canônico (JCS, RFC 8785) e assinatura HMAC-SHA256 de saves e perfil.
##
## O [code]JSON.stringify[/code] do Godot formata números de outro jeito e não
## ordena as chaves pelas unidades UTF-16, então o runtime tem o serializador
## próprio (Build System §5.1, RT §12.1). O mesmo serializador serve ao
## [code]content_hash[/code] do bundle; vetores em
## [code]conformance/canonical.json[/code].
##
## Specs: BS §5.1, §8.3, §11.1; RT §2.1 (chave de debug), §12.1.
## Tarefa: M2-10.

## Prefixo do campo [code]integrity[/code] (save.schema.json).
const INTEGRITY_PREFIX := "hmac-sha256-"

## Chave fixa de debug: 32 bytes zero (RT §2.1, BS §11.1).
static func debug_key() -> PackedByteArray:
	var key := PackedByteArray()
	key.resize(32)
	key.fill(0)
	return key


## Texto canônico de [param value] (tipos JSON: null, bool, int, float,
## String/StringName, Array/Packed*Array e Dictionary).
static func stringify(value: Variant) -> String:
	var parts := PackedStringArray()
	_write(value, parts)
	return "".join(parts)


## SHA-256 do texto canônico, no formato [code]sha256-<base64>[/code] (o [code]Hash[/code] do common.schema.json).
static func hash_sri(value: Variant) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(stringify(value).to_utf8_buffer())
	return "sha256-" + Marshalls.raw_to_base64(ctx.finish())


## [code]hmac-sha256-<base64>[/code] do JSON canônico de [param data] sem o campo [code]integrity[/code] (BS §8.3).
static func signature(data: Dictionary, key: PackedByteArray) -> String:
	var copy := data.duplicate()
	copy.erase("integrity")
	var mac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, stringify(copy).to_utf8_buffer())
	return INTEGRITY_PREFIX + Marshalls.raw_to_base64(mac)


## A assinatura existe e confere com [param key]. Compara em tempo constante.
static func verify(data: Dictionary, key: PackedByteArray) -> bool:
	var got: Variant = data.get("integrity")
	if not got is String:
		return false
	var expected := signature(data, key)
	var a: PackedByteArray = (got as String).to_utf8_buffer()
	var b := expected.to_utf8_buffer()
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


## Os dados como o leitor os verá depois de gravar e ler o JSON de novo.
##
## O leitor de JSON do Godot pode errar o último bit de um número de 17
## algarismos; assinar a forma já relida garante que quem carrega o arquivo
## calcula o mesmo texto canônico e a mesma assinatura. Devolve um
## [Dictionary]/[Array] novo, com todos os números como [code]float[/code],
## igual ao que [code]JSON.parse_string[/code] devolve.
static func stabilize(value: Variant) -> Variant:
	var text := stringify(value)
	var parsed: Variant = JSON.parse_string(text)
	for i in 4:
		var again := stringify(parsed)
		if again == text:
			return parsed
		text = again
		parsed = JSON.parse_string(text)
	return parsed


# --- Serialização -------------------------------------------------------------

static func _write(value: Variant, out: PackedStringArray) -> void:
	match typeof(value):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if value else "false")
		TYPE_INT:
			out.append(str(value))
		TYPE_FLOAT:
			out.append(number(value))
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			out.append(quote(str(value)))
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = []
			for k in d:
				keys.append([str(k), _utf16_units(str(k)), k])
			keys.sort_custom(func(a, b): return _units_less(a[1], b[1]))
			out.append("{")
			var first := true
			for entry in keys:
				if not first:
					out.append(",")
				first = false
				out.append(quote(entry[0]))
				out.append(":")
				_write(d[entry[2]], out)
			out.append("}")
		_:
			if value is Array or typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
				out.append("[")
				var first := true
				for item in value:
					if not first:
						out.append(",")
					first = false
					_write(item, out)
				out.append("]")
			else:
				push_error("VNCanonicalJson: tipo sem forma JSON: %s" % type_string(typeof(value)))
				out.append("null")


## Número como o [code]Number.prototype.toString[/code] do JavaScript (RFC 8785 §3.2.2.3).
static func number(x: float) -> String:
	if is_nan(x) or is_inf(x):
		push_error("VNCanonicalJson: número não finito")
		return "null"
	if x == 0.0:
		return "0"
	# num_scientific dá os algarismos da forma mais curta que volta ao mesmo valor.
	var s := String.num_scientific(x)
	var negative := s.begins_with("-")
	if negative:
		s = s.substr(1)
	var exp10 := 0
	var e_at := s.find("e")
	if e_at >= 0:
		exp10 = s.substr(e_at + 1).to_int()
		s = s.left(e_at)
	var dot := s.find(".")
	var int_part := s if dot < 0 else s.left(dot)
	var frac_part := "" if dot < 0 else s.substr(dot + 1)
	var digits := int_part + frac_part
	# Posição do ponto: valor = 0.digits × 10^n.
	var n := int_part.length() + exp10
	var lead := 0
	while lead < digits.length() - 1 and digits[lead] == "0":
		lead += 1
	digits = digits.substr(lead)
	n -= lead
	var trail := digits.length()
	while trail > 1 and digits[trail - 1] == "0":
		trail -= 1
	digits = digits.left(trail)
	var k := digits.length()
	var r: String
	if k <= n and n <= 21:
		r = digits + "0".repeat(n - k)
	elif 0 < n and n <= 21:
		r = digits.left(n) + "." + digits.substr(n)
	elif -6 < n and n <= 0:
		r = "0." + "0".repeat(-n) + digits
	else:
		var e := n - 1
		var mant := digits if k == 1 else digits.left(1) + "." + digits.substr(1)
		r = mant + ("e+" if e >= 0 else "e-") + str(absi(e))
	return ("-" + r) if negative else r


## Texto entre aspas com o escape mínimo do RFC 8785 §3.2.2.2.
static func quote(s: String) -> String:
	var out := PackedStringArray(["\""])
	var start := 0
	for i in s.length():
		var c := s.unicode_at(i)
		var esc := ""
		if c == 0x22:
			esc = "\\\""
		elif c == 0x5C:
			esc = "\\\\"
		elif c < 0x20:
			match c:
				0x08: esc = "\\b"
				0x09: esc = "\\t"
				0x0A: esc = "\\n"
				0x0C: esc = "\\f"
				0x0D: esc = "\\r"
				_: esc = "\\u%04x" % c
		if not esc.is_empty():
			out.append(s.substr(start, i - start))
			out.append(esc)
			start = i + 1
	out.append(s.substr(start))
	out.append("\"")
	return "".join(out)


static func _utf16_units(s: String) -> PackedInt32Array:
	var units := PackedInt32Array()
	for i in s.length():
		var c := s.unicode_at(i)
		if c > 0xFFFF:
			c -= 0x10000
			units.append(0xD800 + (c >> 10))
			units.append(0xDC00 + (c & 0x3FF))
		else:
			units.append(c)
	return units


static func _units_less(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	var n := mini(a.size(), b.size())
	for i in n:
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()
