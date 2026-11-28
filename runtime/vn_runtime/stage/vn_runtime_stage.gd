class_name VNRuntimeStage
extends VNStage
## O Stage do jogo (tarefa M2-02): camadas fixas, escala, cenário,
## personagens e transições (RT §1.1, §5.2; DM §8 "Apresentação no palco",
## §10.2).
##
## [b]Camadas.[/b] [method attach] cria os [CanvasLayer]s do Stage
## ([constant OWN_LAYERS]) debaixo de um nó [code]Stage[/code]. Todas as
## camadas do Stage têm o mesmo [member CanvasLayer.offset], que põe a área
## base no centro da área visível; o cenário se estende até as bordas da janela.
##
## [b]Escala.[/b] Posições e tamanhos em pixels da resolução base
## ([code]project.json → settings.resolution[/code]). A conta fica em
## [VNStageLayout]. Quando a janela muda de tamanho, o palco é redesenhado.
##
## [b]Personagens.[/b] A âncora do sprite ([code]assets.json → anchor[/code],
## padrão [code][0.5, 1.0][/code]) fica na posição horizontal escolhida e na
## base da tela, com a [code]scale[/code] do asset. Personagens mostrados
## depois ficam na frente; um [code]show[/code] de quem já está no palco troca
## expressão e posição sem mudar a ordem. Não há [code]z[/code] no nó
## [code]show[/code] (scene.schema.json): a ordem de desenho é a de entrada, e é
## ela que [method snapshot] grava na lista [code]characters[/code].
##
## [b]Transições.[/b] [code]none[/code], [code]fade[/code] (o cenário passa
## pelo preto; numa personagem, igual a [code]dissolve[/code]),
## [code]dissolve[/code] (fusão), [code]slide_left[/code] e
## [code]slide_right[/code] (o novo entra pelo lado oposto ao sentido; numa
## personagem que já está no palco, ela desliza até a nova posição). Sem
## [code]duration[/code], vale [constant DEFAULT_DURATION]. Com
## [code]reduce_motion[/code] ligado, toda transição vira corte seco (Req §12).
## O próximo comando no mesmo alvo termina a transição anterior na hora
## (o Narrative Engine espera [method is_busy] antes, RT §5.2).
##
## [b]Sets.[/b] Um [code]background[/code] com [code]set[/code] vira um
## [VNSetView] (M2-08): camadas com estado, animação e parallax, e os hotspots
## cosméticos, que respondem a mouse e toque enquanto não há transição de
## cenário nem minijogo (UI Spec §5.1). O estado das camadas vai no
## [method snapshot]. As ações [code]stage:<camada>[/code] das telas chegam
## pelo sinal [signal VNRuntimeUIManager.set_target_action].
##
## [b]Fora desta tarefa.[/b] Caixa de texto e digitação (M2-03), escolhas e
## hotspots de [code]interact[/code] (M2-04), base por item do modo stream
## (M2-12) e miniatura do save (M2-10). Os métodos dessas partes guardam os
## dados e ficam documentados como tal.

## Camadas criadas pelo Stage. HUD (40) e telas (50) são do UI Manager;
## atividade (60) é do Plugin Host; a camada do sistema (100) é compartilhada.
const OWN_LAYERS: Array[int] = [
	VNLayers.BACKGROUND, VNLayers.CHARACTERS, VNLayers.HOTSPOTS,
	VNLayers.PLUGIN_OVERLAYS, VNLayers.TEXTBOX, VNLayers.SYSTEM,
]

## Tipos de transição de [code]scene.schema.json → Transition[/code].
const TRANSITIONS: Array[String] = ["none", "fade", "dissolve", "slide_left", "slide_right"]

## Duração de uma transição sem [code]duration[/code], em segundos.
const DEFAULT_DURATION := 0.5

## Alvo das transições do cenário (o das personagens é o id delas).
const BACKGROUND_TARGET := &"background"

