class_name VNSetHotspot
extends VNUIHotspot
## Hotspot cosmético de um set (UI Spec §5.1, §5.2; [code]set.schema.json →
## CosmeticHotspot[/code]). Igual ao [VNUIHotspot] da tela, com os três
## momentos do set: [signal VNUIHotspot.activated] ao apertar
## ([code]on_press[/code]), [signal released] ao soltar ([code]on_release[/code])
## e o [code]on_hover[/code], que o [VNSetView] liga a
## [signal Control.mouse_entered] e [signal Control.focus_entered]. Pelo
## teclado e pelo gamepad ([code]vn_confirm[/code]), apertar e soltar
## acontecem juntos.

## O botão do mouse (ou o toque) foi solto sobre o hotspot depois de apertá-lo.
signal released()

## Cursores prontos (UI Spec §5.2). Um nome pronto vence um asset de mesmo id
## ([code]set.schema.json → Cursor[/code]).
const CURSOR_NAMES: Array[String] = ["default", "look", "talk", "use", "walk"]

## id do hotspot no set.
var hotspot_id: String = ""
## Definição do hotspot ([code]sets/<id>.json → hotspots[][/code]).
var definition: Dictionary = {}
## Imagem do cursor quando [code]cursor[/code] é um asset.
var cursor_texture: Texture2D = null

var _pointer_down := false


func _ready() -> void:
	super._ready()
	mouse_entered.connect(_on_cursor_enter)
	mouse_exited.connect(_on_cursor_exit)


## O apertar em curso veio do mouse ou do toque (o soltar chega depois).
func pressed_by_pointer() -> bool:
	return _pointer_down


## Forma do cursor de [param cursor]: [code]default[/code] é a seta; os outros
## nomes prontos usam a mão do sistema até o tema ter imagens para eles; um
## asset vira cursor próprio enquanto o mouse está sobre a área.
func set_cursor(cursor: String, texture: Texture2D = null) -> void:
	cursor_texture = null
	if cursor == "default":
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not CURSOR_NAMES.has(cursor):
			cursor_texture = texture


func _gui_input(event: InputEvent) -> void:
	var press := false
	var release := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		press = event.pressed
		release = not event.pressed
	elif event is InputEventScreenTouch:
		press = event.pressed
		release = not event.pressed
	if press:
		accept_event()
		_pointer_down = true
		activated.emit()
	elif release and _pointer_down:
		accept_event()
		_pointer_down = false
		released.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE:
		if what != NOTIFICATION_MOUSE_EXIT:
			_on_cursor_exit()
		# Soltar fora da área não dispara on_release.
		_pointer_down = false


func _on_cursor_enter() -> void:
	if cursor_texture != null:
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_POINTING_HAND, cursor_texture.get_size() / 2.0)


func _on_cursor_exit() -> void:
	if cursor_texture != null:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
