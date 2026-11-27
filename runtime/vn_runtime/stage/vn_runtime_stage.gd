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
## [b]Fora desta tarefa.[/b] Caixa de texto e digitação (M2-03), escolhas e
## hotspots de [code]interact[/code] (M2-04), animação, parallax e hotspots
## cosméticos de sets (M2-08; aqui o set é desenhado parado, com o estado das
## camadas) e miniatura do save (M2-10). Os métodos dessas partes guardam os
## dados e ficam documentados como tal.
##
## [b]Modo stream (M2-12).[/b] O Stage guarda sempre os ids [b]originais[/b] e,
## por item, a marca [code]censor[/code] do passo que o pôs e o estado a que ele
## volta quando o passo não vale (RT §5.5, decisões D19 e D24): [code]_bg_base[/code]
## para o cenário (o último posto por um passo sem [code]censor[/code]) e
## [code]base[/code] para cada personagem (expressão e posição de imediatamente
## antes do passo censurado). [method set_content_filter] e [method restore]
## desenham cada item pelo que vale no modo atual, sem transição, e o item
## continua no estado para reaparecer se o modo voltar. [method displayed]
## devolve o que está na tela, com os ids originais (o [code]stage[/code] dos
## vetores da spec 08).

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

## Cenário atual: { asset: String | null, set: String | null, set_states: {} }.
var _bg: Dictionary = {"asset": null, "set": null, "set_states": {}}
## Modo stream: [code]censor[/code] do passo que pôs o cenário ("" = sem) e o
## último cenário posto por um passo sem [code]censor[/code]
## ([code]null[/code] ou um estado como [member _bg]).
var _bg_censor := ""
var _bg_base: Variant = null
## Personagens no palco: id → { expression, position, node: Node2D,
## censor: String?, base: { expression, position }? }.
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
	_redraw_all()


func detach() -> void:
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
	var censor := String(node.get("censor", ""))
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
	_bg_censor = censor
	if censor.is_empty():
		_bg_base = state.duplicate(true)   # a base é o último passo sem censor (D19)
	if _bg_holder == null:
		transition_finished.emit(BACKGROUND_TARGET)
		return
	var old := _bg_view
	_bg_view = _make_background_view(_bg_shown())
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


## Monta o nó do cenário: o asset cobrindo a área visível, o set parado com o
## estado das camadas ou, sem nada para desenhar, um nó vazio sobre o fundo.
func _make_background_view(state: Dictionary) -> Node2D:
	var view := Node2D.new()
	view.name = "Background"
	if state.set == null and state.asset == null:
		# Sem cenário no modo atual (passo censurado sem base): placeholder, senão a cor do fundo.
		if not _placeholder.is_empty():
			var ptex := _texture(_placeholder)
			if ptex != null:
				view.add_child(_cover_sprite(ptex, "Image"))
	elif state.set != null:
		view.name = "Set_" + String(state.set)
		_build_set(view, String(state.set), state.set_states)
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


