class_name VNStageInteraction
extends RefCounted
## Escolhas e hotspots do Stage (tarefa M2-04; RT §5.2; UI Spec §6; DM §8.2).
##
## Desenha as opções de [code]choice[/code] como botões na camada da caixa de
## texto (30) e as áreas clicáveis de [code]interact[/code] na camada de
## hotspots (15), mais o botão de saída. Não decide nada: só avisa a escolha
## pelo sinal [signal selected], e o Narrative Engine aplica efeitos, [code]record[/code]
## e [code]goto[/code] (o Stage nunca altera variáveis nem escolhe cenas).
##
## [b]Entrada.[/b] Mouse e toque agem direto nos controles. Teclado e gamepad
## usam as ações [code]vn_*[/code]: a primeira direção ou confirmação só põe o
## foco no primeiro item (como as telas do UI Manager); depois, direções
## percorrem os itens na ordem recebida, com volta ao início, e
## [code]vn_confirm[/code] escolhe o focado. Itens desabilitados aparecem mas não
## recebem foco nem clique. Com uma tela da pilha do UI Manager ou uma caixa de
## confirmação aberta, a navegação fica a cargo delas.
##
## [b]Áreas[/b] ([code]area[/code] de [code]set.schema.json[/code]):
## [code]rect[/code] e [code]polygon[/code] em fração da área base;
## [code]layer[/code] é a máscara alfa da camada do set em cena;
## [code]character[/code] é o retângulo do sprite da personagem no palco
## (sem máscara alfa). Quem não acha a camada ou a personagem fica sem área
## (não aparece nem recebe foco).
##
## [b]Estilo.[/b] Os botões usam o estilo [code]choice[/code] (ou
## [code]theme.choices.style[/code]) do tema, com [code]extends[/code]; sem tema,
## os valores do preset [code]classic[/code]. Fontes por idioma, imagens de
## botão, animações de hover/press e [code]auto_shrink[/code] são do M2-07.

## O jogador escolheu a opção, o hotspot ou a saída.
signal selected(option_id: String)

## Id da saída de [code]interact[/code] quando o Narrative Engine não manda um
## (o cenário não dá id à saída; UI Spec §6).
const EXIT_ID := VNStage.EXIT_ID

const KIND_NONE := &""
const KIND_CHOICES := &"choices"
const KIND_HOTSPOTS := &"hotspots"

## Formas do ponteiro por nome de [code]cursor[/code] (UI Spec §5.2).
const CURSORS := {
	"default": Control.CURSOR_ARROW,
	"look": Control.CURSOR_HELP,
	"talk": Control.CURSOR_POINTING_HAND,
	"use": Control.CURSOR_POINTING_HAND,
	"walk": Control.CURSOR_MOVE,
}
const CURSOR_NAMES: Array[String] = ["default", "look", "talk", "use", "walk"]

## Valores do preset classic, usados quando o tema não traz o estilo.
const DEFAULT_STYLE := {
	"shape": "rounded", "radius": 10, "border_width": 2, "font_size": 28,
	"padding": [32, 14, 32, 14],
	"fill": {"normal": "#101826cc", "hover": "#22406acc", "pressed": "#0a1220cc",
		"disabled": "#10182666", "focus": "#22406acc"},
}
const DEFAULT_COLORS := {"text": "#ffffff", "accent": "#6aa9ff", "disabled": "#ffffff66"}
const PROMPT_FONT_SIZE := 30
const BUTTON_GAP := 14

## O Stage dono; referência fraca para não formar ciclo de [RefCounted].
var _stage_ref: WeakRef = null
var _stage: VNRuntimeStage:
	get:
		return _stage_ref.get_ref() as VNRuntimeStage if _stage_ref != null else null
