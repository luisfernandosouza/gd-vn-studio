class_name VNRuntimeUIManager
extends VNUIManager
## UI Manager do runtime (tarefa M2-06; UI Spec §2–§4, §8, §12; RT §1, §1.1,
## §3.0 passo 6, §10.1).
##
## Mantém a pilha de telas ([code]bundle.ui[/code]) na camada
## [constant VNLayers.SCREENS], a [code]hud[/code] na [constant VNLayers.HUD] e
## confirmações e mensagens na [constant VNLayers.SYSTEM]. Executa as ações do
## UI Spec §4 em ordem, com [code]if[/code]/[code]else[/code] e confirmação;
## [code]effects[/code] vão ao State Manager com
## [constant VNStateManager.CALLER_UI] e [code]emit[/code] ao Event Bus. Abrir
## uma tela durante o jogo pausa o Narrative Engine; a [code]hud[/code] não.
## Teclado e gamepad navegam pelas ações [code]vn_*[/code] do RT §10.1.
##
## O que fica para outras tarefas: estilos do tema e animações [code]idle[/code]
## (M2-07), o set composto atrás da tela e os alvos [code]set:[/code] e
## [code]stage:[/code] (M2-08, por [signal set_target_action]), telas do preset
## (M2-09), perfil e migração de [code]settings.json[/code] (M2-11), licenças do
## [code]licenses.json[/code] (M2-14, por [method set_licenses]). A acessibilidade (M2-15) está em [VNUIAccessibility] e [VNInputActions].

## Ação cosmética sobre o set da tela ([code]set:[/code]) ou o set em cena
## ([code]stage:[/code]): [param action] é [code]set_state[/code],
## [code]toggle_state[/code], [code]play_animation[/code], [code]show[/code],
## [code]hide[/code] ou [code]toggle_visible[/code]; [param args] traz
## [code]state[/code], [code]states[/code] ou [code]animation[/code]. Quem desenha
## o set (M2-08) escuta este sinal.
signal set_target_action(scope: StringName, target: String, action: StringName, args: Dictionary)
## Modo automático ou pular mudou (ações [code]toggle_auto[/code]/[code]toggle_skip[/code]).
signal play_mode_changed(auto: bool, skip: bool)
## A ação [code]quit[/code] foi confirmada. Com [member auto_quit], o UI Manager
## também fecha a árvore.
signal quit_requested()

## Plataformas sem "Sair" nem [code]open_url[/code] pelo jogo.
const WEB := "web"

## [code]true[/code]: [code]quit[/code] chama [method SceneTree.quit].
var auto_quit: bool = true
## Abre links ([code]func(url: String)[/code]); padrão [method OS.shell_open].
var url_opener: Callable = Callable()
## Plataforma ([code]sys.ui.platform[/code]); calculada no início, trocável nos testes.
var platform: String = ""
## Modo automático e pular (o Narrative Engine lê por [signal play_mode_changed]).
var auto_mode: bool = false
var skip_mode: bool = false

var _bundle: Dictionary = {}
var _settings := VNUISettings.new()
var _text := VNUIText.new()
var _licenses: Array = []
var _root: Control = null
var _layers: Dictionary = {}       # camada → CanvasLayer
var _input_node: Node = null
var _stack: Array[VNUIScreen] = []
var _hud: VNUIScreen = null
var _hud_visible: bool = false
var _dialogs: Array[VNUIDialog] = []
var _connected: bool = false
var _free_play_screen: String = ""


func _init() -> void:
	VNInputActions.ensure_registered()
	platform = _detect_platform()
	_text.reader = _read_variable
	_settings.system_locale = OS.get_locale().replace("_", "-")


# --- Bundle e ligação aos outros módulos ------------------------------------

func load_bundle(bundle: Dictionary) -> void:
	_bundle = bundle
	_settings.project = bundle.get("project", {})
	_text.number_formats = _settings.project.get("settings", {}).get("number_formats", {})
	_connect_modules()
	var locales: Variant = bundle.get("locales")
	if locales is Dictionary:
		_use_locale_strings()


## O bundle carregado.
func bundle() -> Dictionary:
	return _bundle


## As traduções do idioma atual ([code]locales/<idioma>.json → strings[/code]).
## O boot as entrega ao carregar o bundle e ao trocar de idioma.
func set_locale_strings(strings: Dictionary, locale: String = "") -> void:
	_text.strings = strings
	if not locale.is_empty():
		_text.locale = locale
	_rebuild_open_screens()


## Entradas de [code]licenses.json → entries[/code] (Build System §4.5).
func set_licenses(licenses: Dictionary) -> void:
	_licenses = licenses.get("entries", [])


## Entradas mostradas por [code]licenses_list[/code]: o aviso do motor e do
## runtime (sempre) e as do [code]licenses.json[/code].
func license_entries() -> Array:
	var out: Array = [
		{"kind": "engine", "title": "Godot Engine", "license": "MIT", "text": Engine.get_license_text()},
		{"kind": "engine", "title": "Visual Novel Studio runtime", "license": "MIT"},
	]
	out.append_array(_licenses)
	return out


func settings_model() -> VNUISettings:
	return _settings


func text_model() -> VNUIText:
	return _text


func _connect_modules() -> void:
	var m := modules()
	if _connected or m == null:
		return
	_connected = true
	if m.engine != null:
		m.engine.phase_changed.connect(_on_phase_changed)
	if m.state != null:
		m.state.state_changed.connect(func(_c): refresh())
	if m.plugins != null:
		m.plugins.activity_ended.connect(_on_activity_ended)


