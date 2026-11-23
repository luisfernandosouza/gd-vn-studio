class_name FakeAudioManager
extends VNAudioManager
## Dublê do Audio Manager: guarda o que toca em cada canal, sem tocar nada.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var playing: Dictionary = {}   # canal → { asset, loop, volume }
var volumes: Dictionary = {MUSIC: 1.0, AMBIENT: 1.0, SFX: 1.0, VOICE: 1.0}
var content_filter: bool = false


func run_audio_node(node: Dictionary) -> void:
	_rec(&"run_audio_node", [node])
	var channel := StringName(node.get("channel", MUSIC))
	if node.get("action", "play") == "play":
		playing[channel] = {"asset": node.get("asset"), "loop": node.get("loop", channel in [MUSIC, AMBIENT]), "volume": node.get("volume", 1.0)}
	else:
		playing.erase(channel)
	if node.has("caption"):
		caption_changed.emit(channel, String(node.caption))


func play(asset: String, channel: StringName = SFX, volume: float = 1.0) -> AudioStreamPlayer:
	_rec(&"play", [asset, channel, volume])
	return null


func stop_channel(channel: StringName, fade: float = 0.0) -> void:
	_rec(&"stop_channel", [channel, fade])
	playing.erase(channel)


func stop_all(fade: float = 0.0) -> void:
	_rec(&"stop_all", [fade])
	playing.clear()


func set_channel_volume(channel: StringName, volume: float) -> void:
	volumes[channel] = clampf(volume, 0.0, 1.0)


func get_channel_volume(channel: StringName) -> float:
	return volumes.get(channel, 1.0)


func snapshot() -> Dictionary:
	var out := {}
	for ch in playing:
		out[String(ch)] = playing[ch].duplicate()
	return out


func restore(audio: Dictionary) -> void:
	_rec(&"restore", [audio])
	playing.clear()
	for ch in audio:
		playing[StringName(ch)] = audio[ch].duplicate()


func set_content_filter(enabled: bool) -> void:
	_rec(&"set_content_filter", [enabled])
	content_filter = enabled
