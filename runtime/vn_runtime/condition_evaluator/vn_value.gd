class_name VNValue
extends RefCounted
## Tipos, valores e semântica de referência (tarefa M1-02).
##
## Um valor com tipo é um [VNEvalResult] com [code]ok = true[/code]:
## [member VNEvalResult.value] guarda o valor e [member VNEvalResult.type] o tipo
## (DM §4.2): [code]boolean[/code] ([code]bool[/code]), [code]integer[/code]
## ([code]int[/code]), [code]number[/code] ([code]float[/code]),
## [code]string[/code] e [code]enum[/code] ([code]String[/code]). As operações
## devolvem um valor novo ou um [VNEvalResult] de falha com o código de
## [VNErrors]; nunca levantam erro do Godot.
##
## Regras normativas (RT §12.1, DM §6.1.1, CV §3):
## [br]- [code]integer[/code] vale em ±(2^53 − 1); o Godot guarda em int64, mas o
##   limite é o do JavaScript. Resultado inteiro fora dele, [code]number[/code]
##   não finito, divisão ou [code]mod[/code] por zero e conversão de
##   [code]number[/code] fora do intervalo para [code]integer[/code] dão
##   [code]OUT_OF_RANGE[/code] (erro de conteúdo: a transação é abortada).
## [br]- Comparar [code]integer[/code] com [code]number[/code] converte o inteiro
##   para [code]number[/code] (exato dentro do intervalo).
## [br]- [code]concat[/code] escreve números como o [code]Number.prototype.toString[/code]
##   do JavaScript, sem casa decimal quando a parte fracionária é zero e sem
##   notação científica dentro do intervalo de inteiros.
## [br]- O arredondamento da interpolação age sobre essa representação decimal
##   mais curta, meio-para-longe-do-zero ([code]1.005 → 1.01[/code]).
##
## A implementação de referência é [code]docs/specs/tools/conformance.py[/code]
## ([code]lit[/code], [code]check_int[/code], [code]arith[/code],
## [code]compare[/code], [code]to_text[/code], [code]format_number[/code]); esta
## classe segue a mesma ordem de verificações para dar o mesmo código de erro.
##
## Quem usa: o Condition Evaluator (M1-03, M1-04), o State Manager (M1-06,
## verificação 8 do RT §6.2) e o formatador de texto (M1-07).

const BOOLEAN := &"boolean"
const INTEGER := &"integer"
const NUMBER := &"number"
const STRING := &"string"
const ENUM := &"enum"

## Maior inteiro aceito: 2^53 − 1 ([code]Number.MAX_SAFE_INTEGER[/code]).
const INT_MAX := 9007199254740991
## Menor inteiro aceito: −(2^53 − 1).
const INT_MIN := -9007199254740991

const ORDERING_OPERATORS: Array[StringName] = [
	&"greater_than", &"greater_than_or_equal", &"less_than", &"less_than_or_equal",
]


# --- Construção ----------------------------------------------------------------

## [code]integer[/code] conferido: fora de ±(2^53 − 1) é [code]OUT_OF_RANGE[/code].
static func integer(i: int) -> VNEvalResult:
	if i > INT_MAX or i < INT_MIN:
		return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "inteiro %d fora de ±(2^53 − 1)" % i)
	return VNEvalResult.of(i, INTEGER)


## [code]number[/code] conferido: infinito ou NaN é [code]OUT_OF_RANGE[/code].
static func number(x: float) -> VNEvalResult:
	if not is_finite(x):
		return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "número não finito %s" % x)
	return VNEvalResult.of(x, NUMBER)


static func boolean(b: bool) -> VNEvalResult:
	return VNEvalResult.of(b, BOOLEAN)


static func string(s: String) -> VNEvalResult:
	return VNEvalResult.of(s, STRING)


