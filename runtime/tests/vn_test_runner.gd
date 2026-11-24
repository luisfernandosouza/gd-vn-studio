extends RefCounted
## Executor headless dos vetores de conformidade: `godot --headless --path runtime -- --vn-test <casos>`
## (RT §12, spec 08 §4; tarefa M1-01).
##
## `<casos>` é um arquivo `.json` da pasta `docs/specs/conformance/` ou a própria pasta (só os `*.json`
## do primeiro nível, como `tools/conformance.py`). `<arquivo>#<id>` roda um caso só. Caminho relativo é
## relativo à pasta de onde o Godot foi chamado.
##
## Cada caso vai para o adaptador do seu `kind` (`tests/conformance/adapters/`), que monta o estado
## mínimo do caso (`VNCaseModules`: módulos reais de `vn_runtime/` onde existem, dublês no resto, e um
## bundle mínimo) e chama o módulo. Um caso cujo módulo ainda não tem implementação real é pulado,
## nunca dado como passado. Os números são lidos com `VNCaseJson`, que preserva a diferença entre `2`
## e `2.0` (spec 08 §2.1), e comparados com a mesma regra da referência (`VNCaseCompare`).
##
## Saída (spec 08 §4): `FALHOU <arquivo>#<id>` com o esperado e o obtido por caso com falha, o resumo
## `N/M` (passaram/executados) e os pulados por motivo.
## Código de saída: 0 sem falhas; 1 com falha; 2 com erro de uso (caminho inexistente, nenhum caso).

const FLAG := "--vn-test"
const ADAPTERS_DIR := "res://tests/conformance/adapters/"
const PENDING_ADAPTER := "pending_adapter.gd"

## id do módulo → [Script]: se não for null, substitui a descoberta dos módulos reais (autoteste).
var implementations: Variant = null
## Linhas impressas, para o autoteste. Também vão para a saída padrão.
var output: PackedStringArray = []
var quiet: bool = false


func run(args: PackedStringArray) -> int:
	var i := args.find(FLAG)
	if i < 0 or i + 1 >= args.size():
		printerr("uso: godot --headless --path runtime -- --vn-test <pasta-ou-arquivo-de-casos>[#<id>]")
		return 2
	var target := args[i + 1]
	var only_id := ""
	var hash_at := target.rfind("#")
	if hash_at > 0:
		only_id = target.substr(hash_at + 1)
		target = target.substr(0, hash_at)
	target = _resolve(target)
	var files := _case_files(target)
	if files.is_empty():
		printerr("--vn-test: nenhum arquivo de casos em %s" % target)
		return 2

	var mods := VNCaseModules.discover() if implementations == null else VNCaseModules.with(implementations)
	_out(mods.describe())
	for w in mods.warnings:
		_out("aviso: " + w)
	var adapters := _load_adapters(mods)

	var passed := 0
	var executed := 0
	var skipped := 0
	var failures := 0
	var skip_reasons := {}  # motivo → { arquivo → quantidade }
	for path in files:
		var name := path.get_file()
		var parsed := VNCaseJson.parse(FileAccess.get_file_as_string(path))
		var data: Variant = parsed.value
		if not parsed.ok or not (data is Dictionary and data.get("cases") is Array):
			_out("FALHOU %s: arquivo ilegível ou sem a lista \"cases\" %s" % [name, parsed.error])
			failures += 1
			continue
		for c in data["cases"]:
			if not c is Dictionary:
				_out("FALHOU %s: caso que não é objeto" % name)
				failures += 1
				continue
			var case_id := String(c.get("id", "?"))
			if only_id != "" and case_id != only_id:
				continue
			var outcome := _run_case(adapters, c)
			if outcome.has("skip"):
				skipped += 1
				var per_file: Dictionary = skip_reasons.get_or_add(outcome["skip"], {})
				per_file[name] = per_file.get(name, 0) + 1
				continue
			executed += 1
			if outcome.has("result") and VNCaseCompare.same(c.get("expect"), outcome["result"]):
				passed += 1
				continue
			failures += 1
			_out("FALHOU %s#%s" % [name, case_id])
			_out("  esperado: %s" % VNCaseCompare.to_json(c.get("expect")))
			if outcome.has("result"):
				_out("  obtido:   %s" % VNCaseCompare.to_json(outcome["result"]))
			else:
				_out("  erro:     %s" % outcome.get("error", "?"))

	if only_id != "" and executed + skipped == 0:
		printerr("--vn-test: nenhum caso com id %s" % only_id)
		return 2
	_out("%d/%d (passaram/executados), %d pulados, em %d arquivos" % [passed, executed, skipped, files.size()])
	for reason in skip_reasons:
		var parts := PackedStringArray()
		var total := 0
		for f in skip_reasons[reason]:
			parts.append("%s %d" % [f, skip_reasons[reason][f]])
			total += skip_reasons[reason][f]
		_out("  pulados (%d): %s [%s]" % [total, reason, ", ".join(parts)])
	return 1 if failures > 0 else 0


## Roda um caso: `{"result": obtido}`, `{"skip": motivo}` ou `{"error": motivo}` (kind sem adaptador).
func _run_case(adapters: Dictionary, c: Dictionary) -> Dictionary:
	var kind := String(c.get("kind", ""))
	if not adapters.has(kind):
		return {"error": "kind sem adaptador no executor: \"%s\"" % kind}
	var adapter: VNCaseAdapter = adapters[kind]
	return adapter.run(c)


## kind → adaptador. Os adaptadores de `adapters/` vêm primeiro; o `pending_adapter.gd` só cobre os
## kinds que nenhum outro cobre, para que a tarefa que liga um kind não precise editar o dele.
func _load_adapters(mods: VNCaseModules) -> Dictionary:
	var out := {}
	var files := PackedStringArray()
	for f in ResourceLoader.list_directory(ADAPTERS_DIR):
		if f.get_extension() == "gd" and f != PENDING_ADAPTER:
			files.append(f)
	files.sort()
	files.append(PENDING_ADAPTER)
	for f in files:
		var adapter: VNCaseAdapter = load(ADAPTERS_DIR + f).new()
		adapter.modules = mods
		for kind in adapter.kinds():
			if out.has(kind):
				if f != PENDING_ADAPTER:
					_out("aviso: kind \"%s\" coberto por mais de um adaptador; usando o primeiro" % kind)
				continue
			out[kind] = adapter
	return out


func _out(line: String) -> void:
	output.append(line)
	if not quiet:
		print(line)


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
