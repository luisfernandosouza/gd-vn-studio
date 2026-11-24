class_name VNPreviewWebSocket
extends Node
## Transporte do Preview na janela: servidor WebSocket em [code]127.0.0.1[/code] (Preview Protocol §1.2, §7).
##
## - Escuta só em [code]127.0.0.1:<porta>[/code], nunca em outra interface.
## - Uma conexão por vez: outra que chegue enquanto há uma aberta é fechada com 4409.
## - Cada quadro de texto leva uma mensagem JSON-RPC 2.0 ([VNPreviewSession]).
## - Mensagem antes do [code]session.hello[/code], token errado ou 5 s sem hello fecham com 4401.
##   Uma conexão que não se autenticou libera a vaga para a próxima.
## - O token é de uso único: depois que uma conexão autenticada cai, o runtime não aceita
##   outra (4409) e encerra sozinho em 10 s, para não deixar processo órfão.
## - Ao fechar a janela do jogo ([method close_window]), manda [code]session.closing[/code]
##   com [code]window_closed[/code], fecha com 1000 e sai.

## A sessão autenticada terminou e o runtime vai sair (ou saiu, com [member quit_on_end]).
signal ended(reason: String)
## Uma nova sessão foi criada para uma conexão; o dono registra os métodos nela (M4-05).
signal session_created(session: VNPreviewSession)

const HOST := "127.0.0.1"
const CLOSE_NORMAL := 1000
const CLOSE_UNAUTHENTICATED := VNPreviewSession.CLOSE_UNAUTHENTICATED
const CLOSE_CONFLICT := 4409
## Prazo para encerrar depois que a conexão autenticada cai (PP §1.2).
const LOST_CONNECTION_EXIT_MS := 10000
## Quanto esperar o fechamento limpo antes de sair mesmo assim.
const CLOSE_FLUSH_MS := 1000
## Tempo mínimo entre o [code]session.closing[/code] e o fechamento, para o Studio ler a notificação.
const CLOSING_GRACE_MS := 100

## Sai do jogo ([method SceneTree.quit]) quando a sessão termina. Os testes desligam.
var quit_on_end := true
## Prazo de [constant LOST_CONNECTION_EXIT_MS]; os testes encurtam.
var lost_connection_exit_ms := LOST_CONNECTION_EXIT_MS
## Repassado a cada sessão nova.
var features: PackedStringArray = []
var modules: VNModules = null

var session: VNPreviewSession = null

var _token: String
var _server := TCPServer.new()
var _peer: WebSocketPeer = null       # conexão que ocupa a vaga
var _peer_opened := false
var _peer_accepted_at := 0
var _peer_tcp: StreamPeerTCP = null
var _refusing: Array[WebSocketPeer] = []
var _draining: Array[WebSocketPeer] = []   # conexões recusadas terminando o fechamento
var _used := false                    # uma sessão já se autenticou: o token foi usado
var _lost_at := -1
var _closing_since := -1
var _closing_reason := ""
var _close_sent := false
var _finished := false


## Abre o servidor. [param token] são os 64 hex de [code]--vn-preview-token[/code].
func listen(port: int, token: String) -> Error:
	_token = token
	return _server.listen(port, HOST)


func port() -> int:
	return _server.get_local_port() if _server.is_listening() else 0


func is_listening() -> bool:
	return _server.is_listening()


## Fecha a janela do jogo: [code]session.closing[/code], fechamento 1000 e saída (PP §1.2).
func close_window(reason: String = "window_closed") -> void:
	if _closing_since >= 0 or _finished:
		return
	_closing_reason = reason
	_closing_since = Time.get_ticks_msec()
	if session != null and session.is_authenticated() and _peer != null \
			and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		session.send_closing(reason)
		session.mark_closed()
	else:
		_finish(reason)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close_window("window_closed")
	elif what == NOTIFICATION_PREDELETE:
		_server.stop()


