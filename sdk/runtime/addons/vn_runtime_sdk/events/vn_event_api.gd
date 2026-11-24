class_name VNEventAPI
extends VNPluginService
## Eventos do jogo vistos pelo plugin (Plugin SDK §5.4, §7; RT §7).
##
## Entrega: enfileirada, FIFO, nunca reentrante (RT §7.2). O callback recebe
## [code](name: String, payload: Dictionary, source: String)[/code].
##
## [b]Emitir[/b] requer [code]events.emit[/code]; o nome DEVE ser do próprio
## namespace e estar em [code]events.emits[/code] ([method VNPluginBridge.can_emit]).
## [b]Ouvir[/b] eventos do próprio namespace é livre; [code]sys.*[/code],
## [code]story.*[/code] e eventos de outros plugins requerem
## [code]events.subscribe[/code]. Padrões com [code]*[/code] só no fim.


## Enfileira [code]<namespace>.<nome>[/code] com [param payload] (só tipos JSON).
func emit(name: String, payload: Dictionary = {}) -> VNResult:
	if not _check_thread("events.emit"):
		return _wrong_thread("events.emit")
	if not _bridge.has_capability(VNRuntimeSDK.CAP_EVENTS_EMIT):
		return _deny(VNRuntimeSDK.CAP_EVENTS_EMIT, "events.emit(%s)" % name)
	if not name.begins_with("%s." % _ns) or not _bridge.can_emit(name):
		return _deny(VNRuntimeSDK.CAP_EVENTS_EMIT, "events.emit(%s)" % name)
	return _bridge.emit_event(name, payload)


## Assina [param pattern] ([code]"story.*"[/code], [code]"sys.scene_ended"[/code]).
## Devolve o id da assinatura (≥ 1), ou 0 se recusada.
func on(pattern: String, callback: Callable) -> int:
	if not _check_thread("events.on"):
		return 0
	if not VNRuntimeSDK.is_valid_event_pattern(pattern) or not callback.is_valid():
		_bridge.report_error(VNRuntimeSDK.INVALID_STATE, "events.on: padrão ou callback inválido (%s)" % pattern)
		return 0
	var own := pattern.begins_with("%s." % _ns)
	if not own and not _bridge.has_capability(VNRuntimeSDK.CAP_EVENTS_SUBSCRIBE):
		_deny(VNRuntimeSDK.CAP_EVENTS_SUBSCRIBE, "events.on(%s)" % pattern)
		return 0
	if not own and not _bridge.can_subscribe(pattern):
		_deny(VNRuntimeSDK.CAP_EVENTS_SUBSCRIBE, "events.on(%s)" % pattern)
		return 0
	return _bridge.subscribe(pattern, callback)


## Cancela uma assinatura feita com [method on]. Ids desconhecidos são ignorados.
func off(subscription_id: int) -> void:
	if subscription_id <= 0 or not _check_thread("events.off"):
		return
	_bridge.unsubscribe(subscription_id)
