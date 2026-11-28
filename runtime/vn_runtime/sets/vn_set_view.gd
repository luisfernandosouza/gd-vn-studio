class_name VNSetView
extends Node2D
## Set composto desenhado (UI Spec §5; [code]set.schema.json[/code]): camadas
## com estados, animação, parallax e hotspots cosméticos. Serve ao fundo das
## telas (UI Manager) e ao fundo das cenas (Stage).
##
## [b]Camadas.[/b] Cada camada é um [Sprite2D] filho, com o nome do id, na ordem
## de [code]z[/code] e depois da lista (um vídeo [code].ogv[/code] vira um
## [VideoStreamPlayer] em loop). Sem [code]position[/code], a camada cobre a área
## visível, sem deformar (as camadas com [code]parallax[/code] cobrem uma
## margem a mais, para o deslocamento não mostrar a borda). Com
## [code]position[/code] e [code]pivot[/code], a imagem fica na fração da área
## base. As coordenadas são as da área base ([VNStageLayout]); quem põe a
## view na árvore a desloca para o centro da área visível.
##
## [b]Estados.[/b] [code]default[/code] é o estado inicial. [method set_state],
## [method toggle_state] e [method play_animation] mudam uma camada;
## [method show_layer], [method hide_layer] e [method toggle_visible] mudam
## só a visibilidade. [method states] devolve camada → estado, no formato de
## [code]save.schema.json → set_states[/code] (só camadas fora do
## [code]default[/code]). A visibilidade mudada por [code]show[/code]/[code]hide[/code]
## não vai no save: o schema guarda só nomes de estado.
##
## [b]Movimento.[/b] A animação da camada ([code]animation[/code], e a do
## estado) roda ao entrar no estado. [code]parallax[/code] move a camada com o
## mouse pelo [member Sprite2D.offset], para não competir com as animações.
## Com [code]reduce_motion[/code], só [code]fade[/code] anima (UI Spec §7.3) e o
## parallax fica desligado (UI Spec §5.1). O giroscópio não é lido no v1.
##
## [b]Hotspots.[/b] Os [VNSetHotspot]s ficam no nó [code]Hotspots[/code]. Só
## aceitam as ações cosméticas do UI Spec §5.1; outra ação é recusada (U004).
## Respondem enquanto [member gate] devolver [code]true[/code] (o Stage a usa
## para parar durante transição e minijogo).

## Camada mudou de estado ([param state] é o nome; [code]default[/code] volta ao início).
signal state_changed(layer: String, state: String)

## Ações aceitas num hotspot de set (UI Spec §5.1).
const COSMETIC_ACTIONS: Array[String] = [
	"set_state", "toggle_state", "play_animation", "play_sfx", "show", "hide", "toggle_visible",
]

const DEFAULT_STATE := "default"
const _ALPHA_THRESHOLD := 0.1

## id do set.
var set_id: String = ""
## Resolução base.
var base_size := Vector2(1920, 1080)
## Tamanho da área visível, em pixels da base (cobertura das camadas sem posição).
var view_size := Vector2(1920, 1080)
## [code]PlayerSettings.reduce_motion[/code]: sem parallax e só [code]fade[/code].
var reduce_motion := false
## [code]PlayerSettings.show_hotspots[/code]: destaca todos os hotspots.
var show_hotspots := false
## Os hotspots são alcançáveis por teclado e gamepad (telas: sim; cenas: não).
var keyboard_focus := false
## [code]func() -> bool[/code]: os hotspots respondem agora. Ausente = sempre.
var gate: Callable = Callable()
## [code]func(asset_id: String) -> Texture2D / VideoStream[/code].
var asset_loader: Callable = Callable()
## [code]func(path: String, fallback: String) -> String[/code]: texto traduzido.
var text_fn: Callable = Callable()
## [code]func(conditions: Array) -> bool[/code]: condições de [code]if[/code].
var check_fn: Callable = Callable()
## [code]func(asset_id: String)[/code]: toca um som da ação [code]play_sfx[/code].
var sfx_fn: Callable = Callable()

