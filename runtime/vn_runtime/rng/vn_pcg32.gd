class_name VNPcg32
extends RefCounted
## PCG32 (XSH-RR) do RNG reproduzível (RT §12.2; DM §6.1.1 [code]random_int[/code]).
##
## Multiplicador 6364136223846793005, incremento 1442695040888963407. O estado de 64 bits fica em
## duas metades de 32 bits ([member _hi], [member _lo]) e toda a aritmética é feita em pedaços que
## cabem no [code]int[/code] com sinal do GDScript sem estourar: o resultado é o mesmo no nativo e
## no Web, sem depender de estouro com sinal. Sementes e estados entram e saem em hexadecimal de
## 16 dígitos minúsculos, como no save ([code]save.schema.json → state.rng[/code]).
##
## Vetores: [code]conformance/rng.json[/code]. Referência: [code]docs/specs/tools/conformance.py[/code].
## Tarefa: M1-08.

const MASK32 := 0xFFFFFFFF
const _MULT_HI := 0x5851F42D   # 6364136223846793005 = 0x5851F42D4C957F2D
const _MULT_LO := 0x4C957F2D
const _INC_HI := 0x14057B7E    # 1442695040888963407 = 0x14057B7EF767814F
const _INC_LO := 0xF767814F
const TWO32 := 0x100000000

var _hi := 0
var _lo := 0


## Gerador semeado com [param seed_hex] (16 dígitos hex): [code]state = 0[/code], avança um passo,
## [code]state += seed[/code], avança um passo (RT §12.2).
static func from_seed(seed_hex: String) -> VNPcg32:
	var r := VNPcg32.new()
	var s := hex_to_halves(seed_hex)
	r._hi = 0
	r._lo = 0
	r._step()
	var lo: int = r._lo + s[1]
	r._hi = (r._hi + s[0] + (lo >> 32)) & MASK32
	r._lo = lo & MASK32
	r._step()
	return r


## Gerador que continua de um estado salvo ([param state_hex], 16 dígitos hex).
static func from_state(state_hex: String) -> VNPcg32:
	var r := VNPcg32.new()
	var s := hex_to_halves(state_hex)
	r._hi = s[0]
	r._lo = s[1]
	return r


## O estado atual em hexadecimal de 16 dígitos minúsculos.
func state_hex() -> String:
	return halves_to_hex(_hi, _lo)


## Cópia independente deste gerador, no mesmo estado.
func duplicate_rng() -> VNPcg32:
	var r := VNPcg32.new()
	r._hi = _hi
	r._lo = _lo
	return r


## Próxima saída de 32 bits, em [0, 2^32). Usa o estado anterior ao passo (XSH-RR padrão).
func next_u32() -> int:
	var hi := _hi
	var lo := _lo
	_step()
	# xorshifted = ((old >> 18) ^ old) >> 27, truncado em 32 bits.
	var sh_hi := hi >> 18
	var sh_lo := ((lo >> 18) | (hi << 14)) & MASK32
	var x_hi := sh_hi ^ hi
	var x_lo := sh_lo ^ lo
	var xs := ((x_lo >> 27) | (x_hi << 5)) & MASK32
	var rot := hi >> 27   # old >> 59
	if rot == 0:
		return xs
	return ((xs >> rot) | (xs << (32 - rot))) & MASK32


## Duas saídas de 32 bits juntas: [code](next_u32() << 32) | next_u32()[/code], como
## [code][alto, baixo][/code] (o valor pode passar de 2^63 e não cabe num [code]int[/code] com sinal).
func next_u64_halves() -> PackedInt64Array:
	var a := next_u32()
	var b := next_u32()
	return PackedInt64Array([a, b])


## Real em [0, 1): [code]next_u32() / 2^32[/code] (usado no sorteio ponderado, RT §4.3).
func unit() -> float:
	return float(next_u32()) / 4294967296.0


## Inteiro uniforme em [min, max], inclusivo, por rejeição, sem viés (RT §12.2). Limites trocados
## são aceitos (como na referência). [code]n = max − min + 1[/code] até 2^32 usa 32 bits; acima
## disso usa 64 bits. O intervalo tem de caber em 2^62 (o intervalo de inteiros do runtime,
## ±(2^53 − 1), RT §12.1, cabe com folga).
func random_int(p_min: int, p_max: int) -> int:
	return random_int_from(self, p_min, p_max)


