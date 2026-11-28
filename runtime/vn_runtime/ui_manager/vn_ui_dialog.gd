class_name VNUIDialog
extends Control
## Caixa de confirmação do tema e mensagem bloqueante (camada
## [constant VNLayers.SYSTEM]; UI Spec §4 [code]confirm[/code], RT §3.0).
## Bloqueia o clique nas camadas de baixo enquanto está aberta. O visual vem do
## tema ([method VNUITheme.style_dialog]).

signal answered(accepted: bool)

var buttons: Array[Button] = []
var label: RichTextLabel
## Painel da caixa (o tema troca o estilo dele).
var panel: PanelContainer


func setup(text: String, yes_text: String, no_text: String) -> void:
	name = "Dialog"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 24)
	panel.add_child(box)
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(640, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = VNUIText.to_bbcode(text)
	box.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 32)
	box.add_child(row)
	_add_button(row, yes_text, true)
	if not no_text.is_empty():
		_add_button(row, no_text, false)


func _add_button(row: HBoxContainer, text: String, value: bool) -> void:
	var b := Button.new()
	b.text = text
	b.name = "Yes" if value else "No"
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(160, 0)
	b.pressed.connect(answer.bind(value))
	row.add_child(b)
	buttons.append(b)


## Fecha com a resposta (uma vez só).
func answer(accepted: bool) -> void:
	if is_queued_for_deletion():
		return
	answered.emit(accepted)
	queue_free()


func focus_default() -> void:
	# Foco começa no "Não" (a escolha segura); numa mensagem, no único botão.
	if buttons.is_empty():
		return
	buttons[-1].grab_focus()


func move_focus(dir: int) -> void:
	var cur := buttons.find(get_viewport().gui_get_focus_owner())
	var i := clampi((cur if cur >= 0 else 0) + dir, 0, buttons.size() - 1)
	buttons[i].grab_focus()


func press_focused() -> void:
	var cur := buttons.find(get_viewport().gui_get_focus_owner())
	if cur >= 0:
		buttons[cur].pressed.emit()
	elif not buttons.is_empty():
		buttons[-1].pressed.emit()
