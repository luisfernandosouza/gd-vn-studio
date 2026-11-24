extends SceneTree
## Testes do VNAssets real ([VNAssetsLoader] e [VNAssetDecoder]), tarefa M4-07.
##
##   python3 runtime/tests/fixtures/generate.py
##   godot --headless --path runtime --import
##   godot --headless --path runtime --script res://tests/assets/test_vn_assets.gd
##
## Usa os bundles de runtime/tests/fixtures/bundles/ (M0-08). O mesmo bundle é
## lido como no jogo (recursos importados pelo Godot) e como no Preview
## (bytes do arquivo do autor), e os dois têm de dar o mesmo resultado
## (PP §1.3). Sai com 1 se algo falhar.

const FIX := "res://tests/fixtures/bundles/"
const TMP := "user://vn_assets_test/"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	if not FileAccess.file_exists(FIX + "dialogue/bundle.json"):
		printerr("faltam as fixtures: rode python3 runtime/tests/fixtures/generate.py e o --import")
		quit(2)
		return
	for t in [
		"contrato", "caminhos", "modo_stream", "bundle_intacto", "mesmas_texturas",
		"mesmo_audio", "mesmas_fontes", "nine_slice", "svg_e_opcoes", "falhas",
		"troca_de_png", "troca_da_substituta", "lru_limitado", "base_res_como_no_jogo",
	]:
		_record(t, call("test_" + t))
	for t in ["assincrono", "troca_assincrona", "troca_durante_leitura"]:
		_record(t, await call("test_" + t))
	print("%d/%d testes do VNAssets passaram." % [_passed, _passed + _failed])
	_rm_tree(TMP)
	quit(1 if _failed > 0 else 0)


func _record(test: String, err: Variant) -> void:
	if err is String and err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err if err is String else "o teste não terminou (erro de script)")


# --- Apoio --------------------------------------------------------------------

func _bundle(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIX + name + "/bundle.json"))


## Loader com o bundle e a base dada ("" = jogo, com o vn_content da fixture via res://).
func _loader(name: String, base: String) -> VNAssetsLoader:
	var a := VNAssetsLoader.new()
	a.load_bundle(_bundle(name))
	a.set_assets_base(base)
	return a


## Como no jogo: a pasta da fixture vale como res://vn_content/assets/ (RT §2.1, --vn-bundle).
func _game(name: String) -> VNAssetsLoader:
	return _loader(name, FIX + name + "/assets/")


## Como na janela do Preview: caminho absoluto da pasta assets/, lido pelos bytes.
func _window(name: String) -> VNAssetsLoader:
	return _loader(name, ProjectSettings.globalize_path(FIX + name + "/assets/"))


