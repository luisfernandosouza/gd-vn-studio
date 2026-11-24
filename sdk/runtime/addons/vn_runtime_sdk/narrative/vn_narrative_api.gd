class_name VNNarrativeAPI
extends VNPluginService
## NarrativeAPI (Plugin SDK §5.3): o caminho do plugin até a história.
##
## [member variables] e [member events] são fachadas sobre o State Manager e o
## Event Bus; [method begin_transaction] abre uma [VNTransaction] (capacidade
## [code]transactions[/code]).

var variables: VNVariableAPI
var events: VNEventAPI


func _init(bridge: VNPluginBridge = null, plugin_namespace: StringName = &"") -> void:
	super(bridge, plugin_namespace)
	variables = VNVariableAPI.new(_bridge, _ns)
	events = VNEventAPI.new(_bridge, _ns)


## Abre uma transação. Sem [code]transactions[/code], a transação existe mas o
## [method VNTransaction.commit] devolve [code]PERMISSION_DENIED[/code].
func begin_transaction() -> VNTransaction:
	var allowed := _bridge.has_capability(VNRuntimeSDK.CAP_TRANSACTIONS)
	if not allowed:
		_bridge.permission_denied(VNRuntimeSDK.CAP_TRANSACTIONS, "begin_transaction")
	return VNTransaction.new(_bridge, _ns, allowed)
