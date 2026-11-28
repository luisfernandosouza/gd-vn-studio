class_name VNUITheme
extends RefCounted
## Tema do jogo (tarefa M2-07; UI Spec §7, Data Model §10.3,
## [code]theme.schema.json[/code]): estilos de botão com [code]extends[/code],
## fontes por idioma, [code]auto_shrink[/code], contraste ([code]high_contrast[/code])
## e a ligação dos efeitos de hover, press, foco, [code]idle[/code] e sons.
##
## Convive com [VNUIAccessibility] (M2-15): ela escala o texto ([code]text_scale[/code])
## e cuida das contas de contraste; o tema grava só o tamanho [i]base[/i] de cada
## controle e leva a escala em conta apenas para saber se o texto cabe
## ([code]auto_shrink[/code]).
##
## O tema do bundle já vem fundido com o do preset (RT §2). Este módulo não
## conhece o UI Manager: recebe só funções para carregar assets e tocar sons, e
## as configurações do jogador por propriedades ([member locale],
## [member text_scale], [member high_contrast], [member reduce_motion]).

## Estilo padrão de cada tipo de elemento (UI Spec §7.1).
const DEFAULT_STYLE := {
	"button": "button", "label": "label", "slider": "slider", "toggle": "toggle",
	"select": "select", "hotspot": "hotspot", "slot_grid": "slot", "gallery_grid": "slot",
}
## Fração da largura base que um botão sem [code]size[/code] pode ocupar antes
## de o [code]auto_shrink[/code] reduzir a fonte.
const AUTO_SHRINK_WIDTH := 0.4
## Menor tamanho que o [code]auto_shrink[/code] aceita, em fração do tamanho pedido.
const MIN_SHRINK_RATIO := 0.5
const MIN_FONT_SIZE := 8
## Contraste mínimo de texto com [code]high_contrast[/code] (Req §12): 4,5:1;
## texto desabilitado, 3:1.
const CONTRAST_TEXT := 4.5
const CONTRAST_DISABLED := 3.0
const DEFAULT_FONT_SIZE := 24
const STATES := ["normal", "hover", "pressed", "disabled", "focus"]

## Tema do bundle ([code]bundle.theme[/code]).
var data: Dictionary = {}
## [code]bundle.assets[/code] (para o [code]nine_slice[/code] das imagens).
var assets: Dictionary = {}
## Idioma atual (escolhe a fonte de reserva).
var locale: String = "en"
## [code]PlayerSettings.text_scale[/code].
var text_scale: float = 1.0
var high_contrast: bool = false
var reduce_motion: bool = false
## Resolução base ([code]settings.resolution[/code]).
var base_size: Vector2 = Vector2(1920, 1080)
## [code]func(asset_id: String) -> Texture2D[/code].
var texture_loader: Callable = Callable()
## [code]func(asset_id: String) -> Font[/code].
var font_loader: Callable = Callable()
## [code]func(asset_id: String)[/code]: toca um som de interface (canal sfx).
var sound_player: Callable = Callable()

var _resolved: Dictionary = {}
var _fonts: Dictionary = {}


func configure(theme_data: Dictionary, bundle_assets: Dictionary = {}) -> void:
	data = theme_data
	assets = bundle_assets
	_resolved.clear()
	_fonts.clear()


## Esvazia o cache de fontes (ao trocar de idioma ou recarregar assets).
func clear_font_cache() -> void:
	_fonts.clear()


# --- Estilos -----------------------------------------------------------------

## Estilo [param name] com a cadeia [code]extends[/code] já resolvida. Nome
## inexistente devolve um dicionário vazio. Um ciclo em [code]extends[/code]
## (erro U002 do validador) é cortado onde se repete.
func style(name: String) -> Dictionary:
	if name.is_empty():
		return {}
	if not _resolved.has(name):
		_resolved[name] = _resolve(name, [])
	return _resolved[name]


