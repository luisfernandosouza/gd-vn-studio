extends SceneTree
## Testes unitários do RNG reproduzível (M1-08; RT §12.2):
##   godot --headless --path runtime --script res://tests/rng/test_vn_rng.gd
## Valores de rng.json e da referência Python (docs/specs/tools/conformance.py). Sai com 1 se algo falhar.

var _fails := 0
var _checks := 0


func _init() -> void:
	_test_sequence()
	_test_random_int()
	_test_big_range()
	_test_seeds()
	_test_save_roundtrip()
	_test_off_mode()
	_test_restore_errors()
	print("%d/%d verificações do RNG passaram" % [_checks - _fails, _checks])
	quit(1 if _fails > 0 else 0)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_checks += 1
	if typeof(got) != typeof(want) or got != want:
		_fails += 1
		print("FALHOU %s: esperava %s, veio %s" % [what, want, got])


func _test_sequence() -> void:
	var r := VNPcg32.from_seed("000000000000002a")
	var got := []
	for i in 8:
		got.append(r.next_u32())
	_eq(got, [3270867926, 1795671209, 1924641435, 1143034755, 4121910957, 1757328946, 3418829100, 3589261271], "seq_42")
	_eq(r.state_hex(), "70100cf1d84a47bc", "estado depois de seq_42")
	var m := VNPcg32.from_seed("ffffffffffffffff")
	for i in 4:
		m.next_u32()
	_eq(m.state_hex(), "2627555c7a761e09", "estado depois de seq_max")


func _test_random_int() -> void:
	var r := VNPcg32.from_seed("000000000000002a")
	var got := []
	for i in 12:
		got.append(r.random_int(1, 6))
	_eq(got, [3, 6, 4, 4, 4, 5, 1, 6, 3, 4, 2, 2], "dado")
	var n := VNPcg32.from_seed("0123456789abcdef")
	got = []
	for i in 6:
		got.append(n.random_int(-10, -5))
	_eq(got, [-8, -10, -10, -8, -5, -6], "limites negativos")
	var s := VNPcg32.from_seed("000000000000002a")
	_eq(s.random_int(7, 7), 7, "intervalo de um valor")
	var t := VNPcg32.from_seed("000000000000002a")
	_eq(t.random_int(6, 1), 3, "limites trocados valem como (1, 6)")


func _test_big_range() -> void:
	var r := VNPcg32.from_seed("00000000deadbeef")
	var got := []
	for i in 4:
		got.append(r.random_int(0, 1099511627776))
	_eq(got, [875754464411, 389070853100, 1078425219582, 529629102242], "intervalo maior que 2^32")
	# Intervalo de inteiros do runtime inteiro (RT §12.1) não pode estourar nem sair dos limites.
	var q := VNPcg32.from_seed("000000000000002a")
	var ok := true
	for i in 200:
		var v := q.random_int(VNValue.INT_MIN, VNValue.INT_MAX)
		ok = ok and v >= VNValue.INT_MIN and v <= VNValue.INT_MAX
	_eq(ok, true, "random_int no intervalo inteiro do runtime")


func _test_seeds() -> void:
	_eq(VNGameRng.activity_seed("000000000000002a", 3, "019a7a00-6590-7a1b-8c2d-3e4f5a6b7c8d", 0), "9d742bde16f4ac91", "activity_seed")
	_eq(VNGameRng.activity_seed("000000000000002a", 3, "019a7a00-6590-7a1b-8c2d-3e4f5a6b7c8d", 1), "ebbc5cbcf2d97032", "activity_seed 2ª passagem")
	_eq(VNGameRng.plugin_seed("000000000000002a", "fishing"), "fc0a20ad838a3b28", "plugin_seed")


func _test_save_roundtrip() -> void:
	var g := VNGameRng.new()
	g.configure(true)
	g.new_game("000000000000002a")
	g.random_int(1, 6)
	var fishing := g.plugin_stream("fishing") as VNPcg32
	fishing.next_u32()
	var saved: Variant = g.to_save()
	_eq(saved["algorithm"], "pcg32", "save.algorithm")
	_eq(saved["seed"], "000000000000002a", "save.seed")
	_eq(saved["streams"].keys(), ["fishing"], "save.streams")
	var next_main := g.random_int(1, 1000000)
	var next_plugin := (g.plugin_stream("fishing") as VNPcg32).next_u32()
	var h := VNGameRng.new()
	h.configure(true)
	_eq(h.restore(saved), "", "restore sem erro")
	_eq(h.random_int(1, 1000000), next_main, "a narrativa continua igual depois do load")
	_eq((h.plugin_stream("fishing") as VNPcg32).next_u32(), next_plugin, "ctx.rng continua igual depois do load")
	# Fluxo de atividade: determinístico pela semente e independente do da narrativa.
	var a1 := g.activity_stream(3, "019a7a00-6590-7a1b-8c2d-3e4f5a6b7c8d", 0) as VNPcg32
	var a2 := h.activity_stream(3, "019a7a00-6590-7a1b-8c2d-3e4f5a6b7c8d", 0) as VNPcg32
	_eq(a1.next_u32(), a2.next_u32(), "fluxo da atividade reproduzível")


func _test_off_mode() -> void:
	var g := VNGameRng.new()
	g.configure(false)
	g.new_game()
	_eq(g.to_save(), null, "desligado: nada vai para o save")
	var v := g.random_int(1, 6)
	_eq(v >= 1 and v <= 6, true, "desligado: random_int no intervalo")
	_eq(g.plugin_stream("x") is VNPcg32, false, "desligado: ctx.rng usa o RNG do motor")
	_eq(g.activity_stream(0, "019a7a00-6590-7a1b-8c2d-3e4f5a6b7c8d", 0) is VNPcg32, false, "desligado: atividade usa o RNG do motor")
	var b := {"project": {"settings": {"reproducible_rng": true}}}
	g.configure_from_bundle(b)
	_eq(g.reproducible, true, "bundle liga o modo")


func _test_restore_errors() -> void:
	var g := VNGameRng.new()
	g.configure(true)
	_eq(g.restore({"algorithm": "xx", "seed": "0".repeat(16), "state": "0".repeat(16)}) != "", true, "algoritmo desconhecido")
	_eq(g.restore({"algorithm": "pcg32", "seed": "zz", "state": "0".repeat(16)}) != "", true, "hex inválido")
	_eq(g.restore("x") != "", true, "não é objeto")
	_eq(g.restore(null), "", "save sem rng semeia de novo")
	_eq(g.is_seeded(), true, "ligado + save sem rng: começa uma semente nova")
