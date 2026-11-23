# Teste B (D18, PP §1.3): o carregador de bytes do Preview, no mínimo para medir.
#
# Não é o `VNAssets` do runtime (M4-07). Faz só o que o teste B pede: troca o
# prefixo `res://vn_content/assets/` por `assets_base` (D24), lê os bytes, cria
# `ImageTexture` (PNG, JPG, WebP) ou `AudioStreamOggVorbis`/`AudioStreamMP3` em
# memória, guarda no cache e descarta um id quando o Studio troca o arquivo.
#
# Dois leitores, para comparar: `js` (fetch da página + js_buffer_to_packed_byte_array)
# e `http` (HTTPRequest do Godot, que no Web lê o corpo em pedaços, um por quadro).
class_name VNAssetsSpike
extends Node

const PREFIX := "res://vn_content/assets/"

var base := ""                 # assets_base de preview.load
var paths: Dictionary = {}     # id → res://… (bundle.json → assets)
var loader := "js"
var mipmaps := false
var max_cache := 0             # 0 = sem limite; senão LRU com até N recursos
var cache: Dictionary = {}     # id → Resource
var _lru: Array = []

signal _fetched(key: int, status: int, bytes: PackedByteArray)
var _next_key := 0
var _js_done: JavaScriptObject = null


func _ready() -> void:
	if OS.has_feature("web"):
		_js_done = JavaScriptBridge.create_callback(_on_js_fetched)
		JavaScriptBridge.get_interface("window").__vnFetchDone = _js_done
		JavaScriptBridge.eval("""
			window.__vnFetch = (url, key) => fetch(url, { cache: 'no-store' })
				.then(r => r.ok ? r.arrayBuffer() : Promise.reject(r.status))
				.then(b => window.__vnFetchDone(key, 200, b), e => window.__vnFetchDone(key, typeof e === 'number' ? e : 0, null));
		""", true)


# PP §1.3: troca o prefixo e codifica cada segmento do resto (RFC 3986, UTF-8).
func resolve(id: String) -> String:
	var p: String = paths[id]
	if base == "" or not p.begins_with(PREFIX):
		return p
	var enc: PackedStringArray = []
	for seg in p.substr(PREFIX.length()).split("/"):
		enc.append(seg.uri_encode())
	return base + "/".join(enc)


func evict(id: String) -> void:
	cache.erase(id)
	_lru.erase(id)


func clear() -> void:
	cache.clear()
	_lru.clear()


# Devolve {res, fetch_ms, decode_ms, upload_ms, bytes, marker|length, cached, error}.
func load_asset(id: String) -> Dictionary:
	if cache.has(id):
		_touch(id)
		return {"res": cache[id], "cached": true}
	var info := {"cached": false}
	var t0 := Time.get_ticks_usec()
	var url := resolve(id)
	var got: Array
	if loader == "js":
		got = await _fetch_js(url)
	else:
		got = await _fetch_http(url)
	info.fetch_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if got[0] != 200:
		info.error = "HTTP %d em %s" % [got[0], url]
		return info
	var bytes: PackedByteArray = got[1]
	info.bytes = bytes.size()
	var ext := (paths[id] as String).get_extension().to_lower()
	var t1 := Time.get_ticks_usec()
	var res: Resource = null
	if ext in ["png", "jpg", "jpeg", "webp"]:
		var img := Image.new()
		var err := img.load_png_from_buffer(bytes) if ext == "png" else (img.load_webp_from_buffer(bytes) if ext == "webp" else img.load_jpg_from_buffer(bytes))
		if err != OK:
			info.error = "decodificação %s: %d" % [ext, err]
			return info
		var c := img.get_pixel(8, 8)
		info.marker = [c.r8, c.g8, c.b8]
		info.size = [img.get_width(), img.get_height()]
		if mipmaps:
			img.generate_mipmaps()
		info.decode_ms = (Time.get_ticks_usec() - t1) / 1000.0
		var t2 := Time.get_ticks_usec()
		res = ImageTexture.create_from_image(img)
		info.upload_ms = (Time.get_ticks_usec() - t2) / 1000.0
	elif ext == "ogg" or ext == "mp3":
		var s: AudioStream = AudioStreamOggVorbis.load_from_buffer(bytes) if ext == "ogg" else AudioStreamMP3.load_from_buffer(bytes)
		if s == null:
			info.error = "decodificação %s" % ext
			return info
		s.loop = true
		info.length = s.get_length()
		info.decode_ms = (Time.get_ticks_usec() - t1) / 1000.0
		info.upload_ms = 0.0
		res = s
	else:
		info.error = "formato não testado: " + ext
		return info
	cache[id] = res
	_touch(id)
	info.res = res
	return info


func _touch(id: String) -> void:
	_lru.erase(id)
	_lru.append(id)
	while max_cache > 0 and _lru.size() > max_cache:
		cache.erase(_lru.pop_front())


func _fetch_js(url: String) -> Array:
	_next_key += 1
	var key := _next_key
	JavaScriptBridge.get_interface("window").__vnFetch(url, key)
	while true:
		var r: Array = await _fetched
		if r[0] == key:
			return [r[1], r[2]]
	return []


func _on_js_fetched(args: Array) -> void:
	var bytes := PackedByteArray()
	if int(args[1]) == 200:
		bytes = JavaScriptBridge.js_buffer_to_packed_byte_array(args[2])
	_fetched.emit(int(args[0]), int(args[1]), bytes)


func _fetch_http(url: String) -> Array:
	var http := HTTPRequest.new()
	http.download_chunk_size = 4 * 1024 * 1024
	add_child(http)
	http.request(url)
	var res: Array = await http.request_completed
	http.queue_free()
	return [res[1], res[3]]
