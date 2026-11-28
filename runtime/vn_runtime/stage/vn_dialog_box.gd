class_name VNDialogBox
extends Control
## Caixa de diálogo do Stage (tarefa M2-03; RT §1.1 camada 30, §5.2
## "Digitação", §8.5 "Automático e pular", §10.1; UI Spec §4).
##
## Mostra a plaquinha de nome e a fala, digita o texto a [code]text_speed[/code]
## ([VNTextScript]) e trata a entrada do jogador na história:
##
## [codeblock]
## vn_advance  durante a digitação: completa a fala; depois: avança
## vn_skip     (segurar) pula as falas lidas
## vn_auto     liga/desliga o modo automático (ação toggle_auto)
## vn_hide     esconde/mostra a caixa; com ela escondida, vn_advance só a mostra
## vn_backlog  abre a tela backlog (ação open_backlog)
## [/codeblock]
##
## O modo automático conta [code]auto_delay[/code] a partir do fim da digitação
## (mais o fim da voz, se houver). Pular avança sem esperar e, com
## [code]skip_unread: false[/code], para no primeiro texto não lido (a fala traz
## [code]seen[/code], que o Narrative Engine calcula do [code]seen_text[/code]
## do perfil). Nada disso age com uma tela aberta, com o Engine pausado ou
## com uma atividade que captura a entrada.
##
## Quem cria a caixa é o [VNRuntimeStage]; ele repassa [signal advance_requested]
## como [signal VNStage.advanced].

## O jogador (ou o modo automático/pular) avançou a fala.
signal advance_requested()

## Intervalo entre falas no modo pular, em segundos (para dar para ver o que passa).
const SKIP_INTERVAL := 0.06
const FONT_SIZE := 36
const NAME_FONT_SIZE := 30
const MARGIN := 40.0
const DEFAULT_HEIGHT := 0.28
const DEFAULT_PADDING: Array[int] = [32, 24, 32, 24]  # esquerda, cima, direita, baixo
const PANEL_COLOR := Color(0.05, 0.05, 0.09, 0.82)
const INDICATOR := "▼"

var _stage_ref: WeakRef = null
var _panel: PanelContainer = null
var _plate: PanelContainer = null
var _name: Label = null
var _text: RichTextLabel = null
var _indicator: Label = null
var _theme_box: Dictionary = {}

var _script: VNTextScript = null
var _timeline := PackedFloat32Array()
var _duration := 0.0
var _elapsed := 0.0
var _complete := true
var _waiting := false       ## há fala na caixa esperando o jogador
var _seen := false
var _auto_elapsed := 0.0
var _skip_elapsed := 0.0
var _voice: AudioStreamPlayer = null
var _voice_done := true
var _blink := 0.0


func _init(stage: VNStage = null) -> void:
	name = "DialogBox"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if stage != null:
		_stage_ref = weakref(stage)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override(&"normal_font_size", FONT_SIZE)
	_text.add_theme_font_size_override(&"bold_font_size", FONT_SIZE)
	_text.add_theme_font_size_override(&"italics_font_size", FONT_SIZE)
	_panel.add_child(_text)
	_plate = PanelContainer.new()
	_plate.name = "NamePlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	_name = Label.new()
	_name.name = "Name"
	_name.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	_plate.add_child(_name)
	_indicator = Label.new()
	_indicator.name = "AdvanceIndicator"
	_indicator.text = INDICATOR
	_indicator.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_indicator)
	visible = false
	set_process(true)
	set_process_unhandled_input(true)


func _stage() -> VNRuntimeStage:
	return _stage_ref.get_ref() as VNRuntimeStage if _stage_ref != null else null


# --- Aparência ----------------------------------------------------------------