func attach(parent: Node) -> void:
	detach()
	_root = Control.new()
	_root.name = "UIManager"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_root)
	for layer in [VNLayers.HUD, VNLayers.SCREENS, VNLayers.SYSTEM]:
		var cl := CanvasLayer.new()
		cl.layer = layer
		cl.name = VNLayers.layer_name(layer)
		_root.add_child(cl)
		var host := Control.new()
		host.name = "Root"
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(host)
		_layers[layer] = host
	_input_node = VNUIInput.new()
	_input_node.manager = self
	_root.add_child(_input_node)
	for s in _stack:
		_layers[VNLayers.SCREENS].add_child(s)
	if _hud != null:
		_layers[VNLayers.HUD].add_child(_hud)


func detach() -> void:
	for s in _stack:
		if s.get_parent() != null:
			s.get_parent().remove_child(s)
	if _hud != null and _hud.get_parent() != null:
		_hud.get_parent().remove_child(_hud)
	for d in _dialogs:
		if is_instance_valid(d):
			d.queue_free()
	_dialogs.clear()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_layers.clear()
	_input_node = null


## O nó onde a camada desenha (HUD, telas ou sistema), ou [code]null[/code] sem attach.
func layer_root(layer: int) -> Control:
	return _layers.get(layer)


# --- Pilha de telas (UI Spec §12) -------------------------------------------

func open_screen(screen_id: String) -> VNResult:
	var data: Variant = _bundle.get("ui", {}).get(screen_id)
	if not data is Dictionary:
		return VNResult.failure(VNErrors.INVALID_STATE, "tela inexistente: %s" % screen_id)
	if screen_id == "hud":
		set_hud_visible(true)
		return VNResult.success()
	if screen_id == "title":
		if not _stack.is_empty() and _stack[-1].screen_id == "title":
			return VNResult.success()
		_clear_stack(false)
	elif String(data.get("kind", "")) == "custom" and not bool(data.get("modal", true)) and not _stack.is_empty():
		_pop(false)
	if not _stack.is_empty():
		var top := _stack[-1]
		if top.is_inside_tree():
			var f := top.get_viewport().gui_get_focus_owner()
			top.last_focus = f if f != null and top.is_ancestor_of(f) else null
	var screen := _make_screen(screen_id, data)
	_stack.append(screen)
	if _layers.has(VNLayers.SCREENS):
		_layers[VNLayers.SCREENS].add_child(screen)
	screen.refresh()
	_play_screen_music(data)
	_transition_in(screen)
	_update_pause()
	screens_changed.emit(screen_stack())
	run_actions(data.get("on_open", []), {"screen": screen_id, "list": "on_open"})
	_focus_top()
	return VNResult.success()


func close_screen() -> void:
	if _stack.is_empty():
		return
	# O título é a base fora do jogo: close_screen/back nele não fazem nada.
	if _stack.size() == 1 and _stack[0].screen_id == "title":
		return
	_pop(true)


func close_all() -> void:
	_clear_stack(true)


func screen_stack() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _stack:
		out.append(s.screen_id)
	return out


## A tela do topo da pilha, ou [code]null[/code].
func top_screen() -> VNUIScreen:
	return _stack[-1] if not _stack.is_empty() else null


## A tela aberta com o id (topo primeiro), a [code]hud[/code], ou [code]null[/code].
func get_screen(screen_id: String) -> VNUIScreen:
	if screen_id == "hud":
		return _hud
	for i in range(_stack.size() - 1, -1, -1):
		if _stack[i].screen_id == screen_id:
			return _stack[i]
	return null


func set_hud_visible(visible: bool) -> void:
	_hud_visible = visible
	var data: Variant = _bundle.get("ui", {}).get("hud")
	if visible and data is Dictionary:
		if _hud == null:
			_hud = _make_screen("hud", data)
			if _layers.has(VNLayers.HUD):
				_layers[VNLayers.HUD].add_child(_hud)
			_hud.refresh()
			run_actions(data.get("on_open", []), {"screen": "hud", "list": "on_open"})
	elif _hud != null:
		var old := _hud
		_hud = null
		run_actions(old.data.get("on_close", []), {"screen": "hud", "list": "on_close"})
		old.queue_free()
	_apply_activity_capture()


func is_hud_visible() -> bool:
	return _hud != null


func _make_screen(screen_id: String, data: Dictionary) -> VNUIScreen:
	var s := VNUIScreen.new()
	var res: Array = _settings.project.get("settings", {}).get("resolution", [1920, 1080])
	s.setup(self, screen_id, data, Vector2(float(res[0]), float(res[1])))
	_apply_accessibility(s)
	return s


func _pop(run_on_close: bool) -> void:
	var s: VNUIScreen = _stack.pop_back()
	if run_on_close:
		run_actions(s.data.get("on_close", []), {"screen": s.screen_id, "list": "on_close"})
	_transition_out(s)
	_update_pause()
	screens_changed.emit(screen_stack())
	_focus_top()


func _clear_stack(run_on_close: bool) -> void:
	if _stack.is_empty():
		return
	while not _stack.is_empty():
		var s: VNUIScreen = _stack.pop_back()
		if run_on_close:
			run_actions(s.data.get("on_close", []), {"screen": s.screen_id, "list": "on_close"})
		s.queue_free()
	_update_pause()
	screens_changed.emit(screen_stack())


func _focus_top() -> void:
	var top := top_screen()
	if top != null and top.is_inside_tree() and _dialogs.is_empty():
		top.focus_first()


## Abrir a pausa ou uma tela própria durante o jogo pausa o Narrative Engine (UI Spec §12).
func _update_pause() -> void:
	var m := modules()
	if m == null or m.engine == null:
		return
	var want := in_game() and not _stack.is_empty()
	if m.engine.is_paused() != want:
		m.engine.set_paused(want)