func _resolve(name: String, seen: Array) -> Dictionary:
	var styles: Dictionary = data.get("styles", {})
	if not styles.has(name) or seen.has(name):
		return {}
	seen.append(name)
	var own: Dictionary = styles[name]
	var parent: Dictionary = _resolve(String(own.extends), seen) if own.has("extends") else {}
	var out := _merge(parent, own)
	out["_name"] = name
	return out


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if k == "extends":
			continue
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = _merge(out[k], over[k])
		elif over[k] is Dictionary or over[k] is Array:
			out[k] = over[k].duplicate(true)
		else:
			out[k] = over[k]
	return out


## Nome do estilo do elemento: [code]style[/code] ou o padrão do tipo.
func style_name_of(def: Dictionary) -> String:
	return String(def.get("style", DEFAULT_STYLE.get(String(def.get("type", "")), "")))


# --- Cores -------------------------------------------------------------------

static func color_of(value: Variant, fallback: Color) -> Color:
	if value is String and not String(value).is_empty():
		return Color.html(String(value))
	return fallback


## Cores do tema com os padrões do preset.
func colors() -> Dictionary:
	var c: Dictionary = data.get("colors", {})
	return {
		"text": color_of(c.get("text"), Color.WHITE),
		"accent": color_of(c.get("accent"), Color("6aa9ff")),
		"panel": color_of(c.get("panel"), Color("101826d9")),
		"disabled": color_of(c.get("disabled"), Color("ffffff66")),
		"focus": color_of(c.get("focus"), color_of(c.get("accent"), Color("6aa9ff"))),
	}


static func opaque(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 1.0)


## Luminância relativa (WCAG 2.x); a conta é a de [VNUIAccessibility].
static func luminance(c: Color) -> float:
	return VNUIAccessibility.luminance(c)


## Razão de contraste (WCAG 2.x), de 1 a 21; a conta é a de [VNUIAccessibility].
static func contrast_ratio(a: Color, b: Color) -> float:
	return VNUIAccessibility.contrast_ratio(a, b)


## [param fg] se já tem [param minimum] de contraste sobre [param bg]; senão a
## cor mais próxima (na direção de branco ou preto, a que contrasta mais) que tem.
static func ensure_contrast(fg: Color, bg: Color, minimum: float = CONTRAST_TEXT) -> Color:
	if contrast_ratio(fg, bg) >= minimum:
		return fg
	var target := Color.WHITE if contrast_ratio(Color.WHITE, bg) >= contrast_ratio(Color.BLACK, bg) else Color.BLACK
	for i in range(1, 21):
		var c := Color(fg.r, fg.g, fg.b, 1.0).lerp(target, i / 20.0)
		if contrast_ratio(c, bg) >= minimum:
			return c
	return target


## Painel e texto da caixa de diálogo, com [member high_contrast] aplicado
## (fundo opaco, texto com contraste >= 4,5:1; Req §12).
func dialogue_colors() -> Dictionary:
	return VNUIAccessibility.dialog_colors(data, high_contrast)


func dialogue_panel_color() -> Color:
	return dialogue_colors().panel


func dialogue_text_color() -> Color:
	return dialogue_colors().text


# --- Fontes ------------------------------------------------------------------

## Ids das fontes de reserva do idioma: [code]fonts.fallbacks[/code] pelo idioma
## inteiro ([code]zh-Hans[/code]) ou pelo código da língua ([code]ja[/code]).
func fallback_ids(for_locale: String) -> Array:
	var fb: Dictionary = data.get("fonts", {}).get("fallbacks", {})
	for key in [for_locale, for_locale.split("-")[0]]:
		if fb.has(key) and fb[key] is Array:
			return fb[key]
	return []


## Fonte do estilo (ou [code]fonts.ui[/code]; no estilo [code]title_label[/code],
## [code]fonts.title[/code]) com a primeira reserva do idioma atual (UI Spec §7.2).
func font_for(st: Dictionary) -> Font:
	var id := String(st.get("font", ""))
	if id.is_empty():
		var fonts: Dictionary = data.get("fonts", {})
		id = String(fonts.get("title" if st.get("_name", "") == "title_label" else "ui", ""))
	var key := "%s|%s" % [id, locale]
	if _fonts.has(key):
		return _fonts[key]
	var base: Font = _load_font(id)
	var reserve: Array[Font] = []
	var ids := fallback_ids(locale)
	if not ids.is_empty():
		var f := _load_font(String(ids[0]))
		if f != null:
			reserve.append(f)
	var out: Font
	if base == null and reserve.is_empty():
		out = ThemeDB.fallback_font
	else:
		var v := FontVariation.new()
		v.base_font = base if base != null else ThemeDB.fallback_font
		v.fallbacks = reserve
		out = v
	_fonts[key] = out
	return out


