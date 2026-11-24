extends SceneTree
## Testes do servidor JSON-RPC do Preview (tarefa M4-04; Preview Protocol §1.1, §1.2, §2, §6, §7).
##
##   godot --headless --path runtime --script res://tests/preview/test_preview_server.gd -- [--transcript <arquivo.jsonl>]
##
## Roda a sessão nos dois transportes: o painel com um dublê de [code]window.vnPreview[/code] e a
## janela com um cliente WebSocket de verdade em 127.0.0.1. Com [code]--transcript[/code], grava
## cada mensagem trocada (uma por linha: [code]{transport, dir, text}[/code]), que
## [code]check_protocol.py[/code] valida contra [code]preview-protocol.schema.json[/code].
## Sai com 1 se algo falhar.

const TOKEN := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var _passed := 0
var _failed := 0
var _transcript: FileAccess = null


## Dublê do [code]window.vnPreview[/code] que o Studio registra na página.
class FakePage:
	var send: Callable
	var received: Array[String] = []
	var log: Callable

	func onmessage(text: String) -> void:
		received.append(text)
		if log.is_valid():
			log.call("out", text)

	func post(text: String) -> void:
		if log.is_valid():
			log.call("in", text)
		send.call([text])

	func take() -> Array:
		var out: Array = received.map(func(t): return JSON.parse_string(t))
		received.clear()
		return out


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--transcript")
	if i >= 0 and i + 1 < args.size():
		_transcript = FileAccess.open(args[i + 1], FileAccess.WRITE)
	_run_all.call_deferred()


