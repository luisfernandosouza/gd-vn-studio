class_name VNResult
extends RefCounted
## Resultado de toda operação de escrita (RT §6.3, Plugin SDK §5.3).
##
## É o mesmo tipo que o Runtime SDK expõe aos plugins. Enquanto o addon
## [code]addons/vn_runtime_sdk/[/code] não faz parte do projeto do runtime, a
## classe mora aqui; quando o SDK entrar no runtime (M3-02), ela passa a ser a
## do addon e este arquivo sai, para haver uma única definição de [code]VNResult[/code].

var ok: bool = true
var error: StringName = &""          ## &"" quando ok; senão um código de [VNErrors]
var message: String = ""
var changes: Array[Dictionary] = []  ## [{ "variable": "global.player_money", "old": 30, "new": 130 }]


static func success(p_changes: Array[Dictionary] = []) -> VNResult:
	var r := VNResult.new()
	r.changes = p_changes
	return r


static func failure(p_error: StringName, p_message: String = "") -> VNResult:
	var r := VNResult.new()
	r.ok = false
	r.error = p_error
	r.message = p_message
	return r
