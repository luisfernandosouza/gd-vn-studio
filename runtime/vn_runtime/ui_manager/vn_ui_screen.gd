class_name VNUIScreen
extends Control
## Uma tela aberta (UI Spec §3): fundo, elementos posicionados, condições
## [code]visible_if[/code]/[code]enabled_if[/code] e foco por teclado/gamepad.
##
## Posição: [code]position[/code] é fração da resolução base, [code]pivot[/code]
## é fração do elemento (padrão [code][0.5, 0.5][/code]). A área base fica
## centrada na janela (RT §1.1); [code]anchor: edge[/code] mede a distância da
## borda mais próxima da janela, não da área base. Elementos dentro de
## [code]container[/code] ignoram [code]position[/code].

## O UI Manager que abriu a tela.
var manager: VNRuntimeUIManager
var screen_id: String = ""
var data: Dictionary = {}
## Resolução base ([code]project.settings.resolution[/code]).
var base_size: Vector2 = Vector2(1920, 1080)
## id → nó do elemento.
var elements: Dictionary = {}
## id → id do container pai ("" no topo).
var parents: Dictionary = {}
## id do elemento → ids na ordem de construção.
var order: PackedStringArray = []
## Nó do fundo ([code]background[/code]) ou o que guarda o set ([code]Set[/code]).
var backdrop: Control = null
## O set composto atrás dos elementos ([code]set[/code], M2-08), ou [code]null[/code].
var set_view: VNSetView = null
var _set_view_size := Vector2.ZERO
## Elemento que tinha o foco quando a tela perdeu o topo da pilha.
var last_focus: Control = null


func setup(p_manager: VNRuntimeUIManager, p_id: String, p_data: Dictionary, p_base: Vector2) -> void:
	manager = p_manager
	screen_id = p_id
	data = p_data
	base_size = p_base
	name = "Screen_" + p_id
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP if p_id != "hud" else Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	if data.has("background"):
		var bg := TextureRect.new()
		bg.name = "Background"
		bg.texture = load_texture(String(data.background))
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		backdrop = bg
	elif data.has("set"):
		var holder := Control.new()
		holder.name = "Set"
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.clip_contents = true
		holder.set_meta(&"vn_set", String(data.set))
		add_child(holder)
		backdrop = holder
		set_view = manager.make_set_view(String(data.set), base_size, view_size())
		if set_view != null:
			holder.add_child(set_view)
			_set_view_size = view_size()
	for def in data.get("elements", []):
		add_child(add_element(def, ""))
	resized.connect(layout)


## Cria o nó do elemento e o registra (chamado também pelos containers).
func add_element(def: Dictionary, parent_id: String) -> Control:
	var id := String(def.get("id", ""))
	parents[id] = parent_id
	order.append(id)
	var node := VNUIElements.build(self, def)
	elements[id] = node
	manager.theme_model().apply_element(node, def)
	return node


## Reaplica o tema a todos os elementos (mudou texto maior, alto contraste,
## movimento reduzido), sem refazer a tela: o foco e os controles seguem iguais.
func restyle() -> void:
	var theme := manager.theme_model()
	for id in order:
		theme.apply_element(elements[id], definition(id))
	layout()
	start_idle()


## Liga as animações [code]idle[/code] dos botões estilizados.
func start_idle() -> void:
	for fx in _fx_of(self):
		fx.start_idle()


func _fx_of(node: Node) -> Array[VNUIButtonFx]:
	var out: Array[VNUIButtonFx] = []
	if node.has_meta(&"vn_fx"):
		out.append(node.get_meta(&"vn_fx"))
	for c in node.get_children():
		out.append_array(_fx_of(c))
	return out


## Foco por navegação (teclado, gamepad): leva o foco e toca o som de hover do estilo.
func _navigate_to(c: Control) -> void:
	c.grab_focus()
	if c.has_meta(&"vn_fx"):
		c.get_meta(&"vn_fx").navigated()


## Texto de um campo do elemento: caminho [code]ui/<tela>/<elemento>[/suffix][/code].
func text_of(def: Dictionary, suffix: String, fallback: String) -> String:
	var path := "ui/%s/%s" % [screen_id, def.get("id", "")]
	if not suffix.is_empty():
		path += "/" + suffix
	return manager.text(path, fallback)


func load_texture(asset_id: String) -> Texture2D:
	return manager.load_texture(asset_id)


func slot_thumbnail(slot: StringName, info: Dictionary) -> Texture2D:
	return manager.slot_thumbnail(slot, info)


