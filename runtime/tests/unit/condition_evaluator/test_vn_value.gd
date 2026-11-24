extends RefCounted
## Testes das bordas de VNValue (tarefa M1-02): DM §5.1, §6.1.1; RT §6.2, §12.1;
## CV §3. Os valores esperados são os de docs/specs/tools/conformance.py.

const MAX := VNValue.INT_MAX


static func I(i: int) -> VNEvalResult:
	return VNEvalResult.of(i, VNValue.INTEGER)


static func N(x: float) -> VNEvalResult:
	return VNEvalResult.of(x, VNValue.NUMBER)


static func S(s: String) -> VNEvalResult:
	return VNEvalResult.of(s, VNValue.STRING)


static func E(s: String) -> VNEvalResult:
	return VNEvalResult.of(s, VNValue.ENUM)


static func B(b: bool) -> VNEvalResult:
	return VNEvalResult.of(b, VNValue.BOOLEAN)


## Confere um resultado: [param want] é um código de erro (StringName) ou
## [code][tipo, valor][/code]. Devolve "" ou a descrição da diferença.
static func _is(label: String, got: VNEvalResult, want: Variant) -> String:
	if want is StringName:
		if got.ok or got.error != want:
			return "%s: esperava erro %s, veio %s" % [label, want, _show(got)]
		return ""
	if not got.ok:
		return "%s: esperava %s, veio %s" % [label, want, _show(got)]
	if got.type != want[0] or typeof(got.value) != typeof(want[1]) or got.value != want[1]:
		return "%s: esperava %s, veio %s" % [label, want, _show(got)]
	return ""


static func _show(r: VNEvalResult) -> String:
	if not r.ok:
		return "erro %s (%s)" % [r.error, r.message]
	return "[%s, %s (%s)]" % [r.type, r.value, type_string(typeof(r.value))]


static func _all(errors: Array) -> String:
	return "; ".join(errors.filter(func(e): return not (e as String).is_empty()))


# --- Intervalo de inteiros e valores não finitos -------------------------------

func test_intervalo_de_inteiros() -> String:
	return _all([
		_is("limite +", VNValue.integer(MAX), [&"integer", MAX]),
		_is("limite −", VNValue.integer(-MAX), [&"integer", -MAX]),
		_is("2^53", VNValue.integer(MAX + 1), VNErrors.OUT_OF_RANGE),
		_is("−2^53", VNValue.integer(-MAX - 1), VNErrors.OUT_OF_RANGE),
		_is("inf", VNValue.number(INF), VNErrors.OUT_OF_RANGE),
		_is("−inf", VNValue.number(-INF), VNErrors.OUT_OF_RANGE),
		_is("nan", VNValue.number(NAN), VNErrors.OUT_OF_RANGE),
		_is("1e308", VNValue.number(1e308), [&"number", 1e308]),
	])