var _theme: Dictionary = {}
var _choices_root: Control = null
var _hotspots_root: Control = null
var _input: _InputNode = null
var _kind: StringName = KIND_NONE
var _locked := false
var _prompt: String = ""
## Itens navegáveis na ordem de entrada: [Button] ou [VNUIHotspot].
var _items: Array[Control] = []
## id de cada item, no mesmo índice de [member _items].
var _ids: Array[String] = []
## Hotspots e a definição de cada um, para refazer a área quando o palco é redesenhado.
var _hotspot_nodes: Array[VNUIHotspot] = []
var _hotspot_defs: Array[Dictionary] = []
var _exit_button: Button = null
var _exit_id: String = ""


func _init(stage: VNRuntimeStage) -> void:
	_stage_ref = weakref(stage)


func set_theme(theme: Dictionary) -> void:
	_theme = theme


# --- Árvore ------------------------------------------------------------------

func attach(choices_layer: CanvasLayer, hotspots_layer: CanvasLayer) -> void:
	_choices_root = _make_root("Choices")
	choices_layer.add_child(_choices_root)
	_hotspots_root = _make_root("Interact")
	hotspots_layer.add_child(_hotspots_root)
	_input = _InputNode.new()
	_input.owner_ref = weakref(self)
	choices_layer.add_child(_input)


func detach() -> void:
	clear()
	for n: Node in [_choices_root, _hotspots_root, _input]:
		if n != null and is_instance_valid(n):
			n.free()
	_choices_root = null
	_hotspots_root = null
	_input = null


func _make_root(node_name: String) -> Control:
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = Vector2.ZERO
	c.size = _stage.base_size
	return c


## Tipo de interação na tela: [constant KIND_CHOICES], [constant KIND_HOTSPOTS] ou [constant KIND_NONE].
func kind() -> StringName:
	return _kind


## Ids dos itens navegáveis, na ordem (as opções ou os hotspots com área, mais a saída).
func item_ids() -> PackedStringArray:
	return PackedStringArray(_ids)


## O controle de um item pelo id (botão ou [VNUIHotspot]); [code]null[/code] se não há.
func item(option_id: String) -> Control:
	var i := _ids.find(option_id)
	return _items[i] if i >= 0 else null


func clear() -> void:
	Input.set_custom_mouse_cursor(null)
	for root: Control in [_choices_root, _hotspots_root]:
		if root == null:
			continue
		for c in root.get_children():
			root.remove_child(c)
			c.queue_free()
	_items.clear()
	_ids.clear()
	_hotspot_nodes.clear()
	_hotspot_defs.clear()
	_exit_button = null
	_exit_id = ""
	_kind = KIND_NONE
	_locked = false
	_prompt = ""


# --- Escolhas ----------------------------------------------------------------

## [param options]: [code][{ id, text, enabled }][/code], só as visíveis.
func show_choices(prompt: String, options: Array[Dictionary]) -> void:
	clear()
	_kind = KIND_CHOICES
	_prompt = prompt
	if _choices_root == null:
		for o in options:
			_ids.append(String(o.get("id", "")))
		return
	var layout := String(_theme.get("choices", {}).get("layout", "center"))
	var base := _stage.base_size
	var width := base.x * (0.5 if layout == "center" else 0.38)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", BUTTON_GAP)
	box.custom_minimum_size.x = width
	_choices_root.add_child(box)
	if not prompt.is_empty():
		box.add_child(_prompt_label(prompt, width, layout))
	var style_name := String(_theme.get("choices", {}).get("style", "choice"))
	for o in options:
		var id := String(o.get("id", ""))
		var b := _make_button(VNUIText.strip_markup(String(o.get("text", ""))), style_name, width)
		b.name = "Option_" + id
		var on: bool = bool(o.get("enabled", true))
		b.disabled = not on
		b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		b.pressed.connect(_select.bind(id, &"choice"))
		box.add_child(b)
		_items.append(b)
		_ids.append(id)
	box.size = box.get_combined_minimum_size()
	var avail := base.y * (1.0 - _textbox_height())
	var x := (base.x - box.size.x) / 2.0
	if layout == "list_left":
		x = base.x * 0.08
	elif layout == "list_right":
		x = base.x * 0.92 - box.size.x
	var y := maxf((avail - box.size.y) / 2.0, base.y * 0.02)
	if String(_theme.get("textbox", {}).get("position", "bottom")) == "top":
		y += base.y * _textbox_height()
	box.position = Vector2(x, y)


