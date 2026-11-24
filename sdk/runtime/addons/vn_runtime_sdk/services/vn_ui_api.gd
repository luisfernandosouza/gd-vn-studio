class_name VNUIAPI
extends VNPluginService
## Camadas do plugin acima da UI narrativa (capacidade [code]ui.overlay[/code]).
## Assinaturas do Plugin SDK §5.6–§5.7; a implementação chega com a tarefa M3-03.
## Até lá o serviço é inerte: devolve o valor vazio de cada método.


func push_overlay(_scene: PackedScene) -> Node:
	return null


func pop_overlay(_node: Node) -> void:
	pass