func test_add_sub_mul_nas_bordas() -> String:
	return _all([
		_is("add_int", VNValue.arith(&"add", I(2), I(3)), [&"integer", 5]),
		_is("add_mixed", VNValue.arith(&"add", I(2), N(0.5)), [&"number", 2.5]),
		_is("add de number inteiro", VNValue.arith(&"add", I(2), N(2.0)), [&"number", 4.0]),
		_is("int_overflow", VNValue.arith(&"add", I(MAX), I(1)), VNErrors.OUT_OF_RANGE),
		_is("int_underflow", VNValue.arith(&"sub", I(-MAX), I(1)), VNErrors.OUT_OF_RANGE),
		_is("int_limit_ok", VNValue.arith(&"sub", I(MAX), I(0)), [&"integer", MAX]),
		_is("add volta ao limite", VNValue.arith(&"add", I(MAX - 1), I(1)), [&"integer", MAX]),
		_is("mul no limite", VNValue.arith(&"mul", I(MAX), I(1)), [&"integer", MAX]),
		_is("mul −1", VNValue.arith(&"mul", I(MAX), I(-1)), [&"integer", -MAX]),
		_is("mul passa do limite", VNValue.arith(&"mul", I(4503599627370496), I(2)), VNErrors.OUT_OF_RANGE),
		# 2^53 × 2^53 passaria do int64 (e daria a volta) sem a guarda.
		_is("mul passa do int64", VNValue.arith(&"mul", I(MAX), I(MAX)), VNErrors.OUT_OF_RANGE),
		_is("mul com sinais", VNValue.arith(&"mul", I(-3037000499), I(3037000499)), VNErrors.OUT_OF_RANGE),
		_is("mul_overflow_number", VNValue.arith(&"mul", N(1e308), N(10.0)), VNErrors.OUT_OF_RANGE),
		_is("sub number −inf", VNValue.arith(&"sub", N(-1.7976931348623157e308), N(1e308)), VNErrors.OUT_OF_RANGE),
		_is("integer com number grande vira number", VNValue.arith(&"add", I(MAX), N(1.0)), [&"number", 9007199254740992.0]),
		_is("add exige números", VNValue.arith(&"add", I(1), S("a")), VNErrors.TYPE_MISMATCH),
		_is("add booleano", VNValue.arith(&"add", B(true), I(1)), VNErrors.TYPE_MISMATCH),
	])


func test_divisao_e_mod() -> String:
	return _all([
		_is("div_always_number", VNValue.arith(&"div", I(7), I(2)), [&"number", 3.5]),
		_is("div_exact_number", VNValue.arith(&"div", I(6), I(3)), [&"number", 2.0]),
		_is("div_zero", VNValue.arith(&"div", I(1), I(0)), VNErrors.OUT_OF_RANGE),
		_is("div por 0.0", VNValue.arith(&"div", N(1.5), N(0.0)), VNErrors.OUT_OF_RANGE),
		_is("div por −0.0", VNValue.arith(&"div", I(1), N(-0.0)), VNErrors.OUT_OF_RANGE),
		_is("0/0", VNValue.arith(&"div", I(0), I(0)), VNErrors.OUT_OF_RANGE),
		_is("div que estoura", VNValue.arith(&"div", N(1e308), N(1e-10)), VNErrors.OUT_OF_RANGE),
		_is("div tipo antes do zero", VNValue.arith(&"div", S("a"), I(0)), VNErrors.TYPE_MISMATCH),
		_is("mod_neg_dividend", VNValue.arith(&"mod", I(-7), I(3)), [&"integer", 2]),
		_is("mod_neg_divisor", VNValue.arith(&"mod", I(7), I(-3)), [&"integer", -2]),
		_is("mod ambos negativos", VNValue.arith(&"mod", I(-7), I(-3)), [&"integer", -1]),
		_is("mod exato", VNValue.arith(&"mod", I(-6), I(3)), [&"integer", 0]),
		_is("mod_zero", VNValue.arith(&"mod", I(5), I(0)), VNErrors.OUT_OF_RANGE),
		_is("mod_number", VNValue.arith(&"mod", N(5.5), I(2)), VNErrors.TYPE_MISMATCH),
		# Tipo vem antes do zero, como na referência.
		_is("mod number por zero", VNValue.arith(&"mod", N(5.5), I(0)), VNErrors.TYPE_MISMATCH),
		_is("mod no limite", VNValue.arith(&"mod", I(-MAX), I(MAX)), [&"integer", 0]),
	])


