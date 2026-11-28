class_name VNCaptionView
extends CanvasLayer
## Legendas de sons (Req §12, [code]PlayerSettings.subtitles[/code]): uma linha
## por canal, no alto da tela, para não cobrir a caixa de fala.
##
## Fica na camada da caixa de texto ([constant VNLayers.TEXTBOX], RT §1.1) e só
## mostra o que o [VNRuntimeAudioManager] manda por
## [signal VNAudioManager.caption_changed]: o texto já vem traduzido, no modo
## atual, e só com [code]subtitles[/code] ligado. Texto vazio apaga a linha do
## canal. O visual é neutro (painel escuro, texto claro) até o UI Manager passar
## o tema do projeto por [method apply_theme] (M2-07): fonte e cores do tema, e
## painel opaco com [code]high_contrast[/code].

const MARGIN_TOP := 48.0
const FONT_SIZE := 30

var _box: VBoxContainer
var _labels: Dictionary = {}   # canal → Label
var _theme: VNUITheme = null


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


## Usa fonte, tamanho, cor do texto e painel do tema ([code]fonts.ui[/code],
## [code]colors[/code]); com [code]high_contrast[/code] o painel é opaco e o
## texto tem contraste de pelo menos 4,5:1. Vale também para as legendas já na tela.
func apply_theme(theme: VNUITheme) -> void:
	_theme = theme
	for label: Label in _labels.values():
		_style(label)


## Apaga todas as legendas.
func clear() -> void:
	for ch: StringName in _labels.keys():
		set_caption(ch, "")


func _make_label(channel: StringName) -> Label:
	var label := Label.new()
	label.name = String(channel).capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(label)
	return label


func _style(label: Label) -> void:
	var size := FONT_SIZE
	var color := Color(1, 1, 1)
	var fill := Color(0, 0, 0, 0.7)
	if _theme != null:
		var st := {"font_size": FONT_SIZE}
		label.add_theme_font_override(&"font", _theme.font_for(st))
		size = _theme.scaled(_theme.font_size_of(st))
		color = _theme.colors().text
		if _theme.high_contrast:
			fill = Color(0, 0, 0, 1.0)
			color = VNUITheme.ensure_contrast(color, fill)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	var panel := StyleBoxFlat.new()
	panel.bg_color = fill
	panel.set_content_margin_all(10)
	panel.set_corner_radius_all(6)
	label.add_theme_stylebox_override(&"normal", panel)


## Ordem fixa das linhas: a dos canais em [constant VNAudioManager.CHANNELS].
func _sort() -> void:
	var i := 0
	for ch in VNAudioManager.CHANNELS:
		if _labels.has(ch):
			_box.move_child(_labels[ch], i)
			i += 1
