extends Node
## Cena de boot do runtime (RT §3.0).
##
## Opções da linha de comando, depois de [code]--[/code]:
## [br]- [code]--vn-test <casos>[/code]: roda os vetores de conformidade e sai
## com o código do executor (RT §12, spec 08 §4);
## [br]- [code]--vn-bundle <res://pasta>[/code]: lê o bundle de outra pasta do
## projeto (RT §2.1), só em debug e no editor;
## [br]- [code]--vn-fakes[/code]: monta o registro com os dublês de
## [code]tests/fakes/[/code] (só em debug, com a pasta tests/), para ver o boot
## chegar ao título antes dos módulos reais.
##
## Sem os módulos reais (até as integrações M1-12 e M2-16) e sem
## [code]--vn-fakes[/code], o boot só lê e confere o bundle (passo 2): mostra
## G001/G002 se ele estiver ruim e, se estiver bom, registra que parou ali.
##
## O executor e os dublês moram em [code]res://tests/[/code], que não entra nos
## templates de exportação (spec 09 §1.2).

const TEST_FLAG := "--vn-test"
const BUNDLE_FLAG := "--vn-bundle"
const FAKES_FLAG := "--vn-fakes"
const TEST_RUNNER := "res://tests/vn_test_runner.gd"
const FAKE_MODULES := "res://tests/fakes/vn_fake_modules.gd"

## Registro dos módulos (null enquanto os módulos reais não existem).
var modules: VNModules
var boot: VNBoot


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if TEST_FLAG in args:
		get_tree().quit(_run_tests(args))
		return
	var loader := VNBundleLoader.new(_bundle_dir(args), VNBuildConfig.load_default())
	modules = _create_modules(args)
	if modules == null:
		if not loader.load_all():
			_show_fatal(loader.error_code, loader.error_detail)
		else:
			print("vn-boot: bundle %s conferido (%s); os módulos do runtime ainda não existem, o boot para no passo 2." % [loader.dir, loader.bundle.content_hash])
		return
	modules.attach_all(self)
	# Preview (PP §1): só abre com as opções do Studio, e só em debug ou no runtime do Preview.
	VNPreview.launch(self, modules, func(session: VNPreviewSession): VNPreviewMethods.install(session, modules),
		PackedStringArray(["reproducible_rng", "show_screen"]))
	boot = VNBoot.new(modules, loader)
	boot.failed.connect(_show_fatal)
	boot.reached_title.connect(func(): print("vn-boot: título aberto (%s, idioma %s)." % [loader.bundle.content_hash, boot.locale]))
	boot.run()


func _bundle_dir(args: PackedStringArray) -> String:
	var i := args.find(BUNDLE_FLAG)
	if i < 0:
		return VNBundleLoader.DEFAULT_DIR
	if not OS.is_debug_build():
		printerr("vn-boot: %s só existe em debug; usando %s." % [BUNDLE_FLAG, VNBundleLoader.DEFAULT_DIR])
		return VNBundleLoader.DEFAULT_DIR
	if i + 1 >= args.size() or not args[i + 1].begins_with("res://"):
		printerr("vn-boot: %s precisa de uma pasta res://; usando %s." % [BUNDLE_FLAG, VNBundleLoader.DEFAULT_DIR])
		return VNBundleLoader.DEFAULT_DIR
	return args[i + 1]


## O registro com os módulos reais. Enquanto eles não existem (M1-12, M2-16),
## só os dublês, com --vn-fakes em debug.
func _create_modules(args: PackedStringArray) -> VNModules:
	if FAKES_FLAG in args and OS.is_debug_build() and ResourceLoader.exists(FAKE_MODULES):
		return load(FAKE_MODULES).create()
	return null


func _show_fatal(code: StringName, detail: String) -> void:
	var player_locale := _player_locale()
	printerr("vn-boot: %s (%s): %s" % [code, detail, VNBootMessages.fatal_text(code, player_locale)])
	var screen := VNFatalScreen.create(code, player_locale)
	screen.acknowledged.connect(func(): get_tree().quit(VNFatalScreen.EXIT_CODE))
	add_child(screen)


## Idioma para a mensagem fatal: o de settings.json, senão o do sistema.
func _player_locale() -> String:
	if modules != null:
		var v: Variant = modules.ui.get_setting(&"locale")
		if v is String:
			return v
	return OS.get_locale()


func _run_tests(args: PackedStringArray) -> int:
	if not OS.is_debug_build() or not ResourceLoader.exists(TEST_RUNNER):
		printerr("--vn-test: o executor de testes só existe no runtime de debug com a pasta tests/.")
		return 2
	var runner: RefCounted = load(TEST_RUNNER).new()
	return runner.run(args)
