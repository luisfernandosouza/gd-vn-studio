class_name FakeAssets
extends VNAssets
## Dublê do VNAssets: ids → caminhos e recursos programados, com o modo stream
## pelas marcas de [member censored] ({ id → { replace_with } ou { hide: true } }).

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var paths: Dictionary = {}       # id → caminho res://
var resources: Dictionary = {}   # id → Resource
var censored: Dictionary = {}
var content_filter: bool = false
var assets_base: String = ""


func load_bundle(bundle: Dictionary) -> void:
	paths = bundle.get("assets", {}).duplicate()


func has_asset(asset_id: String) -> bool:
	return paths.has(asset_id) or resources.has(asset_id)


func resolve_id(asset_id: String) -> String:
	if not content_filter or not censored.has(asset_id):
		return asset_id
	var c: Dictionary = censored[asset_id]
	return "" if c.get("hide", false) else String(c.get("replace_with", asset_id))


func resolve_path(asset_id: String) -> String:
	var path: String = paths.get(asset_id, "")
	if not assets_base.is_empty() and path.begins_with("res://vn_content/assets/"):
		return assets_base.path_join(path.trim_prefix("res://vn_content/assets/"))
	return path


func load_asset(asset_id: String) -> Resource:
	_rec(&"load_asset", [asset_id])
	var id := resolve_id(asset_id)
	return resources.get(id) if not id.is_empty() else null


func set_assets_base(p_assets_base: String) -> void:
	assets_base = p_assets_base


func set_content_filter(enabled: bool) -> void:
	content_filter = enabled


func invalidate(asset_id: String = "") -> void:
	_rec(&"invalidate", [asset_id])
