class_name VNGameRng
extends RefCounted
## RNG do jogo (RT §12.2): a fonte de [code]random_int[/code], do sorteio ponderado do Scheduler
## ([code]weighted_random[/code], RT §4.3), de [code]ctx.rng[/code] e de [code]handle.rng[/code].
##
## [b]Desligado[/b] ([code]settings.reproducible_rng = false[/code], o padrão): tudo sai do
## [RandomNumberGenerator] do motor, semeado ao abrir o jogo; nada vai para o save
## ([method to_save] devolve [code]null[/code]) e os fluxos de plugin e de atividade são RNGs do
## motor independentes.
##
## [b]Ligado[/b]: PCG32 ([VNPcg32]) semeado em [method new_game]. O fluxo da narrativa, a semente e
## o estado de [code]ctx.rng[/code] de cada plugin vão para [code]state.rng[/code] do save
## ([method to_save] / [method restore]). Cada atividade recebe um fluxo próprio derivado por
## SHA-256 ([method activity_stream]); o estado dele não é salvo (não há save durante
## [code]ACTIVITY[/code], RT §8.1).
##
## Fica em [code]VNModules.rng[/code]. Não é um [VNModule]: não tem dublê e é o mesmo nos testes e
## no jogo. Quem sorteia (Condition Evaluator, Scheduler, Plugin Host) chama
## [code]modules().rng[/code]; o Narrative Engine chama [method new_game] ao começar um jogo e
## devolve [method to_save] na parte dele do save ([code]engine_part.rng[/code]).
##
## Tarefa: M1-08. Vetores: [code]conformance/rng.json[/code].

const ALGORITHM := "pcg32"

## Valor de [code]settings.reproducible_rng[/code] do projeto.
var reproducible := false

## Semente do jogo atual em hex de 16 dígitos ([code]""[/code] com o RNG desligado ou antes de
## [method new_game]).
var seed_hex := ""

var _pcg: VNPcg32 = null
var _engine: _EngineSource = null
## ns_id → VNPcg32 (ligado) ou _EngineSource (desligado). Os fluxos de [code]ctx.rng[/code].
var _streams := {}


func _init() -> void:
	_engine = _EngineSource.new(null)


## Lê [code]project.settings.reproducible_rng[/code] do bundle. Não sorteia nem semeia: isso é
## [method new_game] (ou [method restore] ao carregar um save).
func configure_from_bundle(bundle: Dictionary) -> void:
	var project: Dictionary = bundle.get("project", {})
	var settings: Dictionary = project.get("settings", {})
	configure(bool(settings.get("reproducible_rng", false)))


## Liga ou desliga o modo reproduzível. Zera a semente e os fluxos.
func configure(p_reproducible: bool) -> void:
	reproducible = p_reproducible
	seed_hex = ""
	_pcg = null
	_streams.clear()
	_engine = _EngineSource.new(null)


## Começa um jogo novo (RT §2.2, passo 3). Ligado: usa [param fixed_seed_hex] (modo teste ou
## Preview) ou gera uma semente de 64 bits com o RNG do motor. Desligado: só semeia de novo o RNG
## do motor (com [param fixed_seed_hex], de forma fixa, para testes).
func new_game(fixed_seed_hex: String = "") -> void:
	_streams.clear()
	if not reproducible:
		seed_hex = ""
		_pcg = null
		var r := RandomNumberGenerator.new()
		if fixed_seed_hex != "":
			var h := VNPcg32.hex_to_halves(fixed_seed_hex)
			r.seed = (h[0] << 32) | h[1]
		else:
			r.randomize()
		_engine = _EngineSource.new(r)
		return
	if fixed_seed_hex != "":
		assert(VNPcg32.is_hex16(fixed_seed_hex), "VNGameRng.new_game: semente inválida")
		seed_hex = fixed_seed_hex.to_lower()
	else:
		var r := RandomNumberGenerator.new()
		r.randomize()
		seed_hex = VNPcg32.halves_to_hex(r.randi(), r.randi())
	_pcg = VNPcg32.from_seed(seed_hex)


## Verdadeiro quando há um PCG32 ativo (ligado e semeado).
func is_seeded() -> bool:
	return _pcg != null


# --- Fluxo da narrativa ----------------------------------------------------------------------

## Próxima saída de 32 bits do fluxo da narrativa.
func next_u32() -> int:
	return _source().next_u32()


## Inteiro uniforme em [min, max], inclusivo (DM §6.1.1 [code]random_int[/code]). O mesmo algoritmo
## de rejeição nos dois modos; ligado, segue os vetores de [code]rng.json[/code].
func random_int(p_min: int, p_max: int) -> int:
	return VNPcg32.random_int_from(_source(), p_min, p_max)


## Real em [0, 1): [code]next_u32() / 2^32[/code] (sorteio ponderado, RT §4.3).
func unit() -> float:
	return float(next_u32()) / 4294967296.0


## Estado do fluxo da narrativa em hex (ligado e semeado) ou [code]""[/code].
func state_hex() -> String:
	return _pcg.state_hex() if _pcg != null else ""


## Põe o fluxo da narrativa num estado dado (vetores de conformidade com [code]rng_state[/code] e
## Preview). Liga o modo reproduzível se preciso; a semente do jogo não muda.
func set_state_hex(state: String) -> void:
	reproducible = true
	_pcg = VNPcg32.from_state(state)


# --- Fluxos derivados ------------------------------------------------------------------------