func _run_all() -> void:
	for t in [
		"painel_hello_e_estados", "painel_antes_do_hello", "painel_prazo_do_hello",
		"painel_versao_e_parametros", "erros_jsonrpc", "estados_e_busy", "notificacoes_seq_phase",
		"handler_com_erro_e_interno", "opcoes_da_linha_de_comando",
	]:
		await _run(t)
	for t in [
		"janela_hello_e_closing", "janela_token_errado", "janela_mensagem_antes_do_hello",
		"janela_prazo_do_hello", "janela_segunda_conexao", "janela_queda_encerra",
	]:
		await _run(t)
	if _transcript != null:
		_transcript.close()
	print("%d/%d testes do Preview passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	var err: String = await call("test_" + test)
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


func _log(transport: String, dir: String, text: String) -> void:
	if _transcript != null:
		_transcript.store_line(JSON.stringify({"transport": transport, "dir": dir, "text": text}))


func _page() -> Array:
	var bridge := VNPreviewWebBridge.new()
	root.add_child(bridge)
	var page := FakePage.new()
	page.log = func(dir: String, text: String): _log("panel", dir, text)
	bridge.attach_page(page)
	return [bridge, page]


static func _req(id: Variant, method: String, params: Variant = null) -> String:
	var m := {"jsonrpc": "2.0", "id": id, "method": method}
	if params != null:
		m["params"] = params
	return JSON.stringify(m)


static func _hello(id: int = 1, extra: Dictionary = {}) -> String:
	var p := {"protocol": "1.0", "studio_version": "0.1.0"}
	p.merge(extra, true)
	return _req(id, "session.hello", p)


static func _err_code(msg: Variant) -> int:
	if msg is Dictionary and msg.has("error"):
		return int(msg["error"]["code"])
	return 0


# --- Painel -----------------------------------------------------------------

func test_painel_hello_e_estados() -> String:
	var pair := _page()
	var bridge: VNPreviewWebBridge = pair[0]
	var page: FakePage = pair[1]
	var s := bridge.session
	if not page.send.is_valid():
		return "a ponte não pôs vnPreview.send na página"
	s.register("preview.load", func(_p): return {"content_hash": "sha256-" + "0".repeat(64),
		"format_version": "1.0.0", "chapters": 2, "scenes": 5, "plugins": ["vnstudio.fishing"]})
	s.register("preview.start", func(p): return _game_state("PAUSED" if p.get("paused", false) else "RUNNING"))
	s.register("preview.pause", func(_p): return {"node": "019a7a00-2ee0-7000-8000-000000000001"})
	s.register("preview.resume", func(_p): return {"node": "019a7a00-2ee0-7000-8000-000000000001"})
	s.register("preview.stop", func(_p): return {})

	page.post(_hello())
	var got := page.take()
	if got.size() != 1 or not got[0].has("result"):
		return "hello sem resultado: %s" % [got]
	var r: Dictionary = got[0]["result"]
	if r["protocol"] != "1.0" or r["godot_version"] != "4.7.2" or r["platform"] != VNPreviewSession.platform():
		return "resultado do hello: %s" % [r]
	if got[0]["id"] != 1 or typeof(got[0]["id"]) != TYPE_FLOAT:
		return "id do hello"
	if s.state() != VNPreviewSession.READY:
		return "depois do hello o estado é %s" % s.state()

	var steps := [
		[_req(2, "preview.load", {"bundle_url": "vnpreview://localhost/project/preview/narrative/",
			"assets_base": "vnpreview://localhost/project/assets/"}), VNPreviewSession.LOADED],
		[_req(3, "preview.start", {"paused": true}), VNPreviewSession.PAUSED],
		[_req(4, "preview.resume"), VNPreviewSession.RUNNING],
		[_req(5, "preview.pause", {}), VNPreviewSession.PAUSED],
		[_req(6, "preview.stop"), VNPreviewSession.LOADED],
		[_req("sete", "preview.start"), VNPreviewSession.RUNNING],
	]
	for step in steps:
		page.post(step[0])
		var out := page.take()
		if out.size() != 1 or not out[0].has("result"):
			return "%s: %s" % [step[0], out]
		if s.state() != step[1]:
			return "%s levou a %s, esperado %s" % [step[0], s.state(), step[1]]
	bridge.queue_free()
	return ""


func test_painel_antes_do_hello() -> String:
	var pair := _page()
	var page: FakePage = pair[1]
	page.post(_req(1, "preview.get_state"))
	page.post("{isto não é json")
	page.post(_req(2, "preview.load", {}))
	var got := page.take()
	if got.size() != 3:
		return "esperava 3 respostas, veio %d" % got.size()
	for m in got:
		if _err_code(m) != VNPreviewError.UNAUTHENTICATED or m["error"]["data"]["code"] != "UNAUTHENTICATED":
			return "antes do hello: %s" % [m]
	if got[0]["id"] != 1 or got[1]["id"] != null:
		return "ids das respostas UNAUTHENTICATED"
	page.post(_hello(3))
	if not page.take()[0].has("result"):
		return "hello depois das recusas não autenticou"
	pair[0].queue_free()
	return ""


func test_painel_prazo_do_hello() -> String:
	var pair := _page()
	var page: FakePage = pair[1]
	var s: VNPreviewSession = pair[0].session
	s.open(0)
	s.poll(VNPreviewSession.HELLO_TIMEOUT_MS - 1)
	page.post(_hello(1, {"protocol": "x"}))   # parâmetro errado: responde -32602, sem autenticar
	if _err_code(page.take()[0]) != VNPreviewError.INVALID_PARAMS:
		return "hello com protocol inválido"
	s.poll(VNPreviewSession.HELLO_TIMEOUT_MS)
	page.post(_hello(2))
	var m: Dictionary = page.take()[0]
	if _err_code(m) != VNPreviewError.UNAUTHENTICATED:
		return "hello depois de 5 s: %s" % [m]
	if s.is_authenticated():
		return "autenticou depois do prazo"
	pair[0].queue_free()
	return ""


func test_painel_versao_e_parametros() -> String:
	var pair := _page()
	var page: FakePage = pair[1]
	var s: VNPreviewSession = pair[0].session
	page.post(_hello(1, {"protocol": "2.0"}))
	var m: Dictionary = page.take()[0]
	if _err_code(m) != VNPreviewError.UNSUPPORTED_VERSION or m["error"]["data"]["code"] != "UNSUPPORTED_VERSION":
		return "MAJOR diferente: %s" % [m]
	page.post(_req(2, "session.hello", {"protocol": "1.0", "extra": 1}))
	if _err_code(page.take()[0]) != VNPreviewError.INVALID_PARAMS:
		return "campo desconhecido no hello"
	page.post(_req(3, "session.hello", {"studio_version": "0.1.0"}))
	if _err_code(page.take()[0]) != VNPreviewError.INVALID_PARAMS:
		return "hello sem protocol"
	page.post(_hello(4, {"protocol": "1.7"}))
	if not page.take()[0].has("result") or s.state() != VNPreviewSession.READY:
		return "MINOR diferente deveria passar"
	page.post(_hello(5))
	m = page.take()[0]
	if _err_code(m) != VNPreviewError.INVALID_PREVIEW_STATE or m["error"]["data"]["state"] != "READY":
		return "segundo hello: %s" % [m]
	pair[0].queue_free()
	return ""


func test_erros_jsonrpc() -> String:
	var pair := _page()
	var page: FakePage = pair[1]
	page.post(_hello())
	page.take()
	var cases := [
		["{nope", VNPreviewError.PARSE_ERROR, null],
		["[" + _req(2, "preview.get_state") + "]", VNPreviewError.INVALID_REQUEST, null],
		['"texto"', VNPreviewError.INVALID_REQUEST, null],
		['{"jsonrpc":"1.0","id":3,"method":"preview.get_state"}', VNPreviewError.INVALID_REQUEST, 3],
		['{"jsonrpc":"2.0","method":"preview.get_state"}', VNPreviewError.INVALID_REQUEST, null],
		['{"jsonrpc":"2.0","id":1.5,"method":"preview.get_state"}', VNPreviewError.INVALID_REQUEST, null],
		['{"jsonrpc":"2.0","id":4,"method":"preview.get_state","x":1}', VNPreviewError.INVALID_REQUEST, 4],
		[_req(5, "preview.nao_existe"), VNPreviewError.METHOD_NOT_FOUND, 5],
		[_req(6, "preview.load", [1, 2]), VNPreviewError.INVALID_PARAMS, 6],
		# Método do protocolo sem handler ainda (M4-05): -32601.
		[_req(7, "preview.load", {}), VNPreviewError.METHOD_NOT_FOUND, 7],
	]
	for c in cases:
		page.post(c[0])
		var got := page.take()
		if got.size() != 1 or _err_code(got[0]) != c[1]:
			return "%s → %s (esperado %d)" % [c[0], got, c[1]]
		if got[0]["id"] != c[2]:
			return "%s → id %s (esperado %s)" % [c[0], got[0]["id"], c[2]]
	pair[0].queue_free()
	return ""


func test_estados_e_busy() -> String:
	var pair := _page()
	var page: FakePage = pair[1]
	var s: VNPreviewSession = pair[0].session
	var gate := Gate.new()
	s.register("preview.load", func(_p):
		await gate.opened
		return {"content_hash": "sha256-" + "1".repeat(64), "format_version": "1.0.0",
			"chapters": 1, "scenes": 1, "plugins": []})
	s.register("preview.input", func(_p): return {"accepted": true})
	s.register("preview.set_variables", func(_p): return {"changes": []})
	s.register("preview.start", func(_p): return _game_state("RUNNING"))
	page.post(_hello())
	page.take()
	# READY: start, get_state e input fora da tabela.
	for method in ["preview.start", "preview.get_state", "preview.input", "preview.stop", "preview.step"]:
		page.post(_req(10, method, {}))
		var m: Dictionary = page.take()[0]
		if _err_code(m) != VNPreviewError.INVALID_PREVIEW_STATE or m["error"]["data"]["state"] != "READY":
			return "%s em READY: %s" % [method, m]
	# load longo: outra requisição recebe BUSY.
	page.post(_req(11, "preview.load", {"bundle_path": "/p/.vnstudio/preview/narrative", "assets_base": "/p/assets"}))
	if not page.take().is_empty():
		return "load respondeu antes de terminar"
	page.post(_req(12, "preview.load", {}))
	var busy: Dictionary = page.take()[0]
	if _err_code(busy) != VNPreviewError.BUSY or busy["error"]["data"]["code"] != "BUSY":
		return "segunda requisição durante o load: %s" % [busy]
	gate.open()
	await process_frame
	var done := page.take()
	if done.size() != 1 or done[0]["id"] != 11 or not done[0].has("result"):
		return "fim do load: %s" % [done]
	if s.state() != VNPreviewSession.LOADED:
		return "estado depois do load: %s" % s.state()
	# LOADED: input só com ações do modo livre.
	page.post(_req(13, "preview.input", {"action": "advance"}))
	if _err_code(page.take()[0]) != VNPreviewError.INVALID_PREVIEW_STATE:
		return "advance em LOADED"
	page.post(_req(14, "preview.input", {"action": "play_activity", "activity": "fishing.fishing"}))
	if not page.take()[0].has("result"):
		return "play_activity em LOADED"
	page.post(_req(15, "preview.set_variables", {"variables": {}}))
	if _err_code(page.take()[0]) != VNPreviewError.INVALID_PREVIEW_STATE:
		return "set_variables em LOADED"
	# RUNNING durante ACTIVITY: set_variables recusado.
	var m := VNFakeModules.create()
	m.bind_all()
	s.modules = m
	page.post(_req(16, "preview.start"))
	page.take()
	m.engine.set_phase(VNPhase.ACTIVITY)
	page.post(_req(17, "preview.set_variables", {"variables": {}}))
	if _err_code(page.take()[0]) != VNPreviewError.INVALID_PREVIEW_STATE:
		return "set_variables durante ACTIVITY"
	m.engine.set_phase(VNPhase.SCENE_RUNNING)
	page.post(_req(18, "preview.set_variables", {"variables": {}}))
	if not page.take()[0].has("result"):
		return "set_variables em RUNNING fora de ACTIVITY"
	pair[0].queue_free()
	return ""


class Gate:
	signal opened
	func open() -> void:
		opened.emit()


func test_notificacoes_seq_phase() -> String:
	var pair := _page()
	var page: FakePage = pair[1]
	var s: VNPreviewSession = pair[0].session
	if s.notify("log", {"level": "info", "message": "antes"}):
		return "notificação antes do hello"
	page.post(_hello())
	page.take()
	s.notify("log", {"level": "info", "message": "um"})
	s.notify("node.entered", {"scene": "019a7a00-1388-7f6b-b667-94bbd1305982",
		"node": "019a7a00-2ee0-7000-8000-000000000001", "type": "dialogue"})
	var m := VNFakeModules.create()
	m.bind_all()
	s.modules = m
	s.notify("error", {"code": "TYPE_MISMATCH", "message": "x"})
	var got := page.take()
	if got.size() != 3:
		return "esperava 3 notificações, veio %d" % got.size()
	for k in got.size():
		var n: Dictionary = got[k]
		if n.has("id") or n["params"]["seq"] != k + 1 or not n["params"].has("phase"):
			return "notificação %d: %s" % [k, n]
	if got[0]["params"]["phase"] != "BOOT":
		return "phase sem motor deveria ser BOOT"
	if got[2]["params"]["phase"] != String(m.engine.phase()):
		return "phase não vem do Narrative Engine"
	pair[0].queue_free()
	return ""


func test_handler_com_erro_e_interno() -> String:
	var pair := _page()
	var page: FakePage = pair[1]
	var s: VNPreviewSession = pair[0].session
	s.register("preview.load", func(_p): return VNPreviewError.bundle_invalid("/scenes/x", "full_reload_required"))
	s.register("preview.set_locale", func(_p): return 42)
	page.post(_hello())
	page.take()
	page.post(_req(2, "preview.load", {}))
	var m: Dictionary = page.take()[0]
	if _err_code(m) != VNPreviewError.BUNDLE_INVALID or m["error"]["data"]["path"] != "/scenes/x":
		return "erro do handler: %s" % [m]
	if s.state() != VNPreviewSession.READY:
		return "load com erro mudou o estado"
	# Os demais construtores de erro produzem objetos válidos pelo schema (gravados no transcript).
	for e in [VNPreviewError.not_found("scene", "x"), VNPreviewError.state_rejected(&"READ_ONLY"),
			VNPreviewError.internal("falhou")]:
		s.register("preview.reload_plugins", func(_p): return e)
		s.set_state(VNPreviewSession.LOADED)
		page.post(_req(3, "preview.reload_plugins", {"ids": []}))
		if _err_code(page.take()[0]) != e.code:
			return "erro %d" % e.code
	page.post(_req(4, "preview.set_locale", {"locale": "en"}))
	m = page.take()[0]
	if _err_code(m) != VNPreviewError.INTERNAL or m["error"]["data"]["code"] != "INTERNAL":
		return "resultado que não é objeto: %s" % [m]
	pair[0].queue_free()
	return ""


func test_opcoes_da_linha_de_comando() -> String:
	if not VNPreview.window_options(PackedStringArray(["--outra"])).is_empty():
		return "sem opções deveria vir vazio"
	var ok := VNPreview.window_options(PackedStringArray([VNPreview.PORT_FLAG, "5123", VNPreview.TOKEN_FLAG, TOKEN]))
	if ok != {"port": 5123, "token": TOKEN}:
		return "opções válidas: %s" % [ok]
	var eq := VNPreview.window_options(PackedStringArray([VNPreview.PORT_FLAG + "=5123", VNPreview.TOKEN_FLAG + "=" + TOKEN]))
	if eq.get("port") != 5123:
		return "forma --opção=valor"
	for bad in [["0", TOKEN], ["99999", TOKEN], ["5123", "curto"], ["5123", TOKEN.to_upper()]]:
		var r := VNPreview.window_options(PackedStringArray([VNPreview.PORT_FLAG, bad[0], VNPreview.TOKEN_FLAG, bad[1]]))
		if not r.has("error"):
			return "opções inválidas aceitas: %s" % [bad]
		if TOKEN in String(r["error"]):
			return "o token apareceu na mensagem de erro"
	if not VNPreview.is_allowed():
		return "o runtime de debug deveria aceitar o Preview"
	return ""


static func _game_state(preview: String) -> Dictionary:
	return {"phase": "SCENE_RUNNING", "preview": preview, "chapter": null,
		"scene": "019a7a00-1388-7f6b-b667-94bbd1305982", "node": "019a7a00-2ee0-7000-8000-000000000001"}


# --- Janela (WebSocket de verdade em 127.0.0.1) ----------------------------

func _server(lost_ms: int = 300) -> VNPreviewWebSocket:
	var server := VNPreviewWebSocket.new()
	server.quit_on_end = false
	server.lost_connection_exit_ms = lost_ms
	root.add_child(server)
	var err := server.listen(0, TOKEN)
	assert(err == OK)
	return server


func _client(server: VNPreviewWebSocket) -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % server.port())
	return ws