## Cor por trás do cenário: aparece no meio de um [code]fade[/code] e quando
## não há cenário (o tema não tem cor de fundo própria no v1).
const BACKDROP_COLOR := Color.BLACK

## Força [code]reduce_motion[/code] ([code]true[/code]/[code]false[/code]);
## [code]null[/code] lê do UI Manager ([code]PlayerSettings.reduce_motion[/code]).
var reduce_motion_override: Variant = null

## Resolução base do projeto.
var base_size := Vector2(1920, 1080)

var _assets_meta: Dictionary = {}     # id → entrada de bundle.json → assets
var _character_defs: Dictionary = {}  # id → personagem do bundle
var _sets: Dictionary = {}            # id → set do bundle
var _placeholder: String = ""         # project.content_filter.placeholder
var _content_filter := false

var _root: Node = null
var _layers: Dictionary = {}          # layer → CanvasLayer
var _viewport: Viewport = null
var _backdrop: ColorRect = null
var _bg_holder: Node2D = null
var _bg_view: Node2D = null
var _ui_connected: Object = null

## Cenário atual: { asset: String | null, set: String | null, set_states: {} }.
var _bg: Dictionary = {"asset": null, "set": null, "set_states": {}}
## Personagens no palco: id → { expression, position, node: Node2D }.
var _chars: Dictionary = {}
## Ordem de desenho (de trás para a frente).
var _order: Array[String] = []
## Transições em andamento: alvo → Tween.
var _tweens: Dictionary = {}

# Dados guardados para as tarefas M2-03 e M2-04.
var _line: Dictionary = {}
var _choices: Array[Dictionary] = []
var _choices_prompt: String = ""
var _hotspots: Array[Dictionary] = []
var _exit_option: Dictionary = {}
var _textbox_hidden := false


func _init() -> void:
	base_size = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))


# --- Bundle e árvore ---------------------------------------------------------

func load_bundle(bundle: Dictionary) -> void:
	_assets_meta = bundle.get("assets", {})
	_character_defs = bundle.get("characters", {})
	_sets = bundle.get("sets", {})
	var project: Dictionary = bundle.get("project", {})
	var res: Variant = project.get("settings", {}).get("resolution")
	if res is Array and res.size() == 2 and float(res[0]) > 0 and float(res[1]) > 0:
		base_size = Vector2(float(res[0]), float(res[1]))
	_placeholder = String(project.get("content_filter", {}).get("placeholder", ""))
	if _root != null:
		_relayout()


func attach(parent: Node) -> void:
	detach()
	_root = Node.new()
	_root.name = "Stage"
	for layer in OWN_LAYERS:
		var cl := CanvasLayer.new()
		cl.layer = layer
		cl.name = VNLayers.layer_name(layer)
		_root.add_child(cl)
		_layers[layer] = cl
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = BACKDROP_COLOR
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers[VNLayers.BACKGROUND].add_child(_backdrop)
	_bg_holder = Node2D.new()
	_bg_holder.name = "Scenery"
	_layers[VNLayers.BACKGROUND].add_child(_bg_holder)
	_root.tree_entered.connect(_on_tree_entered)
	_root.tree_exiting.connect(_on_tree_exiting)
	parent.add_child(_root)
	_connect_ui()
	_redraw_all()


func detach() -> void:
	_disconnect_ui()
	_kill_tweens()
	if _root != null:
		if _root.is_inside_tree():
			_on_tree_exiting()
		_root.free()
	_root = null
	_layers.clear()
	_backdrop = null
	_bg_holder = null
	_bg_view = null
	for id in _chars:
		_chars[id].node = null


func get_layer(layer: int) -> CanvasLayer:
	return _layers.get(layer)


func _on_tree_entered() -> void:
	_viewport = _root.get_viewport()
	if _viewport != null and not _viewport.size_changed.is_connected(_relayout):
		_viewport.size_changed.connect(_relayout)
	_relayout()


func _on_tree_exiting() -> void:
	if _viewport != null and is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_relayout):
		_viewport.size_changed.disconnect(_relayout)
	_viewport = null