func _prompt_label(text: String, width: float, layout: String) -> Label:
	var l := Label.new()
	l.name = "Prompt"
	l.text = VNUIText.strip_markup(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	l.horizontal_alignment = {"list_left": HORIZONTAL_ALIGNMENT_LEFT, "list_right": HORIZONTAL_ALIGNMENT_RIGHT}.get(layout, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_size_override("font_size", PROMPT_FONT_SIZE)
	l.add_theme_color_override("font_color", _color("text"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _textbox_height() -> float:
	return clampf(float(_theme.get("textbox", {}).get("height", 0.28)), 0.0, 0.6)


# --- Hotspots ----------------------------------------------------------------

## [param hotspots]: [code][{ id, label, area, cursor?, highlight?, enabled }][/code]
## (só os visíveis e ainda não usados); [param exit_option]: [code]{ label, id? }[/code]
## ou vazio; [param prompt]: o texto de [code]interact.prompt[/code].
func show_hotspots(hotspots: Array[Dictionary], exit_option: Dictionary = {}, prompt: String = "") -> void:
	clear()
	_kind = KIND_HOTSPOTS
	_prompt = prompt
	var show_always := _show_hotspots_setting()
	for d in hotspots:
		var h := VNUIHotspot.new()
		var id := String(d.get("id", ""))
		var label := VNUIText.strip_markup(String(d.get("label", "")))
		h.name = "Hotspot_" + id
		h.highlight = String(d.get("highlight", "outline"))
		h.show_always = show_always
		h.accessibility_label = label
		h.tooltip_text = label
		h.disabled = not bool(d.get("enabled", true))
		h.focus_mode = Control.FOCUS_NONE if h.disabled else Control.FOCUS_ALL
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE if h.disabled else Control.MOUSE_FILTER_STOP
		_apply_cursor(h, d.get("cursor", "default"))
		h.activated.connect(_select.bind(id, &"click"))
		if _hotspots_root != null:
			_hotspots_root.add_child(h)
		_hotspot_nodes.append(h)
		_hotspot_defs.append(d)
	if not prompt.is_empty() and _hotspots_root != null:
		var l := _prompt_label(prompt, _stage.base_size.x * 0.6, "center")
		l.name = "Prompt"
		l.position = Vector2(_stage.base_size.x * 0.2, _stage.base_size.y * 0.04)
		_hotspots_root.add_child(l)
	if not exit_option.is_empty() and _hotspots_root != null:
		var width := _stage.base_size.x * 0.22
		var b := _make_button(VNUIText.strip_markup(String(exit_option.get("label", ""))),
				String(_theme.get("choices", {}).get("style", "choice")), width)
		b.name = "Exit"
		b.pressed.connect(_select.bind(String(exit_option.get("id", EXIT_ID)), &"click"))
		_hotspots_root.add_child(b)
		b.size = b.get_combined_minimum_size()
		var base := _stage.base_size
		b.position = Vector2(base.x * 0.96 - b.size.x, base.y * (1.0 - _textbox_height()) - b.size.y - base.y * 0.03)
		_exit_button = b
		_exit_id = String(exit_option.get("id", EXIT_ID))
	refit()


## Refaz a área de cada hotspot no palco atual (depois de mostrar, de redimensionar
## a janela ou de o cenário mudar).
func refit() -> void:
	if _kind != KIND_HOTSPOTS:
		return
	for i in _hotspot_nodes.size():
		_fit_hotspot(_hotspot_nodes[i], _hotspot_defs[i].get("area", {}))
	_rebuild_hotspot_items()


func _rebuild_hotspot_items() -> void:
	_items.clear()
	_ids.clear()
	for i in _hotspot_nodes.size():
		var h := _hotspot_nodes[i]
		if h.has_area():
			h.visible = true
			_items.append(h)
			_ids.append(String(_hotspot_defs[i].get("id", "")))
		else:
			h.visible = false   # sem camada ou personagem no palco: sem área
	if _exit_button != null:
		_items.append(_exit_button)
		_ids.append(_exit_id)


func _fit_hotspot(h: VNUIHotspot, area: Dictionary) -> void:
	h.area = area
	if area.has("rect") or area.has("polygon"):
		h.fit(Vector2.ZERO, _stage.base_size)
	elif area.has("character"):
		var r := _stage.character_rect(String(area.character))
		if r.size.x > 0.0 and r.size.y > 0.0:
			h.fit_rect(r)
		else:
			h.fit_rect(Rect2())
	elif area.has("layer"):
		var view := _stage.set_view()
		var m: Dictionary = view.layer_mask(String(area.layer)) if view != null else {}
		if m.is_empty():
			h.fit_rect(Rect2())
		else:
			h.set_mask(m.bitmap, m.rect, m.outlines)
	else:
		h.fit_rect(Rect2())


func _apply_cursor(h: Control, cursor: Variant) -> void:
	var name := String(cursor)
	if CURSOR_NAMES.has(name):
		h.mouse_default_cursor_shape = CURSORS[name]
		return
	h.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var tex := _stage.asset_texture(name)
	if tex != null:   # asset de imagem como cursor (UI Spec §5.2)
		h.mouse_entered.connect(func(): Input.set_custom_mouse_cursor(tex))
		h.mouse_exited.connect(func(): Input.set_custom_mouse_cursor(null))


func _show_hotspots_setting() -> bool:
	var m := _stage.modules()
	if m != null and m.ui != null:
		var v: Variant = m.ui.get_setting(&"show_hotspots")
		return v is bool and v
	return false


# --- Escolha feita -----------------------------------------------------------

func _select(option_id: String, source: StringName) -> void:
	if _locked or _kind == KIND_NONE:
		return
	var i := _ids.find(option_id)
	if i >= 0 and not _selectable_state(_items[i]):
		return   # item desabilitado: nunca vira escolha
	_locked = true
	var sound := String(_theme.get("sounds", {}).get("choice" if source == &"choice" else "click", ""))
	var m := _stage.modules()
	if not sound.is_empty() and m != null and m.audio != null:
		m.audio.play(sound)
	selected.emit(option_id)


# --- Teclado e gamepad -------------------------------------------------------

func _focus_owner() -> Control:
	for c in _items:
		if c != null and is_instance_valid(c) and c.has_focus():
			return c
	return null


## Habilitado (não olha a área, que depende do palco).
func _selectable_state(c: Control) -> bool:
	return not c.disabled if c is VNUIHotspot or c is Button else true


func _selectable(c: Control) -> bool:
	if c is VNUIHotspot:
		return not c.disabled and c.has_area()
	return c is Button and not c.disabled


## Trata uma ação [code]vn_*[/code]; devolve [code]true[/code] se consumiu o evento.
func handle_input(event: InputEvent) -> bool:
	if _kind == KIND_NONE or _locked or _items.is_empty() or not event.is_pressed():
		return false
	if _other_ui_open():
		return false
	var step := 0
	if event.is_action(&"vn_up") or event.is_action(&"vn_left"):
		step = -1
	elif event.is_action(&"vn_down") or event.is_action(&"vn_right"):
		step = 1
	elif event.is_action(&"vn_confirm") and not event.is_echo():
		pass
	else:
		return false
	var cur := _focus_owner()
	if cur == null:
		_focus_first()
		return true
	if step != 0:
		_move_focus(cur, step)
		return true
	if cur is VNUIHotspot:
		cur.activated.emit()
	elif cur is Button and not cur.disabled:
		cur.pressed.emit()
	return true


func _focus_first() -> void:
	for c in _items:
		if _selectable(c):
			c.grab_focus()
			return


func _move_focus(cur: Control, step: int) -> void:
	var n := _items.size()
	var i := _items.find(cur)
	for k in range(1, n + 1):
		var c := _items[posmod(i + step * k, n)]
		if _selectable(c):
			c.grab_focus()
			return


## Uma tela da pilha do UI Manager ou uma confirmação abertas ficam com a entrada.
func _other_ui_open() -> bool:
	var m := _stage.modules()
	if m == null or m.ui == null:
		return false
	if not m.ui.screen_stack().is_empty():
		return true
	if m.ui.has_method(&"open_dialogs") and not m.ui.open_dialogs().is_empty():
		return true
	return false


class _InputNode extends Node:
	var owner_ref: WeakRef = null

	func _ready() -> void:
		name = "InteractionInput"
		process_mode = Node.PROCESS_MODE_ALWAYS

	## Depois dos controles: um [Button] focado já trata o [code]ui_accept[/code] sozinho.
	func _unhandled_input(event: InputEvent) -> void:
		var o: VNStageInteraction = owner_ref.get_ref() if owner_ref != null else null
		if o != null and o.handle_input(event):
			get_viewport().set_input_as_handled()


# --- Estilo ------------------------------------------------------------------

func _color(key: String) -> Color:
	var colors: Dictionary = _theme.get("colors", {})
	return Color.from_string(String(colors.get(key, DEFAULT_COLORS.get(key, "#ffffff"))), Color.WHITE)


## O estilo com nome, com a cadeia [code]extends[/code] já fundida (o filho vence).
func resolved_style(style_name: String) -> Dictionary:
	var styles: Dictionary = _theme.get("styles", {})
	var chain: Array[Dictionary] = []
	var cur := style_name
	var guard := 0
	while styles.has(cur) and guard < 8:
		chain.push_front(styles[cur])
		cur = String(styles[cur].get("extends", ""))
		guard += 1
	var out := {}
	if chain.is_empty():
		out = DEFAULT_STYLE.duplicate(true)
	for d in chain:
		out = _merge(out, d)
	return out


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if out.get(k) is Dictionary and b[k] is Dictionary:
			out[k] = _merge(out[k], b[k])
		else:
			out[k] = b[k]
	return out


func _make_button(text: String, style_name: String, width: float) -> Button:
	var st := resolved_style(style_name)
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.x = width
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", int(st.get("font_size", 28)))
	var tc: Dictionary = st.get("text_color", {})
	for pair in [["normal", "font_color"], ["hover", "font_hover_color"], ["pressed", "font_pressed_color"],
			["focus", "font_focus_color"], ["disabled", "font_disabled_color"]]:
		var fallback := _color("disabled") if pair[0] == "disabled" else _color("text")
		b.add_theme_color_override(pair[1], Color.from_string(String(tc.get(pair[0], "")), fallback))
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, _box(st, state))
	var focus_box := _box(st, "focus")
	b.add_theme_stylebox_override("focus", focus_box)
	return b


func _box(st: Dictionary, state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var fill: Dictionary = st.get("fill", {})
	var border: Dictionary = st.get("border", {})
	var fill_color := Color.from_string(String(fill.get(state, fill.get("normal", "#101826cc"))), Color(0.06, 0.09, 0.15, 0.8))
	sb.bg_color = fill_color
	var bw := int(st.get("border_width", 0))
	sb.set_border_width_all(bw)
	var accent := _color("accent")
	var default_border := accent if state in ["focus", "hover"] else Color(1, 1, 1, 0.25)
	sb.border_color = Color.from_string(String(border.get(state, "")), default_border)
	if state == "focus":
		sb.draw_center = false
		if bw == 0:
			sb.set_border_width_all(2)
		sb.border_color = Color.from_string(String(border.get("focus", "")), accent)
	var shape := String(st.get("shape", "rect"))
	var r := int(st.get("radius", 0))
	if shape == "pill" or shape == "circle":
		r = 999
	elif shape == "rect":
		r = 0
	sb.set_corner_radius_all(r)
	var p: Array = st.get("padding", [24, 10, 24, 10])
	sb.content_margin_left = float(p[0])
	sb.content_margin_top = float(p[1])
	sb.content_margin_right = float(p[2])
	sb.content_margin_bottom = float(p[3])
	return sb