func _load_font(id: String) -> Font:
	if id.is_empty() or not font_loader.is_valid():
		return null
	return font_loader.call(id) as Font


## Tamanho base da fonte do estilo. A escala do jogador ([member text_scale]) é
## aplicada depois por [VNUIAccessibility.apply_text_scale], a partir deste valor.
func font_size_of(st: Dictionary, kind: String = "ui") -> int:
	var fonts: Dictionary = data.get("fonts", {})
	return maxi(MIN_FONT_SIZE, int(st.get("font_size", fonts.get(kind + "_size", DEFAULT_FONT_SIZE))))


## Tamanho que o texto de base [param size] terá na tela, com [member text_scale].
func scaled(size: int) -> int:
	return VNUIAccessibility.scaled_size(size, text_scale)


## Maior tamanho [i]base[/i] de [param size] para baixo cujo texto, já com a
## escala do jogador, cabe em [param budget] pixels (até [constant MIN_SHRINK_RATIO]
## do tamanho pedido). Texto de várias linhas conta pela mais larga.
func shrink_to_fit(text: String, font: Font, size: int, budget: float) -> int:
	var floor_size := maxi(MIN_FONT_SIZE, int(round(size * MIN_SHRINK_RATIO)))
	var s := size
	while s > floor_size and _text_width(text, font, scaled(s)) > budget:
		s -= 1
	return s


static func _text_width(text: String, font: Font, size: int) -> float:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return widest


# --- Caixas de estilo --------------------------------------------------------

static func padding_of(st: Dictionary) -> Array:
	var p: Array = st.get("padding", [16, 8, 16, 8])
	return [float(p[0]), float(p[1]), float(p[2]), float(p[3])]


func _state_value(table: Variant, state: String) -> Variant:
	if not table is Dictionary:
		return null
	return table.get(state, table.get("normal"))


## Caixa do botão no estado [param state]: imagem com [code]nine_slice[/code]
## ou forma lisa ([code]shape[/code], [code]fill[/code], [code]border[/code]).
func stylebox(st: Dictionary, state: String) -> StyleBox:
	var pad := padding_of(st)
	var img: Variant = st.get("image")
	if img is Dictionary and not img.is_empty():
		var picked: Variant = _state_value(img, state)
		var id := "" if picked == null else String(picked)
		var tex: Texture2D = texture_loader.call(id) if not id.is_empty() and texture_loader.is_valid() else null
		if tex != null:
			var sb := StyleBoxTexture.new()
			sb.texture = tex
			var ns: Variant = assets.get(id, {}).get("nine_slice")
			if ns is Array and ns.size() == 4:
				sb.texture_margin_left = float(ns[0])
				sb.texture_margin_top = float(ns[1])
				sb.texture_margin_right = float(ns[2])
				sb.texture_margin_bottom = float(ns[3])
			_margins(sb, pad)
			return sb
	var cols := colors()
	var sb := StyleBoxFlat.new()
	var fill: Color = color_of(_state_value(st.get("fill"), state), cols.panel)
	var border: Color = color_of(_state_value(st.get("border"), state), Color(0, 0, 0, 0))
	if high_contrast:
		fill = opaque(fill)
		if border.a > 0.0:
			border = opaque(border)
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(st.get("border_width", 0)) if border.a > 0.0 else 0)
	var radius := 0
	match String(st.get("shape", "rounded")):
		"rect": radius = 0
		"rounded": radius = int(st.get("radius", 8))
		_: radius = 4096   # pill, circle: o Godot limita à metade do menor lado
	sb.set_corner_radius_all(radius)
	if state == "hover" and st.get("hover") is Dictionary and st.hover.has("glow"):
		sb.shadow_color = color_of(st.hover.glow, Color.WHITE)
		sb.shadow_size = 8
	_margins(sb, pad)
	return sb


