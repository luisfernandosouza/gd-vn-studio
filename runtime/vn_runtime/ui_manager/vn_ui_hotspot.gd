class_name VNUIHotspot
extends Control
## Elemento [code]hotspot[/code] de tela (UI Spec §3.1, §5.2): área clicável
## sem visual próprio. [code]rect[/code] e [code]polygon[/code] são frações da
## resolução base; a tela posiciona o nó sobre a área. Áreas [code]layer[/code]
## e [code]character[/code] dependem do set e do palco (tarefas M2-08 e
## M2-04): até lá o nó fica sem área. Alcançável por teclado e gamepad, com
## destaque no foco ou com [code]show_hotspots[/code].

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
## Polígono em coordenadas locais, calculado por [method fit].
var _polygon: PackedVector2Array = []
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


## A área tem forma (rect ou polygon resolvidos).
func has_area() -> bool:
	return _polygon.size() >= 3


func _has_point(point: Vector2) -> bool:
	return has_area() and Geometry2D.is_point_in_polygon(point, _polygon)


func _gui_input(event: InputEvent) -> void:
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
			var c := border_focus if has_focus() else border_hover
			draw_polyline(closed, c, border_width, true)
