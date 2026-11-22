# Plugin de teste das fixtures (M0-08): a atividade devolve o resultado na hora,
# conforme params.mode. Nunca entra em artefato: mora em runtime/tests/ (spec 09 §1.2).
extends VNRuntimePlugin

var _ctx: VNPluginContext


func _vn_init(ctx: VNPluginContext) -> void:
	_ctx = ctx


func _vn_start_activity(activity_id: StringName, params: Dictionary, handle: VNActivityHandle) -> void:
	if activity_id != &"probe_game":
		handle.fail("atividade desconhecida: %s" % activity_id)
		return
	var target: int = params.get("target", 1)
	match params.mode:
		"win":
			_ctx.events.emit("probe.finished", {"score": target})
			handle.complete(&"won", {"won": true, "score": target})
		"lose":
			handle.complete(&"lost", {"won": false, "score": 0})
		_:
			handle.fail("modo fail pedido pelos params")