func _transition_in(screen: VNUIScreen) -> void:
	var tr: Dictionary = screen.data.get("transition", {})
	var dur := float(tr.get("duration", 0.0))
	if not screen.is_inside_tree() or String(tr.get("kind", "none")) == "none" or dur <= 0.0:
		_play_appear(screen)
		return
	screen.modulate.a = 0.0
	screen.create_tween().tween_property(screen, "modulate:a", 1.0, dur)
	_play_appear(screen)


func _transition_out(screen: VNUIScreen) -> void:
	var tr: Dictionary = screen.data.get("transition", {})
	var dur := float(tr.get("duration", 0.0))
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not screen.is_inside_tree() or String(tr.get("kind", "none")) == "none" or dur <= 0.0:
		screen.queue_free()
		return
	var tw := screen.create_tween()
	tw.tween_property(screen, "modulate:a", 0.0, dur)
	tw.tween_callback(screen.queue_free)


func _play_appear(screen: VNUIScreen) -> void:
	var reduce := bool(get_setting(&"reduce_motion"))
	for id in screen.order:
		var def: Dictionary = screen.definition(id)
		if def.has("appear"):
			VNUIAnimator.play(screen.elements[id], def.appear, reduce, true)


func _play_screen_music(data: Dictionary) -> void:
	var m := modules()
	if data.has("music") and m != null and m.audio != null:
		m.audio.play(String(data.music), VNAudioManager.MUSIC)


# --- Fases do jogo ----------------------------------------------------------

## Há partida em andamento ([code]sys.ui.in_game[/code]).
func in_game() -> bool:
	var m := modules()
	return m != null and m.engine != null and VNPhase.is_in_game(m.engine.phase())


func _on_phase_changed(phase: StringName, previous: StringName) -> void:
	if phase == VNPhase.TITLE:
		set_hud_visible(false)
		open_screen("title")
	elif phase in [VNPhase.NEW_GAME, VNPhase.LOAD_GAME] or (VNPhase.is_in_game(phase) and not VNPhase.is_in_game(previous)):
		if not _stack.is_empty() and _stack[0].screen_id == "title":
			_clear_stack(false)
		set_hud_visible(true)
	refresh_sys_ui()
	_apply_activity_capture()
	refresh()


func _on_activity_ended(status: StringName, outcome: StringName, _payload: Dictionary) -> void:
	if _free_play_screen.is_empty():
		refresh_sys_ui()
		return
	_free_play_screen = ""
	var value := String(outcome) if status == VNPluginHost.STATUS_COMPLETED else String(status)
	if status == VNPluginHost.STATUS_SKIPPED:
		value = String(VNPluginHost.STATUS_CANCELLED)
	_set_sys("sys.ui.last_activity_outcome", value)
	refresh_sys_ui()
	refresh()
	_focus_top()


# --- Condições e textos -----------------------------------------------------

## Avalia uma lista de condições (Data Model §5); erro conta como falso (RT §9).
func check(conditions: Variant) -> bool:
	var m := modules()
	if m == null or m.conditions == null:
		return true
	var r := m.conditions.evaluate_conditions(conditions)
	return r.ok and r.value == true


## Texto traduzido do caminho, interpolado.
func text(path: String, fallback: String = "") -> String:
	return _text.text(path, fallback)


## Texto de uma entrada do backlog, com os valores guardados nela.
func backlog_text(entry: Dictionary) -> String:
	var vars: Dictionary = entry.get("vars", {})
	var t := VNUIText.new()
	t.strings = _text.strings
	t.locale = _text.locale
	t.number_formats = _text.number_formats
	t.reader = func(id: String): return vars[id] if vars.has(id) else _read_variable(id)
	return t.text(String(entry.get("path", "")), "")


func _read_variable(id: String) -> Variant:
	var m := modules()
	if m == null or m.state == null:
		return null
	return m.state.read_value(id, null, VNStateManager.CALLER_UI)


## Reavalia condições e controles das telas abertas.
func refresh() -> void:
	for s in _stack:
		s.refresh()
	if _hud != null:
		_hud.refresh()
	_apply_activity_capture()


func _rebuild_open_screens() -> void:
	var ids := screen_stack()
	if ids.is_empty() and _hud == null:
		return
	var had_hud := _hud != null
	for s in _stack:
		s.queue_free()
	_stack.clear()
	if had_hud:
		_hud.queue_free()
		_hud = null
	for id in ids:
		var data: Dictionary = _bundle.get("ui", {}).get(id, {})
		if data.is_empty():
			continue
		var s := _make_screen(id, data)
		_stack.append(s)
		if _layers.has(VNLayers.SCREENS):
			_layers[VNLayers.SCREENS].add_child(s)
		s.refresh()
	if had_hud:
		set_hud_visible(true)
	_focus_top()


func load_texture(asset_id: String) -> Texture2D:
	var m := modules()
	if asset_id.is_empty() or m == null or m.assets == null or not m.assets.has_asset(asset_id):
		return null
	return m.assets.load_asset(asset_id) as Texture2D