## Set parado (UI Spec §5): camadas na ordem de [code]z[/code] e depois da
## lista, com o estado de [param states] ([code]asset[/code],
## [code]visible[/code], [code]opacity[/code], [code]tint[/code]). Animação,
## parallax e hotspots cosméticos são da tarefa M2-08.
func _build_set(view: Node2D, set_id: String, states: Dictionary) -> void:
	var set_def: Dictionary = _sets.get(set_id, {})
	var layers: Array = set_def.get("layers", []).duplicate()
	var indexed: Array = []
	for i in layers.size():
		indexed.append([int(layers[i].get("z", 0)), i, layers[i]])
	indexed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for item in indexed:
		var layer: Dictionary = item[2]
		var lid := String(layer.get("id", ""))
		var st: Dictionary = {}
		var sname := String(states.get(lid, "default"))
		if sname != "default":
			st = layer.get("states", {}).get(sname, {})
		var asset := String(st.get("asset", layer.get("asset", "")))
		var tex := _texture(asset)
		if tex == null:
			continue
		var sp: Sprite2D
		if layer.has("position"):
			sp = Sprite2D.new()
			sp.name = lid
			sp.texture = tex
			sp.centered = false
			var p: Array = layer.position
			var pv: Array = layer.get("pivot", [0.5, 0.5])
			var s := float(layer.get("scale", 1.0))
			var size := tex.get_size() * s
			sp.scale = Vector2.ONE * s
			sp.position = Vector2(float(p[0]) * base_size.x, float(p[1]) * base_size.y) - Vector2(float(pv[0]), float(pv[1])) * size
		else:
			sp = _cover_sprite(tex, lid)
		sp.set_meta(&"vn_set_layer", true)
		sp.visible = bool(st.get("visible", true))
		var color := Color.WHITE
		if st.has("tint"):
			color = Color.from_string(String(st.tint), Color.WHITE)
		color.a *= float(st.get("opacity", layer.get("opacity", 1.0)))
		sp.modulate = color
		view.add_child(sp)


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
	var censor := String(node.get("censor", ""))
	if not censor.is_empty():
		entry["censor"] = censor
		if not is_new:
			if current.has("censor"):
				if current.has("base"):
					entry["base"] = (current.base as Dictionary).duplicate()   # dois passos seguidos: a base passa adiante
			else:
				entry["base"] = {"expression": current.expression, "position": current.position}
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
	var entry: Dictionary = _char_shown(id)
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
		(entry.node as Node2D).position = _character_point(_char_shown(id).get("position", entry.position))


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
	_bg_censor = ""
	_bg_base = null
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
		_bg_view = _make_background_view(_bg_shown())
		_bg_holder.add_child(_bg_view)
	var layer: CanvasLayer = _layers.get(VNLayers.CHARACTERS)
	for id in _order:
		var entry: Dictionary = _chars[id]
		if entry.node != null and is_instance_valid(entry.node):
			(entry.node as Node).get_parent().remove_child(entry.node)
			(entry.node as Node).queue_free()
		entry.node = null
		if _char_shown(id).is_empty():
			continue   # passo censurado sem base: fora de cena neste modo
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

## Redesenha o palco na hora, sem transição, com a resolução de assets e a
## base por item do novo modo (RT §5.5). Quem chama liga o modo no [VNAssets]
## antes.
func set_content_filter(enabled: bool) -> void:
	_content_filter = enabled
	_redraw_all()


## O passo [param censor] vale no modo atual (RT §5.5).
func _censor_applies(censor: String) -> bool:
	match censor:
		"skip": return not _content_filter
		"only": return _content_filter
	return true


## O cenário que vale no modo atual: o do passo, a base (passo [code]censor[/code]
## que não vale) ou, sem base, um estado vazio (placeholder ou cor do fundo).
func _bg_shown() -> Dictionary:
	if _censor_applies(_bg_censor):
		return _bg
	if _bg_base is Dictionary:
		return _bg_base
	return {"asset": null, "set": null, "set_states": {}}


## A expressão e a posição que valem no modo atual: as do passo, a [code]base[/code]
## ou [code]{}[/code] (a personagem sai de cena enquanto o passo não vale).
func _char_shown(id: String) -> Dictionary:
	var e: Dictionary = _chars.get(id, {})
	if e.is_empty() or _censor_applies(String(e.get("censor", ""))):
		return e
	return e.get("base", {})


## O que está na tela agora, com os ids originais, no formato do
## [code]stage[/code] dos vetores da spec 08: [code]background[/code] (asset,
## [code]{ "set": … }[/code] ou [code]null[/code]) e [code]characters[/code]
## (id, expressão e posição). Sem o áudio, que é do [VNAudioManager].
func displayed() -> Dictionary:
	var b := _bg_shown()
	var bg: Variant = null
	if b.set != null:
		bg = {"set": b.set}
	elif b.asset != null:
		bg = b.asset
	var chars: Array = []
	for id in _order:
		var e := _char_shown(id)
		if e.is_empty():
			continue
		var c := {"id": id}
		if e.get("expression") != null:
			c["expression"] = e.expression
		if e.get("position") != null:
			c["position"] = e.position
		chars.append(c)
	return {"background": bg, "characters": chars}


