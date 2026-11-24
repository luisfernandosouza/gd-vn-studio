extends SceneTree
## Executor dos testes unitários do runtime.
##
##   godot --headless --path runtime --script res://tests/unit/run_unit_tests.gd
##
## Carrega todo [code]test_*.gd[/code] em [code]res://tests/unit/[/code] (com
## subpastas, em ordem lexicográfica), instancia o script e chama cada método
## [code]test_*[/code]. Um teste devolve [code]""[/code] quando passa ou a
## mensagem de falha. Sai com 1 se algum teste falhar ou um arquivo não
## carregar.
##
## Cada tarefa põe os seus testes em [code]tests/unit/<módulo>/[/code], sem
## mexer neste arquivo nem na workflow.

const ROOT := "res://tests/unit"

var _passed := 0
var _failed := 0


func _init() -> void:
	var files := _find(ROOT)
	files.sort()
	for path in files:
		_run_file(path)
	print("%d/%d testes unitários passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 or files.is_empty() else 0)


func _find(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	return out


func _run_file(path: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		_failed += 1
		print("FALHOU  ", path, ": não carregou")
		return
	var suite: Object = script.new()
	var names := PackedStringArray()
	for m in script.get_script_method_list():
		var n: String = m.name
		if n.begins_with("test_") and not n in names:
			names.append(n)
	names.sort()
	print("# ", path.trim_prefix(ROOT + "/"))
	for n in names:
		var err: Variant = suite.call(n)
		if err is String and (err as String).is_empty():
			_passed += 1
			print("ok      ", n)
		else:
			_failed += 1
			print("FALHOU  ", n, ": ", err)
