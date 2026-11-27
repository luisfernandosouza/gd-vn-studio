class_name VNRandom
extends RefCounted
## Fluxo de números aleatórios do plugin (Plugin SDK §5.6; RT §12.2).
##
## [code]ctx.rng[/code] é o fluxo do plugin fora de atividades e
## [code]handle.rng[/code] o de cada atividade. Quem monta o fluxo (host ou
## harness) decide a fonte: um [RandomNumberGenerator] do motor (o padrão, e o
## modo com [code]settings.reproducible_rng[/code] desligado) ou uma fonte do
## runtime com [code]random_int(min, max)[/code] e [code]unit()[/code] — o PCG32
## reproduzível de [code]VNGameRng.plugin_stream()[/code] e
## [code]activity_stream()[/code] (M1-08). O SDK não depende das classes do
## runtime: a fonte é usada só por esses dois métodos.

var _rng: RandomNumberGenerator = null
var _source: Object = null


func _init(rng: Object = null) -> void:
	if rng is RandomNumberGenerator:
		_rng = rng
	elif rng != null and rng.has_method(&"random_int") and rng.has_method(&"unit"):
		_source = rng
	else:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()


## Inteiro em [from, to], inclusive.
func randi_range(from: int, to: int) -> int:
	if _source != null:
		return _source.random_int(from, to)
	return _rng.randi_range(from, to)


## Real em [0, 1] (com a fonte do runtime, em [0, 1)).
func randf() -> float:
	if _source != null:
		return _source.unit()
	return _rng.randf()