## Tipo de um literal do conteúdo (DM §6.1). O [code]JSON[/code] do Godot lê
## todo número como [code]float[/code] (o JSON não distingue [code]2[/code] de
## [code]2.0[/code], CV §2.1), então o tipo sai do valor:
## [br]- [code]bool[/code] → [code]boolean[/code]; [code]String[/code]/[code]StringName[/code] → [code]string[/code];
## [br]- [code]int[/code] → [code]integer[/code] (conferido);
## [br]- [code]float[/code] com parte fracionária zero dentro de ±(2^53 − 1) →
##   [code]integer[/code]; os demais → [code]number[/code] (conferido).
## [br][param hint] força o tipo quando quem chama o conhece (o tipo da
## variável comparada ou de destino): [code]number[/code] mantém
## [code]float[/code], [code]integer[/code] exige valor inteiro e
## [code]enum[/code] marca o texto como enum. Literal incompatível com o
## [param hint] é [code]TYPE_MISMATCH[/code] (o validador barra antes, T001).
static func from_literal(v: Variant, hint: StringName = &"") -> VNEvalResult:
	match typeof(v):
		TYPE_BOOL:
			if hint != &"" and hint != BOOLEAN:
				return _mismatch("literal booleano para %s" % hint)
			return boolean(v)
		TYPE_STRING, TYPE_STRING_NAME:
			if hint == ENUM:
				return VNEvalResult.of(String(v), ENUM)
			if hint != &"" and hint != STRING:
				return _mismatch("literal de texto para %s" % hint)
			return string(String(v))
		TYPE_INT:
			if hint == NUMBER:
				return number(float(v))
			if hint != &"" and hint != INTEGER:
				return _mismatch("literal numérico para %s" % hint)
			return integer(v)
		TYPE_FLOAT:
			var x: float = v
			if hint == NUMBER:
				return number(x)
			if hint != &"" and hint != INTEGER:
				return _mismatch("literal numérico para %s" % hint)
			if is_finite(x) and x == floorf(x) and absf(x) <= INT_MAX:
				return VNEvalResult.of(int(x), INTEGER)
			if hint == INTEGER:
				if not is_finite(x) or x != floorf(x):
					return _mismatch("literal %s não é inteiro" % x)
				return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "inteiro %s fora de ±(2^53 − 1)" % x)
			return number(x)
	return _mismatch("literal de tipo não suportado (%s)" % type_string(typeof(v)))


## Valor de uma variável com o tipo declarado (DM §4.2), como o Variable
## Manager guarda ou como chega de um JSON (save, vetores). Normaliza
## [code]float[/code] inteiro para [code]int[/code] em [code]integer[/code] e
## [code]int[/code] para [code]float[/code] em [code]number[/code].
## Valor incompatível com o tipo é [code]TYPE_MISMATCH[/code].
static func typed(v: Variant, type: StringName) -> VNEvalResult:
	match type:
		BOOLEAN:
			if typeof(v) == TYPE_BOOL:
				return boolean(v)
		INTEGER:
			if typeof(v) == TYPE_INT:
				return integer(v)
			if typeof(v) == TYPE_FLOAT:
				var x: float = v
				if not is_finite(x) or x != floorf(x):
					return _mismatch("%s não é inteiro" % x)
				if absf(x) > INT_MAX:
					return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "inteiro %s fora de ±(2^53 − 1)" % x)
				return VNEvalResult.of(int(x), INTEGER)
		NUMBER:
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				return number(float(v))
		STRING, ENUM:
			if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
				return VNEvalResult.of(String(v), type)
		_:
			return _mismatch("tipo desconhecido %s" % type)
	return _mismatch("valor %s não é %s" % [v, type])


## Padrão do tipo (DM §6.1: [code]false[/code], [code]0[/code], [code]0.0[/code], [code]""[/code]).
static func default_of(type: StringName) -> Variant:
	match type:
		BOOLEAN: return false
		INTEGER: return 0
		NUMBER: return 0.0
	return ""


static func is_numeric(t: StringName) -> bool:
	return t == INTEGER or t == NUMBER


static func is_text(t: StringName) -> bool:
	return t == STRING or t == ENUM


## Valor numérico como [code]float[/code] (exato para inteiros no intervalo).
static func as_float(r: VNEvalResult) -> float:
	return float(r.value)


## [code]number → integer[/code] truncando em direção a zero (DM §6.2). Fora do
## intervalo ou não finito é [code]OUT_OF_RANGE[/code].
static func to_integer(x: float) -> VNEvalResult:
	if not is_finite(x):
		return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "%s não cabe em integer" % x)
	var t := x - fmod(x, 1.0)  # trunc, sem passar por int64
	if absf(t) > INT_MAX:
		return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "%s não cabe em integer" % x)
	return VNEvalResult.of(int(t), INTEGER)


