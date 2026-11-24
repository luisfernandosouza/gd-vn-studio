class_name VNCanonicalJSON
extends RefCounted
## JSON canônico (JCS, RFC 8785) e hashes no formato das specs (Build System §5.1).
##
## O [code]JSON.stringify[/code] do Godot não serve: formata números de outro
## jeito e não ordena as chaves. Este serializador segue a referência
## [code]tools/conformance.py → jcs[/code] e é conferido pelos vetores
## [code]conformance/canonical.json[/code]. É o mesmo usado no
## [code]content_hash[/code] (RT §2), na assinatura de saves e perfil
## (BS §8.3, [method hmac_integrity]) e no [code]build.json[/code].
##
## Regras: UTF-8, chaves em ordem de unidades UTF-16, sem espaços, strings com
## escape mínimo e números no formato do [code]Number.prototype.toString[/code]
## do ECMAScript (o mais curto que volta ao mesmo double; [code]-0[/code] vira
## [code]0[/code]). O JSON do Godot lê todo número como [code]float[/code]; um
## [code]int[/code] do GDScript também é aceito.

## Maior inteiro exato num double (2^53 − 1).
const MAX_SAFE_INTEGER := 9007199254740991


## Texto canônico de [param value]. Valores fora do JSON (NaN, infinito,
## objetos do Godot) viram [code]null[/code] e registram um aviso.
static func stringify(value: Variant) -> String:
	var parts := PackedStringArray()
	_write(value, parts)
	return "".join(parts)


## SHA-256 do texto canônico no formato SRI ([code]sha256-<base64>[/code],
## [code]common.schema.json → Hash[/code]).
static func hash_of(value: Variant) -> String:
	return sri(stringify(value).to_utf8_buffer())


## [code]content_hash[/code] do bundle (RT §2): SHA-256 do [code]bundle.json[/code]
## canônico sem o próprio campo [code]content_hash[/code].
static func content_hash(bundle: Dictionary) -> String:
	var copy := bundle.duplicate(false)
	copy.erase("content_hash")
	return hash_of(copy)


## Assinatura de save e perfil (BS §8.3): [code]hmac-sha256-<base64>[/code]
## sobre o JSON canônico do documento sem o campo [code]integrity[/code].
static func hmac_integrity(doc: Dictionary, key: PackedByteArray) -> String:
	var copy := doc.duplicate(false)
	copy.erase("integrity")
	var ctx := HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, key)
	ctx.update(stringify(copy).to_utf8_buffer())
	return "hmac-sha256-" + Marshalls.raw_to_base64(ctx.finish())


## SHA-256 cru dos bytes.
static func sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


## SHA-256 dos bytes no formato SRI.
static func sri(data: PackedByteArray) -> String:
	return "sha256-" + Marshalls.raw_to_base64(sha256(data))


## Os 32 bytes de um hash escrito como SRI ([code]sha256-…[/code]), hex ou
## base64 puro, ou já em bytes (BS §5.1, "Representação de hashes"). Vazio se
## não reconhece.
static func hash_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value if value.size() == 32 else PackedByteArray()
	if not (value is String or value is StringName):
		return PackedByteArray()
	var s := String(value).strip_edges()
	if s.begins_with("sha256-"):
		s = s.substr(7)
	elif s.length() == 64 and s.is_valid_hex_number(false):
		return s.hex_decode()
	var raw := Marshalls.base64_to_raw(s)
	return raw if raw.size() == 32 else PackedByteArray()


# --- Serialização -------------------------------------------------------------

static func _write(v: Variant, out: PackedStringArray) -> void:
	match typeof(v):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if v else "false")
		TYPE_INT:
			if absi(v) <= MAX_SAFE_INTEGER:
				out.append(str(v))
			else:
				out.append(number_to_string(float(v)))
		TYPE_FLOAT:
			out.append(number_to_string(v))
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			out.append(quote(String(v)))
		TYPE_DICTIONARY:
			var keys: Array = []
			for k in v:
				keys.append([_utf16_units(String(k)), k])
			keys.sort_custom(_utf16_less)
			out.append("{")
			var first := true
			for pair in keys:
				if not first:
					out.append(",")
				first = false
				out.append(quote(String(pair[1])))
				out.append(":")
				_write(v[pair[1]], out)
			out.append("}")
		_:
			if v is Array or (typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY and typeof(v) != TYPE_PACKED_BYTE_ARRAY):
				out.append("[")
				var first := true
				for item in v:
					if not first:
						out.append(",")
					first = false
					_write(item, out)
				out.append("]")
			else:
				push_warning("VNCanonicalJSON: valor fora do JSON (%s) vira null." % type_string(typeof(v)))
				out.append("null")


