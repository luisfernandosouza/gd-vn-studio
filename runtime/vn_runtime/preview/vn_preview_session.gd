class_name VNPreviewSession
extends RefCounted
## Sessão JSON-RPC 2.0 do Preview (Preview Protocol §1, §2, §6, §7).
##
## Não conhece o transporte: recebe o texto de cada mensagem em [method receive]
## e entrega o que sai pelo sinal [signal outgoing]. Os transportes são
## [VNPreviewWebSocket] (janela, PP §1.2) e [VNPreviewWebBridge] (painel, PP §1.1).
##
## A sessão cuida de:
## [br]- validar a forma de cada mensagem (uma por vez, sem lotes) e responder os
##   erros padrão do JSON-RPC;
## [br]- autenticar com [code]session.hello[/code] (token na janela, prazo de 5 s,
##   [code]UNSUPPORTED_VERSION[/code] para outro MAJOR do protocolo);
## [br]- os estados do Preview (PP §2) e a tabela de estados de cada método (PP §3),
##   com [code]INVALID_PREVIEW_STATE[/code];
## [br]- [code]BUSY[/code] enquanto [code]preview.load[/code] ou [code]preview.reload[/code]
##   está em curso;
## [br]- as notificações, com [code]seq[/code] crescente e [code]phase[/code] (PP §4).
##
## Os métodos [code]preview.*[/code] em si (PP §3) são registrados com [method register]
## (tarefa M4-05). Um método do protocolo ainda sem implementação responde
## [code]-32601[/code].
##
## Um handler recebe os [code]params[/code] (sempre um [Dictionary]) e devolve o
## resultado ([Dictionary]) ou um [VNPreviewError]. Pode ser uma corrotina ([code]await[/code]).

## Cada mensagem a enviar ao Studio, já em texto JSON.
signal outgoing(text: String)
## O transporte deve fechar a conexão (só na janela; PP §1.2: 4401).
signal close_requested(code: int, reason: String)
## O [code]session.hello[/code] foi aceito.
signal authenticated
## O estado do Preview mudou (PP §2).
signal state_changed(state: StringName, previous: StringName)

## Versão do protocolo falada por este runtime (PP §1.4: [code]protocol[/code]).
const PROTOCOL := "1.0"
## Prazo para o [code]session.hello[/code] depois que a conexão abre (PP §1.2).
const HELLO_TIMEOUT_MS := 5000

## Código de fechamento do WebSocket para falha de autenticação (PP §1.2).
const CLOSE_UNAUTHENTICATED := 4401

enum Transport { WINDOW, PANEL }

# Estados do Preview (PP §2).
const CONNECTED := &"CONNECTED"
const READY := &"READY"
const LOADED := &"LOADED"
const RUNNING := &"RUNNING"
const PAUSED := &"PAUSED"

const _AFTER_LOAD: Array[StringName] = [LOADED, RUNNING, PAUSED]

## Estados em que cada método é aceito (PP §3). É também a lista de métodos do protocolo.
const METHOD_STATES := {
	"session.hello": [CONNECTED],
	"preview.load": [READY, LOADED],
	"preview.start": [LOADED],
	"preview.stop": [RUNNING, PAUSED],
	"preview.pause": [RUNNING],
	"preview.resume": [PAUSED],
	"preview.step": [PAUSED],
	"preview.input": [RUNNING, PAUSED, LOADED],
	"preview.set_variables": [RUNNING, PAUSED],
	"preview.get_state": _AFTER_LOAD,
	"preview.explain_selection": [RUNNING, PAUSED],
	"preview.reload": _AFTER_LOAD,
	"preview.reload_plugins": _AFTER_LOAD,
	"preview.show_screen": [LOADED, RUNNING, PAUSED],
	"preview.set_setting": _AFTER_LOAD,
	"preview.set_locale": _AFTER_LOAD,
}

## Ações de [code]preview.input[/code] aceitas em [code]LOADED[/code]: as do modo livre (PP §3).
const LOADED_INPUT_ACTIONS: Array[String] = [
	"play_activity", "skip_activity", "cancel_activity", "complete_activity",
]