## Posição e tamanho da caixa na resolução base, a partir de
## [code]theme.json → textbox[/code] (UI Spec §7; o tema completo é da tarefa M2-07).
func layout(base_size: Vector2, textbox: Dictionary = {}) -> void:
	_theme_box = textbox
	position = Vector2.ZERO
	size = base_size
	var frac := clampf(float(textbox.get("height", DEFAULT_HEIGHT)), 0.1, 1.0)
	var h := base_size.y * frac
	var place := String(textbox.get("position", "bottom"))
	var rect := Rect2(MARGIN, base_size.y - h - MARGIN, base_size.x - 2.0 * MARGIN, h)
	match place:
		"top":
			rect.position.y = MARGIN
		"full_screen":
			rect = Rect2(0.0, 0.0, base_size.x, base_size.y)
	_panel.position = rect.position
	_panel.size = rect.size
	var pad: Array = textbox.get("padding", DEFAULT_PADDING)
	var sb := StyleBoxFlat.new()
	var bg := PANEL_COLOR
	bg.a = float(textbox.get("opacity", PANEL_COLOR.a))
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.content_margin_left = float(pad[0])
	sb.content_margin_top = float(pad[1])
	sb.content_margin_right = float(pad[2])
	sb.content_margin_bottom = float(pad[3])
	_panel.add_theme_stylebox_override(&"panel", sb)
	var plate_sb := StyleBoxFlat.new()
	plate_sb.bg_color = Color(bg.r, bg.g, bg.b, minf(1.0, bg.a + 0.1))
	plate_sb.set_corner_radius_all(8)
	plate_sb.content_margin_left = 20.0
	plate_sb.content_margin_right = 20.0
	plate_sb.content_margin_top = 6.0
	plate_sb.content_margin_bottom = 6.0
	_plate.add_theme_stylebox_override(&"panel", plate_sb)
	var off: Array = textbox.get("name_plate", {}).get("offset", [24, -28])
	_plate.position = rect.position + Vector2(float(off[0]), float(off[1]) - NAME_FONT_SIZE)
	_indicator.position = rect.position + rect.size - Vector2(64.0, 56.0)
	_apply_text_scale()


func _apply_text_scale() -> void:
	var scale := clampf(_number(&"text_scale", 1.0), 0.8, 2.0)
	var fs := int(round(FONT_SIZE * scale))
	for key in [&"normal_font_size", &"bold_font_size", &"italics_font_size"]:
		_text.add_theme_font_size_override(key, fs)


func plate_visible() -> bool:
	return _plate.visible


func name_text() -> String:
	return _name.text


func panel_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size)


# --- Fala ---------------------------------------------------------------------

## Mostra a fala e começa a digitar. [param speaker_name] vazio: narração (sem plaquinha).
func show_line(line: Dictionary, speaker_name: String, speaker_color: Variant) -> void:
	_stop_voice()
	var raw_text: Variant = line.get("text")
	_script = VNTextScript.parse(raw_text if raw_text is String else "")
	_apply_text_scale()
	_text.text = ""
	_text.parse_bbcode(_script.bbcode)
	_plate.visible = not speaker_name.is_empty()
	_name.text = VNUIText.strip_markup(speaker_name)
	var use_color: bool = bool(_theme_box.get("name_plate", {}).get("use_character_color", true))
	if use_color and speaker_color is Color:
		_name.add_theme_color_override(&"font_color", speaker_color)
	else:
		_name.remove_theme_color_override(&"font_color")
	_seen = line.get("seen") == true
	_elapsed = 0.0
	_auto_elapsed = 0.0
	_skip_elapsed = 0.0
	_waiting = true
	var cps := _text_speed()
	var s := _stage()
	var use_speed := s == null or not s.reduce_motion()
	_timeline = _script.timeline(cps, use_speed)
	_duration = _script.duration(cps, use_speed)
	_complete = cps <= 0.0 or _script.length() == 0
	_text.visible_characters = _script.length() if _complete else 0
	_indicator.visible = _complete
	var voice: Variant = line.get("voice")
	_play_voice(voice if voice is String else "")
	visible = true


## Esconde a caixa e esquece a fala (fim da fala, escolha, volta ao título).
func clear_line() -> void:
	_stop_voice()
	_waiting = false
	_complete = true
	_script = null
	_text.text = ""
	_name.text = ""
	_indicator.visible = false
	visible = false


## A fala atual está sendo digitada (ainda não apareceu inteira).
func is_typing() -> bool:
	return _waiting and not _complete


## Há uma fala na caixa esperando o jogador.
func is_waiting() -> bool:
	return _waiting


## Caracteres que já apareceram.
func visible_characters() -> int:
	return _text.visible_characters


## Texto visível da fala inteira (sem marcação).
func full_text() -> String:
	return _script.plain if _script != null else ""


## O que vn_advance faz: completa a fala; já completa, avança. Com a caixa
## escondida, só a mostra de novo.
func advance_input() -> void:
	if not _waiting:
		return
	var s := _stage()
	if s != null and s.is_textbox_hidden():
		s.set_textbox_hidden(false)
		return
	if not _complete:
		_finish_typing()
		return
	_advance()


func _finish_typing() -> void:
	_elapsed = _duration
	_complete = true
	_text.visible_characters = _script.length() if _script != null else 0
	_indicator.visible = true


