class_name VNActivityHandle
extends RefCounted
## Handle de uma atividade em curso (Plugin SDK §6; RT §5.3).
##
## O plugin DEVE chamar [method complete] ou [method fail] exatamente uma vez;
## chamadas depois disso são ignoradas com aviso. Ao pular ou por timeout, o
## runtime chama [method close] [b]antes[/b] de [code]_vn_cancel_activity[/code],
## e [method is_active] passa a ser falso.
##
## Quem cria o handle (Plugin Host, M3-04) passa em [param on_finish] um
## [Callable] [code]func(status: StringName, outcome: StringName, payload: Dictionary, reason: String)[/code],
## com [code]status[/code] [code]&"completed"[/code] ou [code]&"failed"[/code].
## A validação de [code]outcome[/code] contra [code]outcomes[/code] e do
## [code]payload[/code] contra [code]result_schema[/code] é do host.

var activity_id: StringName = &""
var params: Dictionary = {}                ## validado e com defaults do schema
var rng: VNRandom                          ## fluxo próprio desta atividade (RT §12.2)
var mode: StringName = &"story"            ## &"story" ou &"free_play" (§6.1)

var _active: bool = true
var _on_finish: Callable
var _bridge: VNPluginBridge


func _init(p_activity_id: StringName = &"", p_params: Dictionary = {}, p_mode: StringName = &"story",
		p_rng: VNRandom = null, on_finish: Callable = Callable(), bridge: VNPluginBridge = null) -> void:
	activity_id = p_activity_id
	params = p_params
	mode = p_mode
	rng = p_rng if p_rng != null else VNRandom.new()
	_on_finish = on_finish
	_bridge = bridge if bridge != null else VNPluginBridge.new()


func complete(outcome: StringName, payload: Dictionary = {}) -> void:
	if not _finish("complete"):
		return
	if _on_finish.is_valid():
		_on_finish.call(&"completed", outcome, payload, "")


func fail(reason: String) -> void:
	if not _finish("fail"):
		return
	if _on_finish.is_valid():
		_on_finish.call(&"failed", &"", {}, reason)


func is_active() -> bool:
	return _active


## Encerra o handle por fora (pulo, timeout, saída do jogador). Só o host chama.
func close() -> void:
	_active = false


func _finish(call: String) -> bool:
	if not _active:
		_bridge.write_log(&"warn", "%s ignorado: a atividade %s já terminou" % [call, activity_id])
		return false
	_active = false
	return true
