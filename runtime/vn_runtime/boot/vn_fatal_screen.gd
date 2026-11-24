class_name VNFatalScreen
extends CanvasLayer
## Tela do erro fatal do boot (G001, G002; RT §3.0 passo 2, BS §13.1): a
## mensagem no idioma do jogador, na camada [constant VNLayers.SYSTEM], e o jogo
## fecha quando o jogador confirma. Não depende do tema nem do UI Manager,
## porque não há bundle.

## O jogador confirmou; o boot fecha o jogo com [constant EXIT_CODE].
signal acknowledged()

const EXIT_CODE := 1

var code: StringName
var text: String


static func create(p_code: StringName, locale: String) -> VNFatalScreen:
	var s := VNFatalScreen.new()
	s.code = p_code
	s.text = VNBootMessages.fatal_text(p_code, locale)
	s.layer = VNLayers.SYSTEM
	s.name = "VNFatalScreen"
	return s


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(960, 0)
	box.position = Vector2(-480, -80)
	box.add_theme_constant_override("separation", 32)
	bg.add_child(box)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	box.add_child(label)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(200, 56)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func(): acknowledged.emit())
	box.add_child(ok)
	ok.grab_focus.call_deferred()
