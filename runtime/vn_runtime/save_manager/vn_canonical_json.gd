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


# --- Leitura exata de números ---------------------------------------------------

## O [code]float[/code] mais próximo de um número JSON em texto (arredondamento
## correto, empate para o par). O [code]String.to_float[/code] e o [JSON] do
## Godot podem errar o último bit em números de 17+ algarismos e em decimais
## longos; o executor de conformidade lê os vetores por aqui (spec 08 §2.1).
static func parse_number(text: String) -> float:
	var t := text.strip_edges()
	var negative := t.begins_with("-")
	if negative or t.begins_with("+"):
		t = t.substr(1)
	var mant := t
	var exp10 := 0
	var e_at := t.findn("e")
	if e_at >= 0:
		mant = t.left(e_at)
		exp10 = t.substr(e_at + 1).to_int()
	var dot := mant.find(".")
	if dot >= 0:
		exp10 -= mant.length() - dot - 1
		mant = mant.left(dot) + mant.substr(dot + 1)
	mant = mant.lstrip("0")
	if mant.is_empty():
		return -0.0 if negative else 0.0
	# Valor exato = mant × 10^exp10. Parte de uma aproximação e corrige pelos pontos médios.
	var x := _approximate(mant, exp10)
	var digits := _big_from_decimal(mant)
	for _i in 64:
		if is_inf(x):
			break
		var up := _next_up(x)
		var c_up := _compare_with_midpoint(digits, exp10, x, up)
		if c_up > 0 or (c_up == 0 and _mantissa_odd(x)):
			x = up
			continue
		if x == 0.0:
			break
		var down := _next_down(x)
		var c_down := _compare_with_midpoint(digits, exp10, down, x)
		if c_down < 0 or (c_down == 0 and _mantissa_odd(x)):
			x = down
			continue
		break
	return -x if negative else x


## Aproximação a poucos ulps de mant × 10^exp10 (inclusive subnormais).
static func _approximate(mant: String, exp10: int) -> float:
	var e := exp10
	var head := mant
	if head.length() > 17:
		e += head.length() - 17
		head = head.left(17)
	var x := head.to_float()
	while e > 0 and not is_inf(x):
		var step := mini(e, 22)
		x *= pow(10.0, step)
		e -= step
	while e < 0 and x != 0.0:
		var step := mini(-e, 22)
		x /= pow(10.0, step)
		e += step
	return x


## Compara mant × 10^exp10 com (a + b) / 2 (a < b, doubles vizinhos finitos e ≥ 0): −1, 0 ou 1.
static func _compare_with_midpoint(digits: PackedInt64Array, exp10: int, a: float, b: float) -> int:
	if is_inf(b):
		return -1
	var fa := _decompose(a)
	var fb := _decompose(b)
	# a = ma × 2^ea, b = mb × 2^eb → (a + b)/2 = (ma × 2^(ea−e) + mb × 2^(eb−e)) × 2^(e−1).
	var e := mini(fa[1], fb[1])
	var mid := _big_add(_big_shift(_big_from_int(fa[0]), fa[1] - e), _big_shift(_big_from_int(fb[0]), fb[1] - e))
	var exp2 := e - 1
	var left := digits.duplicate()
	var right := mid
	# Lado esquerdo: digits × 10^exp10 = digits × 5^exp10 × 2^exp10.
	var p2_left := exp10
	if exp10 >= 0:
		for _i in exp10:
			left = _big_mul_small(left, 5)
	else:
		for _i in -exp10:
			right = _big_mul_small(right, 5)
	# Junta as potências de 2 no lado que tiver a menor.
	var shift := exp2 - p2_left
	if shift >= 0:
		right = _big_shift(right, shift)
	else:
		left = _big_shift(left, -shift)
	return _big_cmp(left, right)


## [mantissa inteira, expoente binário] de um double finito ≥ 0.
static func _decompose(x: float) -> Array:
	var bits := _bits(x)
	var exp_bits := (bits >> 52) & 0x7FF
	var frac := bits & 0xFFFFFFFFFFFFF
	if exp_bits == 0:
		return [frac, -1074]
	return [frac | (1 << 52), exp_bits - 1075]


static func _bits(x: float) -> int:
	return PackedFloat64Array([x]).to_byte_array().decode_s64(0)


static func _from_bits(bits: int) -> float:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_s64(0, bits)
	return b.decode_double(0)


static func _next_up(x: float) -> float:
	return _from_bits(_bits(x) + 1)


static func _next_down(x: float) -> float:
	return _from_bits(_bits(x) - 1)


static func _mantissa_odd(x: float) -> bool:
	return (_bits(x) & 1) == 1


# Inteiros grandes não negativos: limbs de 24 bits, do menos significativo.
const _LIMB := 1 << 24

static func _big_from_int(v: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	while v > 0:
		out.append(v & (_LIMB - 1))
		v >>= 24
	return out


static func _big_from_decimal(digits: String) -> PackedInt64Array:
	var out := PackedInt64Array()
	for ch in digits:
		out = _big_mul_small(out, 10, int(ch))
	return out


static func _big_mul_small(a: PackedInt64Array, k: int, add: int = 0) -> PackedInt64Array:
	var out := PackedInt64Array()
	var carry := add
	for limb in a:
		var v := limb * k + carry
		out.append(v & (_LIMB - 1))
		carry = v >> 24
	while carry > 0:
		out.append(carry & (_LIMB - 1))
		carry >>= 24
	return out


static func _big_shift(a: PackedInt64Array, n: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	if a.is_empty():
		return out
	for _i in n / 24:
		out.append(0)
	var r := n % 24
	var carry := 0
	for limb in a:
		var v := (limb << r) | carry
		out.append(v & (_LIMB - 1))
		carry = v >> 24
	if carry > 0:
		out.append(carry)
	return out


static func _big_add(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	var carry := 0
	for i in maxi(a.size(), b.size()):
		var v := (a[i] if i < a.size() else 0) + (b[i] if i < b.size() else 0) + carry
		out.append(v & (_LIMB - 1))
		carry = v >> 24
	if carry > 0:
		out.append(carry)
	return out


static func _big_cmp(a: PackedInt64Array, b: PackedInt64Array) -> int:
	var na := a.size()
	while na > 0 and a[na - 1] == 0:
		na -= 1
	var nb := b.size()
	while nb > 0 and b[nb - 1] == 0:
		nb -= 1
	if na != nb:
		return 1 if na > nb else -1
	for i in range(na - 1, -1, -1):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0


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
