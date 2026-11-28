class_name VNUIAPI
extends VNPluginService
## Camadas do plugin acima da UI narrativa (capacidade [code]ui.overlay[/code]; Plugin SDK §5.6–§5.7).
##
## A ponte põe o overlay numa [code]CanvasLayer[/code] cujo [code]Control[/code] raiz
## cobre a resolução base do projeto, com o modo de escala do jogo. Sem
## [code]input.capture[/code], a camada ignora o mouse e não recebe input; com ela,
## recebe durante a atividade (Plugin SDK §4.2, ação do host).

var _overlays: Array[Node] = []


## Instancia [param scene] e a põe na camada do plugin. Um [code]Control[/code] raiz
## é ancorado ao retângulo todo. [code]null[/code] sem a capacidade ou se a cena é inválida.
func push_overlay(scene: PackedScene) -> Node:
	if not _check_thread("ui.push_overlay"):
		return null
	if not _bridge.has_capability(VNRuntimeSDK.CAP_UI_OVERLAY):
		_deny(VNRuntimeSDK.CAP_UI_OVERLAY, "ui.push_overlay")
		return null
	if scene == null:
		_bridge.write_log(&"error", "ui.push_overlay: cena nula")
		return null
	var node := scene.instantiate()
	if node == null:
		_bridge.write_log(&"error", "ui.push_overlay: a cena não instancia")
		return null
	if node is Control:
		(node as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _bridge.add_overlay(node):
		node.free()
		_bridge.write_log(&"error", "ui.push_overlay: a camada do plugin não está disponível")
		return null
	_overlays.append(node)
	return node


## Tira e libera um overlay criado por [method push_overlay]. Um nó que não é
## deste plugin (ou já saiu) só gera aviso no log.
func pop_overlay(node: Node) -> void:
	if not _check_thread("ui.pop_overlay"):
		return
	if not _bridge.has_capability(VNRuntimeSDK.CAP_UI_OVERLAY):
		_deny(VNRuntimeSDK.CAP_UI_OVERLAY, "ui.pop_overlay")
		return
	if node == null or not is_instance_valid(node) or not _overlays.has(node):
		_bridge.write_log(&"warn", "ui.pop_overlay: o nó não é um overlay ativo deste plugin")
		return
	_overlays.erase(node)
	_bridge.remove_overlay(node)
	node.queue_free()