var _def: Dictionary = {}
var _layers: Dictionary = {}       # id → definição da camada
var _nodes: Dictionary = {}        # id → CanvasItem da camada
var _order: Array[String] = []
var _states: Dictionary = {}       # id → nome do estado atual
var _hidden: Dictionary = {}       # id → true (visibilidade mudada por ação)
var _tweens: Dictionary = {}       # id → Tween
var _hotspots_node: Control = null
var _hotspots: Dictionary = {}     # id → VNSetHotspot
var _hotspot_defs: Dictionary = {}
var _masks: Dictionary = {}        # id da camada → { texture, bitmap, outlines }
var _built := false


# --- Montagem ----------------------------------------------------------------

## Monta as camadas e os hotspots de [param set_def] com os estados
## [param states] (camada → estado; nome desconhecido vale [code]default[/code]).
func build(set_def: Dictionary, states: Dictionary = {}) -> void:
	clear()
	_def = set_def
	set_id = String(set_def.get("id", set_id))
	name = "Set_" + set_id
	for layer in set_def.get("layers", []):
		_layers[String(layer.get("id", ""))] = layer
	for lid in _layers:
		var sname := String(states.get(lid, DEFAULT_STATE))
		_states[lid] = sname if _has_state(lid, sname) else DEFAULT_STATE
	var indexed: Array = []
	var i := 0
	for layer in set_def.get("layers", []):
		indexed.append([int(layer.get("z", 0)), i, layer])
		i += 1
	indexed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for item in indexed:
		var node := _make_layer(item[2])
		if node != null:
			add_child(node)
			_nodes[String(item[2].id)] = node
			_order.append(String(item[2].id))
	_hotspots_node = Control.new()
	_hotspots_node.name = "Hotspots"
	_hotspots_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotspots_node)
	for h in set_def.get("hotspots", []):
		_make_hotspot(h)
	_built = true
	_start_idle_animations()
	_update_hotspot_areas()
	set_process(_needs_process())


func clear() -> void:
	_kill_tweens()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_layers.clear()
	_nodes.clear()
	_order.clear()
	_states.clear()
	_hidden.clear()
	_hotspots.clear()
	_hotspot_defs.clear()
	_masks.clear()
	_hotspots_node = null
	_built = false


## Refaz o desenho com o tamanho de janela atual, mantendo estados e visibilidade.
func relayout() -> void:
	if not _built:
		return
	var hidden := _hidden.duplicate()
	build(_def, states_full())
	_hidden = hidden
	for lid in _hidden:
		if _nodes.has(lid):
			_nodes[lid].visible = false
	_update_hotspot_areas()


# --- Estados -----------------------------------------------------------------

## Camada → estado, só as que não estão em [code]default[/code]
## ([code]save.schema.json → set_states[/code]).
func states() -> Dictionary:
	var out := {}
	for lid in _states:
		if _states[lid] != DEFAULT_STATE:
			out[lid] = _states[lid]
	return out


## Camada → estado de todas as camadas.
func states_full() -> Dictionary:
	return _states.duplicate()


func state_of(layer: String) -> String:
	return String(_states.get(layer, ""))


func has_layer(layer: String) -> bool:
	return _layers.has(layer)


## O [CanvasItem] da camada, ou [code]null[/code] (sem textura).
func layer_node(layer: String) -> CanvasItem:
	return _nodes.get(layer)


func layer_ids() -> PackedStringArray:
	return PackedStringArray(_layers.keys())


## Máscara alfa de uma camada visível e com textura, para hotspots de [code]interact[/code]
## com área [code]layer[/code]: [code]{ bitmap, outlines, rect }[/code], com [code]rect[/code]
## em coordenadas da camada do Stage; vazio se a camada está escondida ou sem textura.
func layer_mask(layer: String) -> Dictionary:
	var node: CanvasItem = _nodes.get(layer)
	if not node is Sprite2D or not node.visible or node.texture == null:
		return {}
	var sp := node as Sprite2D
	var m := _mask_of(layer, sp.texture)
	if m.is_empty():
		return {}
	return {"bitmap": m.bitmap, "outlines": m.outlines,
		"rect": Rect2(sp.global_position, sp.texture.get_size() * sp.global_scale)}


func hotspot_node(hotspot_id: String) -> VNSetHotspot:
	return _hotspots.get(hotspot_id)


