class_name VNResult
extends RefCounted
## Resultado de toda operação de escrita (RT §6.3, Plugin SDK §5.3).
##
## Mesma classe de [code]runtime/vn_runtime/core/vn_result.gd[/code] (M0-07),
## com os mesmos campos e construtores. Quando o addon passar a fazer parte do
## projeto do runtime (integração), a cópia de [code]core/[/code] sai e esta fica
## como a única definição.

var ok: bool = true
var error: StringName = &""          ## &"" quando ok; senão um código de erro (RT §6.2)
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