## [method random_int] sobre qualquer fonte com [code]next_u32()[/code] (o PCG32 ou o RNG do motor
## em [VNGameRng]), para que o algoritmo seja um só nos dois modos.
static func random_int_from(source: Object, p_min: int, p_max: int) -> int:
	var lo_v := mini(p_min, p_max)
	var hi_v := maxi(p_min, p_max)
	var n := hi_v - lo_v + 1
	assert(n > 0 and n <= (1 << 62), "VNPcg32.random_int: intervalo grande demais")
	if n <= TWO32:
		var threshold := (TWO32 - n) % n
		while true:
			var r: int = source.next_u32()
			if r >= threshold:
				return lo_v + r % n
	# (2^64 − n) mod n = 2^64 mod n.
	var threshold64 := _pow2_mod(64, n)
	while true:
		var a: int = source.next_u32()
		var b: int = source.next_u32()
		# r = a·2^32 + b. Com a ≥ 2^30, r ≥ 2^62 > threshold64.
		if a >= (1 << 30) or (a << 32) + b >= threshold64:
			return lo_v + _mod_u64(a, b, n)
	return lo_v


## Avança um passo: state = state × MULT + INC (mod 2^64).
func _step() -> void:
	# (hi·2^32 + lo)·(MH·2^32 + ML) mod 2^64 = lo·ML + ((hi·ML + lo·MH) mod 2^32)·2^32.
	var p := _mul32_full(_lo, _MULT_LO)
	var cross := (_mul32_lo(_hi, _MULT_LO) + _mul32_lo(_lo, _MULT_HI) + p[0]) & MASK32
	var lo := p[1] + _INC_LO
	_hi = (cross + _INC_HI + (lo >> 32)) & MASK32
	_lo = lo & MASK32


## a·b (a, b < 2^32) como [alto, baixo], em pedaços de 16 bits.
static func _mul32_full(a: int, b: int) -> PackedInt64Array:
	var p0 := (a & 0xFFFF) * b          # < 2^48
	var p1 := (a >> 16) * b             # < 2^48
	var low := p0 + ((p1 & 0xFFFF) << 16)   # < 2^49
	var high := (p1 >> 16) + (low >> 32)    # < 2^33
	return PackedInt64Array([high & MASK32, low & MASK32])


## (a·b) mod 2^32, com a, b < 2^32.
static func _mul32_lo(a: int, b: int) -> int:
	return ((a & 0xFFFF) * b + ((((a >> 16) * b) & 0xFFFF) << 16)) & MASK32


## 2^e mod n, para n ≤ 2^62.
static func _pow2_mod(e: int, n: int) -> int:
	var r := 1 % n
	for i in e:
		r = (r << 1) % n   # r < n ≤ 2^62, então 2r < 2^63
	return r


## (a·2^32 + b) mod n, com a, b < 2^32 e n ≤ 2^62.
static func _mod_u64(a: int, b: int, n: int) -> int:
	var r := a % n
	for i in 32:
		r = (r << 1) % n
	return (r + b % n) % n


## "0123456789abcdef" → [0x01234567, 0x89abcdef]. Aceita maiúsculas; recusa o que não for 16 hex.
static func hex_to_halves(h: String) -> PackedInt64Array:
	assert(is_hex16(h), "VNPcg32: esperava 16 dígitos hexadecimais, veio \"%s\"" % h)
	return PackedInt64Array([("0x" + h.substr(0, 8)).hex_to_int(), ("0x" + h.substr(8, 8)).hex_to_int()])


static func halves_to_hex(hi: int, lo: int) -> String:
	return "%08x%08x" % [hi & MASK32, lo & MASK32]


## Verdadeiro se [param h] tem exatamente 16 dígitos hexadecimais.
static func is_hex16(h: String) -> bool:
	if h.length() != 16:
		return false
	for ch in h:
		if not "0123456789abcdefABCDEF".contains(ch):
			return false
	return true