func _rgba(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var d := DirAccess.open(from)
	for f in d.get_files():
		if f.get_extension() != "import":
			DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for sub in d.get_directories():
		_copy_tree(from.path_join(sub), to.path_join(sub))


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


## Pasta temporária com uma cópia dos assets da fixture (o "projeto do autor").
func _author_copy(name: String) -> String:
	var dir := TMP + name + "_" + str(Time.get_ticks_usec()) + "/assets/"
	_copy_tree(ProjectSettings.globalize_path(FIX + name + "/assets/"), ProjectSettings.globalize_path(dir))
	return ProjectSettings.globalize_path(dir)


## Dublê do VNAssetWebFetcher: lê o arquivo por trás da URL e responde no quadro seguinte.
class FakeFetcher extends RefCounted:
	signal fetched(key: int, status: int, bytes: PackedByteArray)
	var base_url := ""
	var dir := ""
	var urls: Array[String] = []
	var _key := 0
	func start(url: String) -> int:
		_key += 1
		urls.append(url)
		var rel := url.trim_prefix(base_url).uri_decode()
		var path := dir + rel
		var bytes := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
		_reply.call_deferred(_key, 200 if not bytes.is_empty() else 404, bytes)
		return _key
	func _reply(key: int, status: int, bytes: PackedByteArray) -> void:
		fetched.emit(key, status, bytes)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# --- Testes -------------------------------------------------------------------

func test_contrato() -> String:
	var a := VNAssetsLoader.new()
	if not (a is VNAssets) or a.module_id() != &"assets":
		return "não é um VNAssets"
	var m := VNFakeModules.create()
	m.assets = a
	m.bind_all()
	if m.assets.modules() != m:
		return "bind"
	return ""


func test_caminhos() -> String:
	var a := VNAssetsLoader.new()
	a.load_bundle({"assets": {
		"bg/praia": {"path": "res://vn_content/assets/cenários/praia à noite 007.png", "type": "background"},
		"preset/font": {"path": "res://vn_runtime/presets/fonts/NotoSans-Regular.ttf", "type": "font"},
		"legado": "res://vn_content/assets/bg/x.png",
	}})
	if a.resolve_path("bg/praia") != "res://vn_content/assets/cenários/praia à noite 007.png":
		return "sem base, o caminho é o do bundle"
	a.set_assets_base("vnpreview://localhost/project/assets/")
	var url := "vnpreview://localhost/project/assets/cen%C3%A1rios/praia%20%C3%A0%20noite%20007.png"
	if a.resolve_path("bg/praia") != url:
		return "URL do painel: %s" % a.resolve_path("bg/praia")
	a.set_assets_base("http://vnpreview.localhost/project/assets")
	if a.resolve_path("legado") != "http://vnpreview.localhost/project/assets/bg/x.png":
		return "URL do WebView2 sem barra final: %s" % a.resolve_path("legado")
	if a.resolve_path("preset/font") != "res://vn_runtime/presets/fonts/NotoSans-Regular.ttf":
		return "asset do preset não troca de base"
	a.set_assets_base("C:\\Users\\autor\\Meu Jogo\\assets")
	if a.resolve_path("bg/praia") != "C:/Users/autor/Meu Jogo/assets/cenários/praia à noite 007.png":
		return "janela no Windows: %s" % a.resolve_path("bg/praia")
	a.set_assets_base("/home/autor/jogo/assets/")
	if a.resolve_path("bg/praia") != "/home/autor/jogo/assets/cenários/praia à noite 007.png":
		return "janela: sem codificação"
	a.set_assets_base("")
	if a.resolve_path("legado") != "res://vn_content/assets/bg/x.png" or a.resolve_path("nada") != "":
		return "voltar ao modo normal / id inexistente"
	return ""


func test_modo_stream() -> String:
	var a := _window("stream")
	if a.resolve_id("bg/dusk") != "bg/dusk" or a.resolve_id("bg/secret") != "bg/secret":
		return "sem o modo stream o id não muda"
	a.set_content_filter(true)
	if a.resolve_id("bg/dusk") != "bg/dusk_safe" or a.resolve_id("bg/secret") != "":
		return "replace_with/hide: %s, %s" % [a.resolve_id("bg/dusk"), a.resolve_id("bg/secret")]
	if a.load_asset("bg/secret") != null:
		return "hide devolve null"
	var t: Texture2D = a.load_asset("bg/dusk")
	var safe := _window("stream").load_asset("bg/dusk_safe") as Texture2D
	if t == null or _rgba(t).get_data() != _rgba(safe).get_data():
		return "replace_with carrega a substituta"
	if a.load_asset("sfx/noise") != null or a.load_asset("sfx/chime") == null:
		return "áudio no modo stream"
	return ""


func test_bundle_intacto() -> String:
	# O Preview usa o mesmo bundle.json do build: o VNAssets não reescreve caminhos
	# no bundle, então o content_hash é o mesmo (RT §2, PP §1.3).
	var b := _bundle("dialogue")
	var before := JSON.stringify(b, "", true, true)
	var a := VNAssetsLoader.new()
	a.load_bundle(b)
	a.set_assets_base(ProjectSettings.globalize_path(FIX + "dialogue/assets/"))
	for id in b.assets:
		a.resolve_path(id)
		a.load_asset(id)
	if JSON.stringify(b, "", true, true) != before:
		return "o bundle mudou"
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX + "index.json"))
	if b.content_hash != idx.bundles.dialogue.content_hash:
		return "content_hash"
	return ""


func test_mesmas_texturas() -> String:
	var game := _game("dialogue")
	var win := _window("dialogue")
	var n := 0
	for id in _bundle("dialogue").assets:
		var e: Dictionary = _bundle("dialogue").assets[id]
		if not e.type in ["background", "sprite", "image"]:
			continue
		var g: Texture2D = game.load_asset(id)
		var p: Texture2D = win.load_asset(id)
		if g == null or p == null:
			return "%s não carregou (jogo %s, preview %s)" % [id, g, p]
		if not (g is CompressedTexture2D):
			return "%s no jogo deveria vir do import (%s)" % [id, g.get_class()]
		if not (p is ImageTexture):
			return "%s no Preview deveria vir dos bytes" % id
		if g.get_size() != p.get_size() or g.has_mipmaps() != p.has_mipmaps():
			return "%s: tamanho ou mipmaps diferem" % id
		if _rgba(g).get_data() != _rgba(p).get_data():
			return "%s: pixels diferem do import" % id
		n += 1
	return "" if n >= 10 else "poucas imagens comparadas: %d" % n


