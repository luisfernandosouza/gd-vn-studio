class_name VNRandom
extends RefCounted
## Fluxo de números aleatórios do plugin (Plugin SDK §5.6; RT §12.2).
##
## [code]ctx.rng[/code] é o fluxo do plugin fora de atividades e
## [code]handle.rng[/code] o de cada atividade. Quem monta o fluxo (host ou
## harness) decide a semente; sem semente, é o RNG comum do motor. A
## reprodutibilidade com [code]settings.reproducible_rng[/code] chega com M3-03.

var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_rng = rng


## Inteiro em [from, to], inclusive.
func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Real em [0, 1].
func randf() -> float:
	return _rng.randf()