func test_round_floor_ceil_abs() -> String:
	return _all([
		_is("round 2.5", VNValue.unary(&"round", N(2.5)), [&"integer", 3]),
		_is("round −2.5", VNValue.unary(&"round", N(-2.5)), [&"integer", -3]),
		_is("round 2.4999", VNValue.unary(&"round", N(2.4999)), [&"integer", 2]),
		_is("round −0.4", VNValue.unary(&"round", N(-0.4)), [&"integer", 0]),
		_is("round 0.5", VNValue.unary(&"round", N(0.5)), [&"integer", 1]),
		_is("round integer", VNValue.unary(&"round", I(-7)), [&"integer", -7]),
		_is("floor −1.5", VNValue.unary(&"floor", N(-1.5)), [&"integer", -2]),
		_is("ceil −1.5", VNValue.unary(&"ceil", N(-1.5)), [&"integer", -1]),
		_is("floor no limite", VNValue.unary(&"floor", N(float(MAX))), [&"integer", MAX]),
		_is("floor fora do limite", VNValue.unary(&"floor", N(9007199254740992.0)), VNErrors.OUT_OF_RANGE),
		_is("ceil −2^53", VNValue.unary(&"ceil", N(-9007199254740992.0)), VNErrors.OUT_OF_RANGE),
		_is("round 1e300", VNValue.unary(&"round", N(1e300)), VNErrors.OUT_OF_RANGE),
		_is("abs_int", VNValue.unary(&"abs", I(-3)), [&"integer", 3]),
		_is("abs −limite", VNValue.unary(&"abs", I(-MAX)), [&"integer", MAX]),
		_is("abs_number", VNValue.unary(&"abs", N(-2.5)), [&"number", 2.5]),
		_is("abs de texto", VNValue.unary(&"abs", S("x")), VNErrors.TYPE_MISMATCH),
	])


func test_min_max_clamp() -> String:
	var mixed: Array[VNEvalResult] = [I(3), N(1.5), I(2)]
	var ints: Array[VNEvalResult] = [I(1), I(7), I(3)]
	var tie: Array[VNEvalResult] = [I(2), N(2.0)]
	var bad: Array[VNEvalResult] = [I(1), S("2")]
	return _all([
		_is("min_mixed", VNValue.min_max(&"min", mixed), [&"number", 1.5]),
		_is("max_ints", VNValue.min_max(&"max", ints), [&"integer", 7]),
		_is("max misto vira number", VNValue.min_max(&"max", mixed), [&"number", 3.0]),
		_is("empate fica com o primeiro", VNValue.min_max(&"min", tie), [&"number", 2.0]),
		_is("min com texto", VNValue.min_max(&"min", bad), VNErrors.TYPE_MISMATCH),
		_is("clamp_high", VNValue.clamp_value(I(15), I(0), I(10)), [&"integer", 10]),
		_is("clamp_inverted", VNValue.clamp_value(I(5), I(10), I(0)), [&"integer", 10]),
		_is("clamp baixo", VNValue.clamp_value(I(-1), I(0), I(10)), [&"integer", 0]),
		_is("clamp misto", VNValue.clamp_value(I(5), N(0.5), I(10)), [&"number", 5.0]),
	])


# --- Literais e tipos declarados -------------------------------------------------

func test_literais_do_json() -> String:
	var parsed: Array = JSON.parse_string("[2, 2.5, -0.0, 9007199254740991, 9007199254740992, 1e+308, true, \"x\"]")
	return _all([
		_is("2", VNValue.from_literal(parsed[0]), [&"integer", 2]),
		_is("2.5", VNValue.from_literal(parsed[1]), [&"number", 2.5]),
		_is("-0.0", VNValue.from_literal(parsed[2]), [&"integer", 0]),
		_is("limite", VNValue.from_literal(parsed[3]), [&"integer", MAX]),
		_is("2^53 fica number", VNValue.from_literal(parsed[4]), [&"number", 9007199254740992.0]),
		_is("1e308 fica number", VNValue.from_literal(parsed[5]), [&"number", 1e308]),
		_is("true", VNValue.from_literal(parsed[6]), [&"boolean", true]),
		_is("texto", VNValue.from_literal(parsed[7]), [&"string", "x"]),
		_is("hint number", VNValue.from_literal(parsed[0], VNValue.NUMBER), [&"number", 2.0]),
		_is("hint enum", VNValue.from_literal("noite", VNValue.ENUM), [&"enum", "noite"]),
		_is("hint integer com fração", VNValue.from_literal(2.5, VNValue.INTEGER), VNErrors.TYPE_MISMATCH),
		_is("hint integer fora", VNValue.from_literal(1e20, VNValue.INTEGER), VNErrors.OUT_OF_RANGE),
		_is("hint boolean com número", VNValue.from_literal(1, VNValue.BOOLEAN), VNErrors.TYPE_MISMATCH),
		_is("int do GDScript fora", VNValue.from_literal(MAX + 1), VNErrors.OUT_OF_RANGE),
		_is("inf", VNValue.from_literal(INF), VNErrors.OUT_OF_RANGE),
		_is("lista", VNValue.from_literal([1]), VNErrors.TYPE_MISMATCH),
		_is("null", VNValue.from_literal(null), VNErrors.TYPE_MISMATCH),
	])