func hotspot_nodes() -> Array[VNSetHotspot]:
	var out: Array[VNSetHotspot] = []
	for id in _hotspots:
		out.append(_hotspots[id])
	return out


## Muda a camada para o estado; [code]false[/code] se a camada ou o estado não existem.
func set_state(layer: String, state: String) -> bool:
	if not _layers.has(layer) or not _has_state(layer, state):
		push_warning("Set %s: camada ou estado inexistente: %s/%s" % [set_id, layer, state])
		return false
	var changed: bool = _states[layer] != state
	_states[layer] = state
	_apply_state(layer)
	if changed:
		state_changed.emit(layer, state)
	return true


## Avança para o próximo estado de [param states]; estando fora da lista, vai
## para o primeiro (UI Spec §4, [code]toggle_state[/code]).
func toggle_state(layer: String, state_list: Array) -> bool:
	if state_list.is_empty():
		return false
	var idx := -1
	for i in state_list.size():
		if String(state_list[i]) == state_of(layer):
			idx = i
			break
	return set_state(layer, String(state_list[(idx + 1) % state_list.size()]))


func show_layer(layer: String) -> bool:
	return _set_visible(layer, true)


func hide_layer(layer: String) -> bool:
	return _set_visible(layer, false)


func toggle_visible(layer: String) -> bool:
	return _set_visible(layer, null)


## Toca a animação pronta na camada (uma vez, ou em loop com [code]loop[/code]).
func play_animation(layer: String, animation: Dictionary) -> bool:
	if not _nodes.has(layer):
		return false
	_play(layer, animation, false)
	return true


## Executa uma ação cosmética sobre o set. [param target] aceita o id da camada
## com ou sem o prefixo [code]set:[/code] ([code]stage:[/code] também, nas cenas).
## Devolve [code]false[/code] quando a ação não vale (outra ação, camada inexistente).
func apply_action(action: String, target: String, args: Dictionary = {}) -> bool:
	var layer := target.get_slice(":", 1) if target.contains(":") else target
	match action:
		"set_state": return set_state(layer, String(args.get("state", "")))
		"toggle_state": return toggle_state(layer, args.get("states", []))
		"play_animation": return play_animation(layer, args.get("animation", {}))
		"show": return show_layer(layer)
		"hide": return hide_layer(layer)
		"toggle_visible": return toggle_visible(layer)
	return false


## Executa uma lista de ações de hotspot, em ordem, com [code]if[/code]/[code]else[/code].
## Só as ações cosméticas valem; as outras são recusadas (U004).
func run_actions(actions: Array) -> void:
	for a in actions:
		if not a is Dictionary:
			continue
		if a.has("if") and check_fn.is_valid() and not bool(check_fn.call(a["if"])):
			if a.has("else"):
				run_actions(a["else"])
			continue
		var kind := String(a.get("do", ""))
		if not COSMETIC_ACTIONS.has(kind):
			push_warning("Set %s: ação não cosmética recusada: %s" % [set_id, kind])
			continue
		if kind == "play_sfx":
			if sfx_fn.is_valid():
				sfx_fn.call(String(a.get("asset", "")))
			continue
		var args := {}
		for k in ["state", "states", "animation"]:
			if a.has(k):
				args[k] = a[k]
		apply_action(kind, String(a.get("target", "")), args)


func _has_state(layer: String, state: String) -> bool:
	return state == DEFAULT_STATE or _layers.get(layer, {}).get("states", {}).has(state)


func _state_def(layer: String) -> Dictionary:
	var sname := String(_states.get(layer, DEFAULT_STATE))
	return _layers.get(layer, {}).get("states", {}).get(sname, {}) if sname != DEFAULT_STATE else {}


func _set_visible(layer: String, show: Variant) -> bool:
	var node: CanvasItem = _nodes.get(layer)
	if node == null:
		return false
	var v: bool = (not node.visible) if show == null else bool(show)
	node.visible = v
	if v:
		_hidden.erase(layer)
	else:
		_hidden[layer] = true
	_update_hotspot_areas()
	return true


# --- Camadas -----------------------------------------------------------------