func _process(_delta: float) -> void:
	if _finished:
		return
	var now := Time.get_ticks_msec()
	_accept_new()
	_poll_refusing()
	_poll_peer(now)
	if session != null:
		session.poll(now)
	if _closing_since >= 0:
		# Fecha com 1000 só depois que o session.closing saiu do buffer.
		if not _close_sent and _peer != null and now - _closing_since >= CLOSING_GRACE_MS \
				and _peer.get_current_outbound_buffered_amount() == 0:
			_peer.close(CLOSE_NORMAL, _closing_reason)
			_close_sent = true
		var closed := _peer == null or _peer.get_ready_state() == WebSocketPeer.STATE_CLOSED
		if closed or now - _closing_since >= CLOSING_GRACE_MS + CLOSE_FLUSH_MS:
			_finish(_closing_reason)
	elif _lost_at >= 0 and now - _lost_at >= lost_connection_exit_ms:
		_finish("connection_lost")


func _accept_new() -> void:
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		var ws := WebSocketPeer.new()
		if ws.accept_stream(tcp) != OK:
			continue
		if _peer == null and not _used and _closing_since < 0:
			_peer = ws
			_peer_opened = false
			_peer_accepted_at = Time.get_ticks_msec()
			_peer_tcp = tcp
		else:
			_refusing.append(ws)


## Conexões a mais: completam o handshake e recebem 4409.
func _poll_refusing() -> void:
	for ws in _refusing.duplicate():
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				ws.close(CLOSE_CONFLICT, "outra conexão já está aberta")
			WebSocketPeer.STATE_CLOSED:
				_refusing.erase(ws)
	for ws in _draining.duplicate():
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_draining.erase(ws)


func _poll_peer(now: int) -> void:
	if _peer == null:
		return
	_peer.poll()
	var ready := _peer.get_ready_state()
	if ready == WebSocketPeer.STATE_CONNECTING:
		_peer_tcp.poll()
	if ready == WebSocketPeer.STATE_CONNECTING and (_peer_tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED
			or now - _peer_accepted_at >= VNPreviewSession.HELLO_TIMEOUT_MS):
		# Handshake que não termina (ou TCP que caiu nele) não segura a vaga: o prazo do hello começa no accept.
		_peer.close()
		_peer = null
		return
	if ready == WebSocketPeer.STATE_OPEN and not _peer_opened:
		_peer_opened = true
		_new_session(now)
	if ready == WebSocketPeer.STATE_OPEN or ready == WebSocketPeer.STATE_CLOSING:
		while _peer != null and _peer.get_available_packet_count() > 0:
			var packet := _peer.get_packet()
			if session == null or session.is_closed():
				continue
			if _peer.was_string_packet():
				session.receive(packet.get_string_from_utf8())
			else:
				session.receive_binary()
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_on_peer_closed(now)


func _new_session(_now: int) -> void:
	session = VNPreviewSession.new(VNPreviewSession.Transport.WINDOW, _token)
	session.features = features
	session.modules = modules
	session.outgoing.connect(_on_outgoing)
	session.close_requested.connect(_on_close_requested)
	session.authenticated.connect(func(): _used = true)
	session.open(_peer_accepted_at)
	session_created.emit(session)


func _on_outgoing(text: String) -> void:
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(text)


func _on_close_requested(code: int, reason: String) -> void:
	if _peer == null:
		return
	_peer.close(code, reason)
	if session == null or not session.is_authenticated():
		# Recusada antes do hello (4401): a vaga fica livre já, sem esperar o fechamento terminar.
		_draining.append(_peer)
		_peer = null
		_peer_opened = false
		session = null


func _on_peer_closed(now: int) -> void:
	var was_authenticated := session != null and session.is_authenticated()
	if session != null:
		session.mark_closed()
	_peer = null
	_peer_opened = false
	if _closing_since >= 0:
		return
	if was_authenticated:
		# O token já foi usado: a conexão caiu e o runtime encerra sozinho (PP §1.2).
		_lost_at = now
	else:
		# Não chegou a se autenticar: a vaga fica livre para a próxima conexão.
		session = null


func _finish(reason: String) -> void:
	if _finished:
		return
	_finished = true
	for ws in _refusing:
		ws.close(CLOSE_CONFLICT)
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.close(CLOSE_NORMAL, _closing_reason)
	_server.stop()
	ended.emit(reason)
	if quit_on_end and is_inside_tree():
		get_tree().quit(0)