## String JSON com escape mínimo (RFC 8785 §3.2.2.2): só [code]"[/code],
## [code]\\[/code] e os controles abaixo de U+0020; o resto vai literal.
static func quote(s: String) -> String:
	var needs := false
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 0x20 or c == 0x22 or c == 0x5C:
			needs = true
			break
	if not needs:
		return "\"" + s + "\""
	var parts := PackedStringArray(["\""])
	for i in s.length():
		var c := s.unicode_at(i)
		match c:
			0x22: parts.append("\\\"")
			0x5C: parts.append("\\\\")
			0x08: parts.append("\\b")
			0x09: parts.append("\\t")
			0x0A: parts.append("\\n")
			0x0C: parts.append("\\f")
			0x0D: parts.append("\\r")
			_:
				if c < 0x20:
					parts.append("\\u%04x" % c)
				else:
					parts.append(String.chr(c))
	parts.append("\"")
	return "".join(parts)


static func _utf16_units(s: String) -> PackedInt32Array:
	var units := PackedInt32Array()
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x10000:
			c -= 0x10000
			units.append(0xD800 + (c >> 10))
			units.append(0xDC00 + (c & 0x3FF))
		else:
			units.append(c)
	return units


static func _utf16_less(a: Array, b: Array) -> bool:
	var ua: PackedInt32Array = a[0]
	var ub: PackedInt32Array = b[0]
	var n := mini(ua.size(), ub.size())
	for i in n:
		if ua[i] != ub[i]:
			return ua[i] < ub[i]
	return ua.size() < ub.size()


# --- Números (ECMAScript Number::toString) -------------------------------------

## Número no formato do JCS: os dígitos mais curtos que voltam ao mesmo double
## (algoritmo de Steele & White / Burger & Dybvig, com aritmética exata),
## escritos como o [code]Number.prototype.toString[/code] do ECMAScript.
static func number_to_string(x: float) -> String:
	if is_nan(x) or is_inf(x):
		push_warning("VNCanonicalJSON: número não finito vira null.")
		return "null"
	if x == 0.0:
		return "0"
	var neg := x < 0.0
	var ax := absf(x)
	var text: String
	if ax <= MAX_SAFE_INTEGER and ax == floorf(ax):
		text = str(int(ax))
	else:
		var sd := _shortest_digits(ax)
		text = _format_es(sd[0], sd[1])
	return ("-" + text) if neg else text


## [digitos: String, n: int] com x = 0.d1d2… × 10^n.
static func _shortest_digits(v: float) -> Array:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, v)
	var bits := bytes.decode_u64(0)
	var be := (bits >> 52) & 0x7FF
	var mant := bits & 0xFFFFFFFFFFFFF
	var f: int
	var e: int
	if be == 0:
		f = mant
		e = -1074
	else:
		f = mant | (1 << 52)
		e = be - 1075
	var even := (f & 1) == 0
	var r: Array
	var s: Array
	var mp: Array
	var mm: Array
	var boundary := be > 1 and mant == 0   # o vizinho de baixo está mais perto
	if e >= 0:
		var be2 := _big_pow2(e)
		if not boundary:
			r = _big_shl(_big(f), e + 1)
			s = _big(2)
			mp = be2
			mm = be2
		else:
			r = _big_shl(_big(f), e + 2)
			s = _big(4)
			mp = _big_shl(be2, 1)
			mm = be2
	else:
		if not boundary:
			r = _big_shl(_big(f), 1)
			s = _big_pow2(1 - e)
			mp = _big(1)
			mm = _big(1)
		else:
			r = _big_shl(_big(f), 2)
			s = _big_pow2(2 - e)
			mp = _big(2)
			mm = _big(1)
	# Estimativa de n = ceil(log10(v)); os laços abaixo corrigem para mais ou para menos.
	var k := int(ceil(log(v) / log(10.0) - 1e-10))
	if k >= 0:
		s = _big_mul(s, _big_pow10(k))
	else:
		var p := _big_pow10(-k)
		r = _big_mul(r, p)
		mp = _big_mul(mp, p)
		mm = _big_mul(mm, p)
	while true:
		var c := _big_cmp(_big_add(r, mp), s)
		if c > 0 or (even and c == 0):
			s = _big_mul_small(s, 10)
			k += 1
		else:
			break
	while true:
		var c := _big_cmp(_big_mul_small(_big_add(r, mp), 10), s)
		if c < 0 or (not even and c == 0):
			r = _big_mul_small(r, 10)
			mp = _big_mul_small(mp, 10)
			mm = _big_mul_small(mm, 10)
			k -= 1
		else:
			break
	var digits := PackedStringArray()
	while true:
		r = _big_mul_small(r, 10)
		mp = _big_mul_small(mp, 10)
		mm = _big_mul_small(mm, 10)
		var d := 0
		while _big_cmp(r, s) >= 0:
			r = _big_sub(r, s)
			d += 1
		var c_low := _big_cmp(r, mm)
		var tc1 := c_low < 0 or (even and c_low == 0)
		var c_high := _big_cmp(_big_add(r, mp), s)
		var tc2 := c_high > 0 or (even and c_high == 0)
		if not tc1 and not tc2:
			digits.append(str(d))
			continue
		if tc1 and tc2:
			var c2 := _big_cmp(_big_shl(r, 1), s)
			if c2 > 0 or (c2 == 0 and d % 2 == 1):
				d += 1
		elif tc2:
			d += 1
		digits.append(str(d))
		break
	return ["".join(digits), k]


