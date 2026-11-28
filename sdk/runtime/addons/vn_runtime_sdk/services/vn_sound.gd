class_name VNSound
extends RefCounted
## Som tocado por [method VNAudioAPI.play] (Plugin SDK §5.6).
##
## O host cria o som com [method create], passando como ler o estado e como
## parar; o addon não conhece o player de áudio do runtime.

var _stop: Callable
var _is_playing: Callable


## [param stop_fn]: [code]func(fade: float)[/code]; [param is_playing_fn]:
## [code]func() -> bool[/code].
static func create(stop_fn: Callable, is_playing_fn: Callable) -> VNSound:
	var s := VNSound.new()
	s._stop = stop_fn
	s._is_playing = is_playing_fn
	return s


func stop(fade: float = 0.0) -> void:
	if _stop.is_valid():
		_stop.call(maxf(fade, 0.0))


func is_playing() -> bool:
	return _is_playing.is_valid() and bool(_is_playing.call())
