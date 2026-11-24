class_name VNCaseJson
extends RefCounted
## Leitor de JSON dos vetores de conformidade que preserva inteiros (spec 08 §2.1).
##
## O [JSON] do Godot devolve todo número como [code]float[/code], e os vetores dependem da diferença
## entre [code]2[/code] e [code]2.0[/code]: um literal sem ponto nem expoente é [code]integer[/code]
## (Data Model §6.1.1). Este leitor devolve [code]int[/code] para números sem fração nem expoente que
## cabem em int64 e [code]float[/code] para os demais. Objetos viram [Dictionary] na ordem do texto.
##
## Uso: [code]var r := VNCaseJson.parse(texto)[/code]; [code]r.ok[/code], [code]r.value[/code] e,
## em erro, [code]r.error[/code] com a posição.

var ok: bool = true
var value: Variant = null
var error: String = ""

var _s: String = ""
var _i: int = 0


static func parse(text: String) -> VNCaseJson:
	var p := VNCaseJson.new()
	p._s = text
	p._i = 0
	p._ws()
	p.value = p._value()
	if p.ok:
		p._ws()
		if p._i < p._s.length():
			p._fail("texto depois do valor")
	if not p.ok:
		p.value = null
	return p


func _fail(msg: String) -> void:
	if ok:
		ok = false
		error = "%s (posição %d)" % [msg, _i]


func _ws() -> void:
	while _i < _s.length():
		var c := _s.unicode_at(_i)
		if c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D:
			_i += 1
		else:
			return


func _value() -> Variant:
	if not ok:
		return null
	if _i >= _s.length():
		_fail("fim inesperado")
		return null
	var c := _s[_i]
	match c:
		"{":
			return _object()
		"[":
			return _array()
		"\"":
			return _string()
		"t":
			return _literal("true", true)
		"f":
			return _literal("false", false)
		"n":
			return _literal("null", null)
	if c == "-" or (c >= "0" and c <= "9"):
		return _number()
	_fail("caractere inesperado '%s'" % c)
	return null


func _literal(word: String, v: Variant) -> Variant:
	if _s.substr(_i, word.length()) == word:
		_i += word.length()
		return v
	_fail("literal inválido")
	return null


func _object() -> Variant:
	var out := {}
	_i += 1
	_ws()
	if _i < _s.length() and _s[_i] == "}":
		_i += 1
		return out
	while ok:
		_ws()
		if _i >= _s.length() or _s[_i] != "\"":
			_fail("chave esperada")
			return null
		var key: String = _string()
		_ws()
		if _i >= _s.length() or _s[_i] != ":":
			_fail("':' esperado")
			return null
		_i += 1
		_ws()
		out[key] = _value()
		_ws()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
			continue
		if _i < _s.length() and _s[_i] == "}":
			_i += 1
			return out
		_fail("',' ou '}' esperado")
	return null


func _array() -> Variant:
	var out := []
	_i += 1
	_ws()
	if _i < _s.length() and _s[_i] == "]":
		_i += 1
		return out
	while ok:
		_ws()
		out.append(_value())
		_ws()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
			continue
		if _i < _s.length() and _s[_i] == "]":
			_i += 1
			return out
		_fail("',' ou ']' esperado")
	return null


func _string() -> String:
	_i += 1
	var parts := PackedStringArray()
	var start := _i
	while _i < _s.length():
		var c := _s[_i]
		if c == "\"":
			parts.append(_s.substr(start, _i - start))
			_i += 1
			return "".join(parts)
		if c == "\\":
			parts.append(_s.substr(start, _i - start))
			_i += 1
			if _i >= _s.length():
				break
			var e := _s[_i]
			_i += 1
			match e:
				"\"": parts.append("\"")
				"\\": parts.append("\\")
				"/": parts.append("/")
				"b": parts.append(char(0x08))
				"f": parts.append(char(0x0C))
				"n": parts.append("\n")
				"r": parts.append("\r")
				"t": parts.append("\t")
				"u":
					var cp := _hex4()
					if cp >= 0xD800 and cp <= 0xDBFF and _s.substr(_i, 2) == "\\u":
						_i += 2
						var lo := _hex4()
						if lo >= 0xDC00 and lo <= 0xDFFF:
							cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
						else:
							_fail("par substituto inválido")
					if cp < 0:
						return ""
					parts.append(char(cp))
				_:
					_fail("escape inválido \\%s" % e)
					return ""
			start = _i
			continue
		if c.unicode_at(0) < 0x20:
			_fail("caractere de controle em string")
			return ""
		_i += 1
	_fail("string sem fim")
	return ""


func _hex4() -> int:
	var h := _s.substr(_i, 4)
	if h.length() != 4 or not h.is_valid_hex_number():
		_fail("\\u inválido")
		return -1
	_i += 4
	return h.hex_to_int()


func _number() -> Variant:
	var start := _i
	var is_int := true
	if _s[_i] == "-":
		_i += 1
	var digits := _i
	while _i < _s.length() and _s[_i] >= "0" and _s[_i] <= "9":
		_i += 1
	if _i == digits:
		_fail("número inválido")
		return null
	if _i < _s.length() and _s[_i] == ".":
		is_int = false
		_i += 1
		var frac := _i
		while _i < _s.length() and _s[_i] >= "0" and _s[_i] <= "9":
			_i += 1
		if _i == frac:
			_fail("número inválido")
			return null
	if _i < _s.length() and (_s[_i] == "e" or _s[_i] == "E"):
		is_int = false
		_i += 1
		if _i < _s.length() and (_s[_i] == "+" or _s[_i] == "-"):
			_i += 1
		var exp := _i
		while _i < _s.length() and _s[_i] >= "0" and _s[_i] <= "9":
			_i += 1
		if _i == exp:
			_fail("número inválido")
			return null
	var text := _s.substr(start, _i - start)
	if is_int:
		# int64 vai até 9223372036854775807 (19 dígitos); acima disso o número vira float.
		var magnitude := text.trim_prefix("-").lstrip("0")
		if magnitude.length() < 19 or (magnitude.length() == 19 and magnitude <= "9223372036854775807"):
			return text.to_int()
	# String.to_float erra o último bit de números de 17+ algarismos (ex.: 333333333.33333329).
	return VNCanonicalJson.parse_number(text)