func _make_layer(layer: Dictionary) -> CanvasItem:
	var lid := String(layer.get("id", ""))
	var st := _state_def(lid)
	var asset := String(st.get("asset", layer.get("asset", "")))
	var res: Variant = asset_loader.call(asset) if asset_loader.is_valid() else null
	var node: CanvasItem = null
	if res is Texture2D:
		node = _make_sprite(layer, res)
	elif res is VideoStream:
		node = _make_video(layer, res)
	if node == null:
		return null
	node.set_meta(&"vn_set_layer", true)
	node.visible = bool(st.get("visible", true))
	_apply_look(node, layer, st)
	return node


func _make_sprite(layer: Dictionary, tex: Texture2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = String(layer.id)
	sp.texture = tex
	sp.centered = false
	var rect := _layer_rect(layer, tex.get_size())
	sp.scale = Vector2.ONE * float(rect.scale)
	sp.position = (rect.rect as Rect2).position
	return sp


func _make_video(layer: Dictionary, stream: VideoStream) -> VideoStreamPlayer:
	var vp := VideoStreamPlayer.new()
	vp.name = String(layer.id)
	vp.stream = stream
	vp.loop = true
	vp.expand = true
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size := Vector2(base_size.x, base_size.y)
	if not layer.has("position"):
		var vr := VNStageLayout.visible_rect(base_size, view_size)
		vp.position = vr.position
		size = vr.size
	else:
		var s := float(layer.get("scale", 1.0))
		size = base_size * s
		var p: Array = layer.position
		var pv: Array = layer.get("pivot", [0.5, 0.5])
		vp.position = Vector2(float(p[0]), float(p[1])) * base_size - Vector2(float(pv[0]), float(pv[1])) * size
	vp.size = size
	vp.autoplay = true
	return vp


## Escala e retângulo da camada em coordenadas da base: cobrindo a área visível
## (com margem para o parallax) ou na posição escolhida.
func _layer_rect(layer: Dictionary, tex_size: Vector2) -> Dictionary:
	if layer.has("position"):
		var p: Array = layer.position
		var pv: Array = layer.get("pivot", [0.5, 0.5])
		var s := float(layer.get("scale", 1.0))
		var size := tex_size * s
		var pos := Vector2(float(p[0]) * base_size.x, float(p[1]) * base_size.y) - Vector2(float(pv[0]), float(pv[1])) * size
		return {"scale": s, "rect": Rect2(pos, size)}
	var margin := Vector2.ZERO
	if float(layer.get("parallax", 0.0)) > 0.0 and not reduce_motion:
		margin = base_size * float(layer.parallax)
	return VNStageLayout.cover_rect(base_size, view_size + margin * 2.0, tex_size)


## Opacidade, tint e visibilidade do estado (o nó já está na posição).
func _apply_look(node: CanvasItem, layer: Dictionary, st: Dictionary) -> void:
	var color := Color.WHITE
	if st.has("tint"):
		color = Color.from_string(String(st.tint), Color.WHITE)
	color.a *= float(st.get("opacity", layer.get("opacity", 1.0)))
	node.modulate = color


func _apply_state(layer: String) -> void:
	var lid := layer
	var old: CanvasItem = _nodes.get(lid)
	var layer_def: Dictionary = _layers[lid]
	var st := _state_def(lid)
	var asset := String(st.get("asset", layer_def.get("asset", "")))
	var res: Variant = asset_loader.call(asset) if asset_loader.is_valid() else null
	_kill_tween(lid)
	if old is Sprite2D and res is Texture2D:
		# Mesma camada: troca a textura e refaz posição e escala (a imagem pode ter outro tamanho).
		var rect := _layer_rect(layer_def, (res as Texture2D).get_size())
		old.texture = res
		old.scale = Vector2.ONE * float(rect.scale)
		old.position = (rect.rect as Rect2).position
		old.rotation = 0.0
		old.visible = bool(st.get("visible", true)) and not _hidden.has(lid)
		_apply_look(old, layer_def, st)
	else:
		var node := _make_layer(layer_def)
		var idx := old.get_index() if old != null else get_child_count() - 1
		if old != null:
			remove_child(old)
			old.queue_free()
		_nodes.erase(lid)
		if node != null:
			add_child(node)
			move_child(node, mini(idx, get_child_count() - 1))
			_nodes[lid] = node
			node.visible = node.visible and not _hidden.has(lid)
	_masks.erase(lid)
	var anim: Variant = st.get("animation", layer_def.get("animation"))
	if anim is Dictionary and _nodes.has(lid):
		_play(lid, anim, true)
	_update_hotspot_areas()


# --- Animação ----------------------------------------------------------------

func _start_idle_animations() -> void:
	for lid in _order:
		var anim: Variant = _state_def(lid).get("animation", _layers[lid].get("animation"))
		if anim is Dictionary:
			_play(lid, anim, true)


## Anima a camada. Com [code]reduce_motion[/code], só [code]fade[/code]. Uma
## animação sem [code]loop[/code] volta ao estado de repouso no fim.
func _play(lid: String, anim: Dictionary, idle: bool) -> void:
	var node: CanvasItem = _nodes.get(lid)
	if node == null or anim.is_empty() or not is_inside_tree():
		return
	var kind := String(anim.get("kind", "fade"))
	if reduce_motion and kind != "fade":
		return
	_kill_tween(lid)
	_rest(node)
	var duration := maxf(0.01, float(anim.get("duration", 0.3)))
	var delay := maxf(0.0, float(anim.get("delay", 0.0)))
	var amount := float(anim.get("amount", 0.0))
	var loop := bool(anim.get("loop", false))
	var tw := create_tween()
	_tweens[lid] = tw
	if loop:
		tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE if loop else _trans(String(anim.get("easing", "ease_out"))))
	tw.set_ease(_ease(String(anim.get("easing", "ease_out"))))
	var base_pos: Vector2 = node.position if node is Node2D else Vector2.ZERO
	var base_scale: Vector2 = node.scale if node is Node2D else Vector2.ONE
	var size: Vector2 = _node_size(node)
	if delay > 0.0:
		tw.tween_interval(delay)
	match kind:
		"fade":
			var a: float = node.modulate.a
			tw.tween_property(node, "modulate:a", 0.0, duration / 2.0)
			tw.tween_property(node, "modulate:a", a, duration / 2.0)
		"blink":
			var a2: float = node.modulate.a
			tw.tween_property(node, "modulate:a", 0.0, duration / 2.0)
			tw.tween_property(node, "modulate:a", a2, duration / 2.0)
		"float":
			var h := amount if amount > 0.0 else 8.0
			tw.tween_property(node, "position:y", base_pos.y - h, duration / 2.0)
			tw.tween_property(node, "position:y", base_pos.y, duration / 2.0)
		"slide":
			var dist := amount if amount > 0.0 else 120.0
			var off := Vector2(-dist, 0)
			match String(anim.get("from", "left")):
				"right": off = Vector2(dist, 0)
				"top": off = Vector2(0, -dist)
				"bottom": off = Vector2(0, dist)
			tw.tween_property(node, "position", base_pos + off, duration / 2.0)
			tw.tween_property(node, "position", base_pos, duration / 2.0)
		"shake":
			var d := amount if amount > 0.0 else 6.0
			var steps := 6
			for i in steps:
				var sign := 1.0 if i % 2 == 0 else -1.0
				tw.tween_property(node, "position:x", base_pos.x + sign * d * (1.0 - float(i) / steps), duration / steps)
			tw.tween_property(node, "position:x", base_pos.x, 0.0)
		"scale", "pulse":
			var k := amount if amount > 0.0 else (0.2 if kind == "scale" else 0.06)
			tw.tween_method(_scale_about_center.bind(node, base_pos, base_scale, size), 0.0, k, duration / 2.0)
			tw.tween_method(_scale_about_center.bind(node, base_pos, base_scale, size), k, 0.0, duration / 2.0)
		"rotate":
			var deg := amount if amount != 0.0 else 360.0
			tw.tween_method(_rotate_about_center.bind(node, base_pos, size), 0.0, deg_to_rad(deg), duration)
			tw.tween_callback(_rest.bind(node, base_pos, base_scale))
		_:
			tw.kill()
			_tweens.erase(lid)
			return
	if not loop:
		tw.tween_callback(_rest.bind(node, base_pos, base_scale))