## Requisições longas: enquanto uma está em curso, as outras recebem [code]BUSY[/code] (PP §6).
const LONG_METHODS: Array[String] = ["preview.load", "preview.reload"]

var transport: Transport
## [code]features[/code] do resultado do [code]session.hello[/code].
var features: PackedStringArray = []
## Registro dos módulos, de onde sai o [code]phase[/code] das notificações. Opcional.
var modules: VNModules = null
## Dados do jogador (PP §1.4, M4-08): cada [code]preview.load[/code] passa por
## [method VNPreviewUserData.configure] antes do handler, que troca [code]modules.storage[/code].
## Na janela, o transporte põe aqui a pasta de [code]--vn-user-dir[/code].
var user_data: VNPreviewUserData

var _token: String
var _state: StringName = CONNECTED
var _handlers: Dictionary = {}       # método → Callable
var _seq := 0
var _opened_at := 0                  # ms do [method open]
var _opened := false
var _expired := false                # painel: prazo do hello vencido
var _closed := false
var _long_running := ""              # método longo em curso, ou ""


## [param token] é o token da janela (64 hex, PP §1.2); no painel fica vazio.
func _init(p_transport: Transport, p_token: String = "") -> void:
	transport = p_transport
	_token = p_token
	user_data = VNPreviewUserData.new(p_transport)


## Registra o handler de um método [code]preview.*[/code] do protocolo (M4-05).
func register(method: String, handler: Callable) -> void:
	assert(METHOD_STATES.has(method) and method != "session.hello", "método fora do PP §3: %s" % method)
	_handlers[method] = handler


func state() -> StringName:
	return _state


func is_authenticated() -> bool:
	return _state != CONNECTED


func is_closed() -> bool:
	return _closed


## Muda o estado do Preview fora de uma resposta (por exemplo, o jogo terminou).
func set_state(new_state: StringName) -> void:
	if new_state == _state:
		return
	var previous := _state
	_state = new_state
	state_changed.emit(new_state, previous)


## Estado do motor (RT §3), para o [code]phase[/code] das notificações.
func phase() -> StringName:
	if modules != null and modules.engine != null:
		return modules.engine.phase()
	return VNPhase.BOOT


## A conexão abriu: começa o prazo do [code]session.hello[/code].
func open(now_ms: int = Time.get_ticks_msec()) -> void:
	_opened_at = now_ms
	_opened = true


## Confere o prazo do [code]session.hello[/code]. O transporte chama a cada quadro.
func poll(now_ms: int = Time.get_ticks_msec()) -> void:
	if _closed or not _opened or is_authenticated() or _expired:
		return
	if now_ms - _opened_at >= HELLO_TIMEOUT_MS:
		if transport == Transport.WINDOW:
			_close(CLOSE_UNAUTHENTICATED, "sem session.hello em 5 s")
		else:
			# No painel não há conexão para fechar: a sessão passa a responder só UNAUTHENTICATED.
			_expired = true


## A conexão caiu ou foi fechada pelo transporte; nada mais sai.
func mark_closed() -> void:
	_closed = true


## Avisa o Studio que o runtime vai fechar (PP §4: [code]session.closing[/code]).
func send_closing(reason: String) -> void:
	assert(reason in ["window_closed", "stop", "error"])
	notify("session.closing", {"reason": reason})


## Manda uma notificação (PP §4), com [code]seq[/code] e [code]phase[/code].
## Antes do [code]session.hello[/code] ou depois de fechar, não manda nada e devolve false.
func notify(method: String, params: Dictionary = {}) -> bool:
	if _closed or not is_authenticated():
		return false
	_seq += 1
	var p := params.duplicate()
	p["seq"] = _seq
	p["phase"] = String(phase())
	_send({"jsonrpc": "2.0", "method": method, "params": p})
	return true


## Último [code]seq[/code] usado.
func last_seq() -> int:
	return _seq


## Um quadro binário chegou (o protocolo só usa texto).
func receive_binary() -> void:
	if _closed:
		return
	if transport == Transport.WINDOW and not is_authenticated():
		_close(CLOSE_UNAUTHENTICATED, "mensagem antes do session.hello")
		return
	_respond_error(null, VNPreviewError.invalid_request("quadro binário; use texto UTF-8"))