# --- Aritmética (DM §6.1.1) ----------------------------------------------------

## [code]add[/code], [code]sub[/code], [code]mul[/code], [code]div[/code] e
## [code]mod[/code] sobre dois valores. [code]integer[/code] se os dois forem
## inteiros (salvo [code]div[/code], sempre [code]number[/code]); [code]mod[/code]
## só com inteiros e com o sinal do divisor. Ordem das verificações da
## referência: tipos ([code]TYPE_MISMATCH[/code]), divisor zero, intervalo
## ([code]OUT_OF_RANGE[/code]).
static func arith(fn: StringName, a: VNEvalResult, b: VNEvalResult) -> VNEvalResult:
	if not (is_numeric(a.type) and is_numeric(b.type)):
		return _mismatch("%s exige números" % fn)
	var both_int := a.type == INTEGER and b.type == INTEGER
	match fn:
		&"div":
			if as_float(b) == 0.0:
				return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "divisão por zero")
			return number(as_float(a) / as_float(b))
		&"mod":
			if not both_int:
				return _mismatch("mod exige inteiros")
			if b.value == 0:
				return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "mod por zero")
			return integer(posmod(a.value, b.value))  # sinal do divisor
		&"add":
			return integer(a.value + b.value) if both_int else number(as_float(a) + as_float(b))
		&"sub":
			return integer(a.value - b.value) if both_int else number(as_float(a) - as_float(b))
		&"mul":
			if not both_int:
				return number(as_float(a) * as_float(b))
			# Operandos até 2^53: o produto pode passar do int64. Se o produto em
			# float já passa de 2^62, o resultado está fora do intervalo; senão o
			# produto inteiro é exato e cabe no int64.
			if absf(as_float(a) * as_float(b)) > 4611686018427387904.0:
				return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "produto fora de ±(2^53 − 1)")
			return integer(a.value * b.value)
	return _mismatch("função aritmética desconhecida %s" % fn)


## [code]round[/code] (meio-para-longe-do-zero), [code]floor[/code],
## [code]ceil[/code] e [code]abs[/code]. Os três primeiros devolvem
## [code]integer[/code]; [code]abs[/code] mantém o tipo.
static func unary(fn: StringName, a: VNEvalResult) -> VNEvalResult:
	if not is_numeric(a.type):
		return _mismatch("%s exige número" % fn)
	if fn == &"abs":
		return integer(absi(a.value)) if a.type == INTEGER else number(absf(a.value))
	if not (fn in [&"round", &"floor", &"ceil"]):
		return _mismatch("função desconhecida %s" % fn)
	if a.type == INTEGER:
		return integer(a.value)
	var x: float = a.value
	var r: float
	match fn:
		&"round": r = round_half_away(x)
		&"floor": r = floorf(x)
		_: r = ceilf(x)
	if not is_finite(r) or absf(r) > INT_MAX:
		return VNEvalResult.failure(VNErrors.OUT_OF_RANGE, "%s(%s) fora de ±(2^53 − 1)" % [fn, x])
	return VNEvalResult.of(int(r), INTEGER)


## Meio-para-longe-do-zero ([code]2.5 → 3[/code], [code]-2.5 → -3[/code]),
## com a mesma fórmula da referência.
static func round_half_away(x: float) -> float:
	return floorf(x + 0.5) if x >= 0.0 else -floorf(-x + 0.5)


## [code]min[/code] e [code]max[/code]: o primeiro valor extremo vence o empate;
## [code]integer[/code] se todos forem inteiros, senão [code]number[/code].
static func min_max(fn: StringName, values: Array[VNEvalResult]) -> VNEvalResult:
	if values.is_empty():
		return _mismatch("%s exige argumentos" % fn)
	for v in values:
		if not is_numeric(v.type):
			return _mismatch("%s exige números" % fn)
	var best: VNEvalResult = values[0]
	for v in values.slice(1):
		if (as_float(v) < as_float(best)) if fn == &"min" else (as_float(v) > as_float(best)):
			best = v
	return _numeric_like(best, _all_int(values))