func _scale_about_center(k: float, node: Node2D, base_pos: Vector2, base_scale: Vector2, size: Vector2) -> void:
	if not is_instance_valid(node):
		return
	var s := base_scale * (1.0 + k)
	node.scale = s
	# Mantém o centro da imagem no lugar.
	node.position = base_pos + size * (base_scale - s) / 2.0 / base_scale


func _rotate_about_center(angle: float, node: Node2D, base_pos: Vector2, size: Vector2) -> void:
	if not is_instance_valid(node):
		return
	var c := size / 2.0
	node.rotation = angle
	node.position = base_pos + c - c.rotated(angle)


## Volta a camada ao repouso (posição, escala e rotação do estado).
func _rest(node: CanvasItem, pos: Variant = null, scl: Variant = null) -> void:
	if not is_instance_valid(node) or not node is Node2D:
		return
	if pos is Vector2:
		node.position = pos
	if scl is Vector2:
		node.scale = scl
	node.rotation = 0.0


func _node_size(node: CanvasItem) -> Vector2:
	if node is Sprite2D and node.texture != null:
		return node.texture.get_size() * node.scale
	if node is Control:
		return node.size
	return Vector2.ZERO


static func _trans(easing: String) -> Tween.TransitionType:
	match easing:
		"linear": return Tween.TRANS_LINEAR
		"back": return Tween.TRANS_BACK
		"bounce": return Tween.TRANS_BOUNCE
		"elastic": return Tween.TRANS_ELASTIC
	return Tween.TRANS_QUAD


