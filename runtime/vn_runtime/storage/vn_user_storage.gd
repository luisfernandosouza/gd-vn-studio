class_name VNUserStorage
extends VNFileStorage
## VNStorage do jogo exportado: [code]user://[/code] (no Web, a IndexedDB da
## página), RT §8.5. Tarefa: M2-10.


func _init() -> void:
	super._init("user://", KIND_USER)
