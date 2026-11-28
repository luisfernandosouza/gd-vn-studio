class_name VNCharacterAPI
extends VNPluginService
## Dados públicos de personagens (capacidade [code]characters.read[/code]; Plugin SDK §5.6).


## [code]{ id, name (localizado), color, expressions }[/code]; vazio se o id não existe.
## O modo stream e o idioma já estão aplicados pela ponte.
func get_character(id: String) -> Dictionary:
	if not _check_thread("characters.get_character"):
		return {}
	if not _bridge.has_capability(VNRuntimeSDK.CAP_CHARACTERS_READ):
		_deny(VNRuntimeSDK.CAP_CHARACTERS_READ, "characters.get_character")
		return {}
	return _bridge.character_data(id).duplicate(true)


func list_characters() -> PackedStringArray:
	if not _check_thread("characters.list_characters"):
		return PackedStringArray()
	if not _bridge.has_capability(VNRuntimeSDK.CAP_CHARACTERS_READ):
		_deny(VNRuntimeSDK.CAP_CHARACTERS_READ, "characters.list_characters")
		return PackedStringArray()
	return _bridge.character_ids()
