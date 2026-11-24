class_name VNSound
extends RefCounted
## Som tocado por [method VNAudioAPI.play].
## Assinaturas do Plugin SDK §5.6–§5.7; a implementação chega com a tarefa M3-03.
## Até lá o serviço é inerte: devolve o valor vazio de cada método.


func stop(_fade: float = 0.0) -> void:
	pass


func is_playing() -> bool:
	return false
