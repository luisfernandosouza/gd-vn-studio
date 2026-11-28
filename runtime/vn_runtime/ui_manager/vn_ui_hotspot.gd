class_name VNUIHotspot
extends Control
## Elemento [code]hotspot[/code] de tela (UI Spec §3.1, §5.2): área clicável
## sem visual próprio. [code]rect[/code] e [code]polygon[/code] são frações da
## resolução base; a tela posiciona o nó sobre a área. Uma área
## [code]layer[/code] usa a máscara alfa da camada do set ([method set_mask],
## posta pelo [VNSetView] ou, num [code]interact[/code], pelo [VNStageInteraction]);
## [code]character[/code] é o retângulo do sprite no palco ([method fit_rect], posto
## pelo [VNStageInteraction]); sem isso o nó fica sem área. Alcançável por teclado e gamepad, com destaque no
## foco ou com [code]show_hotspots[/code].

signal activated()

var area: Dictionary = {}
var highlight: String = "outline"
## [code]PlayerSettings.show_hotspots[/code]: destaca sempre.
var show_always: bool = false
## Cores e largura do contorno do estilo [code]hotspot[/code] do tema (UI Spec §7.1).
var border_hover: Color = Color(1, 1, 1, 0.9)
var border_focus: Color = Color(0.42, 0.66, 1.0, 1.0)
var border_width: float = 2.0
## Nome lido por teclado e acessibilidade.
var accessibility_label: String = ""
## Visível mas sem resposta ([code]enabled_if[/code] falso num nó [code]interact[/code]).
var disabled: bool = false:
	set(value):
		disabled = value
		modulate.a = 0.4 if value else 1.0
## Polígono em coordenadas locais, calculado por [method fit].
var _polygon: PackedVector2Array = []
var _hover: bool = false
## Máscara alfa (área [code]layer[/code]): pixels da imagem, escala até o
## tamanho do nó e contornos já na escala do nó.
var _mask: BitMap = null
var _mask_scale := Vector2.ONE
var _outlines: Array[PackedVector2Array] = []


func _ready() -> void:
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Posiciona o nó sobre a área, dada a origem e o tamanho da área base.
func fit(origin: Vector2, base: Vector2) -> void:
	if area.has("rect"):
		var r: Array = area.rect
		position = origin + Vector2(r[0], r[1]) * base
		size = Vector2(r[2], r[3]) * base
		_polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	elif area.has("layer"):
		return   # posição e máscara vêm do set (set_mask)
	elif area.has("polygon"):
		var pts := PackedVector2Array()
		for p in area.polygon:
			pts.append(origin + Vector2(p[0], p[1]) * base)
		var bounds := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bounds = bounds.expand(p)
		position = bounds.position
		size = bounds.size
		_polygon = PackedVector2Array()
		for p in pts:
			_polygon.append(p - bounds.position)
	else:
		size = Vector2.ZERO
		_polygon = PackedVector2Array()
	queue_redraw()


## Posiciona o nó sobre um retângulo já em pixels da área base (área
## [code]character[/code]: o sprite da personagem no palco). Retângulo vazio: sem área.
func fit_rect(rect: Rect2) -> void:
	_mask = null
	_outlines.clear()
	position = rect.position
	size = rect.size
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		_polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	else:
		_polygon = PackedVector2Array()
	queue_redraw()


## Área [code]layer[/code] (UI Spec §5.2): o nó cobre a camada (posição e
## tamanho em coordenadas do pai) e só os pixels não transparentes de
## [param mask] contam. [code]null[/code] tira a área.
func set_mask(mask: BitMap, rect: Rect2, outlines: Array[PackedVector2Array] = []) -> void:
	_mask = mask
	position = rect.position
	size = rect.size
	_polygon = PackedVector2Array()
	_outlines.clear()
	if mask == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_mask = null
		queue_redraw()
		return
	var ms := Vector2(mask.get_size())
	_mask_scale = rect.size / ms
	for o in outlines:
		var pts := PackedVector2Array()
		for p in o:
			pts.append(p * _mask_scale)
		_outlines.append(pts)
	queue_redraw()


## A área tem forma (rect ou polygon resolvidos, ou a máscara de uma camada).
func has_area() -> bool:
	return _polygon.size() >= 3 or _mask != null


func _has_point(point: Vector2) -> bool:
	if _mask != null:
		var p := Vector2i((point / _mask_scale).floor())
		var ms := _mask.get_size()
		return p.x >= 0 and p.y >= 0 and p.x < ms.x and p.y < ms.y and _mask.get_bitv(p)
	return _polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, _polygon)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		activated.emit()
	elif event is InputEventScreenTouch and event.pressed:
		accept_event()
		activated.emit()


func _draw() -> void:
	if not has_area() or highlight == "none":
		return
	var lit := show_always or _hover or has_focus()
	if not lit:
		return
	if _mask != null:
		for o in _outlines:
			if o.size() < 3:
				continue
			var ring := o.duplicate()
			ring.append(o[0])
			# Contornos de máscara podem ser côncavos: só linhas, sem preencher.
			match highlight:
				"tint":
					draw_polyline(ring, Color(1, 1, 1, 0.5), 6.0, true)
				"glow":
					draw_polyline(ring, Color(1, 0.9, 0.5, 0.35), 8.0, true)
					draw_polyline(ring, Color(1, 0.9, 0.5, 0.9), 3.0, true)
				_:
					draw_polyline(ring, Color(1, 1, 1, 0.9), 2.0, true)
		return
	var closed := _polygon.duplicate()
	closed.append(_polygon[0])
	match highlight:
		"tint":
			draw_colored_polygon(_polygon, Color(1, 1, 1, 0.18))
		"glow":
			draw_colored_polygon(_polygon, Color(1, 0.9, 0.5, 0.12))
			draw_polyline(closed, Color(1, 0.9, 0.5, 0.9), 3.0, true)
		_:
			var c := border_focus if has_focus() else border_hover
			draw_polyline(closed, c, border_width, true)
