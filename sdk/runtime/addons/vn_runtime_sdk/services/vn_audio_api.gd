class_name VNAudioAPI
extends VNPluginService
## Áudio do plugin nos canais [code]sfx[/code]/[code]ambient[/code] (capacidade [code]audio.play[/code]).
## Assinaturas do Plugin SDK §5.6–§5.7; a implementação chega com a tarefa M3-03.
## Até lá o serviço é inerte: devolve o valor vazio de cada método.


## [param asset]: id de asset do projeto ou [code]res://vn_plugins/<ns>/…[/code].
func play(_asset: String, _channel: StringName = &"sfx", _volume: float = 1.0) -> VNSound:
	return null


func stop_all(_fade: float = 0.0) -> void:
	pass
