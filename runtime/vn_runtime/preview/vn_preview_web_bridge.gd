class_name VNPreviewWebBridge
extends Node
## Transporte do Preview no painel: ponte JavaScript na mesma página (Preview Protocol §1.1).
##
## O Studio cria [code]window.vnPreview[/code] com [code]onmessage(text)[/code] antes de iniciar
## o motor. A ponte põe ali [code]vnPreview.send(text)[/code], por onde o Studio manda cada
## requisição, e entrega respostas e notificações chamando [code]vnPreview.onmessage(text)[/code].
## Cada chamada leva uma mensagem JSON-RPC 2.0 em texto; lotes não são aceitos.
##
## O [code]session.hello[/code] vem sem token. Mensagem antes do hello e 5 s sem hello dão
## [code]UNAUTHENTICATED[/code] no lugar do fechamento da janela. Fechar o painel descarta a
## página: não há [code]session.closing[/code] nem processo para encerrar.
##
## Fora do navegador (testes), [method attach_page] recebe um objeto qualquer com o método
## [code]onmessage(text)[/code]; a ponte põe em [code]send[/code] um [Callable] que recebe
## [code][text][/code], como a [code]JavaScriptBridge[/code] entrega os argumentos.

## Uma nova sessão foi criada; o dono registra os métodos nela (M4-05).
signal session_created(session: VNPreviewSession)

## Nome do objeto global que o Studio registra na página.
const PAGE_OBJECT := "vnPreview"

var features: PackedStringArray = []
var modules: VNModules = null
var session: VNPreviewSession = null

var _page: Object = null
var _js_send_callback: Variant = null   # mantém o callback JS vivo


## Liga a ponte ao [code]window.vnPreview[/code] da página. Devolve false fora do navegador
## ou se o Studio não registrou o objeto.
func attach_to_window() -> bool:
	if not OS.has_feature("web"):
		return false
	var page: Object = JavaScriptBridge.get_interface(PAGE_OBJECT)
	if page == null:
		push_error("Preview: window.%s não existe; o Studio deve criá-lo antes de iniciar o motor." % PAGE_OBJECT)
		return false
	attach_page(page)
	return true


## Liga a ponte a [param page] (o [code]vnPreview[/code] da página ou um dublê) e abre a sessão.
func attach_page(page: Object) -> void:
	_page = page
	session = VNPreviewSession.new(VNPreviewSession.Transport.PANEL)
	session.features = features
	session.modules = modules
	session.outgoing.connect(_deliver)
	if page is JavaScriptObject:
		_js_send_callback = JavaScriptBridge.create_callback(_on_send)
		page.set("send", _js_send_callback)
	else:
		page.set("send", _on_send)
	session.open()
	session_created.emit(session)


func _process(_delta: float) -> void:
	if session != null:
		session.poll()


## [code]vnPreview.send(text)[/code]: argumentos chegam numa lista.
func _on_send(args: Array) -> void:
	if session == null:
		return
	var text: Variant = args[0] if args.size() > 0 else null
	if text is String:
		session.receive(text)
	else:
		session.receive_binary()


func _deliver(text: String) -> void:
	if _page != null:
		_page.call("onmessage", text)
