class_name VNUIAnimator
extends RefCounted
## Animações prontas dos elementos de tela (UI Spec §7.3): [code]appear[/code]
## e a ação [code]play_animation[/code]. Presets: [code]fade[/code],
## [code]slide[/code], [code]scale[/code], [code]pulse[/code], [code]float[/code],
## [code]shake[/code], [code]rotate[/code], [code]blink[/code]. Com
## [code]reduce_motion[/code], só [code]fade[/code] (o resto vira corte seco).
## O acabamento fino (estilos, [code]idle[/code], easing do tema) é da tarefa M2-07.


## Anima [param node] conforme [param anim] ([code]theme.schema.json → Animation[/code]).
## [param appear] = animação de entrada (parte do estado "fora" e chega ao normal).
static func play(node: Control, anim: Dictionary, reduce_motion: bool = false, appear: bool = false) -> Tween:
	if node == null or not node.is_inside_tree() or anim.is_empty():
		return null
	var kind := String(anim.get("kind", "fade"))
	if reduce_motion and kind != "fade":
		return null
	var duration := maxf(0.0, float(anim.get("duration", 0.3)))
	var delay := maxf(0.0, float(anim.get("delay", 0.0)))
	var amount := float(anim.get("amount", 0.0))
	var loops := 0 if bool(anim.get("loop", false)) else 1
	var tw := node.create_tween()
	tw.set_trans(_trans(String(anim.get("easing", "ease_out"))))
	tw.set_ease(_ease(String(anim.get("easing", "ease_out"))))
	if delay > 0.0:
		tw.tween_interval(delay)
	match kind:
		"fade":
			if appear:
				node.modulate.a = 0.0
				tw.tween_property(node, "modulate:a", 1.0, duration)
			else:
				var a := node.modulate.a
				tw.tween_property(node, "modulate:a", 0.0, duration / 2.0)
				tw.tween_property(node, "modulate:a", a, duration / 2.0)
		"slide":
			var dist := amount if amount > 0.0 else 120.0
			var off := _from_offset(String(anim.get("from", "left")), dist)
			var target := node.position
			if appear:
				node.position = target + off
				node.modulate.a = 0.0
				tw.tween_property(node, "position", target, duration)
				tw.parallel().tween_property(node, "modulate:a", 1.0, duration)
			else:
				tw.tween_property(node, "position", target + off, duration / 2.0)
				tw.tween_property(node, "position", target, duration / 2.0)
		"scale":
			_center_pivot(node)
			var s := amount if amount > 0.0 else 0.2
			if appear:
				node.scale = Vector2.ONE * (1.0 - s)
				tw.tween_property(node, "scale", Vector2.ONE, duration)
			else:
				tw.tween_property(node, "scale", Vector2.ONE * (1.0 + s), duration / 2.0)
				tw.tween_property(node, "scale", Vector2.ONE, duration / 2.0)
		"pulse":
			_center_pivot(node)
			var p := amount if amount > 0.0 else 0.06
			tw.tween_property(node, "scale", Vector2.ONE * (1.0 + p), duration / 2.0)
			tw.tween_property(node, "scale", Vector2.ONE, duration / 2.0)
		"float":
			var h := amount if amount > 0.0 else 8.0
			var y := node.position.y
			tw.tween_property(node, "position:y", y - h, duration / 2.0)
			tw.tween_property(node, "position:y", y, duration / 2.0)
		"shake":
			var d := amount if amount > 0.0 else 6.0
			var x := node.position.x
			var steps := 6
			for i in steps:
				var sign := 1.0 if i % 2 == 0 else -1.0
				tw.tween_property(node, "position:x", x + sign * d * (1.0 - float(i) / steps), duration / steps)
			tw.tween_property(node, "position:x", x, 0.0)
		"rotate":
			_center_pivot(node)
			var deg := amount if amount != 0.0 else 360.0
			var r := node.rotation
			tw.tween_property(node, "rotation", r + deg_to_rad(deg), duration)
			if loops == 1:
				tw.tween_property(node, "rotation", r, 0.0)
		"blink":
			var a2 := node.modulate.a
			tw.tween_property(node, "modulate:a", 0.0, duration / 2.0)
			tw.tween_property(node, "modulate:a", a2, duration / 2.0)
		_:
			tw.kill()
			return null
	if loops == 0 and not appear:
		tw.set_loops()
	return tw


static func _from_offset(from: String, dist: float) -> Vector2:
	match from:
		"right": return Vector2(dist, 0)
		"top": return Vector2(0, -dist)
		"bottom": return Vector2(0, dist)
	return Vector2(-dist, 0)


static func _center_pivot(node: Control) -> void:
	node.pivot_offset = node.size / 2.0


static func _trans(easing: String) -> Tween.TransitionType:
	match easing:
		"linear": return Tween.TRANS_LINEAR
		"back", "ease_out_back": return Tween.TRANS_BACK
		"bounce": return Tween.TRANS_BOUNCE
		"elastic": return Tween.TRANS_ELASTIC
	return Tween.TRANS_QUAD


static func _ease(easing: String) -> Tween.EaseType:
	match easing:
		"ease_in": return Tween.EASE_IN
		"ease_in_out": return Tween.EASE_IN_OUT
	return Tween.EASE_OUT
