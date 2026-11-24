class_name VNAudioChannel
extends Node
## Um canal do Audio Manager (música, ambiente, efeitos ou voz) na árvore de
## cena: os [AudioStreamPlayer] dele, os fades e o volume.
##
## O volume que sai de cada player é
## [code]volume do jogador (geral × canal) × volume do nó × ganho do fade[/code],
## em escala linear, convertido para dB. O canal não sabe nada de nós de cena,
## saves nem modo stream: quem decide o que toca é o [VNRuntimeAudioManager].
##
## Há dois tipos de som:
## [br]- o [b]principal[/b] ([method play_main]): o som do canal que vai para o
## save (a música, o ambiente). Um novo principal substitui o anterior, com
## fade cruzado se houver [code]fade[/code];
## [br]- os [b]avulsos[/b] ([method play_one_shot]): efeitos sonoros que se
## sobrepõem e os sons do [code]VNAudioAPI[/code] dos plugins. Somem sozinhos
## ao terminar.
##
## Os fades andam em [method _process], ou à mão por [method step] (testes).

## O som principal terminou sozinho (sem laço).
signal main_finished()

const SILENCE_DB := -80.0

## Volume do jogador para este canal: [code]volume.master × volume.<canal>[/code].
var player_volume: float = 1.0:
	set(v):
		player_volume = clampf(v, 0.0, 1.0)
		_refresh_all()

var _main: AudioStreamPlayer = null
## player → { node_volume, gain, from, to, t, duration, free_at_end, loop }
var _sounds: Dictionary = {}


func _init(channel_name: StringName = &"") -> void:
	name = String(channel_name).capitalize() if channel_name != &"" else "Channel"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	step(delta)


## Toca o som principal do canal. [param fade] é o fade de entrada e, se já
## houver um principal, o fade de saída dele (fade cruzado). Sem fade, o
## anterior para na hora.
func play_main(stream: AudioStream, loop: bool, node_volume: float = 1.0, fade: float = 0.0) -> AudioStreamPlayer:
	stop_main(fade)
	if stream == null:
		return null
	_main = _start(stream, loop, node_volume, fade, false)
	return _main


## Para o som principal, com fade de saída em segundos.
func stop_main(fade: float = 0.0) -> void:
	if _main == null:
		return
	var p := _main
	_main = null
	_fade_out(p, fade)


## Toca um som avulso (efeito sonoro, som de plugin), que se sobrepõe aos
## outros e é liberado ao terminar.
func play_one_shot(stream: AudioStream, node_volume: float = 1.0, loop: bool = false) -> AudioStreamPlayer:
	if stream == null:
		return null
	return _start(stream, loop, node_volume, 0.0, true)


## Para tudo o que toca no canal (principal e avulsos).
func stop_all(fade: float = 0.0) -> void:
	stop_main(fade)
	for p: AudioStreamPlayer in _sounds.keys():
		_fade_out(p, fade)


## O player do som principal, ou [code]null[/code].
func main_player() -> AudioStreamPlayer:
	return _main


## Há algum som saindo do canal (inclusive em fade de saída).
func is_active() -> bool:
	return not _sounds.is_empty()


## Players vivos do canal (principal, avulsos e os que estão saindo).
func players() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for p: AudioStreamPlayer in _sounds.keys():
		out.append(p)
	return out


## Volume linear que sai do player agora (jogador × nó × fade); 0 se não é deste canal.
func effective_volume(p: AudioStreamPlayer) -> float:
	if not _sounds.has(p):
		return 0.0
	var s: Dictionary = _sounds[p]
	return player_volume * float(s.node_volume) * float(s.gain)


## Avança os fades em [param delta] segundos.
func step(delta: float) -> void:
	for p: AudioStreamPlayer in _sounds.keys():
		var s: Dictionary = _sounds[p]
		if float(s.duration) <= 0.0 or float(s.t) >= float(s.duration):
			continue
		s.t = minf(float(s.t) + delta, float(s.duration))
		s.gain = lerpf(float(s.from), float(s.to), float(s.t) / float(s.duration))
		_apply(p)
		if float(s.t) >= float(s.duration) and s.free_at_end:
			_release(p)


func _start(stream: AudioStream, loop: bool, node_volume: float, fade: float, one_shot: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _with_loop(stream, loop)
	add_child(p)
	_sounds[p] = {
		"node_volume": clampf(node_volume, 0.0, 1.0),
		"gain": 0.0 if fade > 0.0 else 1.0,
		"from": 0.0, "to": 1.0, "t": 0.0,
		"duration": fade if fade > 0.0 else 0.0,
		"free_at_end": false, "loop": loop, "one_shot": one_shot,
	}
	_apply(p)
	p.finished.connect(_on_finished.bind(p))
	p.play()
	return p


func _fade_out(p: AudioStreamPlayer, fade: float) -> void:
	if not _sounds.has(p):
		return
	if fade <= 0.0:
		_release(p)
		return
	var s: Dictionary = _sounds[p]
	s.from = s.gain
	s.to = 0.0
	s.t = 0.0
	s.duration = fade
	s.free_at_end = true


func _on_finished(p: AudioStreamPlayer) -> void:
	if not _sounds.has(p):
		return
	# Streams sem propriedade de laço (WAV sem pontos de laço) recomeçam aqui.
	if _sounds[p].loop and not bool(_sounds[p].free_at_end):
		p.play()
		return
	var was_main := p == _main
	_release(p)
	if was_main:
		_main = null
		main_finished.emit()


func _release(p: AudioStreamPlayer) -> void:
	_sounds.erase(p)
	if p == _main:
		_main = null
	if is_instance_valid(p):
		p.stop()
		p.queue_free()


func _apply(p: AudioStreamPlayer) -> void:
	var v := effective_volume(p)
	p.volume_db = linear_to_db(v) if v > 0.0001 else SILENCE_DB


func _refresh_all() -> void:
	for p: AudioStreamPlayer in _sounds.keys():
		_apply(p)


## Cópia do stream com o laço pedido. OGG e MP3 têm [code]loop[/code]; WAV
## com pontos de laço usa [code]loop_mode[/code]. Sem nenhum dos dois, o laço
## é feito em [method _on_finished].
static func _with_loop(stream: AudioStream, loop: bool) -> AudioStream:
	if "loop" in stream:
		if bool(stream.get("loop")) == loop:
			return stream
		var s: AudioStream = stream.duplicate()
		s.set("loop", loop)
		return s
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		var wants := AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop and w.loop_end <= w.loop_begin:
			# Sem pontos de laço no import: o laço fica com _on_finished.
			if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				return stream
			wants = AudioStreamWAV.LOOP_DISABLED
		if w.loop_mode == wants:
			return stream
		var c := w.duplicate() as AudioStreamWAV
		c.loop_mode = wants
		return c
	return stream