static func _margins(sb: StyleBox, pad: Array) -> void:
	sb.content_margin_left = pad[0]
	sb.content_margin_top = pad[1]
	sb.content_margin_right = pad[2]
	sb.content_margin_bottom = pad[3]


## Anel de foco visível (Req §12): só a borda, em [code]colors.focus[/code] e
## com a espessura da M2-15, na forma do estilo. A caixa do estado
## [code]focus[/code] (preenchimento, borda, imagem) vai por baixo dele.
func focus_ring(st: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	var c: Color = colors().focus
	sb.border_color = opaque(c) if high_contrast else c
	sb.set_border_width_all(VNUIAccessibility.FOCUS_BORDER)
	var shape := String(st.get("shape", "rounded"))
	sb.set_corner_radius_all(4096 if shape in ["pill", "circle"] else (0 if shape == "rect" else int(st.get("radius", 8))))
	sb.expand_margin_left = 2
	sb.expand_margin_top = 2
	sb.expand_margin_right = 2
	sb.expand_margin_bottom = 2
	return sb


func _is_image_style(st: Dictionary) -> bool:
	return st.get("image") is Dictionary and not st.image.is_empty()


func _text_color(st: Dictionary, state: String) -> Color:
	var cols := colors()
	var table: Variant = st.get("text_color")
	var fallback: Color = cols.disabled if state == "disabled" else cols.text
	var c: Color = color_of(table.get(state, table.get("normal")) if table is Dictionary else null, fallback)
	if high_contrast and not _is_image_style(st):
		var fill: Variant = st.get("fill")
		var bg: Color = opaque(color_of(_state_value(fill, "pressed" if state == "pressed" else state), cols.panel))
		c = ensure_contrast(Color(c.r, c.g, c.b, 1.0), bg, CONTRAST_DISABLED if state == "disabled" else CONTRAST_TEXT)
	return c


# --- Aplicação nos nós -------------------------------------------------------

## Aplica o estilo de [param def] ao nó do elemento (e aos controles dentro
## dele). Idempotente: serve também para reaplicar depois de mudar uma
## configuração do jogador.
func apply_element(node: Control, def: Dictionary) -> void:
	var st := style(style_name_of(def))
	match String(def.get("type", "")):
		"button", "toggle":
			if node is BaseButton:
				apply_button(node, st)
		"select":
			for c in _descendants(node):
				if c is OptionButton:
					apply_button(c, st)
					var popup: PopupMenu = c.get_popup()
					popup.add_theme_font_override(&"font", font_for(st))
					popup.add_theme_font_size_override(&"font_size", font_size_of(st))
				elif c is Label:
					apply_plain_label(c, style("label"))
		"slider":
			for c in _descendants(node):
				if c is HSlider:
					apply_slider(c, st)
				elif c is Label:
					apply_plain_label(c, style("label"))
		"label":
			if node is RichTextLabel:
				apply_label(node, st, def)
		"slot_grid", "gallery_grid":
			for c in node.get_children():
				if c is BaseButton:
					apply_button(c, st)
		"backlog_list", "records_list", "licenses_list":
			for c in _descendants(node):
				if c is RichTextLabel:
					apply_label(c, style("label"), {})
		"hotspot":
			if node is VNUIHotspot:
				var border: Dictionary = st.get("border", {})
				node.border_hover = color_of(border.get("hover"), node.border_hover)
				node.border_focus = color_of(border.get("focus"), colors().focus)
				node.border_width = float(st.get("border_width", node.border_width))


static func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_descendants(c))
	return out


