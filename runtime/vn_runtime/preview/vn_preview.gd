class_name VNPreview
extends RefCounted
## Entrada do servidor do Preview (Preview Protocol §1.1, §1.2, §7).
##
## O boot chama [method launch]: no painel (export Web com [code]window.vnPreview[/code]) liga a
## [VNPreviewWebBridge]; na janela (com [code]--vn-preview-port[/code] e [code]--vn-preview-token[/code])
## abre o [VNPreviewWebSocket]. Fora dos builds de debug e do runtime embutido no Studio
## (feature [code]vn_preview[/code]), as opções são ignoradas e nada é aberto (PP §7, BS §4).

const PORT_FLAG := "--vn-preview-port"
const TOKEN_FLAG := "--vn-preview-token"
## Feature tag do runtime do Preview embutido no Studio (export Web e [code]runtime-preview.pck[/code]).
const FEATURE := "vn_preview"


## O servidor do Preview pode existir neste build.
static func is_allowed() -> bool:
	return OS.is_debug_build() or OS.has_feature(FEATURE)


## O runtime foi aberto pelo Studio como Preview: no painel (export Web com
## [code]window.vnPreview[/code]) ou na janela (com [code]--vn-preview-port[/code] e
## [code]--vn-preview-token[/code]). O boot usa para escolher o [VNStorage]
## ([method VNPreviewUserData.boot_storage]): no Preview, nunca [code]user://[/code] (PP §1.4).
static func is_requested(args: PackedStringArray = _all_args()) -> bool:
	if not is_allowed():
		return false
	if OS.has_feature("web"):
		return JavaScriptBridge.get_interface(VNPreviewWebBridge.PAGE_OBJECT) != null
	return not window_options(args).is_empty()


## Opções da janela na linha de comando: [code]{port, token}[/code], ou vazio se não vieram.
## Com opções inválidas, devolve [code]{error}[/code]. O token nunca vai para o log (PP §7).
static func window_options(args: PackedStringArray = _all_args()) -> Dictionary:
	var port_text := _value_of(args, PORT_FLAG)
	var token := _value_of(args, TOKEN_FLAG)
	if port_text.is_empty() and token.is_empty():
		return {}
	if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
		return {"error": "%s precisa de uma porta entre 1 e 65535" % PORT_FLAG}
	if RegEx.create_from_string("^[0-9a-f]{64}$").search(token) == null:
		return {"error": "%s precisa de 32 bytes em hex (64 dígitos)" % TOKEN_FLAG}
	return {"port": int(port_text), "token": token}


## Abre o transporte certo como filho de [param parent] e o devolve, ou null quando não é Preview.
## [param on_session] recebe cada [VNPreviewSession] nova, para registrar os métodos (M4-05).
static func launch(parent: Node, modules: VNModules = null, on_session: Callable = Callable(),
		features: PackedStringArray = []) -> Node:
	if not is_allowed():
		return null
	if OS.has_feature("web"):
		if JavaScriptBridge.get_interface(VNPreviewWebBridge.PAGE_OBJECT) == null:
			return null
		var bridge := VNPreviewWebBridge.new()
		bridge.name = "VNPreviewWebBridge"
		bridge.modules = modules
		bridge.features = features
		if on_session.is_valid():
			bridge.session_created.connect(on_session)
		parent.add_child(bridge)
		bridge.attach_to_window()
		return bridge
	var opts := window_options()
	if opts.is_empty():
		return null
	if opts.has("error"):
		push_error("Preview: " + String(opts["error"]))
		return null
	var server := VNPreviewWebSocket.new()
	server.name = "VNPreviewWebSocket"
	server.modules = modules
	var user_dir_opt := VNPreviewUserData.user_dir_option()
	if user_dir_opt.has("error"):
		push_warning("Preview: %s; os dados do jogador ficam na memória." % user_dir_opt["error"])
	server.user_dir = user_dir_opt.get("dir", "")
	server.features = features
	if on_session.is_valid():
		server.session_created.connect(on_session)
	var err := server.listen(opts["port"], opts["token"])
	if err != OK:
		push_error("Preview: não abriu 127.0.0.1:%d (%s)" % [opts["port"], error_string(err)])
		server.free()
		return null
	# Fechar a janela passa pelo servidor, que manda session.closing antes de sair (PP §1.2).
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.auto_accept_quit = false
	parent.add_child(server)
	return server


static func _all_args() -> PackedStringArray:
	var out := OS.get_cmdline_args()
	out.append_array(OS.get_cmdline_user_args())
	return out


static func _value_of(args: PackedStringArray, flag: String) -> String:
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with(flag + "="):
			return args[i].substr(flag.length() + 1)
	return ""
