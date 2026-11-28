class_name VNAssetAPI
extends VNPluginService
## Assets do projeto por id (capacidade [code]assets.read[/code]; Plugin SDK §5.6).
##
## Todo id do projeto passa pelo filtro do modo stream na ponte (RT §5.5): o
## plugin recebe a substituta ou [code]null[/code] sem precisar fazer nada. Um asset
## escolhido pelo autor num campo [code]vn-asset[/code] da config ou dos params
## dispensa a capacidade (Plugin SDK §4.4).


## Carrega o asset do projeto [param asset_id]. Recursos do próprio plugin são
## carregados por [code]res://[/code] normal, não por aqui.
func load_asset(asset_id: String) -> Resource:
	if not _check_thread("assets.load_asset"):
		return null
	if asset_id.begins_with("res://"):
		_bridge.write_log(&"error", "assets.load_asset recebe ids de asset do projeto; use load() para %s" % asset_id)
		return null
	if not _bridge.has_capability(VNRuntimeSDK.CAP_ASSETS_READ) and not _bridge.is_author_chosen_asset(asset_id):
		_deny(VNRuntimeSDK.CAP_ASSETS_READ, "assets.load_asset")
		return null
	return _bridge.load_asset(asset_id)