## Estilo de [Button], [CheckButton] e [OptionButton]: caixas por estado, anel
## de foco, fonte, cores, ícone, [code]auto_shrink[/code] e efeitos.
func apply_button(b: BaseButton, st: Dictionary) -> void:
	var normal_box := stylebox(st, "normal")
	b.set_meta(&"vn_box_normal", normal_box)
	b.set_meta(&"vn_box_focus", stylebox(st, "focus"))
	b.add_theme_stylebox_override(&"normal", normal_box)
	b.add_theme_stylebox_override(&"hover", stylebox(st, "hover"))
	b.add_theme_stylebox_override(&"pressed", stylebox(st, "pressed"))
	b.add_theme_stylebox_override(&"hover_pressed", stylebox(st, "pressed"))
	b.add_theme_stylebox_override(&"disabled", stylebox(st, "disabled"))
	b.add_theme_stylebox_override(&"focus", focus_ring(st))
	var font := font_for(st)
	var size := font_size_of(st)
	b.add_theme_font_override(&"font", font)
	for pair in [["font_color", "normal"], ["font_hover_color", "hover"], ["font_pressed_color", "pressed"],
			["font_hover_pressed_color", "pressed"], ["font_disabled_color", "disabled"], ["font_focus_color", "focus"]]:
		b.add_theme_color_override(StringName(pair[0]), _text_color(st, pair[1]))
	var outline: Variant = st.get("outline")
	if outline is Dictionary:
		b.add_theme_color_override(&"font_outline_color", color_of(outline.get("color"), Color.BLACK))
		b.add_theme_constant_override(&"outline_size", int(outline.get("size", 0)))
	if b is Button:
		size = _fit_button(b, st, font, size)
		_icon_position(b, st)
	b.add_theme_font_size_override(&"font_size", size)
	VNUIAccessibility.forget_base(b)
	VNUIButtonFx.attach(b, st, self)


func _fit_button(b: Button, st: Dictionary, font: Font, size: int) -> int:
	if not b.has_meta(&"vn_min_x"):
		b.set_meta(&"vn_min_x", b.custom_minimum_size.x)
	var min_x: float = b.get_meta(&"vn_min_x")
	b.custom_minimum_size.x = min_x
	b.clip_text = false
	b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if not bool(st.get("auto_shrink", false)) or b.text.is_empty():
		return size
	var pad := padding_of(st)
	var width := min_x if min_x > 0.0 else base_size.x * AUTO_SHRINK_WIDTH
	var budget: float = width - pad[0] - pad[2]
	if b.icon != null and String(st.get("icon_position", "left")) in ["left", "right"]:
		budget -= b.icon.get_width()
	var fitted := shrink_to_fit(b.text, font, size, budget)
	if _text_width(b.text, font, scaled(fitted)) > budget:
		# Nem no menor tamanho cabe: corta com reticências na largura do botão.
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size.x = width
	return fitted


func _icon_position(b: Button, st: Dictionary) -> void:
	var pos := String(st.get("icon_position", ""))
	if pos.is_empty() or b.icon == null:
		return
	match pos:
		"left":
			b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		"right":
			b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		"top":
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		"only":
			# Só o ícone; o texto vira dica, para o teclado e a acessibilidade ainda terem um nome.
			if not b.has_meta(&"vn_text"):
				b.set_meta(&"vn_text", b.text)
			var t: String = b.get_meta(&"vn_text")
			if b.tooltip_text.is_empty():
				b.tooltip_text = t
			b.text = ""
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Estilo de [RichTextLabel] ([code]label[/code] e listas).
func apply_label(l: RichTextLabel, st: Dictionary, def: Dictionary) -> void:
	var cols := colors()
	var font := font_for(st)
	var size := font_size_of(st)
	var table: Variant = st.get("text_color")
	var color: Color = color_of(table.get("normal") if table is Dictionary else null, cols.text)
	if def.has("size") and bool(st.get("auto_shrink", false)):
		size = shrink_to_fit(VNUIText.strip_markup(l.get_parsed_text()), font, size, float(def.size[0]))
	for f in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]:
		l.add_theme_font_override(f, font)
	for f in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"bold_italics_font_size", &"mono_font_size"]:
		l.add_theme_font_size_override(f, size)
	l.add_theme_color_override(&"default_color", color)
	VNUIAccessibility.forget_base(l)
	var outline: Variant = st.get("outline")
	if outline is Dictionary:
		l.add_theme_color_override(&"font_outline_color", color_of(outline.get("color"), Color.BLACK))
		l.add_theme_constant_override(&"outline_size", int(outline.get("size", 0)))
	elif high_contrast:
		# Sem fundo conhecido, o contorno de cor oposta garante a leitura.
		l.add_theme_color_override(&"font_outline_color", Color.BLACK if luminance(color) > 0.4 else Color.WHITE)
		l.add_theme_constant_override(&"outline_size", 4)
	else:
		l.remove_theme_constant_override(&"outline_size")
	var shadow: Variant = st.get("shadow")
	if shadow is Dictionary:
		l.add_theme_color_override(&"font_shadow_color", color_of(shadow.get("color"), Color(0, 0, 0, 0.6)))
		var off: Array = shadow.get("offset", [2, 2])
		l.add_theme_constant_override(&"shadow_offset_x", int(off[0]))
		l.add_theme_constant_override(&"shadow_offset_y", int(off[1]))