func test_valor_com_tipo_declarado() -> String:
	return _all([
		_is("integer de float do JSON", VNValue.typed(30.0, VNValue.INTEGER), [&"integer", 30]),
		_is("integer com fração", VNValue.typed(30.5, VNValue.INTEGER), VNErrors.TYPE_MISMATCH),
		_is("integer fora", VNValue.typed(1e16, VNValue.INTEGER), VNErrors.OUT_OF_RANGE),
		_is("number de int", VNValue.typed(2, VNValue.NUMBER), [&"number", 2.0]),
		_is("number inf", VNValue.typed(INF, VNValue.NUMBER), VNErrors.OUT_OF_RANGE),
		_is("boolean", VNValue.typed(false, VNValue.BOOLEAN), [&"boolean", false]),
		_is("boolean de 0", VNValue.typed(0, VNValue.BOOLEAN), VNErrors.TYPE_MISMATCH),
		_is("enum", VNValue.typed("day", VNValue.ENUM), [&"enum", "day"]),
		_is("string de número", VNValue.typed(1, VNValue.STRING), VNErrors.TYPE_MISMATCH),
		_is("tipo desconhecido", VNValue.typed(1, &"list"), VNErrors.TYPE_MISMATCH),
	])


func test_conversao_number_para_integer() -> String:
	return _all([
		_is("trunca positivo", VNValue.to_integer(2.9), [&"integer", 2]),
		_is("trunca negativo", VNValue.to_integer(-2.9), [&"integer", -2]),
		_is("limite", VNValue.to_integer(float(MAX)), [&"integer", MAX]),
		_is("limite com fração", VNValue.to_integer(-4503599627370495.5), [&"integer", -4503599627370495]),
		_is("fora", VNValue.to_integer(9007199254740992.0), VNErrors.OUT_OF_RANGE),
		_is("muito fora", VNValue.to_integer(-1e300), VNErrors.OUT_OF_RANGE),
		_is("nan", VNValue.to_integer(NAN), VNErrors.OUT_OF_RANGE),
	])


func test_padroes_dos_tipos() -> String:
	var want := {&"boolean": false, &"integer": 0, &"number": 0.0, &"string": "", &"enum": ""}
	for t in want:
		var got: Variant = VNValue.default_of(t)
		if typeof(got) != typeof(want[t]) or got != want[t]:
			return "padrão de %s: %s" % [t, got]
	return ""


# --- Comparação de tipos (DM §5.1) -------------------------------------------------

