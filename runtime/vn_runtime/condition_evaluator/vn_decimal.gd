class_name VNDecimal
extends RefCounted
## Representação decimal exata e mais curta de um [code]float[/code] (RT §12.1).
##
## O [code]String.num_scientific[/code] do Godot 4.7 nem sempre devolve a menor
## representação que volta ao mesmo valor (às vezes erra o último dígito ou usa
## 17 dígitos), e o [code]Number.prototype.toString[/code] do JavaScript e o
## [code]repr[/code] do Python exigem a menor e, entre as menores, a mais
## próxima. Esta classe calcula com aritmética inteira exata: todo
## [code]float[/code] é [code]m × 2^e[/code], um decimal finito.
##
## Um decimal positivo é [code]{ digits, point }[/code] com
## [code]valor = 0.<digits> × 10^point[/code], sem zeros à esquerda nem à direita
## em [code]digits[/code] ([code]123.45 → { "12345", 3 }[/code]).

const _BASE := 1000000000          # limbs de 9 dígitos decimais
const _POW2_CHUNK := 1 << 30
const _POW5_CHUNK := 1220703125    # 5^13 (< 2^31: limb × fator cabe no int64)


## Menor representação decimal de [param x] (finito, > 0) que volta a
## [param x] no arredondamento IEEE 754; entre duas igualmente curtas, a mais
## próxima de [param x] (empate: último dígito par).
static func shortest(x: float) -> Dictionary:
	var me := _decompose(x)
	var m: int = me[0]
	var e: int = me[1]
	var exact := _exact(m, e)
	var lo: Dictionary
	if m == (1 << 52) and e > -1074:
		lo = _exact(4 * m - 1, e - 2)   # na potência de 2 o vizinho de baixo fica mais perto
	else:
		lo = _exact(2 * m - 1, e - 1)
	var hi := _exact(2 * m + 1, e - 1)
	var inclusive := m % 2 == 0           # empate no arredondamento vai para o par
	var xd: String = exact.digits
	for p in range(1, 18):
		if xd.length() <= p:
			return exact
		var t := xd.substr(0, p)
		var down := _norm(t, exact.point)
		var inc := increment(t)
		var up := _norm(inc, exact.point + (1 if inc.length() > p else 0))
		var down_ok := _inside(down, lo, hi, inclusive)
		var up_ok := _inside(up, lo, hi, inclusive)
		if down_ok and up_ok:
			var tail := xd.substr(p)
			var c := tail.unicode_at(0)
			var go_up: bool
			if c != 0x35:
				go_up = c > 0x35
			elif tail.length() > 1:
				go_up = true                   # "5" seguido de algo diferente de zero (sem zeros à direita)
			else:
				go_up = t.unicode_at(p - 1) % 2 == 1
			return up if go_up else down
		if down_ok:
			return down
		if up_ok:
			return up
	return exact


## Decimal exato de [param x] (finito, > 0).
static func exact(x: float) -> Dictionary:
	var me := _decompose(x)
	return _exact(me[0], me[1])


## Compara dois decimais positivos: -1, 0 ou 1.
static func compare(a: Dictionary, b: Dictionary) -> int:
	if a.point != b.point:
		return -1 if a.point < b.point else 1
	var da: String = a.digits
	var db: String = b.digits
	var n := maxi(da.length(), db.length())
	da = da.rpad(n, "0")
	db = db.rpad(n, "0")
	if da == db:
		return 0
	return -1 if da < db else 1


# --- Internos ------------------------------------------------------------------

## [m, e] com x = m × 2^e (x finito e positivo).
static func _decompose(x: float) -> Array:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, absf(x))
	var bits := bytes.decode_s64(0)
	var biased := (bits >> 52) & 0x7FF
	var frac := bits & ((1 << 52) - 1)
	if biased == 0:
		return [frac, -1074]
	return [frac | (1 << 52), biased - 1075]


## Decimal exato de m × 2^e (m > 0, até 2^62).
static func _exact(m: int, e: int) -> Dictionary:
	var n := _from_int(m)
	var shift := 0
	if e >= 0:
		var k := e
		while k >= 30:
			_mul_small(n, _POW2_CHUNK)
			k -= 30
		if k > 0:
			_mul_small(n, 1 << k)
	else:
		# m × 2^e = m × 5^(−e) / 10^(−e)
		var k := -e
		shift = k
		while k >= 13:
			_mul_small(n, _POW5_CHUNK)
			k -= 13
		var f := 1
		for i in k:
			f *= 5
		if f > 1:
			_mul_small(n, f)
	var s := _limbs_to_string(n)
	return _norm(s, s.length() - shift)


static func _norm(digits: String, point: int) -> Dictionary:
	var d := digits.lstrip("0")
	point -= digits.length() - d.length()
	d = d.rstrip("0")
	return {"digits": d, "point": point}


static func _inside(c: Dictionary, lo: Dictionary, hi: Dictionary, inclusive: bool) -> bool:
	var a := compare(lo, c)
	var b := compare(c, hi)
	if inclusive:
		return a <= 0 and b <= 0
	return a < 0 and b < 0


static func _from_int(v: int) -> PackedInt64Array:
	var n := PackedInt64Array()
	while v > 0:
		n.append(v % _BASE)
		v /= _BASE
	return n


static func _mul_small(n: PackedInt64Array, f: int) -> void:
	var carry := 0
	for i in n.size():
		var p := n[i] * f + carry
		n[i] = p % _BASE
		carry = p / _BASE
	while carry > 0:
		n.append(carry % _BASE)
		carry /= _BASE


static func _limbs_to_string(n: PackedInt64Array) -> String:
	if n.is_empty():
		return "0"
	var parts := PackedStringArray([str(n[n.size() - 1])])
	for i in range(n.size() - 2, -1, -1):
		parts.append(str(n[i]).pad_zeros(9))
	return "".join(parts)


## Soma 1 a um inteiro decimal sem sinal escrito em dígitos ("199" → "200").
static func increment(s: String) -> String:
	var chars := s.to_ascii_buffer()
	var i := chars.size() - 1
	while i >= 0:
		if chars[i] == 0x39:
			chars[i] = 0x30
			i -= 1
		else:
			chars[i] += 1
			return chars.get_string_from_ascii()
	return "1" + chars.get_string_from_ascii()
