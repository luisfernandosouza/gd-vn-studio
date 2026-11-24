class_name VNProfileAPI
extends VNPluginService
## Dados de perfil e recordes (capacidade [code]profile.data[/code]; Plugin SDK §9.1).
## Assinaturas do Plugin SDK §9.1; a implementação chega com a tarefa M3-06.
## Até lá o serviço é inerte.


## [code]null[/code] se o plugin nunca gravou.
func get_data() -> Variant:
	return null


## JSON, até 64 KB.
func set_data(_data: Variant) -> VNResult:
	return VNResult.failure(VNRuntimeSDK.INVALID_STATE, "perfil indisponível")


## Posição alcançada (1…keep) ou 0.
func submit_record(_board: StringName, _score: float, _meta: Dictionary = {}) -> int:
	return 0


## [code][{ score, at, meta }][/code], já ordenado.
func get_records(_board: StringName) -> Array[Dictionary]:
	return []
