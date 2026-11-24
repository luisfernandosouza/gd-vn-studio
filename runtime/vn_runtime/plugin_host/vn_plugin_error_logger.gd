extends Logger
## Recebe os erros de script que o motor reporta (RT §9: "erros de script
## reportados pelo motor") e os guarda numa fila, com o arquivo e a pilha.
##
## O motor pode chamar [method _log_error] de qualquer thread, então este
## objeto só enfileira, com [Mutex]; o Plugin Host esvazia a fila na thread
## principal ([method take]) e atribui cada erro ao plugin pelo caminho do
## script ([code]res://vn_plugins/<namespace>/…[/code]).
##
## Sem [code]class_name[/code]: carregado por [code]preload[/code] no Plugin Host.

var _mutex := Mutex.new()
var _queue: Array[Dictionary] = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	var files := PackedStringArray([file])
	for bt in script_backtraces:
		for i in bt.get_frame_count():
			files.append(bt.get_frame_file(i))
	var message := rationale if not rationale.is_empty() else code
	_mutex.lock()
	_queue.append({"function": function, "file": file, "line": line, "message": message, "files": files})
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


## Esvazia a fila e devolve os erros, na ordem em que chegaram.
func take() -> Array[Dictionary]:
	_mutex.lock()
	var out := _queue
	_queue = []
	_mutex.unlock()
	return out