## Clique ou confirmação no elemento.
func activate(element_id: String) -> void:
	manager.element_activated(self, element_id)


## Ações [code]on_hover[/code] de hotspot.
func hover(element_id: String) -> void:
	var def: Dictionary = definition(element_id)
	if def.has("on_hover") and is_element_enabled(element_id):
		manager.run_actions(def.on_hover, {"screen": screen_id, "element": element_id, "list": "on_hover"})


func change_setting(_element_id: String, setting: String, value: Variant) -> void:
	manager.set_setting(StringName(setting), value)


func definition(element_id: String) -> Dictionary:
	var node: Control = elements.get(element_id)
	return node.get_meta(&"vn_def", {}) if node != null else {}


# --- Condições ---------------------------------------------------------------

## Reavalia [code]visible_if[/code] e [code]enabled_if[/code] de todos os elementos.
func refresh() -> void:
	for id in order:
		var node: Control = elements[id]
		var def: Dictionary = node.get_meta(&"vn_def")
		if not node.has_meta(&"vn_hidden_by_action"):
			node.visible = not def.has("visible_if") or manager.check(def.visible_if)
		var enabled := _enabled_chain(id)
		var fc := VNUIElements.focus_control(node)
		if node is GridContainer and String(def.get("type", "")) in ["slot_grid", "gallery_grid"]:
			for c in node.get_children():
				if c is BaseButton:
					c.disabled = not enabled or c.has_meta(&"vn_locked")
			continue
		if fc is BaseButton:
			fc.disabled = not enabled or fc.has_meta(&"vn_locked")
		elif fc is Range:
			fc.editable = enabled
		elif fc != null:
			fc.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		if fc != null:
			fc.focus_mode = Control.FOCUS_ALL if enabled or fc is BaseButton else Control.FOCUS_NONE
	_apply_focus_neighbors()
	layout()


func _enabled_chain(id: String) -> bool:
	var cur := id
	while not cur.is_empty():
		var def: Dictionary = definition(cur)
		if def.has("enabled_if") and not manager.check(def.enabled_if):
			return false
		cur = parents.get(cur, "")
	return true


## O elemento está visível (ele e todos os containers acima).
func is_element_visible(element_id: String) -> bool:
	var cur := element_id
	while not cur.is_empty():
		var node: Control = elements.get(cur)
		if node == null or not node.visible:
			return false
		cur = parents.get(cur, "")
	return true


## Visível e habilitado: o jogador pode acioná-lo.
func is_element_enabled(element_id: String) -> bool:
	return is_element_visible(element_id) and _enabled_chain(element_id)


# --- Ações cosméticas sobre elementos (UI Spec §4) ---------------------------

func set_element_visible(element_id: String, show: Variant) -> bool:
	var node: Control = elements.get(element_id)
	if node == null:
		return false
	var v: bool = (not node.visible) if show == null else bool(show)
	node.visible = v
	node.set_meta(&"vn_hidden_by_action", true)
	layout()
	return true


# --- Layout -----------------------------------------------------------------

## Tamanho da área visível, em pixels da resolução base.
func view_size() -> Vector2:
	var s := size
	if s.x <= 0 or s.y <= 0:
		s = get_viewport_rect().size if is_inside_tree() else base_size
	return s


func layout() -> void:
	var view := view_size()
	var origin := (view - base_size) / 2.0
	if set_view != null:
		if view != _set_view_size:
			_set_view_size = view
			set_view.view_size = view
			set_view.relayout()
		set_view.position = origin
	for id in order:
		if not parents.get(id, "").is_empty():
			continue
		var node: Control = elements[id]
		var def: Dictionary = node.get_meta(&"vn_def")
		if node is VNUIHotspot:
			node.fit(origin, base_size)
			continue
		var frac: Array = def.get("position", [0.5, 0.5])
		var piv: Array = def.get("pivot", [0.5, 0.5])
		var sz := node.custom_minimum_size if def.has("size") else node.get_combined_minimum_size()
		node.size = sz
		var p: Vector2
		if String(def.get("anchor", "stretch")) == "edge":
			var fx := float(frac[0])
			var fy := float(frac[1])
			p.x = fx * base_size.x if fx <= 0.5 else view.x - (1.0 - fx) * base_size.x
			p.y = fy * base_size.y if fy <= 0.5 else view.y - (1.0 - fy) * base_size.y
		else:
			p = origin + Vector2(float(frac[0]), float(frac[1])) * base_size
		node.position = p - Vector2(float(piv[0]), float(piv[1])) * sz


