class_name VNPluginService
extends RefCounted
## Base dos serviços do [VNPluginContext] (Plugin SDK §5.2).
##
## Guarda a [VNPluginBridge] e o namespace do plugin, e concentra as duas
## verificações que toda fachada faz antes de chamar a ponte:
## thread principal (RT §6.1) e capacidade concedida (Plugin SDK §4.2). Um
## serviço sem a capacidade existe, mas não faz nada: devolve
## [code]PERMISSION_DENIED[/code] nos métodos com [VNResult] e
## [code]null[/code]/[code]fallback[/code]/[code]false[/code] nos outros, e
## avisa a ponte ([method VNPluginBridge.permission_denied]).

var _bridge: VNPluginBridge
var _ns: StringName


func _init(bridge: VNPluginBridge = null, plugin_namespace: StringName = &"") -> void:
	_bridge = bridge if bridge != null else VNPluginBridge.new()
	_ns = plugin_namespace


## Recusa por capacidade: avisa a ponte e devolve o [VNResult] de erro.
func _deny(capability: StringName, call: String) -> VNResult:
	_bridge.permission_denied(capability, call)
	return VNResult.failure(VNRuntimeSDK.PERMISSION_DENIED, "%s requer %s" % [call, capability])


## [code]true[/code] na thread principal. Fora dela, conta o erro na ponte
## (RT §6.1: o plugin reenvia com [code]call_deferred[/code]).
func _check_thread(call: String) -> bool:
	if VNRuntimeSDK.on_main_thread():
		return true
	_bridge.report_error(VNRuntimeSDK.WRONG_THREAD, "%s chamado fora da thread principal" % call)
	return false


func _wrong_thread(call: String) -> VNResult:
	return VNResult.failure(VNRuntimeSDK.WRONG_THREAD, "%s chamado fora da thread principal" % call)