func test_comparacao_de_tipos() -> String:
	return _all([
		_is("1 = 1.0", VNValue.compare(&"equals", I(1), N(1.0)), [&"boolean", true]),
		_is("1 ≠ 1.5", VNValue.compare(&"not_equals", I(1), N(1.5)), [&"boolean", true]),
		_is("limite = limite.0", VNValue.compare(&"equals", I(MAX), N(float(MAX))), [&"boolean", true]),
		_is("limite−1 ≠ limite.0", VNValue.compare(&"equals", I(MAX - 1), N(float(MAX))), [&"boolean", false]),
		_is("enum = string", VNValue.compare(&"equals", E("night"), S("night")), [&"boolean", true]),
		_is("bool = bool", VNValue.compare(&"equals", B(true), B(true)), [&"boolean", true]),
		_is("bool vs int", VNValue.compare(&"equals", B(true), I(1)), VNErrors.TYPE_MISMATCH),
		_is("string vs int", VNValue.compare(&"not_equals", S("1"), I(1)), VNErrors.TYPE_MISMATCH),
		_is("2 > 1.5", VNValue.compare(&"greater_than", I(2), N(1.5)), [&"boolean", true]),
		_is("2 >= 2.0", VNValue.compare(&"greater_than_or_equal", I(2), N(2.0)), [&"boolean", true]),
		_is("−1 < 0", VNValue.compare(&"less_than", I(-1), I(0)), [&"boolean", true]),
		_is("1.0 <= 1", VNValue.compare(&"less_than_or_equal", N(1.0), I(1)), [&"boolean", true]),
		_is("ordem com texto", VNValue.compare(&"greater_than", S("b"), S("a")), VNErrors.TYPE_MISMATCH),
		_is("ordem com bool", VNValue.compare(&"less_than", B(false), B(true)), VNErrors.TYPE_MISMATCH),
		_is("contains", VNValue.compare(&"contains", S("pescador"), S("esca")), [&"boolean", true]),
		_is("contains vazio", VNValue.compare(&"contains", S("x"), S("")), [&"boolean", true]),
		_is("contains com enum", VNValue.compare(&"contains", E("night"), S("ig")), VNErrors.TYPE_MISMATCH),
		_is("contains com número", VNValue.compare(&"contains", S("10"), I(1)), VNErrors.TYPE_MISMATCH),
		_is("operador desconhecido", VNValue.compare(&"matches", S("a"), S("a")), VNErrors.TYPE_MISMATCH),
	])


func test_in_e_not_in() -> String:
	var nums: Array[VNEvalResult] = [I(1), I(2), N(3.0)]
	var texts: Array[VNEvalResult] = [S("day"), S("night")]
	var mixed: Array[VNEvalResult] = [S("day"), I(2)]
	return _all([
		_is("3 in [1, 2, 3.0]", VNValue.is_in(I(3), nums), [&"boolean", true]),
		_is("4 in [1, 2, 3.0]", VNValue.is_in(I(4), nums), [&"boolean", false]),
		_is("enum in textos", VNValue.is_in(E("night"), texts), [&"boolean", true]),
		_is("lista vazia", VNValue.is_in(I(1), [] as Array[VNEvalResult]), [&"boolean", false]),
		_is("achou antes do tipo errado", VNValue.is_in(S("day"), mixed), [&"boolean", true]),
		_is("tipo errado na lista", VNValue.is_in(S("dusk"), mixed), VNErrors.TYPE_MISMATCH),
	])


# --- Texto (RT §12.1) -------------------------------------------------------------

func test_concat_converte_numeros() -> String:
	var cases := [
		[I(1000), "1000"], [I(-MAX), "-9007199254740991"], [B(true), "true"], [B(false), "false"],
		[N(2.0), "2"], [N(-0.0), "0"], [N(3.5), "3.5"], [N(1.0 / 3.0), "0.3333333333333333"],
		[N(0.1 + 0.2), "0.30000000000000004"], [N(1e-7), "1e-7"], [N(1.5e-5), "0.000015"],
		[N(1e-6), "0.000001"], [N(-1.5e-7), "-1.5e-7"], [N(123456789012.5), "123456789012.5"],
		[N(float(MAX)), "9007199254740991"], [N(9007199254740992.0), "9007199254740992"],
		[N(1e20), "100000000000000000000"], [N(1e21), "1e+21"], [N(1.7976931348623157e308), "1.7976931348623157e+308"],
		[N(pow(2.0, -1074)), "5e-324"], [N(2.5e-5), "0.000025"], [N(100.25), "100.25"], [E("night"), "night"], [S("x"), "x"],
	]
	var errors := []
	for c in cases:
		var got := VNValue.to_text(c[0])
		if got != c[1]:
			errors.append("%s → %s (esperava %s)" % [_show(c[0]), got, c[1]])
	return "; ".join(errors)