# --- Foco (UI Spec §1 princípio 4, §3.1 focus) -------------------------------

## Controles que podem receber foco agora, na ordem dos elementos.
func focusables() -> Array[Control]:
	var out: Array[Control] = []
	for id in order:
		var fc := VNUIElements.focus_control(elements[id])
		if fc != null and is_element_visible(id) and fc.focus_mode != Control.FOCUS_NONE and not (fc is BaseButton and fc.disabled):
			out.append(fc)
		elif elements[id] is GridContainer or elements[id] is ScrollContainer:
			for c in _grid_focusables(elements[id]):
				if is_element_visible(id):
					out.append(c)
	# Hotspots do set: depois dos elementos, na ordem do set (UI Spec §1, princípio 4).
	if set_view != null:
		for h in set_view.hotspot_nodes():
			if h.has_area() and h.is_visible_in_tree() and h.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				out.append(h)
	return out


func _grid_focusables(node: Control) -> Array[Control]:
	var out: Array[Control] = []
	if node is GridContainer:
		for c in node.get_children():
			if c is BaseButton and not c.disabled and not out.has(c) and c != VNUIElements.focus_control(node):
				out.append(c)
	return out


func _apply_focus_neighbors() -> void:
	for id in order:
		var def: Dictionary = definition(id)
		var fc := VNUIElements.focus_control(elements[id])
		if fc == null or not def.has("focus"):
			continue
		for side in ["up", "down", "left", "right"]:
			if def.focus.has(side):
				var target := VNUIElements.focus_control(elements.get(String(def.focus[side])))
				if target != null:
					var prop: String = "focus_neighbor_" + {"up": "top", "down": "bottom", "left": "left", "right": "right"}[side]
					fc.set(prop, fc.get_path_to(target))


## Põe o foco em [code]focus_start[/code] (ou no primeiro elemento focável).
func focus_first() -> void:
	if last_focus != null and is_instance_valid(last_focus) and last_focus.is_visible_in_tree():
		last_focus.grab_focus()
		return
	var start := String(data.get("focus_start", ""))
	if not start.is_empty() and elements.has(start):
		var fc := VNUIElements.focus_control(elements[start])
		if fc == null:
			fc = _first_focusable_in(start)
		if fc != null and fc.is_visible_in_tree() and fc.focus_mode != Control.FOCUS_NONE and not (fc is BaseButton and fc.disabled):
			fc.grab_focus()
			return
	var all := focusables()
	if not all.is_empty():
		all[0].grab_focus()


func _first_focusable_in(container_id: String) -> Control:
	for id in order:
		var cur := String(parents.get(id, ""))
		while not cur.is_empty() and cur != container_id:
			cur = parents.get(cur, "")
		if cur != container_id:
			continue
		var fc := VNUIElements.focus_control(elements[id])
		if fc != null and is_element_enabled(id) and fc.is_visible_in_tree():
			return fc
	return null


## Move o foco na direção (vn_up/down/left/right): vizinho de [code]focus[/code],
## senão o mais próximo naquela direção pela posição.
func move_focus(dir: Vector2) -> void:
	var cur := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var all := focusables()
	if all.is_empty():
		return
	if cur == null or not all.has(cur):
		focus_first()
		return
	var prop := ""
	if dir == Vector2.UP: prop = "focus_neighbor_top"
	elif dir == Vector2.DOWN: prop = "focus_neighbor_bottom"
	elif dir == Vector2.LEFT: prop = "focus_neighbor_left"
	else: prop = "focus_neighbor_right"
	var np: NodePath = cur.get(prop)
	if not np.is_empty():
		var n := cur.get_node_or_null(np) as Control
		if n != null and all.has(n):
			_navigate_to(n)
			return
	var from := cur.get_global_rect().get_center()
	var best: Control = null
	var best_score := INF
	for c in all:
		if c == cur:
			continue
		var d := c.get_global_rect().get_center() - from
		var along := d.dot(dir)
		if along <= 1.0:
			continue
		var across := absf(d.dot(Vector2(-dir.y, dir.x)))
		var score := along + across * 2.0
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		_navigate_to(best)


## O elemento de tela dono do controle focado, ou "".
func element_of(control: Control) -> String:
	for id in order:
		if VNUIElements.focus_control(elements[id]) == control or elements[id] == control:
			return id
	return ""
