class_name VNUIElements
extends RefCounted
## Constrói os elementos de tela do UI Spec §3.1 como nós [Control].
##
## Cada elemento é um nó com os metadados [code]vn_id[/code] (id do elemento),
## [code]vn_def[/code] (o dicionário do bundle) e [code]vn_focus[/code] (o
## [Control] que recebe foco e clique, que pode ser o próprio nó ou um filho,
## como o [HSlider] de um [code]slider[/code]). O estilo visual (tema, estados,
## sons) é da tarefa M2-07; aqui vale o tema padrão do Godot.

const CLICKABLE := ["button", "hotspot", "slider", "toggle", "select"]


## Cria o nó do elemento [param def] na tela [param screen].
static func build(screen: VNUIScreen, def: Dictionary) -> Control:
	var node: Control
	match String(def.get("type", "")):
		"button": node = _button(screen, def)
		"image": node = _image(screen, def)
		"label": node = _label(screen, def)
		"hotspot": node = _hotspot(screen, def)
		"slider": node = _slider(screen, def)
		"toggle": node = _toggle(screen, def)
		"select": node = _select(screen, def)
		"slot_grid": node = _slot_grid(screen, def)
		"gallery_grid": node = _gallery_grid(screen, def)
		"backlog_list": node = _backlog_list(screen, def)
		"container": node = _container(screen, def)
		"records_list": node = _records_list(screen, def)
		"licenses_list": node = _licenses_list(screen, def)
		_:
			node = Control.new()
	node.name = String(def.get("id", "element"))
	node.set_meta(&"vn_id", String(def.get("id", "")))
	node.set_meta(&"vn_def", def)
	if not node.has_meta(&"vn_focus"):
		node.set_meta(&"vn_focus", node if String(def.get("type", "")) in CLICKABLE else null)
	if def.has("size"):
		node.custom_minimum_size = Vector2(float(def.size[0]), float(def.size[1]))
	if def.has("z"):
		node.z_index = int(def.z)
	var focus_node: Control = focus_control(node)
	if def.has("tooltip"):
		var tip := screen.text_of(def, "tooltip", String(def.tooltip))
		node.tooltip_text = VNUIText.strip_markup(tip)
		if focus_node != null:
			focus_node.tooltip_text = node.tooltip_text
	return node


## O [Control] interativo do elemento (foco, clique), ou [code]null[/code].
static func focus_control(node: Control) -> Control:
	if node == null or not node.has_meta(&"vn_focus"):
		return null
	return node.get_meta(&"vn_focus") as Control


# --- Tipos simples ----------------------------------------------------------