func snapshot() -> Dictionary:
	var out := {"background": _bg.asset}
	if _bg.set != null:
		out.background = null
		out["set"] = _bg.set
		out["set_states"] = (_bg.set_states as Dictionary).duplicate()
	if not _bg_censor.is_empty():
		out["background_censor"] = _bg_censor
		out["background_base"] = _bg_base_to_save()
	var chars: Array = []
	for id in _order:
		var c := {"id": id}
		if _chars[id].expression != null:
			c["expression"] = _chars[id].expression
		if _chars[id].position != null:
			c["position"] = _chars[id].position
		if _chars[id].has("censor"):
			c["censor"] = _chars[id].censor
			if _chars[id].has("base"):
				c["base"] = (_chars[id].base as Dictionary).duplicate()
		chars.append(c)
	out["characters"] = chars
	return out


## [code]background_base[/code] no formato do save: o asset, [code]{ set, set_states }[/code] ou [code]null[/code].
func _bg_base_to_save() -> Variant:
	if not (_bg_base is Dictionary):
		return null
	if _bg_base.set != null:
		return {"set": _bg_base.set, "set_states": (_bg_base.set_states as Dictionary).duplicate()}
	return _bg_base.asset


## Restaura sem transição, na ordem gravada, já no modo atual (RT §8.3 passo 7).
func restore(stage: Dictionary) -> void:
	clear()
	var set_id: Variant = stage.get("set")
	if set_id != null and String(set_id) != "":
		_bg = {"asset": null, "set": String(set_id), "set_states": (stage.get("set_states", {}) as Dictionary).duplicate()}
	elif stage.get("background") != null:
		_bg = {"asset": String(stage.background), "set": null, "set_states": {}}
	var censor := String(stage.get("background_censor", ""))
	if censor == "skip" or censor == "only":
		_bg_censor = censor
		var base: Variant = stage.get("background_base")
		if base is Dictionary and base.has("set"):
			_bg_base = {"asset": null, "set": String(base.set), "set_states": (base.get("set_states", {}) as Dictionary).duplicate()}
		elif base != null and base is String and not String(base).is_empty():
			_bg_base = {"asset": String(base), "set": null, "set_states": {}}
	else:
		_bg_base = _bg.duplicate(true) if (_bg.asset != null or _bg.set != null) else null
	for c in stage.get("characters", []):
		var id := String(c.get("id", ""))
		if not _character_defs.has(id) or _chars.has(id):
			continue
		var entry := {"expression": c.get("expression"), "position": c.get("position", "center"), "node": null}
		var cc := String(c.get("censor", ""))
		if cc == "skip" or cc == "only":
			entry["censor"] = cc
			if c.get("base") is Dictionary:
				var b: Dictionary = c.base
				entry["base"] = {"expression": b.get("expression"), "position": b.get("position", "center")}
		_chars[id] = entry
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
	var b := _bg_shown()
	if b.asset != null:
		ids.append(String(b.asset))
	if b.set != null:
		for layer in _sets.get(String(b.set), {}).get("layers", []):
			var sname := String(b.set_states.get(String(layer.get("id", "")), "default"))
			ids.append(String(layer.get("states", {}).get(sname, {}).get("asset", layer.get("asset", ""))))
	for id in _order:
		var e: Variant = _char_shown(id).get("expression")
		if e != null:
			ids.append(String(_character_defs.get(id, {}).get("expressions", {}).get(String(e), "")))
	for a in ids:
		if _assets_meta.get(a, {}).has("censored"):
			return true
	return false