## [code]clamp(v, lo, hi)[/code]; com [code]lo > hi[/code] devolve [code]lo[/code].
static func clamp_value(v: VNEvalResult, lo: VNEvalResult, hi: VNEvalResult) -> VNEvalResult:
	var args: Array[VNEvalResult] = [v, lo, hi]
	for x in args:
		if not is_numeric(x.type):
			return _mismatch("clamp exige números")
	var r := v
	if as_float(lo) > as_float(hi) or as_float(v) < as_float(lo):
		r = lo
	elif as_float(v) > as_float(hi):
		r = hi
	return _numeric_like(r, _all_int(args))


# --- Comparação (DM §5.1) ------------------------------------------------------

## Igualdade com a regra de tipos do DM §5.1: [code]integer[/code] e
## [code]number[/code] pelo valor ([code]1 = 1.0[/code]); [code]string[/code] e
## [code]enum[/code] pelo texto; [code]boolean[/code] só com [code]boolean[/code].
## Outras combinações são [code]TYPE_MISMATCH[/code]. Devolve [code]boolean[/code].
static func equals(a: VNEvalResult, b: VNEvalResult) -> VNEvalResult:
	if is_numeric(a.type) and is_numeric(b.type):
		if a.type == INTEGER and b.type == INTEGER:
			return boolean(a.value == b.value)
		return boolean(as_float(a) == as_float(b))
	if is_text(a.type) and is_text(b.type):
		return boolean(String(a.value) == String(b.value))
	if a.type == b.type and a.type == BOOLEAN:
		return boolean(a.value == b.value)
	return _mismatch("%s equals %s" % [a.type, b.type])


## Aplica um operador binário do DM §5.1 ([code]equals[/code],
## [code]not_equals[/code], [code]greater_than[/code],
## [code]greater_than_or_equal[/code], [code]less_than[/code],
## [code]less_than_or_equal[/code], [code]contains[/code]). Devolve
## [code]boolean[/code] ou [code]TYPE_MISMATCH[/code].
static func compare(op: StringName, a: VNEvalResult, b: VNEvalResult) -> VNEvalResult:
	if op == &"equals" or op == &"not_equals":
		var eq := equals(a, b)
		if not eq.ok:
			return eq
		return boolean(eq.value if op == &"equals" else not eq.value)
	if op in ORDERING_OPERATORS:
		if not (is_numeric(a.type) and is_numeric(b.type)):
			return _mismatch("%s exige números" % op)
		var x := as_float(a)  # exato para inteiros no intervalo
		var y := as_float(b)
		match op:
			&"greater_than": return boolean(x > y)
			&"greater_than_or_equal": return boolean(x >= y)
			&"less_than": return boolean(x < y)
			_: return boolean(x <= y)
	if op == &"contains":
		if a.type != STRING or b.type != STRING:
			return _mismatch("contains exige string")
		var needle := String(b.value)
		# O String.contains do Godot dá falso para "" (Python e JavaScript dão verdadeiro).
		return boolean(needle.is_empty() or String(a.value).contains(needle))
	return _mismatch("operador desconhecido %s" % op)


## [code]in[/code]/[code]not_in[/code]: [param a] é igual (pela regra de
## [method equals]) a algum dos [param candidates]? Elemento de tipo
## incompatível é [code]TYPE_MISMATCH[/code].
static func is_in(a: VNEvalResult, candidates: Array[VNEvalResult]) -> VNEvalResult:
	for c in candidates:
		var eq := equals(a, c)
		if not eq.ok or eq.value:
			return eq
	return boolean(false)


# --- Texto (RT §12.1) ----------------------------------------------------------

## Conversão usada por [code]concat[/code]: booleanos como
## [code]true[/code]/[code]false[/code], inteiros sem casa decimal,
## [code]number[/code] com parte fracionária zero sem casa ([code]2.0 → 2[/code])
## e os demais pela [method shortest_repr].
static func to_text(r: VNEvalResult) -> String:
	match r.type:
		BOOLEAN:
			return "true" if r.value else "false"
		INTEGER:
			return str(r.value)
		NUMBER:
			var x: float = r.value
			if x == floorf(x) and absf(x) <= INT_MAX:
				return str(int(x))
			return shortest_repr(x)
	return String(r.value)


