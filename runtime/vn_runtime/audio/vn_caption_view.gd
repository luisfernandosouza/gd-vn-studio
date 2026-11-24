class_name VNCaptionView
extends CanvasLayer
## Legendas de sons (Req §12, [code]PlayerSettings.subtitles[/code]): uma linha
## por canal, no alto da tela, para não cobrir a caixa de fala.
##
## Fica na camada da caixa de texto ([constant VNLayers.TEXTBOX], RT §1.1) e só
## mostra o que o [VNRuntimeAudioManager] manda por
## [signal VNAudioManager.caption_changed]: o texto já vem traduzido, no modo
## atual, e só com [code]subtitles[/code] ligado. Texto vazio apaga a linha do
## canal. O visual é neutro (painel escuro, texto claro); o tema do projeto
## entra com a tarefa M2-07.

const MARGIN_TOP := 48.0
const FONT_SIZE := 30

var _box: VBoxContainer
var _labels: Dictionary = {}   # canal → Label


func _init() -> void:
	name = "Captions"
	layer = VNLayers.TEXTBOX
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_box = VBoxContainer.new()
	_box.name = "Lines"
	_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.position.y = MARGIN_TOP
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_box)


## Mostra (ou apaga, com texto vazio) a legenda do canal.
func set_caption(channel: StringName, text: String) -> void:
	if text.is_empty():
		if _labels.has(channel):
			(_labels[channel] as Label).queue_free()
			_labels.erase(channel)
		return
	var label: Label = _labels.get(channel)
	if label == null:
		label = _make_label(channel)
		_labels[channel] = label
		_box.add_child(label)
		_sort()
	label.text = text


## O texto mostrado para o canal ([code]""[/code] se não há legenda).
func caption(channel: StringName) -> String:
	var label: Label = _labels.get(channel)
	return label.text if label != null else ""


## Apaga todas as legendas.
func clear() -> void:
	for ch: StringName in _labels.keys():
		set_caption(ch, "")


func _make_label(channel: StringName) -> Label:
	var label := Label.new()
	label.name = String(channel).capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.7)
	panel.set_content_margin_all(10)
	panel.set_corner_radius_all(6)
	label.add_theme_stylebox_override(&"normal", panel)
	return label


## Ordem fixa das linhas: a dos canais em [constant VNAudioManager.CHANNELS].
func _sort() -> void:
	var i := 0
	for ch in VNAudioManager.CHANNELS:
		if _labels.has(ch):
			_box.move_child(_labels[ch], i)
			i += 1