func test_arredondamento_sobre_a_representacao_mais_curta() -> String:
	var cases := [
		[1.005, 2, "1.01"], [-1.005, 2, "-1.01"], [2.675, 2, "2.68"], [1.2345, 2, "1.23"],
		[0.125, 2, "0.13"], [-0.004, 2, "0"], [-0.005, 2, "-0.01"], [0.0, 2, "0"], [-0.0, 2, "0"],
		[1234567.5, 2, "1234567.5"], [9.995, 2, "10"], [99.999, 2, "100"], [-9.999, 2, "-10"],
		[2.0, 2, "2"], [1.10, 2, "1.1"], [1e-7, 2, "0"], [1e21, 2, "1000000000000000000000"],
		[0.5, 0, "1"], [-2.5, 0, "-3"], [1.45, 1, "1.5"], [1.0 / 3.0, 4, "0.3333"],
		[1234567, 2, "1234567"], [-42, 2, "-42"], [0, 2, "0"], [MAX, 2, "9007199254740991"],
	]
	var errors := []
	for c in cases:
		var got := VNValue.round_decimal(c[0], c[1])
		if got != c[2]:
			errors.append("round_decimal(%s, %d) → %s (esperava %s)" % [c[0], c[1], got, c[2]])
	return "; ".join(errors)


func test_digitos_mais_curtos() -> String:
	var errors := []
	for c in [[123.45, "12345", 3], [0.001, "1", -2], [1e21, "1", 22], [5.0, "5", 1], [0.1, "1", 0]]:
		var d := VNValue.shortest_digits(c[0])
		if d.digits != c[1] or d.point != c[2]:
			errors.append("%s → %s" % [c[0], d])
	# Os dígitos voltam ao mesmo float (propriedade da representação mais curta).
	for x in [0.1, 1.0 / 3.0, 2.0 / 3.0, 1e-300, 1.7976931348623157e308, 123456.789e10, 0.000123]:
		var d := VNValue.shortest_digits(x)
		var back: float = ("0." + d.digits + "e" + str(d.point)).to_float()
		if back != x:
			errors.append("%s não volta: %s" % [x, d])
	return "; ".join(errors)


## Valores em que o String.num_scientific do Godot 4.7.2 não dá a menor
## representação (achados comparando 30 mil floats com a referência Python).
## Os bits vêm em hex little-endian para não depender do parser de literais.
func test_representacao_mais_curta_onde_o_godot_erra() -> String:
	var cases := [
		["96a69a4d6ac66043", "37774075985474740"],
		["590bef11a16ead9f", "-4.2874017110381797e-156"],
		["8e225b7fef830ac3", "-932926756447313.8"],
		["2846c59d0bb316c1", "-371906.9040728533"],
		["fc2aefa066c7e0c2", "-147588850874711.88"],
		["c9c325fb035823c1", "-633857.9905224975"],
		["d08b7a82a0a21641", "370856.12742060144"],
		["3e804f986e6e6323", "3.2634392538353173e-138"],
		["b53206fdd3d31bc3", "-1958182951947437.2"],
		["0100000000000000", "5e-324"],
		["ffffffffffff0f00", "2.225073858507201e-308"],
		["0000000000001000", "2.2250738585072014e-308"],
		["ffffffffffffef7f", "1.7976931348623157e+308"],
		["0000000000003043", "4503599627370496"],
	]
	var errors := []
	for c in cases:
		var x: float = (c[0] as String).hex_decode().decode_double(0)
		var got := VNValue.to_text(N(x))
		if got != c[1]:
			errors.append("%s → %s (esperava %s)" % [c[0], got, c[1]])
	return "; ".join(errors)
