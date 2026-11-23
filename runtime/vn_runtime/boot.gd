extends Node
## Cena de boot do runtime.
##
## Por enquanto ela só despacha o executor de testes: com `-- --vn-test <casos>` na linha de comando
## (RT §12, spec 08 §4), roda os vetores de conformidade e sai com o código do executor.
## Sem a opção, não faz nada; o boot do RT §3.0 entra com o Narrative Engine.
##
## O executor mora em `res://tests/`, que não entra nos templates de exportação (spec 09 §1.2).
## Por isso `--vn-test` só existe no build de debug e quando os testes estão no projeto (Build System §5).

const TEST_FLAG := "--vn-test"
const TEST_RUNNER := "res://tests/vn_test_runner.gd"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if TEST_FLAG in args:
		get_tree().quit(_run_tests(args))


func _run_tests(args: PackedStringArray) -> int:
	if not OS.is_debug_build() or not ResourceLoader.exists(TEST_RUNNER):
		printerr("--vn-test: o executor de testes só existe no runtime de debug com a pasta tests/.")
		return 2
	var runner: RefCounted = load(TEST_RUNNER).new()
	return runner.run(args)