func test_mesmo_audio() -> String:
	var game := _game("dialogue")
	var win := _window("dialogue")
	for id in _bundle("dialogue").assets:
		var e: Dictionary = _bundle("dialogue").assets[id]
		if not String(e.type).begins_with("audio_"):
			continue
		var g: AudioStream = game.load_asset(id)
		var p: AudioStream = win.load_asset(id)
		if g == null or p == null:
			return "%s não carregou" % id
		if absf(g.get_length() - p.get_length()) > 0.001:
			return "%s: duração %f ≠ %f" % [id, g.get_length(), p.get_length()]
		# O formato pode diferir: o import comprime o WAV (QOA), o Preview usa os bytes originais (PP §1.3).
		if g is AudioStreamWAV and (g.mix_rate != p.mix_rate or g.stereo != p.stereo):
			return "%s: taxa ou canais do WAV diferem" % id
		# Música toca em laço (BS §6.2: no build vira OGG com loop); efeito e voz não.
		var loops: bool = p.loop_mode != AudioStreamWAV.LOOP_DISABLED if p is AudioStreamWAV else p.loop
		if loops != (e.type == "audio_music"):
			return "%s: laço %s" % [id, loops]
	# OGG e MP3, a partir dos bytes (gerados aqui; as fixtures só têm WAV).
	var dec := VNAssetDecoder.new()
	if dec.decode(PackedByteArray([1, 2, 3]), "x.ogg", "audio_music") != null or dec.last_error.is_empty():
		return "OGG inválido devia falhar com mensagem"
	return ""


func test_mesmas_fontes() -> String:
	var game := _game("dialogue")
	var win := _window("dialogue")
	var g: FontFile = game.load_asset("preset/font_body")
	var path := ProjectSettings.globalize_path("res://vn_runtime/presets/fonts/NotoSans-Regular.ttf")
	var p: FontFile = VNAssetDecoder.new().decode(FileAccess.get_file_as_bytes(path), path, "font")
	if g == null or p == null:
		return "fonte não carregou"
	# Assets do preset vêm do pacote do runtime, também no Preview.
	if win.load_asset("preset/font_body") != g:
		return "fonte do preset no Preview devia vir do import"
	for prop in VNAssetDecoder.FONT_PROPS:
		if g.get(prop) != p.get(prop):
			return "%s: jogo %s, bytes %s" % [prop, g.get(prop), p.get(prop)]
	var s := "Ação à noite, 夜"
	if g.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32) != p.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32):
		return "medida do texto difere"
	var q: FontFile = VNAssetDecoder.new().decode(FileAccess.get_file_as_bytes(path), path, "font", {"antialiasing": 0, "hinting": 0})
	if q.antialiasing != 0 or q.hinting != 0:
		return "opções de import da fonte"
	return ""


func test_nine_slice() -> String:
	for a in [_game("dialogue"), _window("dialogue")]:
		var t: Texture2D = a.load_asset("ui/textbox")
		if t == null or t.get_meta(VNAssetDecoder.META_NINE_SLICE, PackedInt32Array()) != PackedInt32Array([16, 16, 16, 16]):
			return "nine_slice no metadado"
	return ""


func test_svg_e_opcoes() -> String:
	var dec := VNAssetDecoder.new()
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#ff0000"/></svg>'.to_utf8_buffer()
	var t: Texture2D = dec.decode(svg, "a.svg", "image")
	if t == null or t.get_size() != Vector2(40, 20):
		return "SVG na escala 1: %s" % (t.get_size() if t else null)
	t = dec.decode(svg, "a.svg", "image", {"svg/scale": 2.0})
	if t.get_size() != Vector2(80, 40):
		return "svg/scale"
	var png := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	png.fill(Color(0, 0.5, 1, 1))
	var bytes := png.save_png_to_buffer()
	# O renderizador headless não guarda mipmaps na textura; confere na imagem.
	if not dec.decode_image(bytes, "png", {"mipmaps/generate": true}).has_mipmaps() or dec.decode_image(bytes, "png").has_mipmaps():
		return "mipmaps/generate"
	t = dec.decode(bytes, "b.png", "image", {"process/size_limit": 16})
	if t.get_size() != Vector2(16, 8):
		return "process/size_limit: %s" % t.get_size()
	t = dec.decode(png.save_webp_to_buffer(true), "b.webp", "background")
	if t == null or t.get_size() != Vector2(64, 32):
		return "WebP"
	t = dec.decode(png.save_jpg_to_buffer(), "b.jpg", "background")
	if t == null:
		return "JPG"
	var wav: AudioStreamWAV = dec.decode(FileAccess.get_file_as_bytes(FIX + "dialogue/assets/audio/sfx/click.wav"), "c.wav", "audio_music", {"loop": false})
	if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return "import.loop: false na música"
	return ""