## Tamanho da área visível em pixels da resolução base: com
## [code]stretch_aspect = expand[/code], é a resolução base aumentada no eixo
## que sobra. Fora da árvore, é a própria resolução base.
func view_size() -> Vector2:
	if _root != null and _root.is_inside_tree():
		var s := _root.get_viewport().get_visible_rect().size
		if s.x > 0 and s.y > 0:
			return s
	return base_size


## A área visível em coordenadas da área base (pode começar em x ou y negativos).
func view_rect() -> Rect2:
	return VNStageLayout.visible_rect(base_size, view_size())


# --- Cenário -----------------------------------------------------------------

func set_background(node: Dictionary) -> void:
	_finish(BACKGROUND_TARGET)
	var state := {"asset": null, "set": null, "set_states": {}}
	if node.has("set"):
		var set_id := String(node.get("set", ""))
		if not _sets.has(set_id):
			push_warning("Stage: set desconhecido: %s" % set_id)
		state.set = set_id
	else:
		var asset := String(node.get("asset", ""))
		if not _assets_meta.has(asset):
			push_warning("Stage: asset de cenário desconhecido: %s" % asset)
		state.asset = asset
	_bg = state
	if _bg_holder == null:
		transition_finished.emit(BACKGROUND_TARGET)
		return
	var old := _bg_view
	_bg_view = _make_background_view(state)
	_bg_holder.add_child(_bg_view)
	_play_background_transition(old, _bg_view, node.get("transition"))


func _play_background_transition(old: Node2D, new_view: Node2D, transition: Variant) -> void:
	var t := _transition_of(transition)
	if t.kind == "none" or t.duration <= 0.0:
		if old != null:
			old.get_parent().remove_child(old)
			old.queue_free()
		transition_finished.emit(BACKGROUND_TARGET)
		return
	var tw := _begin(BACKGROUND_TARGET)
	var w := view_size().x
	match t.kind:
		"fade":
			new_view.modulate.a = 0.0
			if old != null:
				tw.tween_property(old, "modulate:a", 0.0, t.duration / 2.0)
				tw.tween_callback(old.queue_free)
				tw.tween_property(new_view, "modulate:a", 1.0, t.duration / 2.0)
			else:
				tw.tween_property(new_view, "modulate:a", 1.0, t.duration)
		"dissolve":
			new_view.modulate.a = 0.0
			tw.tween_property(new_view, "modulate:a", 1.0, t.duration)
			if old != null:
				tw.tween_callback(old.queue_free)
		"slide_left", "slide_right":
			var dir := -1.0 if t.kind == "slide_left" else 1.0
			new_view.position.x = -dir * w
			tw.set_parallel(true)
			tw.tween_property(new_view, "position:x", 0.0, t.duration)
			if old != null:
				tw.tween_property(old, "position:x", dir * w, t.duration)
				tw.chain().tween_callback(old.queue_free)


## Monta o nó do cenário: o asset cobrindo a área visível, o [VNSetView] com o
## estado das camadas ou, sem nada para desenhar, um nó vazio sobre o fundo.
func _make_background_view(state: Dictionary) -> Node2D:
	var view := Node2D.new()
	view.name = "Background"
	if state.set != null:
		view.free()
		return _make_set_view(String(state.set), state.set_states)
	elif state.asset != null:
		var tex := _texture(String(state.asset))
		if tex == null and _resolve(String(state.asset)).is_empty() and not _placeholder.is_empty():
			tex = _texture(_placeholder)   # censored.hide: placeholder do projeto (DM §10.4)
		if tex != null:
			view.add_child(_cover_sprite(tex, "Image"))
	return view


func _cover_sprite(tex: Texture2D, node_name: String) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = node_name
	sp.texture = tex
	sp.centered = false
	_fit_cover(sp)
	return sp


func _fit_cover(sp: Sprite2D) -> void:
	var c := VNStageLayout.cover_rect(base_size, view_size(), sp.texture.get_size())
	sp.scale = Vector2.ONE * float(c.scale)
	sp.position = (c.rect as Rect2).position


