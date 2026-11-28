class_name VNInputActions
extends RefCounted
## Ações de entrada [code]vn_*[/code] (RT §10.1; Plugin SDK §5.7). O runtime as
## registra no [InputMap] ao iniciar, se o projeto Godot ainda não as tiver
## (o Build System gera o [code]project.godot[/code] do export, BS §4.3, e o
## projeto do editor já traz todas). A lista é fechada no v1.

const ACTIONS: Array[StringName] = [
	&"vn_confirm", &"vn_cancel", &"vn_up", &"vn_down", &"vn_left", &"vn_right",
	&"vn_advance", &"vn_skip", &"vn_auto", &"vn_hide", &"vn_backlog", &"vn_menu",
	&"vn_quick_save", &"vn_quick_load",
]

const DEADZONE := 0.5


## Registra as ações que faltam, com as teclas, o mouse e o gamepad do RT §10.1.
## Uma ação que o projeto já tem fica como está. Devolve as que registrou.
static func ensure_registered() -> Array[StringName]:
	var added: Array[StringName] = []
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for ev in _default_events(action):
			InputMap.action_add_event(action, ev)
		added.append(action)
	return added


static func _default_events(action: StringName) -> Array[InputEvent]:
	match action:
		&"vn_confirm":
			return [_key(KEY_ENTER), _key(KEY_SPACE), _pad(JOY_BUTTON_A)]
		&"vn_cancel":
			return [_key(KEY_ESCAPE), _key(KEY_BACKSPACE), _mouse(MOUSE_BUTTON_RIGHT), _pad(JOY_BUTTON_B)]
		&"vn_up":
			return [_key(KEY_UP), _phys(KEY_W), _pad(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)]
		&"vn_down":
			return [_key(KEY_DOWN), _phys(KEY_S), _pad(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)]
		&"vn_left":
			return [_key(KEY_LEFT), _phys(KEY_A), _pad(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]
		&"vn_right":
			return [_key(KEY_RIGHT), _phys(KEY_D), _pad(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)]
		&"vn_advance":
			return [_key(KEY_ENTER), _key(KEY_SPACE), _mouse(MOUSE_BUTTON_LEFT), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _pad(JOY_BUTTON_A)]
		&"vn_skip":
			return [_key(KEY_CTRL), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
		&"vn_auto":
			return [_key(KEY_A), _pad(JOY_BUTTON_Y)]
		&"vn_hide":
			return [_key(KEY_H), _mouse(MOUSE_BUTTON_MIDDLE), _pad(JOY_BUTTON_X)]
		&"vn_backlog":
			return [_key(KEY_L), _key(KEY_PAGEUP), _mouse(MOUSE_BUTTON_WHEEL_UP), _pad(JOY_BUTTON_LEFT_SHOULDER)]
		&"vn_menu":
			return [_key(KEY_ESCAPE), _mouse(MOUSE_BUTTON_RIGHT), _pad(JOY_BUTTON_START)]
		&"vn_quick_save":
			return [_key(KEY_F5)]
		&"vn_quick_load":
			return [_key(KEY_F9)]
	return []


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e


## As letras WASD valem pela posição da tecla, não pelo layout (AZERTY etc.).
static func _phys(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
