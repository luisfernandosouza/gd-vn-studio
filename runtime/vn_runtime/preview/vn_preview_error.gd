class_name VNPreviewError
extends RefCounted
## Erro de uma requisição do Preview (Preview Protocol §6).
##
## Um método do Preview devolve um [VNPreviewError] no lugar do resultado para
## responder com erro; a [VNPreviewSession] o transforma no objeto [code]error[/code]
## do JSON-RPC 2.0 ([code]preview-protocol.schema.json → $defs/ErrorObject[/code]).

# Erros padrão do JSON-RPC 2.0.
const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602

# Erros do protocolo (PP §6), com o código legível em [code]data.code[/code].
const UNAUTHENTICATED := -32001
const UNSUPPORTED_VERSION := -32002
const INVALID_PREVIEW_STATE := -32003
const BUNDLE_INVALID := -32004
const NOT_FOUND := -32005
const STATE_REJECTED := -32006
const BUSY := -32007
const INTERNAL := -32099

## Campos que [code]error.data[/code] aceita (o schema não admite outros).
const DATA_KEYS: Array[String] = ["code", "vn_code", "state", "kind", "id", "path", "detail", "message"]

var code: int
var message: String
var data: Dictionary = {}


func _init(p_code: int, p_message: String, p_data: Dictionary = {}) -> void:
	code = p_code
	message = p_message
	for key in p_data:
		assert(String(key) in DATA_KEYS, "campo de error.data fora do schema: %s" % key)
		data[String(key)] = p_data[key]


## O objeto [code]error[/code] da resposta.
func to_dict() -> Dictionary:
	var out := {"code": code, "message": message}
	if not data.is_empty():
		out["data"] = data
	return out


static func parse_error(detail: String = "") -> VNPreviewError:
	return VNPreviewError.new(PARSE_ERROR, _join("JSON inválido", detail))


static func invalid_request(detail: String = "") -> VNPreviewError:
	return VNPreviewError.new(INVALID_REQUEST, _join("Requisição inválida", detail))


static func method_not_found(method: String) -> VNPreviewError:
	return VNPreviewError.new(METHOD_NOT_FOUND, "Método inexistente: %s" % method)


static func invalid_params(detail: String) -> VNPreviewError:
	return VNPreviewError.new(INVALID_PARAMS, _join("Parâmetros inválidos", detail))


static func unauthenticated() -> VNPreviewError:
	return VNPreviewError.new(UNAUTHENTICATED, "Sessão sem session.hello válido",
		{"code": "UNAUTHENTICATED"})


static func unsupported_version(detail: String) -> VNPreviewError:
	return VNPreviewError.new(UNSUPPORTED_VERSION, _join("Versão sem suporte", detail),
		{"code": "UNSUPPORTED_VERSION", "detail": detail})


static func invalid_state(state: StringName, detail: String = "") -> VNPreviewError:
	var data := {"code": "INVALID_PREVIEW_STATE", "state": String(state)}
	if not detail.is_empty():
		data["detail"] = detail
	return VNPreviewError.new(INVALID_PREVIEW_STATE,
		_join("Método fora dos estados permitidos (estado atual: %s)" % state, detail), data)


static func bundle_invalid(path: String = "", detail: String = "") -> VNPreviewError:
	var data := {"code": "BUNDLE_INVALID"}
	if not path.is_empty():
		data["path"] = path
	if not detail.is_empty():
		data["detail"] = detail
	return VNPreviewError.new(BUNDLE_INVALID, _join("Bundle inválido", detail), data)


static func not_found(kind: String, id: String) -> VNPreviewError:
	return VNPreviewError.new(NOT_FOUND, "%s inexistente: %s" % [kind, id],
		{"code": "NOT_FOUND", "kind": kind, "id": id})


static func state_rejected(vn_code: StringName, detail: String = "") -> VNPreviewError:
	return VNPreviewError.new(STATE_REJECTED, _join("Escrita recusada (%s)" % vn_code, detail),
		{"code": "STATE_REJECTED", "vn_code": String(vn_code)})


static func busy(running: String) -> VNPreviewError:
	return VNPreviewError.new(BUSY, "Requisição longa em curso: %s" % running,
		{"code": "BUSY", "detail": running})


static func internal(detail: String) -> VNPreviewError:
	return VNPreviewError.new(INTERNAL, "Falha interna do runtime",
		{"code": "INTERNAL", "message": detail})


static func _join(head: String, detail: String) -> String:
	return head if detail.is_empty() else "%s: %s" % [head, detail]