## Monta o [VNSetView] do set com o estado das camadas e liga os hotspots ao
## palco: o estado novo vai para [code]_bg.set_states[/code] (e para o save).
func _make_set_view(set_id: String, states: Dictionary) -> VNSetView:
	var view := VNSetView.new()
	view.set_id = set_id
	view.base_size = base_size
	view.view_size = view_size()
	view.reduce_motion = reduce_motion()
	view.show_hotspots = _show_hotspots()
	view.asset_loader = _texture_or_video
	view.text_fn = _ui_text
	view.check_fn = _ui_check
	view.sfx_fn = _play_sfx
	view.gate = _set_gate
	var def: Dictionary = (_sets.get(set_id, {}) as Dictionary).duplicate()
	def["id"] = set_id
	view.build(def, states)
	view.state_changed.connect(func(_layer: String, _state: String):
		if _bg.set == set_id and view == _bg_view:
			_bg.set_states = view.states())
	return view


func _texture_or_video(asset_id: String) -> Resource:
	if asset_id.is_empty():
		return null
	var m := modules()
	if m == null or m.assets == null:
		return null
	return m.assets.load_asset(asset_id)


func _ui_text(path: String, fallback: String) -> String:
	var m := modules()
	if m != null and m.ui != null and m.ui.has_method("text"):
		return m.ui.text(path, fallback)
	return fallback


func _ui_check(conditions: Array) -> bool:
	var m := modules()
	if m != null and m.ui != null and m.ui.has_method("check"):
		return m.ui.check(conditions)
	return true


func _play_sfx(asset_id: String) -> void:
	var m := modules()
	if m != null and m.audio != null and not asset_id.is_empty():
		m.audio.play(asset_id, VNAudioManager.SFX)


func _show_hotspots() -> bool:
	var m := modules()
	if m != null and m.ui != null:
		var v: Variant = m.ui.get_setting(&"show_hotspots")
		return v is bool and v
	return false


## Os hotspots do set respondem em falas e escolhas, não durante a transição
## do cenário nem com um minijogo na tela (UI Spec §5.1).
func _set_gate() -> bool:
	if is_busy(BACKGROUND_TARGET):
		return false
	var m := modules()
	if m != null and m.plugins != null and not m.plugins.current_activity().is_empty():
		return false
	return true


## O [VNSetView] do cenário atual, ou [code]null[/code] (cenário de imagem, ou sem árvore).
func set_view() -> VNSetView:
	return _bg_view as VNSetView


func _connect_ui() -> void:
	var m := modules()
	if m == null or m.ui == null or _ui_connected == m.ui:
		return
	_disconnect_ui()
	_ui_connected = m.ui
	if m.ui.has_signal("set_target_action"):
		m.ui.connect("set_target_action", _on_set_target_action)
	m.ui.connect("setting_changed", _on_setting_changed)


func _disconnect_ui() -> void:
	if _ui_connected != null and is_instance_valid(_ui_connected):
		if _ui_connected.has_signal("set_target_action") and _ui_connected.is_connected("set_target_action", _on_set_target_action):
			_ui_connected.disconnect("set_target_action", _on_set_target_action)
		if _ui_connected.is_connected("setting_changed", _on_setting_changed):
			_ui_connected.disconnect("setting_changed", _on_setting_changed)
	_ui_connected = null


func _on_set_target_action(scope: StringName, target: String, action: StringName, args: Dictionary) -> void:
	var view := set_view()
	if scope == &"stage" and view != null:
		view.apply_action(String(action), target, args)


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	var view := set_view()
	if view == null:
		return
	if setting == &"show_hotspots":
		view.set_show_hotspots(bool(value))
	elif setting == &"reduce_motion" and reduce_motion_override == null:
		view.reduce_motion = bool(value)
		view.relayout()
		view.set_process(view._needs_process())


# --- Personagens -------------------------------------------------------------