static func _button(screen: VNUIScreen, def: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	if def.has("text"):
		b.text = VNUIText.strip_markup(screen.text_of(def, "", String(def.text)))
	if def.has("icon"):
		var tex := screen.load_texture(String(def.icon))
		if tex != null:
			b.icon = tex
			b.expand_icon = def.has("size")
	if b.text.is_empty() and b.icon == null and def.has("tooltip"):
		b.text = VNUIText.strip_markup(screen.text_of(def, "tooltip", String(def.tooltip)))
	b.pressed.connect(screen.activate.bind(String(def.id)))
	return b


static func _image(screen: VNUIScreen, def: Dictionary) -> Control:
	var t := TextureRect.new()
	t.texture = screen.load_texture(String(def.get("asset", "")))
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if def.has("size"):
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func _label(screen: VNUIScreen, def: Dictionary) -> Control:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF if not def.has("size") else TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var align := String(def.get("align", "left"))
	l.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(align, HORIZONTAL_ALIGNMENT_LEFT)
	l.text = VNUIText.to_bbcode(screen.text_of(def, "", String(def.get("text", ""))))
	return l


static func _hotspot(screen: VNUIScreen, def: Dictionary) -> Control:
	var h := VNUIHotspot.new()
	h.area = def.get("area", {})
	h.highlight = String(def.get("highlight", "outline"))
	h.show_always = bool(screen.manager.get_setting(&"show_hotspots"))
	h.focus_mode = Control.FOCUS_ALL
	h.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var label := screen.text_of(def, "", String(def.get("label", "")))
	h.accessibility_label = VNUIText.strip_markup(label)
	if h.tooltip_text.is_empty() and not label.is_empty():
		h.tooltip_text = h.accessibility_label
	h.activated.connect(screen.activate.bind(String(def.id)))
	if def.has("on_hover"):
		h.mouse_entered.connect(screen.hover.bind(String(def.id)))
		h.focus_entered.connect(screen.hover.bind(String(def.id)))
	return h


# --- Controles ligados a configurações (UI Spec §8) -------------------------

static func _labeled(screen: VNUIScreen, def: Dictionary, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	if def.has("label"):
		var l := Label.new()
		l.text = VNUIText.strip_markup(screen.text_of(def, "", String(def.label)))
		l.custom_minimum_size.x = 260
		row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	row.set_meta(&"vn_focus", control)
	return row


static func _slider(screen: VNUIScreen, def: Dictionary) -> Control:
	var s := HSlider.new()
	var bind := String(def.bind)
	var rg: Array = VNUISettings.RANGES.get(bind, [0.0, 1.0])
	s.min_value = float(def.get("min", rg[0]))
	s.max_value = float(def.get("max", rg[1] if is_finite(rg[1]) else 100.0))
	s.step = float(def.get("step", 0.0 if VNUISettings.TYPES.get(bind) == "number" else 1.0))
	s.custom_minimum_size.x = 320
	s.focus_mode = Control.FOCUS_ALL
	var v: Variant = screen.manager.get_setting(StringName(bind))
	if v is float or v is int:
		s.set_value_no_signal(float(v))
	s.value_changed.connect(func(x: float): screen.change_setting(String(def.id), bind, x))
	return _labeled(screen, def, s)


static func _toggle(screen: VNUIScreen, def: Dictionary) -> Control:
	var t := CheckButton.new()
	var bind := String(def.bind)
	t.focus_mode = Control.FOCUS_ALL
	if def.has("label"):
		t.text = VNUIText.strip_markup(screen.text_of(def, "", String(def.label)))
	t.set_pressed_no_signal(bool(screen.manager.get_setting(StringName(bind))))
	t.toggled.connect(func(on: bool): screen.change_setting(String(def.id), bind, on))
	return t


## Opções do [code]select[/code]: as da tela ou, sem elas, as do próprio [code]bind[/code].
static func select_options(screen: VNUIScreen, def: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var id := String(def.id)
	if def.has("options"):
		for o in def.options:
			var path := "ui/%s/%s/option/%s" % [screen.screen_id, id, _option_key(o.value)]
			out.append({"value": o.value, "text": screen.manager.text(path, String(o.text))})
		return out
	var settings: VNUISettings = screen.manager.settings_model()
	match String(def.bind):
		"display_mode":
			for m in VNUISettings.DISPLAY_MODES:
				out.append({"value": m, "text": screen.manager.text("runtime/settings/display_mode/" + m, m.capitalize())})
		"resolution":
			for r in settings.resolutions():
				out.append({"value": r, "text": "%d × %d" % [r[0], r[1]]})
		"fps_limit_vn", "fps_limit_activity":
			for f in VNUISettings.FPS_OPTIONS:
				out.append({"value": f, "text": str(f) if f > 0 else screen.manager.text("runtime/settings/fps_unlimited", "∞")})
		"locale":
			for l in settings.locales():
				var name := TranslationServer.get_locale_name(l.replace("-", "_"))
				out.append({"value": l, "text": name if not name.is_empty() else l})
		_:
			if VNUISettings.TYPES.get(String(def.bind)) == "boolean":
				out.append({"value": false, "text": "Off"})
				out.append({"value": true, "text": "On"})
	return out


static func _option_key(v: Variant) -> String:
	if v is float and v == floor(v):
		return str(int(v))
	if v is bool:
		return "true" if v else "false"
	return str(v)


static func _select(screen: VNUIScreen, def: Dictionary) -> Control:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_ALL
	var opts := select_options(screen, def)
	var current: Variant = screen.manager.get_setting(StringName(def.bind))
	for i in opts.size():
		o.add_item(VNUIText.strip_markup(String(opts[i].text)), i)
		if _same_value(opts[i].value, current):
			o.select(i)
	o.set_meta(&"vn_options", opts)
	o.item_selected.connect(func(i: int): screen.change_setting(String(def.id), String(def.bind), opts[i].value))
	return _labeled(screen, def, o)


static func _same_value(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Array and b is Array and a.size() == b.size():
		for i in a.size():
			if not _same_value(a[i], b[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


# --- Listas e grades ---------------------------------------------------------

static func _slot_grid(screen: VNUIScreen, def: Dictionary) -> Control:
	var g := GridContainer.new()
	var cols := int(def.get("columns", 3))
	var rows := int(def.get("rows", 2))
	g.columns = cols
	g.add_theme_constant_override(&"h_separation", 16)
	g.add_theme_constant_override(&"v_separation", 16)
	var mode := String(def.get("mode", "load"))
	var slots := {}
	var saves := screen.manager.modules().saves if screen.manager.modules() != null else null
	if saves != null:
		for s in saves.list_slots():
			slots[String(s.get("slot", ""))] = s
	var first: Control = null
	for n in range(1, mini(cols * rows, VNSaveManager.MAX_MANUAL_SLOTS) + 1):
		var slot := String(VNSaveManager.manual_slot(n))
		var b := Button.new()
		b.name = slot
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(320, 180 + 48)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if slots.has(slot):
			var info: Dictionary = slots[slot]
			var label := String(info.get("label", ""))
			b.text = "%d. %s" % [n, label if not label.is_empty() else String(info.get("created_at", "")).replace("T", " ").left(16)]
			b.icon = screen.slot_thumbnail(StringName(slot), info)
		else:
			b.text = "%d. %s" % [n, screen.manager.text("runtime/slot/empty", "Empty")]
			if mode == "load":
				b.disabled = true
				b.set_meta(&"vn_locked", true)
		b.pressed.connect(screen.manager.slot_pressed.bind(screen, mode, n, slots.has(slot)))
		g.add_child(b)
		if first == null:
			first = b
	g.set_meta(&"vn_focus", first)
	return g


## Itens da galeria: [code]{ id, title, asset, unlocked, kind }[/code] (UI Spec §3.1).
static func gallery_items(screen: VNUIScreen, source: String) -> Array[Dictionary]:
	var m := screen.manager
	var bundle: Dictionary = m.bundle()
	var profile: Dictionary = m.modules().saves.profile() if m.modules() != null and m.modules().saves != null else {}
	var out: Array[Dictionary] = []
	if source == "endings":
		var ends: Array = bundle.get("project", {}).get("endings", []).duplicate()
		ends.sort_custom(func(a, b): return [a.get("order", 0), a.id] < [b.get("order", 0), b.id])
		var seen: Array = profile.get("endings", [])
		for e in ends:
			out.append({"id": e.id, "kind": "ending", "asset": String(e.get("image", "")),
				"title": m.text("ending/%s/title" % e.id, String(e.get("title", e.id))),
				"unlocked": seen.has(e.id)})
		return out
	var types: Array = ["image", "background"] if source == "images" else ["audio_music"]
	var seen_assets: Array = profile.get("seen_assets", [])
	var ids: Array = []
	for aid in bundle.get("assets", {}):
		var a: Dictionary = bundle.assets[aid]
		if a.get("gallery", false) and String(a.get("type", "")) in types:
			ids.append(aid)
	ids.sort_custom(func(x, y):
		var ax: Dictionary = bundle.assets[x]
		var ay: Dictionary = bundle.assets[y]
		return [ax.get("gallery_order", 2147483647), x] < [ay.get("gallery_order", 2147483647), y])
	for aid in ids:
		out.append({"id": aid, "kind": "music" if source == "music" else "image", "asset": aid,
			"title": String(aid).get_file(), "unlocked": seen_assets.has(aid)})
	return out


static func _gallery_grid(screen: VNUIScreen, def: Dictionary) -> Control:
	var g := GridContainer.new()
	g.columns = int(def.get("columns", 4))
	g.add_theme_constant_override(&"h_separation", 12)
	g.add_theme_constant_override(&"v_separation", 12)
	var first: Control = null
	for item in gallery_items(screen, String(def.get("source", "images"))):
		var b := Button.new()
		b.name = String(item.id).replace("/", "_")
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(240, 160)
		b.expand_icon = true
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		if item.unlocked:
			b.text = VNUIText.strip_markup(String(item.title))
			if item.kind != "music" and not String(item.asset).is_empty():
				b.icon = screen.load_texture(String(item.asset))
		else:
			b.text = screen.manager.text("runtime/gallery/locked", "???")
			if def.has("locked_asset"):
				b.icon = screen.load_texture(String(def.locked_asset))
			b.disabled = true
			b.set_meta(&"vn_locked", true)
		b.set_meta(&"vn_item", item)
		b.pressed.connect(screen.manager.gallery_pressed.bind(screen, item))
		g.add_child(b)
		if first == null:
			first = b
	g.set_meta(&"vn_focus", first)
	return g


static func _scroll_list(def: Dictionary) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if not def.has("size"):
		sc.custom_minimum_size = Vector2(900, 480)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 10)
	sc.add_child(box)
	sc.focus_mode = Control.FOCUS_ALL
	sc.set_meta(&"vn_focus", sc)
	return [sc, box]


static func _text_line(text: String) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = text
	return l


static func _backlog_list(screen: VNUIScreen, def: Dictionary) -> Control:
	var parts := _scroll_list(def)
	var box: VBoxContainer = parts[1]
	var m := screen.manager
	var entries: Array = []
	if m.modules() != null and m.modules().engine != null:
		entries = m.modules().engine.snapshot().get("backlog", [])
	var max_items := int(def.get("max_items", 100))
	var start := maxi(0, entries.size() - max_items)
	for i in range(start, entries.size()):
		var e: Dictionary = entries[i]
		var body := m.backlog_text(e)
		var speaker := ""
		if e.get("speaker") is String and not String(e.speaker).is_empty():
			var chars: Dictionary = m.bundle().get("characters", {})
			var fallback := String(chars.get(e.speaker, {}).get("name", ""))
			speaker = m.text("character/%s/name" % e.speaker, fallback)
		var line := ("[b]%s[/b]\n" % VNUIText.escape_markup(speaker) if not speaker.is_empty() else "") + VNUIText.to_bbcode(body)
		box.add_child(_text_line(line))
	parts[0].set_meta(&"vn_count", box.get_child_count())
	return parts[0]


static func _records_list(screen: VNUIScreen, def: Dictionary) -> Control:
	var parts := _scroll_list(def)
	var box: VBoxContainer = parts[1]
	var m := screen.manager
	var board := String(def.get("board", ""))
	var plugin := StringName(board.get_slice(".", 0))
	var name := StringName(board.get_slice(".", 1))
	var records: Array = []
	if m.modules() != null and m.modules().saves != null:
		records = m.modules().saves.get_records(plugin, name)
	var max_items := int(def.get("max_items", 10))
	if records.is_empty():
		var empty := screen.text_of(def, "empty_text", String(def.get("empty_text", m.text("runtime/records/empty", "No records yet"))))
		box.add_child(_text_line(VNUIText.to_bbcode(empty)))
	for i in mini(records.size(), max_items):
		var r: Dictionary = records[i]
		box.add_child(_text_line("%d.  %s" % [i + 1, m.text_model().format_value(r.get("score", 0))]))
	parts[0].set_meta(&"vn_count", mini(records.size(), max_items))
	return parts[0]


static func _licenses_list(screen: VNUIScreen, def: Dictionary) -> Control:
	var parts := _scroll_list(def)
	var box: VBoxContainer = parts[1]
	var include: Array = def.get("include", ["engine", "plugins", "fonts", "assets"])
	var kinds := {"plugins": "plugin", "fonts": "font", "assets": "asset"}
	var count := 0
	for e in screen.manager.license_entries():
		var k := String(e.get("kind", ""))
		# O aviso do motor aparece sempre, mesmo fora de include (UI Spec §3.1).
		if k != "engine" and not include.has(kinds.find_key(k)):
			continue
		var head := "[b]%s[/b]" % VNUIText.escape_markup(String(e.get("title", "")))
		if e.has("author"):
			head += " — " + VNUIText.escape_markup(String(e.author))
		if e.has("license"):
			head += " (%s)" % VNUIText.escape_markup(String(e.license))
		var body := head
		for key in ["url", "notice", "text"]:
			if e.has(key):
				body += "\n" + VNUIText.escape_markup(String(e[key]))
		box.add_child(_text_line(body))
		count += 1
	parts[0].set_meta(&"vn_count", count)
	return parts[0]


static func _container(screen: VNUIScreen, def: Dictionary) -> Control:
	var c: Container
	match String(def.get("layout", "column")):
		"row":
			c = HBoxContainer.new()
		"grid":
			var g := GridContainer.new()
			g.columns = int(def.get("columns", 2))
			c = g
		_:
			c = VBoxContainer.new()
	var spacing := int(def.get("spacing", 8))
	if c is GridContainer:
		c.add_theme_constant_override(&"h_separation", spacing)
		c.add_theme_constant_override(&"v_separation", spacing)
	else:
		c.add_theme_constant_override(&"separation", spacing)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta(&"vn_focus", null)
	for child in def.get("children", []):
		c.add_child(screen.add_element(child, String(def.id)))
	return c