func test_falhas() -> String:
	var a := VNAssetsLoader.new()
	a.load_bundle({"assets": {
		"bg/sumiu": {"path": "res://vn_content/assets/backgrounds/nao_existe.png", "type": "background"},
		"bg/quebrado": {"path": "res://vn_content/assets/audio/sfx/click.wav", "type": "background"},
	}})
	a.set_assets_base(ProjectSettings.globalize_path(FIX + "dialogue/assets/"))
	var failed: Array = []
	a.asset_failed.connect(func(id, msg): failed.append([id, msg]))
	if a.load_asset("bg/sumiu") != null or a.load_asset("bg/quebrado") != null or a.load_asset("nada") != null:
		return "falha devolve null"
	if failed.size() != 2 or String(failed[0][1]).is_empty():
		return "asset_failed: %s" % [failed]
	return ""


func test_troca_de_png() -> String:
	var dir := _author_copy("dialogue")
	var a := _loader("dialogue", dir)
	var night: Texture2D = a.load_asset("bg/night")
	var shown: Texture2D = a.load_asset("bg/day")  # "na tela": quem desenha guarda a referência
	var changed: Array[String] = []
	a.asset_changed.connect(func(id): changed.append(id))
	# O Studio grava o arquivo novo por cima do do autor e manda /assets/bg/day.
	DirAccess.copy_absolute(dir + "backgrounds/night.png", dir + "backgrounds/day.png")
	if a.load_asset("bg/day") != shown:
		return "antes da troca, o cache vale"
	a.invalidate("bg/day")
	if changed != ["bg/day"]:
		return "asset_changed: %s" % [changed]
	var now: Texture2D = a.load_asset("bg/day")
	if now == shown or _rgba(now).get_data() != _rgba(night).get_data():
		return "a tela não recebeu o PNG novo"
	# Um asset que não está em uso só sai do cache, sem aviso.
	changed.clear()
	now = null
	shown = null
	a.invalidate("bg/day")
	if not changed.is_empty() or a.is_loaded("bg/day"):
		return "invalidate de asset fora de uso"
	return ""


func test_troca_da_substituta() -> String:
	var a := _loader("stream", _author_copy("stream"))
	a.set_content_filter(true)
	var shown: Texture2D = a.load_asset("bg/dusk")  # mostra bg/dusk_safe
	var changed: Array[String] = []
	a.asset_changed.connect(func(id): changed.append(id))
	a.invalidate("bg/dusk_safe")
	changed.sort()
	if changed != ["bg/dusk", "bg/dusk_safe"] or shown == null:
		return "quem mostra a substituta também é avisado: %s" % [changed]
	# Recarga do bundle: só sai do cache a entrada que mudou.
	var b := _bundle("stream")
	a.load_asset("bg/day")
	a.load_asset("bg/night")
	b.assets["bg/night"]["path"] = "res://vn_content/assets/backgrounds/day.png"
	a.load_bundle(b)
	if not a.is_loaded("bg/day") or a.is_loaded("bg/night"):
		return "load_bundle descarta só o que mudou"
	return ""


func test_lru_limitado() -> String:
	var a := _window("dialogue")
	a.cache_limit_bytes = 1
	var keep: Texture2D = a.load_asset("bg/day")   # em uso: nunca sai
	for id in ["bg/night", "bg/dusk", "obj/box", "obj/lamp_on", "obj/lamp_off"]:
		a.load_asset(id)
	var ids := a.cached_ids()
	if not ids.has("bg/day") or ids.size() > 2 or ids[ids.size() - 1] != "obj/lamp_off":
		return "LRU: %s" % ids
	a.cache_limit_bytes = VNAssetsLoader.DEFAULT_CACHE_LIMIT
	for id in ["bg/night", "bg/dusk", "obj/box"]:
		a.load_asset(id)
	if a.cached_ids().size() != 5 or a.cache_bytes() <= 0:
		return "com folga, tudo fica: %s" % a.cached_ids()
	keep = null
	return ""