func show_character(node: Dictionary) -> void:
	var id := String(node.get("character", ""))
	var def: Dictionary = _character_defs.get(id, {})
	if def.is_empty():
		push_warning("Stage: personagem desconhecida: %s" % id)
		return
	_finish(StringName(id))
	var current: Dictionary = _chars.get(id, {})
	var is_new := current.is_empty()
	var expression: Variant = node.get("expression", current.get("expression") if not is_new else def.get("default_expression"))
	if expression != null and not def.get("expressions", {}).has(String(expression)):
		push_warning("Stage: expressão '%s' não existe na personagem %s" % [expression, id])
		expression = current.get("expression") if not is_new else def.get("default_expression")
	var position: Variant = node.get("position", current.get("position", "center") if not is_new else "center")
	var entry := {"expression": expression, "position": position, "node": current.get("node")}
	_chars[id] = entry
	if is_new:
		_order.append(id)
	if _root == null:
		transition_finished.emit(StringName(id))
		return
	var t := _transition_of(node.get("transition"))
	var instant: bool = t.kind == "none" or t.duration <= 0.0
	if is_new or entry.node == null:
		entry.node = _make_character_node(id)
		_layers[VNLayers.CHARACTERS].add_child(entry.node)
		_restack()
		_place_character(id)
		if instant:
			transition_finished.emit(StringName(id))
			return
		var tw := _begin(StringName(id))
		var holder: Node2D = entry.node
		match t.kind:
			"fade", "dissolve":
				holder.modulate.a = 0.0
				tw.tween_property(holder, "modulate:a", 1.0, t.duration)
			"slide_left", "slide_right":
				var target_x := holder.position.x
				holder.position.x = _offscreen_x(holder, t.kind == "slide_left")
				tw.tween_property(holder, "position:x", target_x, t.duration)
		return
	# Já estava no palco: troca a expressão e move para a nova posição.
	var holder: Node2D = entry.node
	var old_sprite := holder.get_node_or_null("Sprite") as Sprite2D
	var new_sprite := _make_sprite(id)
	var changed_sprite: bool = old_sprite == null or new_sprite == null \
			or old_sprite.texture != new_sprite.texture or old_sprite.scale != new_sprite.scale or old_sprite.offset != new_sprite.offset
	var target := _character_point(position)
	if instant or not changed_sprite and holder.position == target:
		if changed_sprite:
			_swap_sprite(holder, old_sprite, new_sprite)
		elif new_sprite != null:
			new_sprite.free()
		holder.position = target
		transition_finished.emit(StringName(id))
		return
	var tw := _begin(StringName(id))
	tw.set_parallel(true)
	if holder.position != target:
		tw.tween_property(holder, "position", target, t.duration)
	if changed_sprite:
		if old_sprite != null:
			old_sprite.name = "OldSprite"
			tw.tween_property(old_sprite, "modulate:a", 0.0, t.duration)
			tw.chain().tween_callback(old_sprite.queue_free)
		if new_sprite != null:
			new_sprite.modulate.a = 0.0
			holder.add_child(new_sprite)
			tw.tween_property(new_sprite, "modulate:a", 1.0, t.duration)
	elif new_sprite != null:
		new_sprite.free()


func hide_character(node: Dictionary) -> void:
	var who := String(node.get("character", ""))
	var ids: Array[String] = []
	if who == "*":
		ids = _order.duplicate()
	elif _chars.has(who):
		ids = [who]
	for id in ids:
		_finish(StringName(id))
		var entry: Dictionary = _chars[id]
		_chars.erase(id)
		_order.erase(id)
		var holder: Node2D = entry.node
		var t := _transition_of(node.get("transition"))
		if holder == null or t.kind == "none" or t.duration <= 0.0:
			if holder != null:
				holder.get_parent().remove_child(holder)
				holder.queue_free()
			transition_finished.emit(StringName(id))
			continue
		holder.name = "Leaving_" + id
		var tw := _begin(StringName(id))
		match t.kind:
			"fade", "dissolve":
				tw.tween_property(holder, "modulate:a", 0.0, t.duration)
			"slide_left", "slide_right":
				tw.tween_property(holder, "position:x", _offscreen_x(holder, t.kind == "slide_right"), t.duration)
		tw.tween_callback(holder.queue_free)