## O fluxo [code]ctx.rng[/code] do plugin [param ns_id] (namespace) (criado na primeira chamada e mantido
## até o fim do jogo). Ligado: PCG32 semeado com [method plugin_seed], ou o estado restaurado do
## save. Desligado: um RNG do motor só desse plugin.
func plugin_stream(ns_id: String) -> Object:
	if not _streams.has(ns_id):
		if _pcg != null:
			_streams[ns_id] = VNPcg32.from_seed(plugin_seed(seed_hex, ns_id))
		else:
			_streams[ns_id] = _EngineSource.new(null)
	return _streams[ns_id]


## Fluxo novo para uma atividade (o [code]handle.rng[/code], SDK §6). [param selection_count] é o
## do histórico do Scheduler, [param node_id] o UUID do nó [code]plugin[/code] e
## [param activity_index] quantas atividades já começaram na execução atual da cena (a partir de 0).
## Desligado: um RNG do motor novo.
func activity_stream(selection_count: int, node_id: String, activity_index: int) -> Object:
	if _pcg == null:
		return _EngineSource.new(null)
	return VNPcg32.from_seed(activity_seed(seed_hex, selection_count, node_id, activity_index))


## Semente do fluxo de uma atividade: 8 primeiros bytes (big-endian) de
## SHA-256(seed ‖ selection_count (u64 BE) ‖ UUID (16 bytes) ‖ activity_index (u32 BE)).
static func activity_seed(p_seed_hex: String, selection_count: int, node_id: String, activity_index: int) -> String:
	var buf := _hex_bytes(p_seed_hex)
	buf.append_array(_be_bytes(selection_count, 8))
	buf.append_array(_hex_bytes(node_id.replace("-", "")))
	buf.append_array(_be_bytes(activity_index, 4))
	return _sha256_prefix(buf)


## Semente de [code]ctx.rng[/code]: 8 primeiros bytes de SHA-256(seed ‖ ns_id em UTF-8).
static func plugin_seed(p_seed_hex: String, ns_id: String) -> String:
	var buf := _hex_bytes(p_seed_hex)
	buf.append_array(ns_id.to_utf8_buffer())
	return _sha256_prefix(buf)


# --- Save ------------------------------------------------------------------------------------

## O objeto [code]state.rng[/code] do save ([code]save.schema.json[/code]), ou [code]null[/code]
## com o RNG desligado ou sem semente. [code]streams[/code] só aparece com algum plugin que usou
## [code]ctx.rng[/code].
func to_save() -> Variant:
	if not reproducible or _pcg == null or seed_hex == "":
		return null
	var out := {"algorithm": ALGORITHM, "seed": seed_hex, "state": _pcg.state_hex()}
	var streams := {}
	var names := _streams.keys()
	names.sort()
	for ns in names:
		if _streams[ns] is VNPcg32:
			streams[ns] = (_streams[ns] as VNPcg32).state_hex()
	if not streams.is_empty():
		out["streams"] = streams
	return out


## Restaura de [code]state.rng[/code] do save. [code]null[/code] (ou save sem RNG): desligado, só
## semeia de novo o RNG do motor; ligado, começa uma semente nova (o save veio de quando a opção
## estava desligada). Devolve [code]""[/code] ou a descrição do erro (o save fica sem efeito no RNG).
func restore(data: Variant) -> String:
	if data == null or not reproducible:
		new_game()
		return ""
	if not (data is Dictionary):
		return "state.rng não é um objeto"
	var d: Dictionary = data
	if String(d.get("algorithm", "")) != ALGORITHM:
		return "state.rng.algorithm desconhecido: %s" % d.get("algorithm")
	var s := String(d.get("seed", ""))
	var st := String(d.get("state", ""))
	if not VNPcg32.is_hex16(s) or not VNPcg32.is_hex16(st):
		return "state.rng.seed e state.rng.state precisam de 16 dígitos hexadecimais"
	var streams: Dictionary = d.get("streams", {}) if d.get("streams") is Dictionary else {}
	for ns in streams:
		if not VNPcg32.is_hex16(String(streams[ns])):
			return "state.rng.streams.%s precisa de 16 dígitos hexadecimais" % ns
	seed_hex = s.to_lower()
	_pcg = VNPcg32.from_state(st)
	_streams.clear()
	for ns in streams:
		_streams[String(ns)] = VNPcg32.from_state(String(streams[ns]))
	return ""


# --- Internos --------------------------------------------------------------------------------

func _source() -> Object:
	return _pcg if _pcg != null else _engine


static func _hex_bytes(h: String) -> PackedByteArray:
	return h.hex_decode()


static func _be_bytes(v: int, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		out[n - 1 - i] = (v >> (8 * i)) & 0xFF
	return out


static func _sha256_prefix(buf: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	return ctx.finish().slice(0, 8).hex_encode()


## O RNG do motor com a mesma interface de saída do PCG32 ([code]next_u32[/code]).
class _EngineSource:
	extends RefCounted
	var _rng: RandomNumberGenerator

	func _init(rng: RandomNumberGenerator) -> void:
		if rng == null:
			rng = RandomNumberGenerator.new()
			rng.randomize()
		_rng = rng

	func next_u32() -> int:
		return _rng.randi()

	func random_int(p_min: int, p_max: int) -> int:
		return VNPcg32.random_int_from(self, p_min, p_max)

	func unit() -> float:
		return float(next_u32()) / 4294967296.0
