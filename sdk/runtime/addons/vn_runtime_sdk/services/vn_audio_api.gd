class_name VNAudioAPI
extends VNPluginService
## Áudio do plugin nos canais [code]sfx[/code] e [code]ambient[/code] (capacidade
## [code]audio.play[/code]; Plugin SDK §5.6). Música é do Narrative Engine.
##
## Ids de asset do projeto também pedem [code]assets.read[/code], salvo os escolhidos
## pelo autor num campo [code]vn-asset[/code] (Plugin SDK §4.4). Recursos próprios
## ficam em [code]res://vn_plugins/<namespace>/…[/code]. O filtro do modo stream
## é da ponte: asset oculto não toca e [method play] devolve [code]null[/code].

const CHANNELS: Array[StringName] = [&"sfx", &"ambient"]


## [param asset]: id de asset do projeto ou [code]res://vn_plugins/<ns>/…[/code].
## [param volume] vai de 0 a 1 (linear).
func play(asset: String, channel: StringName = &"sfx", volume: float = 1.0) -> VNSound:
	if not _check_thread("audio.play"):
		return null
	if not _bridge.has_capability(VNRuntimeSDK.CAP_AUDIO_PLAY):
		_deny(VNRuntimeSDK.CAP_AUDIO_PLAY, "audio.play")
		return null
	if not CHANNELS.has(channel):
		_bridge.write_log(&"error", "audio.play: canal inválido '%s' (sfx ou ambient)" % channel)
		return null
	if asset.begins_with("res://"):
		if not asset.begins_with("res://vn_plugins/%s/" % _ns):
			_bridge.write_log(&"error", "audio.play: %s não está em res://vn_plugins/%s/" % [asset, _ns])
			return null
	elif not _bridge.has_capability(VNRuntimeSDK.CAP_ASSETS_READ) and not _bridge.is_author_chosen_asset(asset):
		_deny(VNRuntimeSDK.CAP_ASSETS_READ, "audio.play")
		return null
	return _bridge.play_sound(asset, channel, clampf(volume, 0.0, 1.0))


## Para todos os sons deste plugin, com [param fade] segundos.
func stop_all(fade: float = 0.0) -> void:
	if not _check_thread("audio.stop_all"):
		return
	if not _bridge.has_capability(VNRuntimeSDK.CAP_AUDIO_PLAY):
		_deny(VNRuntimeSDK.CAP_AUDIO_PLAY, "audio.stop_all")
		return
	_bridge.stop_sounds(maxf(fade, 0.0))
