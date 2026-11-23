# Spike do teste B (M4-01, D18, PP §1.3): o mínimo de runtime para medir o carregador
# de bytes dos assets no painel do Preview.
#
# Não é o runtime do v1. Expõe ao JavaScript da página (o "Studio") as operações que
# o Preview usaria para os assets (preview.load com assets_base, troca /assets/<id>) e
# avisa a página quando o quadro com o resultado foi desenhado, para ela medir o tempo.
extends Control

@onready var _text: Label = $Text
@onready var _picture: TextureRect = $Picture
@onready var _music: AudioStreamPlayer = $Music

var _js_callbacks: Array = []      # referências vivas dos callbacks (o GC do JS)
var _host: JavaScriptObject = null
var _assets: VNAssetsSpike = null
var _picture_id := ""
var _music_id := ""


func _ready() -> void:
	_assets = VNAssetsSpike.new()
	add_child(_assets)
	if OS.has_feature("web"):
		_install_bridge()
	_text.text = "Preview pronto"
	await RenderingServer.frame_post_draw
	_notify("ready", {"godot": Engine.get_version_info().string})


# ---------------------------------------------------------------- ponte JS

func _install_bridge() -> void:
	var window := JavaScriptBridge.get_interface("window")
	_host = window.vnPreviewHost if window.vnPreviewHost else null
	var api: JavaScriptObject = JavaScriptBridge.create_object("Object")
	for name in ["assets_config", "assets_load", "assets_reload", "assets_clear", "assets_stats"]:
		var cb: JavaScriptObject = JavaScriptBridge.create_callback(Callable(self, "_js_" + name))
		_js_callbacks.append(cb)
		api[name] = cb
	window.vnPreview = api
	if _host == null:
		_host = window.parent.vnPreviewHost if window.parent else null


func _notify(kind: String, info: Dictionary) -> void:
	var text := JSON.stringify(info)
	if _host != null:
		_host.onEvent(kind, text)
	else:
		print("[preview] ", kind, " ", text)


# ---------------------------------------------------------------- teste B (assets por bytes)

func _js_assets_config(args: Array) -> void:
	# preview.load: assets_base e o mapa do bundle. args: req, assets_base, assets_json, opções_json
	var req := int(args[0])
	var opts = JSON.parse_string(str(args[3]))
	_assets.base = str(args[1])
	_assets.paths = JSON.parse_string(str(args[2]))
	_assets.loader = str(opts.get("loader", "js"))
	_assets.mipmaps = bool(opts.get("mipmaps", false))
	_assets.max_cache = int(opts.get("max_cache", 0))
	_assets.clear()
	_picture.texture = null
	_picture_id = ""
	_music.stop()
	_music.stream = null
	_music_id = ""
	await RenderingServer.frame_post_draw
	_notify("done", _asset_stats({"req": req}))


func _js_assets_load(args: Array) -> void:
	# Carrega um asset e, se show, põe na tela (imagem) ou toca (música). args: req, id, show
	var req := int(args[0])
	var id := str(args[1])
	var t0 := Time.get_ticks_usec()
	var info := await _assets.load_asset(id)
	if info.has("error"):
		_notify("error", {"req": req, "message": info.error})
		return
	if bool(args[2]):
		_use(id, info.res)
	info.erase("res")
	await RenderingServer.frame_post_draw
	info.merge({"req": req, "runtime_ms": (Time.get_ticks_usec() - t0) / 1000.0})
	_notify("done", _asset_stats(info))


func _js_assets_reload(args: Array) -> void:
	# preview.reload com a troca /assets/<id>: descarta o cache e redesenha o que usa o id.
	var req := int(args[0])
	var id := str(args[1])
	var t0 := Time.get_ticks_usec()
	_assets.evict(id)
	var in_use := id == _picture_id or id == _music_id
	var info := {"in_use": in_use}
	if in_use:
		info = await _assets.load_asset(id)
		if info.has("error"):
			_notify("error", {"req": req, "message": info.error})
			return
		info.in_use = true
		_use(id, info.res)
		info.erase("res")
	await RenderingServer.frame_post_draw
	info.merge({"req": req, "runtime_ms": (Time.get_ticks_usec() - t0) / 1000.0})
	_notify("done", _asset_stats(info))


func _js_assets_clear(args: Array) -> void:
	var req := int(args[0])
	_assets.clear()
	_picture.texture = null
	_picture_id = ""
	_music.stop()
	_music.stream = null
	_music_id = ""
	for i in 3:
		await RenderingServer.frame_post_draw
	_notify("done", _asset_stats({"req": req}))


func _js_assets_stats(args: Array) -> void:
	_notify("done", _asset_stats({"req": int(args[0])}))


func _use(id: String, res: Resource) -> void:
	if res is Texture2D:
		_picture.texture = res
		_picture_id = id
	elif res is AudioStream:
		# Troca da música em uso: continua do mesmo ponto (como o jogo faria ao recarregar).
		var pos := _music.get_playback_position() if _music_id == id and _music.playing else 0.0
		_music.stream = res
		_music.play(minf(pos, (res as AudioStream).get_length() - 0.1))
		_music_id = id


func _asset_stats(info: Dictionary) -> Dictionary:
	info.merge({
		"tex_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"cached": info.get("cached", false),
		"cache_size": _assets.cache.size(),
		"picture": _picture_id,
		"music": _music_id,
		"music_pos": _music.get_playback_position() if _music.playing else -1.0,
	})
	return info