static func _ease(easing: String) -> Tween.EaseType:
	match easing:
		"ease_in": return Tween.EASE_IN
		"ease_in_out": return Tween.EASE_IN_OUT
	return Tween.EASE_OUT


func _kill_tween(lid: String) -> void:
	var tw: Tween = _tweens.get(lid)
	if tw != null and tw.is_valid():
		tw.kill()
	_tweens.erase(lid)


func _kill_tweens() -> void:
	for lid in _tweens.keys():
		_kill_tween(lid)


# --- Parallax ----------------------------------------------------------------

func _needs_process() -> bool:
	for id in _hotspots:
		if _hotspots[id].area.has("layer"):
			return true
	if reduce_motion:
		return false
	for lid in _layers:
		if float(_layers[lid].get("parallax", 0.0)) > 0.0:
			return true
	return false


func _process(_delta: float) -> void:
	if not reduce_motion:
		_apply_parallax(_pointer_normal())
	_follow_layer_hotspots()


## Posição do ponteiro em [code]-1..1[/code] em relação ao centro da janela.
func _pointer_normal() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var rect := vp.get_visible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ZERO
	var m := vp.get_mouse_position()
	return ((m - rect.position) / rect.size * 2.0 - Vector2.ONE).clamp(Vector2(-1, -1), Vector2.ONE)


## Desloca cada camada com [code]parallax[/code] até o máximo da fração da base
## para o lado oposto ao do ponteiro. Usa o [code]offset[/code] do sprite.
func _apply_parallax(normal: Vector2) -> void:
	for lid in _order:
		var amount := float(_layers[lid].get("parallax", 0.0))
		var node: CanvasItem = _nodes.get(lid)
		if amount <= 0.0 or not node is Sprite2D:
			continue
		var s: Vector2 = node.scale
		node.offset = (-normal * amount * base_size) / (s if s.x > 0.0 and s.y > 0.0 else Vector2.ONE)


## Desloca todas as camadas com parallax como o ponteiro em [param normal]
## (para os testes, sem mouse).
func set_parallax_pointer(normal: Vector2) -> void:
	_apply_parallax(normal)


# --- Hotspots ----------------------------------------------------------------

