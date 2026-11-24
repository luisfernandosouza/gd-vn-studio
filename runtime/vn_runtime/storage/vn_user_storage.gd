class_name VNUserStorage
extends VNFileStorage
## VNStorage do jogo exportado: [code]user://[/code] (no Web, a IndexedDB da
## página), RT §8.5. [param subdir] é para testes, que não devem tocar nos
## dados do jogo. Tarefa: M2-10.


func _init(subdir: String = "") -> void:
	super._init("user://" + subdir)


func kind() -> StringName:
	return KIND_USER
