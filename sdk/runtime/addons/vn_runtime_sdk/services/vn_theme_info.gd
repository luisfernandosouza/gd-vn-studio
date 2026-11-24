class_name VNThemeInfo
extends RefCounted
## Aparência do projeto, somente leitura (Plugin SDK §5.7).
## Assinaturas do Plugin SDK §5.6–§5.7; a implementação chega com a tarefa M3-03.
## Até lá o serviço é inerte: devolve o valor vazio de cada método.

var resolution: Vector2i = Vector2i(1920, 1080)


## [code]&"dialogue"[/code], [code]&"name"[/code], [code]&"ui"[/code].
func font(_role: StringName) -> Font:
	return null


func font_size(_role: StringName) -> int:
	return 0


## [code]&"text"[/code], [code]&"accent"[/code], [code]&"panel"[/code], [code]&"disabled"[/code].
func color(_role: StringName) -> Color:
	return Color.WHITE
