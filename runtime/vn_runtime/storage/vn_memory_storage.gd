class_name VNMemoryStorage
extends VNStorage
## VNStorage em memória (RT §8.5): um dicionário descartado ao fechar. É o
## padrão do Preview (PP §1.4) e a base do modo painel de [VNFolderStorage].
## Tarefa: M2-10.

var _files: Dictionary = {}   # caminho → PackedByteArray


func kind() -> StringName:
	return KIND_MEMORY


func exists(path: String) -> bool:
	return _files.has(path)


func read_bytes(path: String) -> PackedByteArray:
	return _files.get(path, PackedByteArray())


func write_bytes(path: String, data: PackedByteArray) -> Error:
	if not is_valid_path(path):
		return ERR_INVALID_PARAMETER
	_files[path] = data.duplicate()
	file_written.emit(path, data)
	return OK


func delete(path: String) -> Error:
	if not is_valid_path(path):
		return ERR_INVALID_PARAMETER
	if not _files.has(path):
		return ERR_FILE_NOT_FOUND
	_files.erase(path)
	file_deleted.emit(path)
	return OK


func rename(from_path: String, to_path: String) -> Error:
	if not is_valid_path(from_path) or not is_valid_path(to_path):
		return ERR_INVALID_PARAMETER
	if not _files.has(from_path):
		return ERR_FILE_NOT_FOUND
	var data: PackedByteArray = _files[from_path]
	delete(from_path)
	return write_bytes(to_path, data)


func list(dir: String) -> PackedStringArray:
	var prefix := "" if dir.is_empty() else dir.trim_suffix("/") + "/"
	var out := PackedStringArray()
	for path: String in _files:
		if path.begins_with(prefix) and not path.substr(prefix.length()).contains("/"):
			out.append(path)
	out.sort()
	return out


## Troca todo o conteúdo, sem emitir sinais (o Preview carrega a pasta do
## projeto assim, PP §1.4).
func seed_files(files: Dictionary) -> void:
	_files.clear()
	for path: String in files:
		if is_valid_path(path):
			_files[path] = files[path]