func _make_character_node(id: String) -> Node2D:
	var holder := Node2D.new()
	holder.name = id
	var sp := _make_sprite(id)
	if sp != null:
		holder.add_child(sp)
	return holder


## O sprite da expressão atual, já resolvido pelo modo stream, com a âncora e
## a escala do asset que vale (a substituta usa as dela, RT §5.5).
## [code]null[/code] sem expressão ou com [code]censored.hide[/code].
func _make_sprite(id: String) -> Sprite2D:
	var entry: Dictionary = _chars.get(id, {})
	var expression: Variant = entry.get("expression")
	if expression == null:
		return null
	var asset := String(_character_defs.get(id, {}).get("expressions", {}).get(String(expression), ""))
	var tex := _texture(asset)
	if tex == null:
		return null
	var meta: Dictionary = _assets_meta.get(_resolve(asset), {})
	var anchor := VNStageLayout.anchor_of(meta)
	var s := VNStageLayout.scale_of(meta)
	var sp := Sprite2D.new()
	sp.name = "Sprite"
	sp.texture = tex
	sp.centered = false
	sp.offset = -anchor * tex.get_size()
	sp.scale = Vector2.ONE * s
	return sp


func _swap_sprite(holder: Node2D, old_sprite: Sprite2D, new_sprite: Sprite2D) -> void:
	if old_sprite != null:
		holder.remove_child(old_sprite)
		old_sprite.queue_free()
	if new_sprite != null:
		holder.add_child(new_sprite)


func _character_point(position: Variant) -> Vector2:
	return VNStageLayout.character_point(base_size, position)


func _place_character(id: String) -> void:
	var entry: Dictionary = _chars[id]
	if entry.node != null:
		(entry.node as Node2D).position = _character_point(entry.position)


## x da âncora com o sprite inteiro fora da área visível, à direita ou à esquerda.
func _offscreen_x(holder: Node2D, from_right: bool) -> float:
	var r := character_rect_of(holder)
	var vr := view_rect()
	if from_right:
		return holder.position.x + (vr.end.x - r.position.x)
	return holder.position.x - (r.end.x - vr.position.x)


## Personagens na ordem de entrada, a última na frente.
func _restack() -> void:
	var layer: CanvasLayer = _layers.get(VNLayers.CHARACTERS)
	if layer == null:
		return
	for id in _order:
		var n: Node = _chars[id].node
		if n != null and n.get_parent() == layer:
			layer.move_child(n, layer.get_child_count() - 1)


## Retângulo do sprite da personagem em coordenadas da área base (vazio se ela
## não está no palco ou não tem sprite). Serve para os hotspots
## [code]{ "character": … }[/code] do [code]interact[/code] (UI Spec §5.2).
func character_rect(id: String) -> Rect2:
	var entry: Dictionary = _chars.get(id, {})
	if entry.is_empty() or entry.node == null:
		return Rect2()
	return character_rect_of(entry.node)


func character_rect_of(holder: Node2D) -> Rect2:
	var sp := holder.get_node_or_null("Sprite") as Sprite2D
	if sp == null:
		return Rect2(holder.position, Vector2.ZERO)
	return Rect2(holder.position + sp.offset * sp.scale, sp.texture.get_size() * sp.scale)


## Ids das personagens no palco, de trás para a frente.
func character_order() -> PackedStringArray:
	return PackedStringArray(_order)


func is_busy(target: StringName) -> bool:
	var tw: Tween = _tweens.get(target)
	return tw != null and tw.is_valid() and tw.is_running()


## Termina na hora todas as transições em andamento (modo pular, carregar um
## save, mudar o tamanho da janela).
func skip_transitions() -> void:
	for target in _tweens.keys():
		_finish(target)