## Trata uma mensagem do Studio. Pode esperar um handler longo; quem chama não precisa esperar.
func receive(text: String) -> void:
	if _closed:
		return
	var json := JSON.new()
	var parsed_ok := json.parse(text) == OK
	var msg: Variant = json.data if parsed_ok else null

	# Antes do hello, na janela, qualquer coisa que não seja um hello válido fecha a conexão (PP §1.2).
	if not is_authenticated():
		if transport == Transport.WINDOW:
			if not _is_window_hello(msg):
				_close(CLOSE_UNAUTHENTICATED, "mensagem antes do session.hello ou token errado")
				return
		elif _expired or not (msg is Dictionary and msg.get("method") == "session.hello"):
			_respond_error(_safe_id(msg), VNPreviewError.unauthenticated())
			return

	if not parsed_ok:
		_respond_error(null, VNPreviewError.parse_error(json.get_error_message()))
		return
	if msg is Array:
		_respond_error(null, VNPreviewError.invalid_request("lotes não são aceitos"))
		return
	var shape_error := _check_shape(msg)
	if not shape_error.is_empty():
		_respond_error(_safe_id(msg), VNPreviewError.invalid_request(shape_error))
		return

	var id: Variant = _normalize_id(msg["id"])
	var method: String = msg["method"]
	var params: Variant = msg.get("params", {})
	if not params is Dictionary:
		_respond_error(id, VNPreviewError.invalid_params("params deve ser um objeto"))
		return
	if not METHOD_STATES.has(method):
		_respond_error(id, VNPreviewError.method_not_found(method))
		return
	if not _long_running.is_empty():
		_respond_error(id, VNPreviewError.busy(_long_running))
		return
	var state_error := _check_state(method, params)
	if state_error != null:
		_respond_error(id, state_error)
		return

	if method == "session.hello":
		_hello(id, params)
		return

	var handler: Callable = _handlers.get(method, Callable())
	if not handler.is_valid():
		_respond_error(id, VNPreviewError.new(VNPreviewError.METHOD_NOT_FOUND,
			"Método ainda não implementado neste runtime: %s" % method))
		return

	if method == "preview.load":
		var user_data_error := user_data.configure(params, self)
		if user_data_error != null:
			_respond_error(id, user_data_error)
			return

	var long := method in LONG_METHODS
	if long:
		_long_running = method
	var result: Variant = await handler.call(params)
	if long:
		_long_running = ""

	if result is VNPreviewError:
		_respond_error(id, result)
	elif result is Dictionary:
		_after_success(method, result)
		_send({"jsonrpc": "2.0", "id": id, "result": result})
	else:
		_respond_error(id, VNPreviewError.internal("%s devolveu %s" % [method, type_string(typeof(result))]))


# --- session.hello -----------------------------------------------------------

func _hello(id: Variant, params: Dictionary) -> void:
	var allowed := ["token", "protocol", "studio_version"]
	for key in params:
		if not String(key) in allowed:
			_respond_error(id, VNPreviewError.invalid_params("campo desconhecido: %s" % key))
			return
	var protocol: Variant = params.get("protocol")
	if not protocol is String or not _matches(protocol, "^[0-9]+\\.[0-9]+$"):
		_respond_error(id, VNPreviewError.invalid_params("protocol deve ser \"MAJOR.MINOR\""))
		return
	if params.has("studio_version") and not params["studio_version"] is String:
		_respond_error(id, VNPreviewError.invalid_params("studio_version deve ser texto"))
		return
	if params.has("token") and not (params["token"] is String and _matches(params["token"], "^[0-9a-f]{64}$")):
		# Só chega aqui no painel: na janela, um token errado já fechou a conexão.
		_respond_error(id, VNPreviewError.invalid_params("token deve ter 64 dígitos hex"))
		return
	if protocol.get_slice(".", 0) != PROTOCOL.get_slice(".", 0):
		_respond_error(id, VNPreviewError.unsupported_version(
			"protocolo %s pedido; este runtime fala %s" % [protocol, PROTOCOL]))
		return
	set_state(READY)
	_send({"jsonrpc": "2.0", "id": id, "result": {
		"runtime_version": runtime_version(),
		"godot_version": godot_version(),
		"protocol": PROTOCOL,
		"platform": platform(),
		"features": Array(features),
	}})
	authenticated.emit()


