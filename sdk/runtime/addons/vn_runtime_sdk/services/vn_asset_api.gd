class_name VNAssetAPI
extends VNPluginService
## Assets do projeto por id (capacidade [code]assets.read[/code]; modo stream, §5.6).
## Assinaturas do Plugin SDK §5.6–§5.7; a implementação chega com a tarefa M3-03.
## Até lá o serviço é inerte: devolve o valor vazio de cada método.


## Recursos do próprio plugin são carregados por [code]res://[/code] normal.
func load_asset(_asset_id: String) -> Resource:
	return null