func _make_hotspot(def: Dictionary) -> void:
	var hid := String(def.get("id", ""))
	var h := VNSetHotspot.new()
	h.name = hid
	h.hotspot_id = hid
	h.definition = def
	h.area = def.get("area", {})
	h.highlight = String(def.get("highlight", "outline"))
	h.show_always = show_hotspots
	h.focus_mode = Control.FOCUS_ALL if keyboard_focus else Control.FOCUS_NONE
	var label := String(def.get("label", ""))
	if text_fn.is_valid() and def.has("label"):
		label = String(text_fn.call("sets/%s/%s" % [set_id, hid], label))
	h.accessibility_label = VNUIText.strip_markup(label)
	h.tooltip_text = h.accessibility_label
	var cursor := String(def.get("cursor", "default"))
	var tex: Texture2D = null
	if not VNSetHotspot.CURSOR_NAMES.has(cursor) and asset_loader.is_valid():
		tex = asset_loader.call(cursor) as Texture2D
	h.set_cursor(cursor, tex)
	h.set_meta(&"vn_id", hid)
	h.activated.connect(_on_hotspot.bind(hid, "on_press"))
	h.released.connect(_on_hotspot.bind(hid, "on_release"))
	h.mouse_entered.connect(_on_hotspot.bind(hid, "on_hover"))
	h.focus_entered.connect(_on_hotspot.bind(hid, "on_hover"))
	_hotspots[hid] = h
	_hotspot_defs[hid] = def
	_hotspots_node.add_child(h)


func _on_hotspot(hid: String, list: String) -> void:
	if gate.is_valid() and not bool(gate.call()):
		return
	var def: Dictionary = _hotspot_defs.get(hid, {})
	if def.has(list):
		run_actions(def[list])


## Aperta e solta o hotspot, como o [code]vn_confirm[/code] num hotspot focado.
func activate_hotspot(hid: String) -> void:
	var h: VNSetHotspot = _hotspots.get(hid)
	if h != null:
		h.activated.emit()
		h.released.emit()


func set_show_hotspots(value: bool) -> void:
	show_hotspots = value
	for id in _hotspots:
		_hotspots[id].show_always = value
		_hotspots[id].queue_redraw()


## Posiciona cada hotspot sobre a área dele. [code]rect[/code] e
## [code]polygon[/code] são frações da base; [code]layer[/code] usa a máscara
## alfa da camada. Um hotspot sobre camada escondida (ou sem textura) fica sem
## área, e um [code]character[/code] não vale fora do [code]interact[/code].
func _update_hotspot_areas() -> void:
	for id in _hotspots:
		var h: VNSetHotspot = _hotspots[id]
		var area: Dictionary = h.area
		if area.has("layer"):
			_fit_layer_hotspot(h, String(area.layer))
		elif area.has("rect") or area.has("polygon"):
			h.fit(Vector2.ZERO, base_size)
		else:
			h.fit(Vector2.ZERO, base_size)   # character: sem área (UI Spec §5.2, só em interact)


func _fit_layer_hotspot(h: VNSetHotspot, lid: String) -> void:
	var node: CanvasItem = _nodes.get(lid)
	if not node is Sprite2D or not node.visible or node.texture == null:
		h.set_mask(null, Rect2())
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	var sp := node as Sprite2D
	var m := _mask_of(lid, sp.texture)
	if m.is_empty():
		h.set_mask(null, Rect2())
		return
	h.set_mask(m.bitmap, Rect2(sp.position, sp.texture.get_size() * sp.scale), m.outlines)


## Máscara alfa e contornos da textura atual da camada, em cache até a troca de estado.
func _mask_of(lid: String, tex: Texture2D) -> Dictionary:
	var cached: Dictionary = _masks.get(lid, {})
	if not cached.is_empty() and cached.texture == tex:
		return cached
	var img := tex.get_image()
	if img == null or img.is_empty():
		return {}
	if img.is_compressed():
		img.decompress()
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, _ALPHA_THRESHOLD)
	var outlines: Array[PackedVector2Array] = []
	for poly in bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, bm.get_size()), 2.0):
		outlines.append(poly)
	var out := {"texture": tex, "bitmap": bm, "outlines": outlines}
	_masks[lid] = out
	return out


## Hotspots de camada seguem a camada enquanto ela se mexe (animação).
func _follow_layer_hotspots() -> void:
	for id in _hotspots:
		var h: VNSetHotspot = _hotspots[id]
		if not h.area.has("layer"):
			continue
		var node: CanvasItem = _nodes.get(String(h.area.layer))
		if node is Sprite2D and node.visible:
			h.position = node.position


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_kill_tweens()
