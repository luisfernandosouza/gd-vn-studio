@abstract
class_name VNFileStorage
extends VNStorage
## VNStorage numa pasta de arquivos (RT §8.5). Com a raiz [code]user://[/code]
## é a implementação do jogo exportado (no Web, o Godot guarda
## [code]user://[/code] na IndexedDB da página); com uma pasta absoluta, é o
## modo janela de [VNFolderStorage] ([code]--vn-user-dir[/code]).
##
## Grava num arquivo [code].tmp[/code] e renomeia, para que um jogo fechado no
## meio da gravação não deixe um save pela metade.
##
## É abstrata (falta [method VNStorage.kind]): as implementações concretas são
## [VNUserStorage] e a pasta da janela dentro de [VNFolderStorage].
## Tarefa: M2-10.

var _root: String


## [param root]: [code]user://[/code] ou uma pasta absoluta.
func _init(root: String = "user://") -> void:
	_root = root if root.ends_with("/") else root + "/"


## A pasta raiz, terminada em [code]/[/code].
func root() -> String:
	return _root


func _abs(path: String) -> String:
	return _root + path


func exists(path: String) -> bool:
	return is_valid_path(path) and FileAccess.file_exists(_abs(path))


func read_bytes(path: String) -> PackedByteArray:
	if not exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(_abs(path))


func write_bytes(path: String, data: PackedByteArray) -> Error:
	if not is_valid_path(path):
		return ERR_INVALID_PARAMETER
	var target := _abs(path)
	var err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(data)
	f.close()
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	err = DirAccess.rename_absolute(tmp, target)
	if err != OK:
		return err
	file_written.emit(path, data)
	return OK


func delete(path: String) -> Error:
	if not is_valid_path(path):
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(_abs(path)):
		return ERR_FILE_NOT_FOUND
	var err := DirAccess.remove_absolute(_abs(path))
	if err == OK:
		file_deleted.emit(path)
	return err


func rename(from_path: String, to_path: String) -> Error:
	if not is_valid_path(from_path) or not is_valid_path(to_path):
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(_abs(from_path)):
		return ERR_FILE_NOT_FOUND
	var data := read_bytes(from_path)
	var err := write_bytes(to_path, data)
	if err != OK:
		return err
	return delete(from_path)


func list(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not dir.is_empty() and not is_valid_path(dir.trim_suffix("/")):
		return out
	var prefix := "" if dir.is_empty() else dir.trim_suffix("/") + "/"
	var d := DirAccess.open(_root + prefix)
	if d == null:
		return out
	for name in d.get_files():
		if not name.ends_with(".tmp"):
			out.append(prefix + name)
	out.sort()
	return out
