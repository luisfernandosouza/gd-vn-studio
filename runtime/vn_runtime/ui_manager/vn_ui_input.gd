class_name VNUIInput
extends Node
## Recebe a entrada do jogador para o UI Manager (RT §10.1) antes dos
## controles, para que [code]vn_*[/code] naveguem pelas telas com teclado e
## gamepad. Roda mesmo com a árvore pausada.

var manager: VNRuntimeUIManager


func _ready() -> void:
	name = "UIInput"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if manager != null and manager.handle_input(event):
		get_viewport().set_input_as_handled()