## Na janela, o único primeiro contato aceito é um hello com o token certo (PP §1.2, §7).
func _is_window_hello(msg: Variant) -> bool:
	if not msg is Dictionary or msg.get("jsonrpc") != "2.0" or msg.get("method") != "session.hello":
		return false
	var params: Variant = msg.get("params")
	if not params is Dictionary:
		return false
	var token: Variant = params.get("token")
	return token is String and not _token.is_empty() and _constant_time_equals(token, _token)


static func _constant_time_equals(a: String, b: String) -> bool:
	var x := a.to_utf8_buffer()
	var y := b.to_utf8_buffer()
	var diff := x.size() ^ y.size()
	for i in mini(x.size(), y.size()):
		diff |= x[i] ^ y[i]
	return diff == 0


static func runtime_version() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return v if not v.is_empty() else "0.1.0"


static func godot_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]


## [code]platform[/code] do hello: [code]windows[/code], [code]macos[/code], [code]linux[/code] ou [code]web[/code].
static func platform() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		"Web":
			return "web"
		_:
			return "linux"


# --- Estados e forma --------------------------------------------------------

func _check_state(method: String, params: Dictionary) -> VNPreviewError:
	var allowed: Array = METHOD_STATES[method]
	if not _state in allowed:
		return VNPreviewError.invalid_state(_state)
	if method == "preview.input" and _state == LOADED:
		var action: Variant = params.get("action")
		if not action in LOADED_INPUT_ACTIONS:
			return VNPreviewError.invalid_state(_state, "em LOADED só as ações de atividade do modo livre")
	if method == "preview.set_variables" and _state == RUNNING and phase() == VNPhase.ACTIVITY:
		return VNPreviewError.invalid_state(_state, "set_variables durante uma atividade")
	return null


## Transições de estado depois de uma resposta de sucesso (PP §2).
func _after_success(method: String, result: Dictionary) -> void:
	match method:
		"preview.load":
			set_state(LOADED)
		"preview.start":
			set_state(PAUSED if result.get("preview") == "PAUSED" else RUNNING)
		"preview.stop":
			set_state(LOADED)
		"preview.pause":
			set_state(PAUSED)
		"preview.resume":
			set_state(RUNNING)


func _check_shape(msg: Variant) -> String:
	if not msg is Dictionary:
		return "a mensagem deve ser um objeto"
	if msg.get("jsonrpc") != "2.0":
		return "jsonrpc deve ser \"2.0\""
	if not msg.get("method") is String:
		return "method ausente"
	if not msg.has("id"):
		return "o Studio só manda requisições, com id"
	if _normalize_id(msg["id"]) == null:
		return "id deve ser inteiro ou texto"
	for key in msg:
		if not String(key) in ["jsonrpc", "id", "method", "params"]:
			return "campo desconhecido: %s" % key
	return ""


## O JSON do Godot lê todo número como float; o id volta como inteiro.
static func _normalize_id(id: Variant) -> Variant:
	if id is String or id is int:
		return id
	if id is float and is_finite(id) and id == floorf(id) and absf(id) <= 9007199254740991.0:
		return int(id)
	return null


## O id da mensagem, se dá para ler um; senão null (JSON-RPC 2.0 §5).
static func _safe_id(msg: Variant) -> Variant:
	if msg is Dictionary and msg.has("id"):
		return _normalize_id(msg["id"])
	return null


static func _matches(text: String, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	return re.search(text) != null


# --- Saída ------------------------------------------------------------------

func _respond_error(id: Variant, error: VNPreviewError) -> void:
	_send({"jsonrpc": "2.0", "id": id, "error": error.to_dict()})


func _send(message: Dictionary) -> void:
	if _closed:
		return
	outgoing.emit(JSON.stringify(message))


func _close(code: int, reason: String) -> void:
	if _closed:
		return
	_closed = true
	close_requested.emit(code, reason)
