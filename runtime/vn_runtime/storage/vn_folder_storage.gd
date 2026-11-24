class_name VNFolderStorage
extends VNStorage
## VNStorage do Preview com "Manter saves do Preview" (RT §8.5, PP §1.4): a
## pasta [code].vnstudio/preview/user/[/code] do projeto.
##
## Na janela, grava direto na pasta de [code]--vn-user-dir[/code]
## ([param user_dir] absoluto). No painel ([param user_dir] vazio), guarda na
## memória; cada gravação sai por [signal file_written]/[signal file_deleted],
## que a ponte do Preview (M4-08) transforma em
## [code]storage.write[/code]/[code]storage.delete[/code], e o conteúdo
## inicial chega por [method seed_files].
## Tarefas: M2-10 (armazenamento), M4-08 (ponte com o Studio).

var _backend: VNStorage


## A pasta de [code]--vn-user-dir[/code] no modo janela.
class _Dir extends VNFileStorage:
	func kind() -> StringName:
		return KIND_FOLDER


func _init(user_dir: String = "") -> void:
	if user_dir.is_empty():
		_backend = VNMemoryStorage.new()
	else:
		_backend = _Dir.new(user_dir)
	# Métodos, não lambdas: uma lambda guardaria uma referência a este objeto e formaria ciclo.
	_backend.file_written.connect(_on_written)
	_backend.file_deleted.connect(_on_deleted)


func _on_written(path: String, data: PackedByteArray) -> void:
	file_written.emit(path, data)


func _on_deleted(path: String) -> void:
	file_deleted.emit(path)


func kind() -> StringName:
	return KIND_FOLDER


## Modo painel: os arquivos ficam na memória e o Studio grava a pasta.
func is_panel_mode() -> bool:
	return _backend is VNMemoryStorage


## Conteúdo inicial da pasta no modo painel (caminho → bytes), sem emitir sinais.
func seed_files(files: Dictionary) -> void:
	if _backend is VNMemoryStorage:
		(_backend as VNMemoryStorage).seed_files(files)


func exists(path: String) -> bool:
	return _backend.exists(path)


func read_bytes(path: String) -> PackedByteArray:
	return _backend.read_bytes(path)


func write_bytes(path: String, data: PackedByteArray) -> Error:
	return _backend.write_bytes(path, data)


func delete(path: String) -> Error:
	return _backend.delete(path)


func rename(from_path: String, to_path: String) -> Error:
	return _backend.rename(from_path, to_path)


func list(dir: String) -> PackedStringArray:
	return _backend.list(dir)
