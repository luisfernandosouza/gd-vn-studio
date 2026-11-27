class_name VNUIHotspot
extends Control
## Elemento [code]hotspot[/code] de tela (UI Spec §3.1, §5.2): área clicável
## sem visual próprio. [code]rect[/code] e [code]polygon[/code] são frações da
## resolução base; a tela posiciona o nó sobre a área. Áreas [code]layer[/code]
## e [code]character[/code] dependem do set e do palco: quem as resolve é o
## Stage (M2-04, [VNStageInteraction]), que chama [method fit_rect] ou
## [method fit_mask]; sem isso o nó fica sem área. Alcançável por teclado e
## gamepad, com destaque no foco ou com [code]show_hotspots[/code].

signal activated()

var area: Dictionary = {}
var highlight: String = "outline"
## [code]PlayerSettings.show_hotspots[/code]: destaca sempre.
var show_always: bool = false
## Nome lido por teclado e acessibilidade.
var accessibility_label: String = ""
## Visível mas sem resposta ([code]enabled_if[/code] falso num nó [code]interact[/code]).
var disabled: bool = false:
	set(value):
		disabled = value
		modulate.a = 0.4 if value else 1.0
## Polígono em coordenadas locais, calculado por [method fit].
var _polygon: PackedVector2Array = []
## Máscara alfa (área [code]layer[/code]): só os pixels com alfa acima de zero respondem.
var _mask: Image = null
var _mask_scale := Vector2.ONE
var _hover: bool = false


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
## [code]character[/code]: o sprite da personagem no palco).
func fit_rect(rect: Rect2) -> void:
	_mask = null
	position = rect.position
	size = rect.size
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		_polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	else:
		_polygon = PackedVector2Array()   # retângulo vazio: sem área
	queue_redraw()


## Como [method fit_rect], mas só os pixels não transparentes de [param image]
## respondem (área [code]layer[/code]: máscara alfa da camada do set).
## [param image_scale] é o tamanho de um pixel da imagem na tela.
func fit_mask(rect: Rect2, image: Image, image_scale: Vector2) -> void:
	fit_rect(rect)
	_mask = image
	_mask_scale = image_scale


## A área tem forma (rect ou polygon resolvidos).
func has_area() -> bool:
	return _polygon.size() >= 3


func _has_point(point: Vector2) -> bool:
	if not has_area() or not Geometry2D.is_point_in_polygon(point, _polygon):
		return false
	if _mask != null:
		var px := Vector2i((point / _mask_scale).floor())
		if px.x < 0 or px.y < 0 or px.x >= _mask.get_width() or px.y >= _mask.get_height():
			return false
		return _mask.get_pixelv(px).a > 0.0
	return true


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
	var closed := _polygon.duplicate()
	closed.append(_polygon[0])
	match highlight:
		"tint":
			draw_colored_polygon(_polygon, Color(1, 1, 1, 0.18))
		"glow":
			draw_colored_polygon(_polygon, Color(1, 0.9, 0.5, 0.12))
			draw_polyline(closed, Color(1, 0.9, 0.5, 0.9), 3.0, true)
		_:
			draw_polyline(closed, Color(1, 1, 1, 0.9), 2.0, true)
