class_name VNCharacterAPI
extends VNPluginService
## Dados públicos de personagens (capacidade [code]characters.read[/code]).
## Assinaturas do Plugin SDK §5.6–§5.7; a implementação chega com a tarefa M3-03.
## Até lá o serviço é inerte: devolve o valor vazio de cada método.


## [code]{ id, name (localizado), color, expressions }[/code].
func get_character(_id: String) -> Dictionary:
	return {}


func list_characters() -> PackedStringArray:
	return PackedStringArray()
