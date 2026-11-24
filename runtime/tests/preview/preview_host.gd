extends SceneTree
## Hospedeiro do servidor do Preview para o teste de ponta a ponta da janela (M4-04).
##
##   godot --headless --path runtime --script res://tests/preview/preview_host.gd -- --vn-preview-port <porta> --vn-preview-token <token>
##
## Abre o servidor como o boot abrirá ([method VNPreview.launch]) e registra métodos falsos de
## [code]preview.load[/code] e [code]preview.get_state[/code], para o teste conferir as transições.
## Sai quando o servidor termina (queda da conexão, PP §1.2). Sem as opções, sai com 2.


func _initialize() -> void:
	var server := VNPreview.launch(root, null, _register, PackedStringArray(["show_screen"]))
	if server == null:
		printerr("preview_host: sem --vn-preview-port/--vn-preview-token válidos")
		quit(2)
		return
	print("preview_host: ouvindo em 127.0.0.1:%d" % (server as VNPreviewWebSocket).port())


func _register(session: VNPreviewSession) -> void:
	session.register("preview.load", func(_p): return {
		"content_hash": "sha256-" + "a".repeat(64), "format_version": "1.0.0",
		"chapters": 2, "scenes": 5, "plugins": ["vnstudio.fishing"]})
	session.register("preview.get_state", func(_p): return {
		"phase": "TITLE", "preview": "RUNNING", "chapter": null, "scene": null, "node": null})
	session.register("preview.start", func(_p): return {
		"phase": "SCENE_RUNNING", "preview": "RUNNING", "chapter": null, "scene": null, "node": null})
