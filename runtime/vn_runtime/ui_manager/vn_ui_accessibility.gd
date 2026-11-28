class_name VNUIAccessibility
extends RefCounted
## Acessibilidade mínima do v1 (Req §12; UI Spec §8): tamanho do texto de 80% a
## 200% ([code]text_scale[/code]), foco visível com [code]colors.focus[/code] do
## tema e alto contraste ([code]high_contrast[/code]: fundo opaco e texto com
## contraste de pelo menos 4,5:1). [code]reduce_motion[/code] fica com o Stage e o
## animador; as ações [code]vn_*[/code] com o [VNUIInput] e o [VNInputActions].
##
## Tudo aqui é estático e sem estado, para a caixa de diálogo, as telas e o
## minijogo usarem as mesmas contas.

const SCALE_MIN := 0.8
const SCALE_MAX := 2.0
## Contraste mínimo do texto sobre o painel (WCAG AA, texto normal).
const MIN_CONTRAST := 4.5
## [code]colors.focus[/code] quando o tema não define (o do preset classic).
const DEFAULT_FOCUS := Color("6aa9ff")
const FOCUS_BORDER := 4

const _BASE_META := &"vn_base_font_sizes"
const _FONT_SIZE_ITEMS := {
	"font_size": true, "normal_font_size": true, "bold_font_size": true,
	"italics_font_size": true, "bold_italics_font_size": true, "mono_font_size": true,
}


## O fator de escala dentro de 80%–200%.
static func clamp_scale(scale: float) -> float:
	return clampf(scale, SCALE_MIN, SCALE_MAX)


## Tamanho de fonte escalado, ao inteiro mais próximo e com mínimo de 1.
static func scaled_size(base: int, scale: float) -> int:
	return maxi(1, roundi(float(base) * clamp_scale(scale)))


## Aplica [param scale] ao texto de [param root] e dos filhos. O tamanho original
## de cada controle é guardado na primeira vez; chamar de novo parte sempre do
## original, então 200% e depois 100% volta ao tamanho do tema.
static func apply_text_scale(root: Node, scale: float) -> void:
	var s := clamp_scale(scale)
	if root is Control:
		_scale_control(root, s)
	for child in root.get_children():
		apply_text_scale(child, s)


## Esquece o tamanho base guardado de [param c] (o tema pôs um novo): a próxima
## [method apply_text_scale] parte dele.
static func forget_base(c: Control) -> void:
	if c.has_meta(_BASE_META):
		c.remove_meta(_BASE_META)


static func _scale_control(c: Control, scale: float) -> void:
	var bases: Dictionary = c.get_meta(_BASE_META, {})
	if bases.is_empty():
		for item in _FONT_SIZE_ITEMS:
			if c.has_theme_font_size(item):
				bases[item] = c.get_theme_font_size(item)
		if bases.is_empty():
			return
		c.set_meta(_BASE_META, bases)
	for item in bases:
		c.add_theme_font_size_override(item, scaled_size(int(bases[item]), scale))


# --- Foco visível -----------------------------------------------------------

## [code]theme.colors.focus[/code] ou o padrão do preset.
static func focus_color(theme: Dictionary) -> Color:
	var raw: Variant = theme.get("colors", {}).get("focus")
	if raw is String and Color.html_is_valid(raw):
		return Color.html(raw)
	return DEFAULT_FOCUS


## Moldura de foco: contorno de [constant FOCUS_BORDER] px na cor [param color],
## sem preencher, por cima do estilo normal.
static func focus_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(FOCUS_BORDER)
	sb.border_color = Color(color, 1.0)
	sb.set_corner_radius_all(6)
	sb.expand_margin_left = 2.0
	sb.expand_margin_right = 2.0
	sb.expand_margin_top = 2.0
	sb.expand_margin_bottom = 2.0
	return sb


## Dá a moldura de foco a todo controle focável de [param root] (botões, sliders,
## listas e o resto). [VNUIHotspot] desenha o próprio foco.
static func apply_focus_style(root: Node, color: Color) -> void:
	# Controles que o tema (VNUITheme) já estilizou têm a moldura própria, com a forma do estilo.
	if root is Control and root.focus_mode != Control.FOCUS_NONE and not root is VNUIHotspot \
			and not root.has_theme_stylebox_override(&"focus"):
		root.add_theme_stylebox_override(&"focus", focus_style(color))
	for child in root.get_children():
		apply_focus_style(child, color)


# --- Contraste e alto contraste ---------------------------------------------

## Luminância relativa (WCAG 2.x).
static func luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


## Razão de contraste (de 1 a 21) entre duas cores, sobre fundo opaco. A cor de
## cima, se tiver alfa, é composta sobre a de baixo.
static func contrast_ratio(fg: Color, bg: Color) -> float:
	var bg_opaque := Color(bg, 1.0)
	var top := bg_opaque.lerp(Color(fg, 1.0), fg.a)
	var l1 := luminance(top)
	var l2 := luminance(bg_opaque)
	return (maxf(l1, l2) + 0.05) / (minf(l1, l2) + 0.05)


## [code]true[/code] quando o texto sobre o painel passa dos 4,5:1 (o aviso do
## Menu Editor usa a mesma conta).
static func has_enough_contrast(text: Color, panel: Color) -> bool:
	return contrast_ratio(text, panel) >= MIN_CONTRAST


## Preto ou branco, o que contrasta mais com [param bg].
static func readable_on(bg: Color) -> Color:
	return Color.BLACK if contrast_ratio(Color.BLACK, bg) >= contrast_ratio(Color.WHITE, bg) else Color.WHITE


## Painel e texto da caixa de diálogo. Sem [param high_contrast] devolve as
## cores do tema como estão. Com ele, o painel fica opaco e, se a cor do texto
## não chegar a 4,5:1, vira preto ou branco (o que contrastar mais).
## Devolve [code]{"panel": Color, "text": Color}[/code].
static func dialog_colors(theme: Dictionary, high_contrast: bool) -> Dictionary:
	var colors: Dictionary = theme.get("colors", {})
	var panel := _color(colors.get("panel"), Color("101826d9"))
	var text := _color(colors.get("text"), Color.WHITE)
	if not high_contrast:
		return {"panel": panel, "text": text}
	panel = Color(panel, 1.0)
	if not has_enough_contrast(text, panel):
		text = readable_on(panel)
	return {"panel": panel, "text": text}


static func _color(raw: Variant, fallback: Color) -> Color:
	if raw is String and Color.html_is_valid(raw):
		return Color.html(raw)
	return fallback