## Miniatura do slot; com o modo stream, a de [code]thumbnail_sensitive[/code]
## vira [code]content_filter.placeholder[/code] (UI Spec §3.1, RT §8.5).
func slot_thumbnail(slot: StringName, info: Dictionary) -> Texture2D:
	var m := modules()
	if m == null or m.storage == null:
		return null
	if bool(info.get("thumbnail_sensitive", false)) and bool(get_setting(&"content_filter")):
		return load_texture(String(_settings.project.get("content_filter", {}).get("placeholder", "")))
	var path := VNSaveManager.thumbnail_path(slot)
	if not m.storage.exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(m.storage.read_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


# --- sys.ui.* (UI Spec §3.2) -------------------------------------------------

## Recalcula as variáveis [code]sys.ui.*[/code] que dependem da interface, do
## bundle e dos saves (RT §3.0 passo 6; RT §8.5 depois de [code]reset_profile[/code]).
## Só grava as que o Variable Manager define.
func refresh_sys_ui() -> void:
	var m := modules()
	if m == null:
		return
	var project: Dictionary = _settings.project
	var sections: Array = project.get("gallery", {}).get("sections", [])
	var act: Dictionary = m.plugins.current_activity() if m.plugins != null else {}
	_set_sys("sys.ui.has_save", m.saves != null and m.saves.has_save())
	_set_sys("sys.ui.in_game", in_game())
	_set_sys("sys.ui.platform", platform)
	_set_sys("sys.ui.activity", not act.is_empty())
	_set_sys("sys.ui.activity_skippable", not act.is_empty() and bool(act.get("skippable", false)) and act.get("mode", VNPluginHost.MODE_STORY) == VNPluginHost.MODE_STORY)
	_set_sys("sys.ui.has_minigames", _bundle.get("ui", {}).has("minigames"))
	_set_sys("sys.ui.has_gallery", not sections.is_empty())
	_set_sys("sys.ui.gallery_endings", sections.has("endings"))
	_set_sys("sys.ui.gallery_images", sections.has("images"))
	_set_sys("sys.ui.gallery_music", sections.has("music"))
	_set_sys("sys.ui.content_filter", bool(get_setting(&"content_filter")))
	_set_sys("sys.ui.content_filter_available", not _settings.is_censored_edition() and _has_censored_content())


func _set_sys(id: String, value: Variant) -> void:
	var m := modules()
	if m == null or m.state == null or m.variables == null or not m.variables.has(id):
		return
	if m.variables.read(id) != value:
		m.state.set_system_value(id, value)


func _has_censored_content() -> bool:
	for a in _bundle.get("assets", {}).values():
		if a is Dictionary and a.has("censored"):
			return true
	var scenes := JSON.stringify(_bundle.get("scenes", {}))
	return scenes.contains("\"censor\"") or scenes.contains("\"censored_")


# --- Ações (UI Spec §4) -----------------------------------------------------

## Executa a lista em ordem. Uma confirmação suspende a lista até a resposta;
## o resultado devolvido é o da parte já executada. A primeira ação recusada
## interrompe a lista e volta como falha.
func run_actions(actions: Array, context: Dictionary = {}) -> VNResult:
	if actions.is_empty():
		return VNResult.success()
	var run := {
		"frames": [{"list": actions, "i": 0}],
		"ctx": context,
		"confirms": _confirm_order(actions),
	}
	return _resume(run)


func _resume(run: Dictionary) -> VNResult:
	var frames: Array = run.frames
	while not frames.is_empty():
		var top: Dictionary = frames[-1]
		if top.i >= top.list.size():
			frames.pop_back()
			continue
		var a: Dictionary = top.list[top.i]
		top.i += 1
		if a.has("if") and not check(a["if"]):
			if a.has("else"):
				frames.append({"list": a["else"], "i": 0})
			continue
		var r: Variant = _do(a, run)
		if r == null:
			return VNResult.success()   # suspensa numa confirmação
		if not (r as VNResult).ok:
			push_warning("UI: ação %s recusada (%s): %s" % [a.get("do"), r.error, r.message])
			return r
	return VNResult.success()


## Ordem das ações confirm na lista (inclusive em else e then), para o caminho
## [code]…/confirm<n>[/code] (UI Spec §3.3).
static func _confirm_order(actions: Array) -> Array:
	var out: Array = []
	_walk_confirms(actions, out)
	return out


static func _walk_confirms(actions: Variant, out: Array) -> void:
	if not actions is Array:
		return
	for a in actions:
		if a.get("do") == "confirm":
			out.append(a)
		_walk_confirms(a.get("else"), out)
		_walk_confirms(a.get("then"), out)


func _confirm_path(a: Dictionary, run: Dictionary) -> String:
	var n := 0
	for i in run.confirms.size():
		if is_same(run.confirms[i], a):
			n = i + 1
			break
	var ctx: Dictionary = run.ctx
	var owner := String(ctx.get("element", ctx.get("list", "")))
	return "ui/%s/%s/confirm%d" % [ctx.get("screen", ""), owner, n]


## Pergunta e continua a lista com [param then] ou [param otherwise].
func _ask(run: Dictionary, text_value: String, then: Variant, otherwise: Variant) -> Variant:
	_confirm_text(text_value, func(accepted: bool):
		var branch: Variant = then if accepted else otherwise
		if branch is Array and not branch.is_empty():
			run.frames.append({"list": branch, "i": 0})
		elif branch is Callable:
			var r: Variant = branch.call()
			if r is VNResult and not r.ok:
				return
		_resume(run))
	return null


func _screen_kind(run: Dictionary) -> String:
	var id := String(run.ctx.get("screen", ""))
	var s := get_screen(id)
	return String(s.data.get("kind", "")) if s != null else String(_bundle.get("ui", {}).get(id, {}).get("kind", ""))


func _do(a: Dictionary, run: Dictionary) -> Variant:
	var m := modules()
	var game := in_game()
	var refuse := func(msg: String) -> VNResult: return VNResult.failure(VNErrors.INVALID_STATE, "%s: %s" % [a.get("do"), msg])
	match String(a.get("do", "")):
		"new_game":
			if game:
				return refuse.call("só no título")
			close_all()
			m.engine.new_game()
		"continue":
			if game:
				return refuse.call("só no título")
			var slot := m.saves.latest_slot()
			if slot == &"":
				return refuse.call("nenhum save")
			var r := m.saves.load_slot(slot)
			if not r.ok:
				return r
			close_all()
		"open_screen":
			var sid := String(a.screen)
			if sid == "gallery" and not _bundle.get("ui", {}).has("gallery"):
				return VNResult.success()   # jogo sem galeria: não faz nada (U014)
			return open_screen(sid)
		"close_screen", "back":
			close_screen()
		"return_to_title":
			if not game:
				return refuse.call("só durante o jogo")
			var go := func() -> VNResult:
				close_all()
				modules().engine.return_to_title()
				return VNResult.success()
			if bool(a.get("confirm", true)):
				return _ask(run, text("runtime/confirm/return_to_title", "Return to the title screen?"), go, null)
			return go.call()
		"quit":
			if platform == WEB:
				return refuse.call("indisponível no Web")
			if bool(a.get("confirm", true)):
				return _ask(run, text("runtime/confirm/quit", "Quit the game?"), _quit, null)
			return _quit()
		"save":
			if not game:
				return refuse.call("só durante o jogo")
			if not a.has("slot"):
				return open_screen("save")
			return m.saves.save(VNSaveManager.manual_slot(int(a.slot)))
		"load":
			if not a.has("slot"):
				return open_screen("load")
			var r := m.saves.load_slot(VNSaveManager.manual_slot(int(a.slot)))
			if r.ok:
				close_all()
			return r
		"quick_save":
			if not game:
				return refuse.call("só durante o jogo")
			return m.saves.save(VNSaveManager.QUICK)
		"quick_load":
			var r := m.saves.load_slot(VNSaveManager.QUICK)
			if r.ok:
				close_all()
			return r
		"toggle_auto", "toggle_skip":
			if not game:
				return refuse.call("só durante o jogo")
			if a.do == "toggle_auto":
				auto_mode = not auto_mode
			else:
				skip_mode = not skip_mode
			play_mode_changed.emit(auto_mode, skip_mode)
		"hide_textbox":
			if not game:
				return refuse.call("só durante o jogo")
			m.stage.set_textbox_hidden(true)
		"open_backlog":
			if not game:
				return refuse.call("só durante o jogo")
			return open_screen("backlog")
		"set_setting":
			return set_setting(StringName(a.setting), a.value)
		"play_sfx":
			if m.audio != null:
				m.audio.play(String(a.asset), VNAudioManager.SFX)
		"set_state", "toggle_state", "play_animation", "show", "hide", "toggle_visible":
			return _target_action(a, run)
		"effects":
			return _effects(a, game)
		"emit":
			if not game:
				return refuse.call("só durante o jogo")
			var ev := String(a.event)
			if not ev.begins_with("story."):
				return VNResult.failure(VNErrors.PERMISSION_DENIED, "emit: só eventos story.* (%s)" % ev)
			var payload := {}
			for k in a.get("payload", {}):
				var r := m.conditions.evaluate_expression(a.payload[k])
				if not r.ok:
					return VNResult.failure(r.error, r.message)
				payload[k] = r.value
			return m.events.emit(ev, payload, VNEventBus.SOURCE_STORY)
		"open_url":
			var allow: bool = _settings.project.get("build", {}).get("allow_urls", _bundle.get("project", {}).get("allow_urls", true))
			if platform == WEB or not allow:
				return refuse.call("links desligados")
			var url := String(a.url)
			var fallback := "Open this link in your browser?\n%s" % url
			return _ask(run, text("runtime/confirm/open_url", fallback), func() -> VNResult:
				if url_opener.is_valid():
					url_opener.call(url)
				else:
					OS.shell_open(url)
				return VNResult.success(), null)
		"confirm":
			return _ask(run, text(_confirm_path(a, run), String(a.get("text", ""))), a.get("then", []), a.get("else", []))
		"skip_activity":
			var act: Dictionary = m.plugins.current_activity()
			if _screen_kind(run) != "pause" or act.is_empty() or not bool(act.get("skippable", false)) or act.get("mode", VNPluginHost.MODE_STORY) != VNPluginHost.MODE_STORY:
				return refuse.call("nenhuma atividade pulável")
			close_all()
			m.plugins.cancel_activity(VNPluginHost.STATUS_SKIPPED)
		"play_activity":
			if game:
				return refuse.call("só fora do jogo")
			var r := m.plugins.start_activity(StringName(a.activity), a.get("params", {}), VNPluginHost.MODE_FREE_PLAY)
			if not r.ok:
				_set_sys("sys.ui.last_activity_outcome", String(VNPluginHost.STATUS_FAILED))
				refresh()
				return r
			_free_play_screen = String(run.ctx.get("screen", ""))
			refresh_sys_ui()
		"reset_profile":
			if game:
				return refuse.call("só fora do jogo")
			var path := _confirm_path(a, run) if a.has("text") else "runtime/confirm/reset_profile"
			return _ask(run, text(path, String(a.get("text", "Delete all game data?"))), _reset_profile, null)
		_:
			return VNResult.failure(VNErrors.TYPE_MISMATCH, "ação desconhecida: %s" % a.get("do"))
	return VNResult.success()


func _quit() -> VNResult:
	quit_requested.emit()
	if auto_quit and _root != null and _root.is_inside_tree():
		_root.get_tree().quit()
	return VNResult.success()


func _reset_profile() -> VNResult:
	var m := modules()
	var r := m.saves.reset_profile()
	if not r.ok:
		return r
	m.events.emit("sys.profile_reset", {}, VNEventBus.SOURCE_SYS)
	refresh_sys_ui()
	_rebuild_open_screens()
	return r


## [code]effects[/code]: no título só variáveis [code]profile[/code]; no jogo,
## qualquer variável gravável, como transação (UI Spec §4).
func _effects(a: Dictionary, game: bool) -> VNResult:
	var m := modules()
	var effects: Array = a.get("effects", [])
	if not game:
		for e in effects:
			var id := String(e.get("variable", ""))
			var def: Dictionary = m.variables.get_definition(id) if m.variables.has(id) else {}
			if String(def.get("persistence", "")) != "profile":
				return VNResult.failure(VNErrors.PERMISSION_DENIED, "no título, effects só em variáveis profile: %s" % id)
	var r := m.state.apply_effects(effects, {}, VNStateManager.CALLER_UI)
	if r.ok and not game and m.saves != null:
		m.saves.mark_profile_dirty()
	return r


## Ações cosméticas com [code]target[/code]: elemento da tela, [code]set:[/code] ou [code]stage:[/code].
func _target_action(a: Dictionary, run: Dictionary) -> VNResult:
	var target := String(a.target)
	var action := StringName(a.do)
	var args := {}
	for k in ["state", "states", "animation"]:
		if a.has(k):
			args[k] = a[k]
	if target.contains(":"):
		set_target_action.emit(StringName(target.get_slice(":", 0)), target.get_slice(":", 1), action, args)
		return VNResult.success()
	var screen := get_screen(String(run.ctx.get("screen", "")))
	if screen == null or not screen.elements.has(target):
		return VNResult.failure(VNErrors.INVALID_STATE, "%s: elemento %s não está aberto" % [action, target])
	match action:
		&"show": screen.set_element_visible(target, true)
		&"hide": screen.set_element_visible(target, false)
		&"toggle_visible": screen.set_element_visible(target, null)
		&"play_animation": VNUIAnimator.play(screen.elements[target], a.animation, bool(get_setting(&"reduce_motion")))
		_: pass   # elementos não têm estados; set_state/toggle_state valem para sets (U001)
	return VNResult.success()


## Clique, toque ou confirmação num elemento.
func element_activated(screen: VNUIScreen, element_id: String) -> void:
	if not screen.is_element_enabled(element_id) or not _dialogs.is_empty():
		return
	var def := screen.definition(element_id)
	if def.has("actions"):
		run_actions(def.actions, {"screen": screen.screen_id, "element": element_id})


## Slot de [code]slot_grid[/code] (UI Spec §3.1): salvar pede confirmação para sobrescrever.
func slot_pressed(screen: VNUIScreen, mode: String, n: int, exists: bool) -> void:
	var m := modules()
	var slot := VNSaveManager.manual_slot(n)
	if mode == "load":
		if m.saves.load_slot(slot).ok:
			close_all()
		return
	var do_save := func():
		if m.saves.save(slot).ok:
			_rebuild_screen(screen.screen_id)
	if exists:
		_confirm_text(text("runtime/confirm/overwrite_save", "Overwrite this save?"), func(ok: bool):
			if ok:
				do_save.call())
	else:
		do_save.call()


## Item da galeria: imagem abre em tela cheia; música toca.
func gallery_pressed(_screen: VNUIScreen, item: Dictionary) -> void:
	var m := modules()
	if not item.get("unlocked", false):
		return
	if item.kind == "music":
		if m.audio != null:
			m.audio.play(String(item.asset), VNAudioManager.MUSIC)
		return
	var tex := load_texture(String(item.asset))
	if tex == null or not _layers.has(VNLayers.SYSTEM):
		return
	var viewer := VNUIDialog.new()
	viewer.setup("", "×", "")
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewer.add_child(img)
	viewer.move_child(img, 1)
	_show_dialog(viewer, func(_ok): pass)


func _rebuild_screen(screen_id: String) -> void:
	for i in _stack.size():
		if _stack[i].screen_id == screen_id:
			var old := _stack[i]
			var s := _make_screen(screen_id, old.data)
			_stack[i] = s
			if old.get_parent() != null:
				old.get_parent().add_child(s)
				old.get_parent().move_child(s, old.get_index())
			old.queue_free()
			s.refresh()
	_focus_top()


# --- Confirmação e mensagens -------------------------------------------------

func confirm(text_path: String, on_answer: Callable) -> void:
	_confirm_text(text(text_path, text_path), on_answer)


func show_message(text_path: String) -> void:
	var d := VNUIDialog.new()
	d.setup(text(text_path, text_path), text("runtime/message/ok", "OK"), "")
	_show_dialog(d, func(_ok): pass)


func _confirm_text(value: String, on_answer: Callable) -> void:
	var d := VNUIDialog.new()
	d.setup(value, text("runtime/confirm/yes", "Yes"), text("runtime/confirm/no", "No"))
	_show_dialog(d, on_answer)


func _show_dialog(d: VNUIDialog, on_answer: Callable) -> void:
	_dialogs.append(d)
	_apply_accessibility(d)
	d.answered.connect(func(ok: bool):
		_dialogs.erase(d)
		on_answer.call(ok)
		if _dialogs.is_empty():
			_focus_top()
		else:
			_dialogs[-1].focus_default())
	if _layers.has(VNLayers.SYSTEM):
		_layers[VNLayers.SYSTEM].add_child(d)
		d.focus_default()


## Caixas de confirmação ou mensagens abertas, da mais antiga à mais nova.
func open_dialogs() -> Array[VNUIDialog]:
	return _dialogs.duplicate()


## Responde a caixa do topo (atalho para testes e para o Preview).
func answer_dialog(accepted: bool) -> bool:
	if _dialogs.is_empty():
		return false
	_dialogs[-1].answer(accepted)
	return true


# --- Configurações do jogador (UI Spec §8; RT §8.5) -------------------------

func load_settings() -> void:
	var m := modules()
	var data: Variant = null
	var bad := false
	if m != null and m.storage != null and m.storage.exists("settings.json"):
		# JSON.parse (e não read_json) para um arquivo quebrado não sujar o log com ERROR.
		var json := JSON.new()
		bad = json.parse(m.storage.read_text("settings.json")) != OK
		data = null if bad else json.data
	if bad or not _settings.load_player(data):
		_settings.player = {}
		if m != null and m.storage != null:
			m.storage.rename("settings.json", "settings.json.bad")
	_settings.screen_size = DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	_text.locale = String(get_setting(&"locale"))
	_use_locale_strings()
	for s in VNUISettings.TYPES:
		_apply_setting(s, _settings.get_value(s))


func get_setting(setting: StringName) -> Variant:
	return _settings.get_value(String(setting))


func set_setting(setting: StringName, value: Variant) -> VNResult:
	var key := String(setting)
	var norm := _settings.normalize(key, value)
	if not norm[0]:
		return VNResult.failure(VNErrors.TYPE_MISMATCH, "%s: valor fora do schema (%s)" % [key, value])
	if key == "content_filter" and _settings.is_censored_edition():
		return VNResult.success()   # edição censurada: sempre ligado (UI Spec §8)
	var old: Variant = _settings.get_value(key)
	_settings.set_player_value(key, norm[1])
	var m := modules()
	if m != null and m.storage != null:
		m.storage.write_json("settings.json", _settings.player)
	if old != norm[1] or typeof(old) != typeof(norm[1]):
		_apply_setting(key, norm[1])
		setting_changed.emit(setting, norm[1])
		if key == "locale":
			_text.locale = String(norm[1])
			_use_locale_strings()
		elif key == "content_filter":
			_set_sys("sys.ui.content_filter", norm[1])
		_sync_bound_controls(key)
	return VNResult.success()


func _use_locale_strings() -> void:
	var locales: Variant = _bundle.get("locales")
	if locales is Dictionary and locales.has(_text.locale):
		var doc: Variant = locales[_text.locale]
		set_locale_strings(doc.get("strings", {}) if doc is Dictionary else {}, _text.locale)


## Aplica a configuração ao motor (volumes, tela, FPS). Idioma e modo stream o
## runtime repassa aos módulos por [signal setting_changed].
func _apply_setting(key: String, value: Variant) -> void:
	var m := modules()
	if key.begins_with("volume."):
		var ch := key.trim_prefix("volume.")
		if ch == "master":
			var bus := AudioServer.get_bus_index(&"Master")
			if bus >= 0:
				AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(value), 0.0001)))
		elif m != null and m.audio != null and StringName(ch) in VNAudioManager.CHANNELS:
			m.audio.set_channel_volume(StringName(ch), float(value))
		return
	if key == "text_scale" or key == "high_contrast":
		_reapply_accessibility()
		return
	var windowed := DisplayServer.get_name() not in ["headless", ""] and platform != WEB
	match key:
		"fps_limit_vn":
			if platform != WEB and (m == null or m.engine == null or m.engine.phase() != VNPhase.ACTIVITY):
				Engine.max_fps = int(value)
		"fps_limit_activity":
			if platform != WEB and m != null and m.engine != null and m.engine.phase() == VNPhase.ACTIVITY:
				Engine.max_fps = int(value)
		"vsync":
			if windowed:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"display_mode":
			if windowed:
				match String(value):
					"fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
					"borderless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
					_: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"resolution":
			if windowed and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_size(Vector2i(int(value[0]), int(value[1])))