func clear() -> void:
	_kill_tweens()
	_bg = {"asset": null, "set": null, "set_states": {}}
	_chars.clear()
	_order.clear()
	if _bg_holder != null:
		for c in _bg_holder.get_children():
			_bg_holder.remove_child(c)
			c.queue_free()
	_bg_view = null
	var layer: CanvasLayer = _layers.get(VNLayers.CHARACTERS)
	if layer != null:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	clear_interaction()


# --- Transições --------------------------------------------------------------

## [code]{ kind, duration }[/code] de um [code]transition[/code] do nó, já com
## [code]reduce_motion[/code] aplicado (corte seco).
func _transition_of(transition: Variant) -> Dictionary:
	var kind := "none"
	var duration := DEFAULT_DURATION
	if transition is Dictionary:
		kind = String(transition.get("kind", "none"))
		if not TRANSITIONS.has(kind):
			push_warning("Stage: transição desconhecida: %s" % kind)
			kind = "none"
		var d: Variant = transition.get("duration")
		if d is float or d is int:
			duration = maxf(float(d), 0.0)
	if reduce_motion():
		kind = "none"
	return {"kind": kind, "duration": duration}


## [code]PlayerSettings.reduce_motion[/code] (ou [member reduce_motion_override]).
func reduce_motion() -> bool:
	if reduce_motion_override != null:
		return bool(reduce_motion_override)
	var m := modules()
	if m != null and m.ui != null:
		var v: Variant = m.ui.get_setting(&"reduce_motion")
		return v is bool and v
	return false


func _begin(target: StringName) -> Tween:
	_finish(target)
	var tw := _root.create_tween()
	_tweens[target] = tw
	tw.finished.connect(_on_tween_finished.bind(target, tw), CONNECT_ONE_SHOT)
	return tw


func _on_tween_finished(target: StringName, tw: Tween) -> void:
	if _tweens.get(target) == tw:
		_tweens.erase(target)
	transition_finished.emit(target)


## Termina na hora a transição do alvo, deixando o estado final.
func _finish(target: StringName) -> void:
	var tw: Tween = _tweens.get(target)
	if tw == null:
		return
	if tw.is_valid():
		tw.custom_step(1.0e6)
	if _tweens.get(target) == tw:
		_tweens.erase(target)
		if tw.is_valid():
			tw.kill()
		transition_finished.emit(target)


func _kill_tweens() -> void:
	for target in _tweens.keys():
		var tw: Tween = _tweens[target]
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()


# --- Desenho ----------------------------------------------------------------

func _resolve(asset_id: String) -> String:
	if asset_id.is_empty():
		return ""
	var m := modules()
	if m != null and m.assets != null:
		return m.assets.resolve_id(asset_id)
	return asset_id


func _texture(asset_id: String) -> Texture2D:
	if asset_id.is_empty():
		return null
	var m := modules()
	if m == null or m.assets == null:
		return null
	return m.assets.load_asset(asset_id) as Texture2D


## Recalcula o deslocamento das camadas e redesenha na hora (sem transição),
## com a resolução de assets atual.
func _relayout() -> void:
	if _root == null:
		return
	skip_transitions()
	var offset := VNStageLayout.base_offset(base_size, view_size())
	for layer in _layers:
		(_layers[layer] as CanvasLayer).offset = offset
	if _backdrop != null:
		var vr := view_rect()
		_backdrop.position = vr.position
		_backdrop.size = vr.size
	_redraw_all()


func _redraw_all() -> void:
	if _root == null:
		return
	skip_transitions()
	if _bg_holder != null:
		for c in _bg_holder.get_children():
			_bg_holder.remove_child(c)
			c.queue_free()
		_bg_view = null
		if _bg.asset != null or _bg.set != null:
			_bg_view = _make_background_view(_bg)
			_bg_holder.add_child(_bg_view)
	var layer: CanvasLayer = _layers.get(VNLayers.CHARACTERS)
	for id in _order:
		var entry: Dictionary = _chars[id]
		if entry.node != null and is_instance_valid(entry.node):
			(entry.node as Node).get_parent().remove_child(entry.node)
			(entry.node as Node).queue_free()
		entry.node = _make_character_node(id)
		layer.add_child(entry.node)
		_place_character(id)
	_restack()