static func _format_es(digits: String, n: int) -> String:
	var k := digits.length()
	if k <= n and n <= 21:
		return digits + "0".repeat(n - k)
	if 0 < n and n <= 21:
		return digits.substr(0, n) + "." + digits.substr(n)
	if -6 < n and n <= 0:
		return "0." + "0".repeat(-n) + digits
	var exp := n - 1
	var sign := "+" if exp >= 0 else "-"
	var mant := digits if k == 1 else digits.substr(0, 1) + "." + digits.substr(1)
	return mant + "e" + sign + str(absi(exp))


# --- Inteiros grandes não negativos: limbs de 28 bits, do menos significativo --

const _LIMB_BITS := 28
const _LIMB_MASK := (1 << 28) - 1


static func _big(n: int) -> Array:
	var out: Array = []
	while n > 0:
		out.append(n & _LIMB_MASK)
		n >>= _LIMB_BITS
	return out


static func _big_trim(a: Array) -> Array:
	while not a.is_empty() and a[-1] == 0:
		a.pop_back()
	return a


static func _big_cmp(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return 1 if a.size() > b.size() else -1
	for i in range(a.size() - 1, -1, -1):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0


static func _big_add(a: Array, b: Array) -> Array:
	var out: Array = []
	var carry := 0
	for i in maxi(a.size(), b.size()):
		var t: int = carry + (a[i] if i < a.size() else 0) + (b[i] if i < b.size() else 0)
		out.append(t & _LIMB_MASK)
		carry = t >> _LIMB_BITS
	if carry > 0:
		out.append(carry)
	return out


## a − b, com a ≥ b.
static func _big_sub(a: Array, b: Array) -> Array:
	var out: Array = []
	var borrow := 0
	for i in a.size():
		var t: int = a[i] - borrow - (b[i] if i < b.size() else 0)
		if t < 0:
			t += 1 << _LIMB_BITS
			borrow = 1
		else:
			borrow = 0
		out.append(t)
	return _big_trim(out)


static func _big_mul_small(a: Array, m: int) -> Array:
	var out: Array = []
	var carry := 0
	for limb in a:
		var t: int = limb * m + carry
		out.append(t & _LIMB_MASK)
		carry = t >> _LIMB_BITS
	while carry > 0:
		out.append(carry & _LIMB_MASK)
		carry >>= _LIMB_BITS
	return out


static func _big_mul(a: Array, b: Array) -> Array:
	if a.is_empty() or b.is_empty():
		return []
	var out: Array = []
	out.resize(a.size() + b.size())
	out.fill(0)
	for i in a.size():
		var carry := 0
		var ai: int = a[i]
		for j in b.size():
			var t: int = out[i + j] + ai * b[j] + carry
			out[i + j] = t & _LIMB_MASK
			carry = t >> _LIMB_BITS
		var p := i + b.size()
		while carry > 0:
			var t2: int = out[p] + carry
			out[p] = t2 & _LIMB_MASK
			carry = t2 >> _LIMB_BITS
			p += 1
	return _big_trim(out)


static func _big_shl(a: Array, bits: int) -> Array:
	if a.is_empty():
		return []
	var out: Array = []
	for i in bits / _LIMB_BITS:
		out.append(0)
	var sh := bits % _LIMB_BITS
	var carry := 0
	for limb in a:
		var t: int = (limb << sh) | carry
		out.append(t & _LIMB_MASK)
		carry = t >> _LIMB_BITS
	if carry > 0:
		out.append(carry)
	return out


static func _big_pow2(n: int) -> Array:
	return _big_shl(_big(1), n)


static func _big_pow10(n: int) -> Array:
	var out := _big(1)
	while n >= 9:
		out = _big_mul_small(out, 1000000000)
		n -= 9
	for i in n:
		out = _big_mul_small(out, 10)
	return out
