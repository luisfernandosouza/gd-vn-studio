extends SceneTree
## Executor dos testes do addon: godot --headless --path sdk/runtime --script res://tests/run_tests.gd
## Roda todo res://tests/test_*.gd; sai com 0 sem falhas e 1 com falha.


func _init() -> void:
	var files := DirAccess.get_files_at("res://tests")
	var total := 0
	var failed := 0
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load("res://tests/%s" % f)
		if script == null:
			printerr("FALHOU %s: não carregou" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var t: VNSdkTest = script.new()
			await t.call(name)
			total += 1
			if t.failures.is_empty():
				print("ok      %s::%s" % [f, name])
			else:
				failed += 1
				for msg in t.failures:
					printerr("FALHOU  %s::%s: %s" % [f, name, msg])
	print("%d/%d testes passaram" % [total - failed, total])
	quit(1 if failed > 0 or total == 0 else 0)
