class_name VNThemeInfo
extends RefCounted
## Aparência do projeto, somente leitura (Plugin SDK §5.7). Não pede capacidade.
##
## O overlay cobre [member resolution] com as âncoras do jogo; o minijogo
## DEVERIA usar estas fontes e cores para não destoar da VN. Papel desconhecido
## devolve o valor neutro ([code]null[/code], 0, branco).

const FONT_ROLES: Array[StringName] = [&"dialogue", &"name", &"ui"]
const COLOR_ROLES: Array[StringName] = [&"text", &"accent", &"panel", &"disabled"]

var _bridge: VNPluginBridge

## [code]project.json → settings.resolution[/code].
var resolution: Vector2i:
	get:
		return _bridge.theme_resolution()


func _init(bridge: VNPluginBridge = null) -> void:
	_bridge = bridge if bridge != null else VNPluginBridge.new()


## [code]&"dialogue"[/code], [code]&"name"[/code], [code]&"ui"[/code].
func font(role: StringName) -> Font:
	return _bridge.theme_font(role) if FONT_ROLES.has(role) else null


func font_size(role: StringName) -> int:
	return _bridge.theme_font_size(role) if FONT_ROLES.has(role) else 0


## [code]&"text"[/code], [code]&"accent"[/code], [code]&"panel"[/code], [code]&"disabled"[/code].
func color(role: StringName) -> Color:
	return _bridge.theme_color(role) if COLOR_ROLES.has(role) else Color.WHITE