# --- Acessibilidade (Req §12) --------------------------------------------------

## O tema do bundle ([code]theme.json[/code]), ou vazio.
func _theme() -> Dictionary:
	var t: Variant = _bundle.get("theme", {})
	return t if t is Dictionary else {}


## Cor da moldura de foco ([code]theme.colors.focus[/code]).
func focus_color() -> Color:
	return VNUIAccessibility.focus_color(_theme())


## Fator de escala do texto ([code]PlayerSettings.text_scale[/code], 0,8 a 2,0).
func text_scale() -> float:
	return VNUIAccessibility.clamp_scale(float(get_setting(&"text_scale")))


## Painel e texto da caixa de diálogo já com [code]high_contrast[/code] aplicado
## (fundo opaco, contraste do texto ≥ 4,5:1). O Stage e a caixa de diálogo usam estas cores.
func dialog_colors() -> Dictionary:
	return VNUIAccessibility.dialog_colors(_theme(), bool(get_setting(&"high_contrast")))


## Escala o texto e dá foco visível a uma tela ou caixa recém-criada ou aberta.
func _apply_accessibility(node: Control) -> void:
	VNUIAccessibility.apply_focus_style(node, focus_color())
	VNUIAccessibility.apply_text_scale(node, text_scale())
	if node is VNUIDialog and node.panel != null:
		var hc := bool(get_setting(&"high_contrast"))
		var colors := dialog_colors()
		if hc:
			var sb := StyleBoxFlat.new()
			sb.bg_color = colors.panel
			sb.set_content_margin_all(24)
			node.panel.add_theme_stylebox_override(&"panel", sb)
			node.label.add_theme_color_override(&"default_color", colors.text)
		else:
			node.panel.remove_theme_stylebox_override(&"panel")
			node.label.remove_theme_color_override(&"default_color")