func _advance() -> void:
	if not _waiting:
		return
	_waiting = false
	_stop_voice()
	_indicator.visible = false
	advance_requested.emit()


# --- Tempo: digitação, automático e pular --------------------------------------

func _process(delta: float) -> void:
	if not _waiting:
		return
	if not _complete:
		_elapsed += delta
		_text.visible_characters = VNTextScript.visible_at(_timeline, _elapsed, _script.length())
		if _elapsed >= _duration and _text.visible_characters >= _script.length():
			_complete = true
			_indicator.visible = true
	if _indicator.visible:
		_blink = fmod(_blink + delta, 1.0)
		_indicator.modulate.a = 1.0 if _blink < 0.6 else 0.35
	if _input_blocked():
		return
	var s := _stage()
	if s != null and s.is_textbox_hidden():
		return
	if _skipping():
		if _seen or _skip_unread():
			if not _complete:
				_finish_typing()
			_skip_elapsed += delta
			if _skip_elapsed >= SKIP_INTERVAL:
				_skip_elapsed = 0.0
				_advance()
			return
		# Texto não lido: o modo pular desliga e a fala segue normal.
		_stop_skip_mode()
	if _complete and _auto_mode() and not _voice_playing():
		_auto_elapsed += delta
		if _auto_elapsed >= _auto_delay():
			_auto_elapsed = 0.0
			_advance()


func _skipping() -> bool:
	var ui := _ui()
	return Input.is_action_pressed(&"vn_skip") or (ui != null and bool(ui.get(&"skip_mode")))


func _auto_mode() -> bool:
	var ui := _ui()
	return ui != null and bool(ui.get(&"auto_mode"))


func _stop_skip_mode() -> void:
	var ui := _ui()
	if ui != null and bool(ui.get(&"skip_mode")) and ui.has_method(&"set_play_mode"):
		ui.call(&"set_play_mode", _auto_mode(), false)


## Configuração numérica do jogador, ou o padrão do runtime (UI Spec §8) se faltar.
func _number(setting: StringName, fallback: float) -> float:
	var ui := _ui()
	var v: Variant = ui.get_setting(setting) if ui != null else null
	return float(v) if v is float or v is int else fallback


func _text_speed() -> float:
	return _number(&"text_speed", 40.0)


func _auto_delay() -> float:
	return _number(&"auto_delay", 1.5)


func _skip_unread() -> bool:
	var ui := _ui()
	return ui != null and bool(ui.get_setting(&"skip_unread"))


func _ui() -> VNUIManager:
	var s := _stage()
	if s == null or s.modules() == null:
		return null
	return s.modules().ui


## Tela aberta, Engine pausado ou atividade que captura a entrada: a história
## não avança por entrada nem por tempo.
func _input_blocked() -> bool:
	var s := _stage()
	if s == null or s.modules() == null:
		return false
	var m := s.modules()
	if m.ui != null:
		if not m.ui.screen_stack().is_empty():
			return true
		if m.ui.has_method(&"activity_captures_input") and bool(m.ui.call(&"activity_captures_input")):
			return true
	return m.engine != null and m.engine.is_paused()


# --- Voz ----------------------------------------------------------------------

func _play_voice(asset: String) -> void:
	var s := _stage()
	if asset.is_empty() or s == null or s.modules() == null or s.modules().audio == null:
		return
	_voice = s.modules().audio.play(asset, VNAudioManager.VOICE)
	_voice_done = _voice == null
	if _voice != null:
		_voice.finished.connect(func(): _voice_done = true, CONNECT_ONE_SHOT)


func _stop_voice() -> void:
	if _voice != null and is_instance_valid(_voice):
		_voice.stop()
	_voice = null
	_voice_done = true


## A voz da fala ainda não terminou (sinal [signal AudioStreamPlayer.finished]).
func _voice_playing() -> bool:
	return not _voice_done and _voice != null and is_instance_valid(_voice)


# --- Entrada ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _waiting or _input_blocked():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if not event.is_pressed() or event.is_echo():
			return
	else:
		return
	var s := _stage()
	var ui := _ui()
	if event.is_action_pressed(&"vn_hide"):
		if s != null:
			s.set_textbox_hidden(not s.is_textbox_hidden())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"vn_backlog"):
		if ui != null and ui.has_method(&"run_actions") and not (s != null and s.is_textbox_hidden()):
			ui.run_actions([{"do": "open_backlog"}])
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"vn_auto"):
		if ui != null:
			ui.run_actions([{"do": "toggle_auto"}])
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"vn_advance"):
		advance_input()
		get_viewport().set_input_as_handled()
