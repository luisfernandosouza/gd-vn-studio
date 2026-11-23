class_name FakeStorage
extends VNStorage
## Dublê do VNStorage: arquivos num dicionário, como a implementação em
## memória do Preview (RT §8.5). Emite file_written/file_deleted.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var files: Dictionary = {}   # caminho → PackedByteArray


func kind() -> StringName:
	return KIND_MEMORY


func exists(path: String) -> bool:
	return files.has(path)


func read_bytes(path: String) -> PackedByteArray:
	return files.get(path, PackedByteArray())


func write_bytes(path: String, data: PackedByteArray) -> Error:
	_rec(&"write_bytes", [path])
	if not is_valid_path(path):
		return ERR_INVALID_PARAMETER
	files[path] = data
	file_written.emit(path, data)
	return OK


func delete(path: String) -> Error:
	_rec(&"delete", [path])
	if not files.has(path):
		return ERR_FILE_NOT_FOUND
	files.erase(path)
	file_deleted.emit(path)
	return OK


func rename(from_path: String, to_path: String) -> Error:
	if not files.has(from_path):
		return ERR_FILE_NOT_FOUND
	var data: PackedByteArray = files[from_path]
	delete(from_path)
	return write_bytes(to_path, data)


func list(dir: String) -> PackedStringArray:
	var prefix := dir.trim_suffix("/") + "/" if not dir.is_empty() else ""
	var out := PackedStringArray()
	for path: String in files:
		if path.begins_with(prefix) and not path.substr(prefix.length()).contains("/"):
			out.append(path)
	out.sort()
	return out