func _reapply_accessibility() -> void:
	var nodes: Array = _stack.duplicate()
	nodes.append_array(_dialogs)
	if _hud != null:
		nodes.append(_hud)
	for n in nodes:
		_apply_accessibility(n)


## Atualiza os controles ligados à configuração nas telas abertas, sem disparar sinal.
func _sync_bound_controls(key: String) -> void:
	var screens: Array = _stack.duplicate()
	if _hud != null:
		screens.append(_hud)
	var value: Variant = get_setting(StringName(key))
	for s: VNUIScreen in screens:
		for id in s.order:
			var def := s.definition(id)
			if String(def.get("bind", "")) != key:
				continue
			var fc := VNUIElements.focus_control(s.elements[id])
			if fc is Range and (value is float or value is int):
				fc.set_value_no_signal(float(value))
			elif fc is CheckButton:
				fc.set_pressed_no_signal(bool(value))
			elif fc is OptionButton:
				var opts: Array = fc.get_meta(&"vn_options", [])
				for i in opts.size():
					if VNUIElements._same_value(opts[i].value, value):
						fc.select(i)
		if key == "show_hotspots":
			for id in s.order:
				if s.elements[id] is VNUIHotspot:
					s.elements[id].show_always = bool(value)
					s.elements[id].queue_redraw()


