class_name VNRandom
extends RefCounted
## Fluxo de números aleatórios do plugin (Plugin SDK §5.6; RT §12.2).
##
## [code]ctx.rng[/code] é o fluxo do plugin fora de atividades e
## [code]handle.rng[/code] o de cada atividade. Quem monta o fluxo (host ou
## harness) escolhe o gerador:
## [br]- [code]VNRandom.new()[/code]: RNG comum do motor (padrão; sem
## [code]settings.reproducible_rng[/code]).
## [br]- [code]VNRandom.pcg32(seed)[/code]: PCG32 do RT §12.2, reproduzível, com
## [method get_state_hex]/[method set_state_hex] para o save.
## As sementes dos fluxos vêm de [method plugin_seed] e [method activity_seed].

const _MULT := 6364136223846793005
const _INC := 1442695040888963407
const _MASK32 := 0xFFFFFFFF
const _INT64_MAX := 9223372036854775807

var _rng: RandomNumberGenerator
var _pcg := false
var _state := 0   # PCG32: 64 bits sem sinal guardados num int de 64 bits


func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_rng = rng


# --- Fábricas e sementes -------------------------------------------------------

## PCG32 semeado: [code]state = 0[/code], um passo, [code]state += seed[/code], um
## passo (RT §12.2). [param seed] é um uint64 guardado num [int] (bits).
static func pcg32(seed: int) -> VNRandom:
	var r := VNRandom.new(RandomNumberGenerator.new())
	r._pcg = true
	r._state = 0
	r._step()
	r._state += seed
	r._step()
	return r


## Semente de hexadecimal de 16 dígitos ([code]"000000000000002a"[/code]) para uint64.
static func seed_from_hex(hex: String) -> int:
	if hex.length() != 16 or not hex.is_valid_hex_number():
		return 0
	return (hex.substr(0, 8).hex_to_int() << 32) | hex.substr(8, 8).hex_to_int()


static func seed_to_hex(value: int) -> String:
	return "%08x%08x" % [(value >> 32) & _MASK32, value & _MASK32]


## Semente de [code]ctx.rng[/code]: 8 primeiros bytes (big-endian) de
## SHA-256(seed ‖ namespace em UTF-8).
static func plugin_seed(game_seed: int, plugin_namespace: String) -> int:
	return _seed_from_hash(_u64_be(game_seed) + plugin_namespace.to_utf8_buffer())


## Semente de [code]handle.rng[/code]: SHA-256(seed ‖ selection_count ‖ uuid do nó
## ‖ activity_index). [param node_uuid] com ou sem hífens.
static func activity_seed(game_seed: int, selection_count: int, node_uuid: String, activity_index: int) -> int:
	var data := _u64_be(game_seed) + _u64_be(selection_count)
	data += node_uuid.replace("-", "").hex_decode()
	var idx := PackedByteArray()
	idx.resize(4)
	idx.encode_u32(0, activity_index)
	idx.reverse()
	return _seed_from_hash(data + idx)


static func _u64_be(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_s64(0, value)
	b.reverse()
	return b


static func _seed_from_hash(data: PackedByteArray) -> int:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	var d := h.finish()
	var v := 0
	for i in 8:
		v = (v << 8) | d[i]
	return v


# --- API do plugin ---------------------------------------------------------------

## Inteiro em [from, to], inclusive (sem viés no PCG32; limites trocados se [code]from > to[/code]).
func randi_range(from: int, to: int) -> int:
	if not _pcg:
		return _rng.randi_range(from, to)
	if from > to:
		var t := from
		from = to
		to = t
	var span := to - from + 1
	if span <= 0:
		return from   # intervalo além de 2^63: fora do domínio seguro (RT §12.1)
	if span <= 1 << 32:
		var threshold := (1 << 32) % span
		while true:
			var r := _next_u32()
			if r >= threshold:
				return from + r % span
	var threshold64 := _two_pow_64_mod(span)
	while true:
		var r64 := _next_u64()
		if r64 < 0 or r64 >= threshold64:   # r64 < 0 é ≥ 2^63 sem sinal
			return from + _umod(r64, span)
	return from


## Real em [0, 1] no motor comum e em [0, 1) no PCG32 ([code]next_u32 / 2^32[/code]).
func randf() -> float:
	if not _pcg:
		return _rng.randf()
	return float(_next_u32()) / 4294967296.0


## [code]true[/code] se o fluxo é o PCG32 reproduzível.
func is_reproducible() -> bool:
	return _pcg


## Estado do PCG32 em hexadecimal de 16 dígitos (vai no save em
## [code]rng.streams.<namespace>[/code]); vazio no RNG do motor.
func get_state_hex() -> String:
	return seed_to_hex(_state) if _pcg else ""


## Restaura o estado gravado por [method get_state_hex]. Ignorado no RNG do motor.
func set_state_hex(hex: String) -> void:
	if _pcg and hex.length() == 16 and hex.is_valid_hex_number():
		_state = seed_from_hex(hex)


# --- PCG32 -------------------------------------------------------------------------

func _step() -> void:
	_state = _state * _MULT + _INC   # a multiplicação de int64 dá a volta, como o mod 2^64


func _next_u32() -> int:
	var old := _state
	_step()
	var xorshifted := ((((old >> 18) & 0x3FFFFFFFFFFF) ^ old) >> 27) & _MASK32
	var rot := (old >> 59) & 31
	return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & _MASK32


func _next_u64() -> int:
	var hi := _next_u32()
	var lo := _next_u32()
	return (hi << 32) | lo


## 2^64 mod [param d] (0 < d < 2^62).
static func _two_pow_64_mod(d: int) -> int:
	var half := ((_INT64_MAX % d) + 1) % d   # 2^63 mod d
	return (half * 2) % d


## [param u] como uint64 mod [param d].
static func _umod(u: int, d: int) -> int:
	if u >= 0:
		return u % d
	return (((u & _INT64_MAX) % d) + ((_INT64_MAX % d) + 1) % d) % d