func test_base_res_como_no_jogo() -> String:
	var a := _game("dialogue")
	if not (a.load_asset("bg/day") is CompressedTexture2D):
		return "base res:// usa o import do Godot"
	a.set_assets_base("")
	if a.load_asset("bg/day") != null:
		return "sem vn_content, o jogo não acha o asset"
	return ""


func test_assincrono() -> String:
	var dir := ProjectSettings.globalize_path(FIX + "dialogue/assets/")
	var f := FakeFetcher.new()
	f.base_url = "vnpreview://localhost/project/assets/"
	f.dir = dir
	var a := VNAssetsLoader.new()
	a.fetcher = f
	a.load_bundle(_bundle("dialogue"))
	a.set_assets_base(f.base_url)
	var ready: Array[String] = []
	a.asset_ready.connect(func(id): ready.append(id))
	if a.load_asset("bg/day") != null:
		return "no painel a leitura é assíncrona"
	a.load_asset("bg/day")
	if f.urls.size() != 1:
		return "dois pedidos do mesmo id viram uma leitura: %s" % [f.urls]
	await _frames(2)
	if ready != ["bg/day"] or not a.is_loaded("bg/day"):
		return "asset_ready: %s" % [ready]
	var t: Texture2D = a.load_asset("bg/day")
	var ref: Texture2D = _window("dialogue").load_asset("bg/day")
	if t == null or _rgba(t).get_data() != _rgba(ref).get_data():
		return "bytes lidos pelo fetch"
	var m: AudioStream = await a.fetch_asset("music/loop_a")
	if m == null or not (m is AudioStreamWAV):
		return "fetch_asset espera a leitura"
	a.load_asset("preset/font_body")
	if f.urls.size() != 2:
		return "asset do preset não passa pelo fetch: %s" % [f.urls]
	var failed: Array = []
	a.asset_failed.connect(func(id, _m): failed.append(id))
	a.load_bundle({"assets": {"bg/x": {"path": "res://vn_content/assets/nao/existe.png", "type": "background"}}})
	if await a.fetch_asset("bg/x") != null or failed != ["bg/x"]:
		return "404 vira asset_failed"
	return ""


func test_troca_assincrona() -> String:
	var dir := _author_copy("dialogue")
	var f := FakeFetcher.new()
	f.base_url = "http://vnpreview.localhost/project/assets/"
	f.dir = dir
	var a := VNAssetsLoader.new()
	a.fetcher = f
	a.load_bundle(_bundle("dialogue"))
	a.set_assets_base(f.base_url)
	var shown: Texture2D = await a.fetch_asset("bg/day")
	var night: Texture2D = await a.fetch_asset("bg/night")
	var changed: Array[String] = []
	a.asset_changed.connect(func(id): changed.append(id))
	DirAccess.copy_absolute(dir + "backgrounds/night.png", dir + "backgrounds/day.png")
	a.invalidate("bg/day")
	if not changed.is_empty():
		return "no painel o aviso espera o arquivo novo chegar"
	await _frames(2)
	if changed != ["bg/day"]:
		return "asset_changed depois da leitura: %s" % [changed]
	var now: Texture2D = a.load_asset("bg/day")
	if now == null or now == shown or _rgba(now).get_data() != _rgba(night).get_data():
		return "PNG novo na tela"
	return ""


func test_troca_durante_leitura() -> String:
	var dir := _author_copy("dialogue")
	var f := FakeFetcher.new()
	f.base_url = "vnpreview://localhost/project/assets/"
	f.dir = dir
	var a := VNAssetsLoader.new()
	a.fetcher = f
	a.load_bundle(_bundle("dialogue"))
	a.set_assets_base(f.base_url)
	a.load_asset("bg/day")                      # leitura com o arquivo antigo em andamento
	DirAccess.copy_absolute(dir + "backgrounds/night.png", dir + "backgrounds/day.png")
	a.invalidate("bg/day")                      # chega a troca antes da resposta
	await _frames(3)
	var t: Texture2D = a.load_asset("bg/day")
	var night: Texture2D = await a.fetch_asset("bg/night")
	if t == null or _rgba(t).get_data() != _rgba(night).get_data():
		return "a resposta antiga foi usada"
	if f.urls.size() != 3:
		return "a troca relê o arquivo: %s" % [f.urls]
	return ""
