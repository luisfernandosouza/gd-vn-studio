class_name VNAssetWebFetcher
extends RefCounted
## Leitor dos bytes de um asset no painel do Preview (runtime Web): o
## [code]fetch[/code] da página, com [code]cache: 'no-store'[/code], entregue ao
## Godot por [method JavaScriptBridge.js_buffer_to_packed_byte_array].
##
## Por que não o [HTTPRequest] (spike M4-01, relatório de 2026-11-23): ele lê o
## corpo um pedaço por quadro e foi de 1,7 a 8,5 vezes mais lento num PNG de
## 3,3 MB, e recusa a origem [code]vnpreview://[/code] do macOS e do Linux. O
## [code]no-store[/code] é o que faz a troca [code]/assets/<id>[/code] trazer o
## arquivo novo, e não a cópia do cache HTTP do webview.
##
## Só existe no Web ([method is_available]); na janela o [VNAssetsLoader] lê o
## arquivo pelo caminho. Specs: PP §1.1, §1.3. Tarefa: M4-07.

## Uma leitura terminou. [param status] é o HTTP (200 = ok; 0 = falha de rede).
signal fetched(key: int, status: int, bytes: PackedByteArray)

var _next_key := 0
var _callback: JavaScriptObject = null  # mantém a callback viva enquanto o leitor existir


## Há [code]fetch[/code] da página (export Web).
static func is_available() -> bool:
	return OS.has_feature("web")


func _init() -> void:
	if not is_available():
		return
	_callback = JavaScriptBridge.create_callback(_on_done)
	var window := JavaScriptBridge.get_interface("window")
	window.__vnAssetsDone = _callback
	JavaScriptBridge.eval("""
		window.__vnAssetsFetch = (url, key) => fetch(url, { cache: 'no-store' })
			.then(r => r.ok ? r.arrayBuffer() : Promise.reject(r.status))
			.then(b => window.__vnAssetsDone(key, 200, b),
			      e => window.__vnAssetsDone(key, typeof e === 'number' ? e : 0, null));
	""", true)


## Começa a ler [param url] e devolve a chave que vai em [signal fetched].
func start(url: String) -> int:
	_next_key += 1
	var key := _next_key
	JavaScriptBridge.get_interface("window").__vnAssetsFetch(url, key)
	return key


func _on_done(args: Array) -> void:
	var status := int(args[1])
	var bytes := PackedByteArray()
	if status == 200:
		bytes = JavaScriptBridge.js_buffer_to_packed_byte_array(args[2])
	fetched.emit(int(args[0]), status, bytes)