## [code]Number.prototype.toString[/code] do ECMAScript: a menor representação
## decimal que volta ao mesmo [code]float[/code], em notação científica só
## fora de [1e-6, 1e21) ([code]1/3 → 0.3333333333333333[/code],
## [code]1e-7 → 1e-7[/code], [code]1.5e-5 → 0.000015[/code]).
static func shortest_repr(x: float) -> String:
	if is_nan(x):
		return "NaN"
	if is_inf(x):
		return "Infinity" if x > 0 else "-Infinity"
	if x == 0.0:
		return "0"
	if x < 0.0:
		return "-" + shortest_repr(-x)
	var d := shortest_digits(x)
	var digits: String = d.digits
	var n: int = d.point
	var k := digits.length()
	if k <= n and n <= 21:
		return digits + "0".repeat(n - k)
	if 0 < n and n <= 21:
		return digits.substr(0, n) + "." + digits.substr(n)
	if -6 < n and n <= 0:
		return "0." + "0".repeat(-n) + digits
	var e := n - 1
	var mant := digits.substr(0, 1) + ("." + digits.substr(1) if k > 1 else "")
	return mant + "e" + ("+" if e >= 0 else "-") + str(absi(e))


## Dígitos significativos da menor representação de [param x] (finito, não
## negativo, diferente de zero) e a posição do ponto decimal:
## [code]x = 0.<digits> × 10^point[/code], como na referência
## ([code]123.45 → { digits = "12345", point = 3 }[/code]). Ver [VNDecimal].
static func shortest_digits(x: float) -> Dictionary:
	return VNDecimal.shortest(absf(x))


## Arredonda [param v] ([code]int[/code] ou [code]float[/code] finito) para no
## máximo [param places] casas, meio-para-longe-do-zero sobre a representação
## decimal mais curta (CV §3, regra 2: [code]1.005 → "1.01"[/code]), sem zeros à
## direita nem notação científica, com [code].[/code] como separador e sem
## separador de milhar. Um negativo que arredonda para zero sai sem sinal
## (CV §3, regra 3: [code]-0.004 → "0"[/code]). É a base da formatação na
## interpolação (M1-07), que só troca os separadores.
static func round_decimal(v: Variant, places: int = 2) -> String:
	var neg := false
	var digits: String
	var point: int
	if typeof(v) == TYPE_INT:
		var i: int = v
		neg = i < 0
		digits = str(absi(i)) if i != 0 else ""
		point = digits.length()
	else:
		var x: float = v
		if not is_finite(x):
			return shortest_repr(x)
		if x == 0.0:
			return "0"
		neg = x < 0.0
		var d := shortest_digits(x)
		digits = d.digits
		point = d.point
	# Inteira e fração como texto: x = 0.<digits> × 10^point.
	var ip: String
	var fp: String
	if point <= 0:
		ip = "0"
		fp = "0".repeat(-point) + digits
	elif point >= digits.length():
		ip = digits + "0".repeat(point - digits.length())
		fp = ""
	else:
		ip = digits.substr(0, point)
		fp = digits.substr(point)
	if ip.is_empty():
		ip = "0"
	if fp.length() > places:
		var round_up := fp.unicode_at(places) >= 0x35  # '5'..'9': meio-para-longe-do-zero
		fp = fp.substr(0, places)
		if round_up:
			var carried := VNDecimal.increment(ip + fp)
			ip = carried.substr(0, carried.length() - places)
			fp = carried.substr(carried.length() - places)
	fp = fp.rstrip("0")
	ip = ip.lstrip("0")
	if ip.is_empty():
		ip = "0"
	var out := ip + ("." + fp if not fp.is_empty() else "")
	if neg and out != "0":
		out = "-" + out
	return out


# --- Internos ------------------------------------------------------------------

static func _mismatch(message: String) -> VNEvalResult:
	return VNEvalResult.failure(VNErrors.TYPE_MISMATCH, message)


static func _all_int(values: Array[VNEvalResult]) -> bool:
	for v in values:
		if v.type != INTEGER:
			return false
	return true


static func _numeric_like(r: VNEvalResult, as_int: bool) -> VNEvalResult:
	return VNEvalResult.of(r.value, INTEGER) if as_int else VNEvalResult.of(as_float(r), NUMBER)
