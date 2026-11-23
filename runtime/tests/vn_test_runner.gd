extends RefCounted
## Executor headless dos vetores de conformidade: `godot --headless --path runtime -- --vn-test <casos>`
## (RT §12, spec 08 §4).
##
## `<casos>` é um arquivo `.json` da pasta `docs/specs/conformance/` ou a própria pasta (só os `*.json`
## do primeiro nível, como `tools/conformance.py`). Caminho relativo é relativo à pasta de onde o Godot
## foi chamado.
##
## Estado atual (tarefa M0-04): o executor carrega os arquivos e conta os casos, mas nenhum módulo do
## runtime existe ainda, então todo caso aparece como pulado, nunca como passado. A tarefa M1-01 monta o
## estado de cada caso e chama os módulos.
##
## Saída (spec 08 §4): uma linha `FALHOU <arquivo>#<id>` por caso com falha e o resumo `N/M`
## (passaram/executados), mais os pulados.
## Código de saída: 0 sem falhas; 1 com falha; 2 com erro de uso (caminho inexistente, nenhum caso).

const FLAG := "--vn-test"


func run(args: PackedStringArray) -> int:
	var i := args.find(FLAG)
	if i < 0 or i + 1 >= args.size():
		printerr("uso: godot --headless --path runtime -- --vn-test <pasta-ou-arquivo-de-casos>")
		return 2
	var target := _resolve(args[i + 1])
	var files := _case_files(target)
	if files.is_empty():
		printerr("--vn-test: nenhum arquivo de casos em %s" % target)
		return 2

	var passed := 0
	var executed := 0
	var skipped := 0
	var failures := 0
	for path in files:
		var name := path.get_file()
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary and data.get("cases") is Array):
			print("FALHOU %s: arquivo ilegível ou sem a lista \"cases\"" % name)
			failures += 1
			continue
		for case in data["cases"]:
			var result := _run_case(name, case)
			match result:
				"skip":
					skipped += 1
				"pass":
					executed += 1
					passed += 1
				_:
					executed += 1
					failures += 1
					print("FALHOU %s#%s: %s" % [name, case.get("id", "?"), result])

	print("%d/%d (passaram/executados), %d pulados, em %d arquivos" % [passed, executed, skipped, files.size()])
	return 1 if failures > 0 else 0


## Roda um caso e devolve "pass", "skip" ou a descrição da falha (esperado e obtido).
## Nenhum tipo de vetor tem implementação ainda (M1-01 em diante).
func _run_case(_file: String, _case: Variant) -> String:
	return "skip"


func _resolve(path: String) -> String:
	if path.is_absolute_path():
		return path.simplify_path()
	return OS.get_environment("PWD").path_join(path).simplify_path() if OS.has_environment("PWD") else path


func _case_files(target: String) -> PackedStringArray:
	var out := PackedStringArray()
	if FileAccess.file_exists(target):
		out.append(target)
		return out
	var dir := DirAccess.open(target)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json":
			out.append(target.path_join(f))
	out.sort()
	return out