# --- Texto, escolhas e hotspots (tarefas M2-03 e M2-04) ----------------------

## Guarda a fala; a caixa de texto e a digitação são da tarefa M2-03.
func show_line(line: Dictionary) -> void:
	_line = line


## Guarda as opções; os botões de escolha são da tarefa M2-04.
func show_choices(prompt: String, options: Array[Dictionary]) -> void:
	_choices_prompt = prompt
	_choices = options


## Guarda os hotspots; as áreas clicáveis na camada 15 são da tarefa M2-04.
func show_hotspots(hotspots: Array[Dictionary], exit_option: Dictionary = {}) -> void:
	_hotspots = hotspots
	_exit_option = exit_option


func clear_interaction() -> void:
	_line = {}
	_choices = []
	_choices_prompt = ""
	_hotspots = []
	_exit_option = {}


func set_textbox_hidden(hidden: bool) -> void:
	_textbox_hidden = hidden
	var layer: CanvasLayer = _layers.get(VNLayers.TEXTBOX)
	if layer != null:
		layer.visible = not hidden


# --- Modo stream, save e miniatura -------------------------------------------

## Redesenha o palco na hora com a resolução de assets do novo modo. Quem
## chama liga o modo no [VNAssets] antes. A volta à base por item
## ([code]censor[/code]/[code]base[/code], RT §5.5) é da tarefa M2-12.
func set_content_filter(enabled: bool) -> void:
	_content_filter = enabled
	_redraw_all()


func snapshot() -> Dictionary:
	var out := {"background": _bg.asset}
	if _bg.set != null:
		out.background = null
		out["set"] = _bg.set
		out["set_states"] = (_bg.set_states as Dictionary).duplicate()
	var chars: Array = []
	for id in _order:
		var c := {"id": id}
		if _chars[id].expression != null:
			c["expression"] = _chars[id].expression
		if _chars[id].position != null:
			c["position"] = _chars[id].position
		chars.append(c)
	out["characters"] = chars
	return out


## Restaura sem transição, na ordem gravada (RT §8.3 passo 7).
func restore(stage: Dictionary) -> void:
	clear()
	var set_id: Variant = stage.get("set")
	if set_id != null and String(set_id) != "":
		_bg = {"asset": null, "set": String(set_id), "set_states": (stage.get("set_states", {}) as Dictionary).duplicate()}
	elif stage.get("background") != null:
		_bg = {"asset": String(stage.background), "set": null, "set_states": {}}
	for c in stage.get("characters", []):
		var id := String(c.get("id", ""))
		if not _character_defs.has(id) or _chars.has(id):
			continue
		_chars[id] = {"expression": c.get("expression"), "position": c.get("position", "center"), "node": null}
		_order.append(id)
	_redraw_all()


## Miniatura do save: da tarefa M2-10. Por enquanto, uma imagem vazia.
func capture_thumbnail() -> Image:
	return Image.create_empty(320, 180, false, Image.FORMAT_RGB8)


## Algum asset desenhado tem [code]censored[/code] e o modo está desligado (RT §8.5).
func is_showing_sensitive() -> bool:
	if _content_filter:
		return false
	var ids: Array[String] = []
	if _bg.asset != null:
		ids.append(String(_bg.asset))
	if _bg.set != null:
		for layer in _sets.get(String(_bg.set), {}).get("layers", []):
			var sname := String(_bg.set_states.get(String(layer.get("id", "")), "default"))
			ids.append(String(layer.get("states", {}).get(sname, {}).get("asset", layer.get("asset", ""))))
	for id in _order:
		var e: Variant = _chars[id].expression
		if e != null:
			ids.append(String(_character_defs.get(id, {}).get("expressions", {}).get(String(e), "")))
	for a in ids:
		if _assets_meta.get(a, {}).has("censored"):
			return true
	return false