## Espera até [param cond] ficar verdadeira (ou [param ms] passar), girando os quadros.
func _until(cond: Callable, ms: int = 3000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _ws_send(ws: WebSocketPeer, text: String) -> void:
	_log("window", "in", text)
	ws.send_text(text)


func _ws_read(ws: WebSocketPeer) -> Array:
	var out := []
	ws.poll()
	while ws.get_available_packet_count() > 0:
		var text := ws.get_packet().get_string_from_utf8()
		_log("window", "out", text)
		out.append(JSON.parse_string(text))
	return out


func _open(ws: WebSocketPeer) -> bool:
	return await _until(func(): ws.poll(); return ws.get_ready_state() == WebSocketPeer.STATE_OPEN)


func _closed(ws: WebSocketPeer) -> bool:
	return await _until(func(): ws.poll(); return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)


func _reply(ws: WebSocketPeer) -> Array:
	var got := []
	await _until(func(): got.append_array(_ws_read(ws)); return not got.is_empty())
	return got


func test_janela_hello_e_closing() -> String:
	var server := _server()
	var ended := []
	server.ended.connect(func(r): ended.append(r))
	server.session_created.connect(func(s: VNPreviewSession):
		s.register("preview.get_state", func(_p): return _game_state("RUNNING")))
	if server.port() == 0:
		return "servidor não abriu"
	var ws := _client(server)
	if not await _open(ws):
		return "cliente não conectou"
	_ws_send(ws, _hello(1, {"token": TOKEN}))
	var got := await _reply(ws)
	if got.size() != 1 or not got[0].has("result"):
		return "hello na janela: %s" % [got]
	if server.session.state() != VNPreviewSession.READY:
		return "estado depois do hello"
	server.session.notify("log", {"level": "info", "message": "olá"})
	got = await _reply(ws)
	if got.size() != 1 or got[0]["method"] != "log" or got[0]["params"]["seq"] != 1:
		return "notificação na janela: %s" % [got]
	server.close_window()
	got = await _reply(ws)
	if got.size() != 1 or got[0]["method"] != "session.closing" or got[0]["params"]["reason"] != "window_closed":
		return "session.closing: %s" % [got]
	if not await _closed(ws):
		return "conexão não fechou"
	if ws.get_close_code() != 1000:
		return "fechou com %d, esperado 1000" % ws.get_close_code()
	if not await _until(func(): return not ended.is_empty()):
		return "servidor não terminou"
	if ended[0] != "window_closed" or server.is_listening():
		return "fim: %s" % [ended]
	server.queue_free()
	return ""


func test_janela_token_errado() -> String:
	var server := _server()
	var ws := _client(server)
	if not await _open(ws):
		return "cliente não conectou"
	_ws_send(ws, _hello(1, {"token": TOKEN.replace("0", "f")}))
	if not await _closed(ws):
		return "token errado não fechou"
	if ws.get_close_code() != 4401:
		return "token errado fechou com %d" % ws.get_close_code()
	if not _ws_read(ws).is_empty():
		return "token errado recebeu resposta"
	# A vaga fica livre: a conexão certa entra depois.
	var ws2 := _client(server)
	if not await _open(ws2):
		return "segunda tentativa não conectou"
	_ws_send(ws2, _hello(1, {"token": TOKEN}))
	var got := await _reply(ws2)
	if got.size() != 1 or not got[0].has("result"):
		return "hello certo depois do errado: %s" % [got]
	ws2.close()
	server.queue_free()
	return ""


func test_janela_mensagem_antes_do_hello() -> String:
	var server := _server()
	for first in [_req(1, "preview.get_state"), "{json quebrado", _hello(1)]:
		var ws := _client(server)
		if not await _open(ws):
			return "cliente não conectou"
		_ws_send(ws, first)
		if not await _closed(ws) or ws.get_close_code() != 4401:
			return "%s antes do hello fechou com %d" % [first, ws.get_close_code()]
	server.queue_free()
	return ""


func test_janela_prazo_do_hello() -> String:
	var server := _server()
	var ws := _client(server)
	if not await _open(ws):
		return "cliente não conectou"
	await process_frame
	server.session.open(Time.get_ticks_msec() - VNPreviewSession.HELLO_TIMEOUT_MS)  # adianta o relógio
	if not await _closed(ws) or ws.get_close_code() != 4401:
		return "5 s sem hello fecharam com %d" % ws.get_close_code()
	server.queue_free()
	return ""


func test_janela_segunda_conexao() -> String:
	var server := _server()
	var ws := _client(server)
	if not await _open(ws):
		return "cliente não conectou"
	_ws_send(ws, _hello(1, {"token": TOKEN}))
	await _reply(ws)
	var ws2 := _client(server)
	await _until(func(): ws2.poll(); return ws2.get_ready_state() != WebSocketPeer.STATE_CONNECTING)
	if not await _closed(ws2) or ws2.get_close_code() != 4409:
		return "segunda conexão fechou com %d" % ws2.get_close_code()
	ws.poll()
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return "a primeira conexão caiu"
	ws.close()
	server.queue_free()
	return ""


func test_janela_queda_encerra() -> String:
	var server := _server(400)
	var ended := []
	server.ended.connect(func(r): ended.append(r))
	var ws := _client(server)
	if not await _open(ws):
		return "cliente não conectou"
	_ws_send(ws, _hello(1, {"token": TOKEN}))
	await _reply(ws)
	ws.close()
	await _closed(ws)
	var t0 := Time.get_ticks_msec()
	# Durante o prazo, o token já foi usado: nova conexão recebe 4409.
	var ws2 := _client(server)
	await _until(func(): ws2.poll(); return ws2.get_ready_state() != WebSocketPeer.STATE_CONNECTING)
	if not await _closed(ws2) or ws2.get_close_code() != 4409:
		return "reconexão depois da queda fechou com %d" % ws2.get_close_code()
	if not await _until(func(): return not ended.is_empty(), 3000):
		return "não encerrou depois da queda"
	if ended[0] != "connection_lost" or Time.get_ticks_msec() - t0 < 300:
		return "encerramento: %s" % [ended]
	if VNPreviewWebSocket.LOST_CONNECTION_EXIT_MS != 10000:
		return "prazo padrão deveria ser 10 s"
	server.queue_free()
	return ""
