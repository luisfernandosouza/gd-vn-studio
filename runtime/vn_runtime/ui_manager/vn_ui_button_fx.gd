class_name VNUIButtonFx
extends RefCounted
## Efeitos de um botão estilizado (UI Spec §7.1): [code]hover[/code],
## [code]press[/code] e [code]focus[/code] (escala, deslocamento, rotação,
## tinta e brilho), animação [code]idle[/code] e sons. Fica no metadado
## [code]vn_fx[/code] do nó; reaplicar o estilo só troca a configuração.
##
## Com [code]reduce_motion[/code], escala, deslocamento, rotação e [code]idle[/code]
## não acontecem (UI Spec §7.3: só corte seco); a tinta muda sem transição.
## O deslocamento só vale fora de containers, que mandam na posição dos filhos.

const DEFAULT_DURATION := 0.1

var style: Dictionary = {}
var _node: Control
var _theme: VNUITheme
var _hover := false
var _focus := false
var _down := false
var _tween: Tween
var _idle: Tween
var _rest_pos := Vector2.ZERO
var _moved := false
var _last_duration := DEFAULT_DURATION


## Liga (ou reconfigura) os efeitos de [param node] com o estilo [param st].
static func attach(node: Control, st: Dictionary, theme: VNUITheme) -> VNUIButtonFx:
	var fx: VNUIButtonFx = node.get_meta(&"vn_fx") if node.has_meta(&"vn_fx") else null
	if fx == null:
		fx = VNUIButtonFx.new()
		fx._node = node
		node.set_meta(&"vn_fx", fx)
		fx._connect()
	fx.style = st
	fx._theme = theme
	fx._update()
	return fx


func _connect() -> void:
	var n := _node
	n.mouse_entered.connect(func(): _hover = true; _play(&"hover"); _update())
	n.mouse_exited.connect(func(): _hover = false; _down = false; _update())
	n.focus_entered.connect(func(): _focus = true; _update())
	n.focus_exited.connect(func(): _focus = false; _update())
	n.resized.connect(func(): n.pivot_offset = n.size / 2.0)
	n.gui_input.connect(_on_gui_input)
	if n is BaseButton:
		n.button_down.connect(func(): _down = true; _play(&"press"); _update())
		n.button_up.connect(func(): _down = false; _update())


func _on_gui_input(event: InputEvent) -> void:
	if _node is BaseButton and _node.disabled and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_theme.play_sound(_theme.sound_id(style, "disabled_press"))


func _disabled() -> bool:
	return _node is BaseButton and _node.disabled


func _play(kind: StringName) -> void:
	if _theme == null or _disabled():
		return
	_theme.play_sound(_theme.sound_id(style, String(kind)))


## O jogador chegou ao botão pelo teclado ou gamepad: toca o som de [code]hover[/code].
func navigated() -> void:
	_play(&"hover")


func _effect() -> Dictionary:
	if _disabled():
		return {}
	if _down and style.get("press") is Dictionary:
		return style.press
	if _hover and style.get("hover") is Dictionary:
		return style.hover
	if _focus and style.get("focus") is Dictionary:
		return style.focus
	return {}


func _is_image_style() -> bool:
	return style.get("image") is Dictionary and not style.image.is_empty()


## Com foco, a caixa do estado [code]focus[/code] do estilo (preenchimento, borda
## ou imagem de foco) toma o lugar da [code]normal[/code]; o anel de foco fica por cima.
func _update_focus_box() -> void:
	var key := &"vn_box_focus" if _focus and not _disabled() else &"vn_box_normal"
	if _node.has_meta(key):
		_node.add_theme_stylebox_override(&"normal", _node.get_meta(key))


## Leva o nó ao estado do efeito atual (ou de repouso).
func _update() -> void:
	if _node == null or not is_instance_valid(_node):
		return
	_update_focus_box()
	var eff := _effect()
	var tint := Color.WHITE
	if eff.has("tint"):
		tint = VNUITheme.color_of(eff.tint, Color.WHITE)
	if eff.has("glow") and _is_image_style():
		# Sem forma lisa para projetar sombra, o brilho vira um tom da cor do brilho.
		tint = tint.lerp(VNUITheme.color_of(eff.glow, Color.WHITE), 0.35)
	if _tween != null:
		_tween.kill()
		_tween = null
	var reduce := _theme != null and _theme.reduce_motion
	if reduce:
		stop_idle(false)
		_node.self_modulate = tint
		_node.scale = Vector2.ONE
		_node.rotation = 0.0
		return
	var moving := not eff.is_empty()
	if moving:
		stop_idle(false)
		_last_duration = float(eff.get("duration", DEFAULT_DURATION))
	var can_move := _node.get_parent() != null and not _node.get_parent() is Container
	if moving and can_move and not _moved:
		_rest_pos = _node.position
		_moved = true
	var scale_to := Vector2.ONE * float(eff.get("scale", 1.0))
	var rot_to := deg_to_rad(float(eff.get("rotation", 0.0)))
	var offset: Array = eff.get("offset", [0, 0])
	var tw := _node.create_tween()
	tw.set_parallel(true)
	tw.set_trans(VNUIAnimator.transition_of(String(eff.get("easing", "ease_out"))))
	tw.set_ease(VNUIAnimator.ease_of(String(eff.get("easing", "ease_out"))))
	var dur := maxf(0.0, _last_duration)
	tw.tween_property(_node, "scale", scale_to, dur)
	tw.tween_property(_node, "rotation", rot_to, dur)
	tw.tween_property(_node, "self_modulate", tint, dur)
	if can_move and _moved:
		tw.tween_property(_node, "position", _rest_pos + Vector2(float(offset[0]), float(offset[1])), dur)
		if not moving:
			_moved = false
	if not moving:
		tw.chain().tween_callback(start_idle)
	_tween = tw


## Começa a animação [code]idle[/code] do estilo, se houver e se nada mais estiver animando o botão.
func start_idle() -> void:
	stop_idle(false)
	if _node == null or not is_instance_valid(_node) or not _node.is_inside_tree():
		return
	if not style.get("idle") is Dictionary or (_theme != null and _theme.reduce_motion) or not _effect().is_empty():
		return
	_rest_pos = _node.position
	_idle = VNUIAnimator.play(_node, style.idle, false, false)


## Para o [code]idle[/code]; [param reset] devolve escala e rotação ao repouso.
func stop_idle(reset: bool = true) -> void:
	if _idle != null:
		_idle.kill()
		_idle = null
		if reset and is_instance_valid(_node):
			_node.scale = Vector2.ONE
			_node.rotation = 0.0


func is_idle_running() -> bool:
	return _idle != null and _idle.is_valid() and _idle.is_running()