# --- Entrada (RT §10.1; UI Spec §1 princípio 4) ------------------------------

## A atividade em curso captura a entrada (Plugin SDK §4.2).
func activity_captures_input() -> bool:
	var m := modules()
	if m == null or m.plugins == null:
		return false
	var act: Dictionary = m.plugins.current_activity()
	return not act.is_empty() and bool(act.get("input_capture", act.get("capture", false)))


## Durante uma atividade com [code]input.capture[/code], só os elementos da
## [code]hud[/code] com [code]during_activity: true[/code] recebem input (UI Spec §12).
func _apply_activity_capture() -> void:
	if _hud == null:
		return
	var capture := activity_captures_input()
	for id in _hud.order:
		var fc := VNUIElements.focus_control(_hud.elements[id])
		if fc == null:
			continue
		var allowed := not capture or bool(_hud.definition(id).get("during_activity", false))
		fc.set_meta(&"vn_capture_blocked", not allowed)
		fc.mouse_filter = Control.MOUSE_FILTER_STOP if allowed else Control.MOUSE_FILTER_IGNORE


## Trata uma entrada; devolve [code]true[/code] se ela foi consumida.
func handle_input(event: InputEvent) -> bool:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventMouseButton or event is InputEventAction):
		return false
	if not event.is_pressed() or event.is_echo() and not _is_direction(event):
		return false
	# Caixa de confirmação ou mensagem: só ela responde.
	if not _dialogs.is_empty():
		var d := _dialogs[-1]
		if event.is_action_pressed(&"vn_cancel"):
			d.answer(false)
		elif event.is_action_pressed(&"vn_left") or event.is_action_pressed(&"vn_up"):
			d.move_focus(-1)
		elif event.is_action_pressed(&"vn_right") or event.is_action_pressed(&"vn_down"):
			d.move_focus(1)
		elif event.is_action_pressed(&"vn_confirm"):
			d.press_focused()
		else:
			return event is InputEventKey or event is InputEventJoypadButton
		return true
	var top := top_screen()
	if _popup_open(top):
		return false
	var capture := activity_captures_input()
	# Atalhos (shortcut) da tela do topo; sem tela, da hud.
	var target := top if top != null else _hud
	if target != null and not (capture and target != _hud):
		for id in target.order:
			var def := target.definition(id)
			if def.has("shortcut") and InputMap.has_action(StringName(def.shortcut)) and event.is_action_pressed(StringName(def.shortcut)):
				if capture and not bool(def.get("during_activity", false)):
					continue
				if target.is_element_enabled(id):
					element_activated(target, id)
					return true
	# vn_menu: com a pilha vazia, abre a pausa (no modo livre, pergunta se sai do minijogo).
	if top == null and event.is_action_pressed(&"vn_menu"):
		var m := modules()
		var act: Dictionary = m.plugins.current_activity() if m != null and m.plugins != null else {}
		if not act.is_empty() and act.get("mode") == VNPluginHost.MODE_FREE_PLAY:
			confirm("runtime/confirm/quit_activity", func(ok: bool):
				if ok:
					modules().plugins.cancel_activity(VNPluginHost.STATUS_CANCELLED))
			return true
		if in_game() and _bundle.get("ui", {}).has("pause"):
			open_screen("pause")
			return true
		return false
	if top == null or capture and top != null and modules().plugins.current_activity().get("mode") == VNPluginHost.MODE_FREE_PLAY:
		return false
	if event.is_action_pressed(&"vn_cancel"):
		var back: Array = top.data.get("back", [] if top.screen_id == "title" else [{"do": "close_screen"}])
		run_actions(back, {"screen": top.screen_id, "list": "back"})
		return true
	var focus := top.get_viewport().gui_get_focus_owner() if top.is_inside_tree() else null
	if event.is_action_pressed(&"vn_left") or event.is_action_pressed(&"vn_right"):
		if focus is Range and focus.editable and top.is_ancestor_of(focus):
			var step: float = focus.step if focus.step > 0.0 else (focus.max_value - focus.min_value) / 20.0
			focus.value += step if event.is_action_pressed(&"vn_right") else -step
			return true
		top.move_focus(Vector2.RIGHT if event.is_action_pressed(&"vn_right") else Vector2.LEFT)
		return true
	if event.is_action_pressed(&"vn_up"):
		top.move_focus(Vector2.UP)
		return true
	if event.is_action_pressed(&"vn_down"):
		top.move_focus(Vector2.DOWN)
		return true
	if event.is_action_pressed(&"vn_confirm"):
		if focus == null or not top.is_ancestor_of(focus):
			top.focus_first()
			return true
		if focus is VNUIHotspot:
			focus.activated.emit()
		elif focus is OptionButton:
			focus.show_popup()
		elif focus is CheckButton:
			focus.button_pressed = not focus.button_pressed
		elif focus is BaseButton and not focus.disabled:
			focus.pressed.emit()
		return true
	return false


func _is_direction(event: InputEvent) -> bool:
	for a in [&"vn_up", &"vn_down", &"vn_left", &"vn_right"]:
		if InputMap.has_action(a) and event.is_action(a):
			return true
	return false


func _popup_open(top: VNUIScreen) -> bool:
	if top == null:
		return false
	for id in top.order:
		var fc := VNUIElements.focus_control(top.elements[id])
		if fc is OptionButton and fc.get_popup().visible:
			return true
	return false


static func _detect_platform() -> String:
	match OS.get_name():
		"Windows": return "windows"
		"macOS": return "macos"
		"Web": return "web"
	return "linux"