## Estilo de [Label] simples (rótulo de slider e de select).
func apply_plain_label(l: Label, st: Dictionary) -> void:
	l.add_theme_font_override(&"font", font_for(st))
	l.add_theme_font_size_override(&"font_size", font_size_of(st))
	VNUIAccessibility.forget_base(l)
	var table: Variant = st.get("text_color")
	l.add_theme_color_override(&"font_color", color_of(table.get("normal") if table is Dictionary else null, colors().text))


func apply_slider(s: HSlider, st: Dictionary) -> void:
	var cols := colors()
	var track := stylebox(st, "normal") as StyleBoxFlat
	if track != null:
		track.content_margin_top = 0.0
		track.content_margin_bottom = 0.0
		s.add_theme_stylebox_override(&"slider", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = opaque(cols.accent) if high_contrast else cols.accent
	grab.set_corner_radius_all(4)
	s.add_theme_stylebox_override(&"grabber_area", grab)
	s.add_theme_stylebox_override(&"grabber_area_highlight", grab)
	s.add_theme_stylebox_override(&"focus", focus_ring(st))


## Caixa de confirmação ou mensagem: painel do tema ([code]dialog.image[/code]
## ou a cor do painel) e botões no estilo [code]dialog.button_style[/code].
func style_dialog(d: VNUIDialog) -> void:
	var cfg: Dictionary = data.get("dialog", {})
	var sb: StyleBox = null
	var id := String(cfg.get("image", ""))
	if not id.is_empty() and texture_loader.is_valid():
		var tex: Texture2D = texture_loader.call(id)
		if tex != null:
			var t := StyleBoxTexture.new()
			t.texture = tex
			var ns: Variant = assets.get(id, {}).get("nine_slice")
			if ns is Array and ns.size() == 4:
				t.texture_margin_left = float(ns[0])
				t.texture_margin_top = float(ns[1])
				t.texture_margin_right = float(ns[2])
				t.texture_margin_bottom = float(ns[3])
			_margins(t, [32.0, 24.0, 32.0, 24.0])
			sb = t
	if sb == null:
		var f := StyleBoxFlat.new()
		f.bg_color = dialogue_panel_color()
		f.set_corner_radius_all(12)
		f.set_border_width_all(2)
		f.border_color = colors().accent
		_margins(f, [32.0, 24.0, 32.0, 24.0])
		sb = f
	d.panel.add_theme_stylebox_override(&"panel", sb)
	var bst := style(String(cfg.get("button_style", "button")))
	for b in d.buttons:
		apply_button(b, bst)
	apply_label(d.label, style("label"), {})
	d.label.add_theme_color_override(&"default_color", dialogue_text_color())


# --- Sons --------------------------------------------------------------------

## Som do estilo para [param kind] ([code]hover[/code], [code]press[/code],
## [code]disabled_press[/code]); sem ele, o som do tema ([code]sounds.hover[/code],
## [code]sounds.click[/code]).
func sound_id(st: Dictionary, kind: String) -> String:
	var own: Dictionary = st.get("sounds", {})
	if own.has(kind):
		return String(own[kind])
	var theme_sounds: Dictionary = data.get("sounds", {})
	match kind:
		"hover": return String(theme_sounds.get("hover", ""))
		"press": return String(theme_sounds.get("click", ""))
	return ""


func play_sound(id: String) -> void:
	if not id.is_empty() and sound_player.is_valid():
		sound_player.call(id)
