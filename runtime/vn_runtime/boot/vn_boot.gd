class_name VNBoot
extends RefCounted
## Sequência de boot do runtime (RT §3.0), sobre o registro [VNModules].
##
## Cada passo só começa depois do anterior:
## [br]1. [method VNUIManager.load_settings] lê [code]settings.json[/code]
## (arquivo inválido vira [code]settings.json.bad[/code], no UI Manager);
## [br]2. [VNBundleLoader] lê e confere o bundle; erro fatal G001/G002 pelo
## sinal [signal failed], e o jogo fecha. Com o bundle, os módulos o recebem
## ([method VNModules.load_bundle]) e as configurações do jogador passam a valer
## (tela, VSync, FPS e volumes), já com os padrões do [code]project.json[/code];
## [br]3. idioma: [code]settings.locale[/code], senão o do sistema se o projeto o
## tiver, senão [code]default_locale[/code]; sem arquivo, [code]default_locale[/code];
## [br]4. [method VNSaveManager.load_profile]; perfil recusado mostra G006 no título;
## [br]5. [method VNPluginHost.load_plugins] com o [code]plugins.json[/code]
## (a ordem topológica e o [code]_vn_init[/code]/[code]_vn_ready[/code] são do Plugin Host);
## [br]6. calcula [code]sys.locale[/code] e [code]sys.ui.*[/code], faz a pergunta
## da primeira abertura (modo stream) e entra no título.
##
## Nada de narrativa roda e nenhum evento é emitido antes do passo 6. O boot
## também repassa as mudanças de configuração que não são do UI Manager: o modo
## stream ao Stage, ao Audio, a VNAssets e ao Engine, os volumes ao Audio e o
## modo de tela e o FPS ao Godot.

## Erro fatal (BS §13.1): [param code] é G001 ou G002; [param detail] vai só para o log.
signal failed(code: StringName, detail: String)
## O título abriu (fim do passo 6).
signal reached_title()
## O idioma mudou (boot ou configuração [code]locale[/code]); [param strings] é o
## [code]strings[/code] do arquivo do idioma (bundle-locale.schema.json).
signal locale_changed(locale: String, strings: Dictionary)

const STEP_SETTINGS := 1
const STEP_BUNDLE := 2
const STEP_LOCALE := 3
const STEP_PROFILE := 4
const STEP_PLUGINS := 5
const STEP_TITLE := 6

const ASK_TEXT := "runtime/content_filter/ask"
const TITLE_SCREEN := "title"

## Padrões do runtime para o que o boot aplica (UI Spec §8).
const DEFAULTS := {
	"volume.master": 0.8, "volume.music": 0.8, "volume.ambient": 0.8, "volume.sfx": 0.8, "volume.voice": 1.0,
	"display_mode": "windowed", "vsync": true, "fps_limit_vn": 60,
}

var modules: VNModules
var loader: VNBundleLoader

var locale: String = ""
var strings: Dictionary = {}
## Passos concluídos, em ordem.
var steps_done: PackedInt32Array = []
var fatal_code: StringName = &""
var fatal_detail: String = ""
## O perfil foi recusado (G006 no título).
var profile_rejected: bool = false
## A pergunta da primeira abertura foi feita neste boot.
var asked_content_filter: bool = false
## Aplica modo de tela, resolução, VSync e FPS no Godot (desligado nos testes).
var apply_display: bool = DisplayServer.get_name() != "headless" and not OS.has_feature("web")

var _in_title := false


func _init(p_modules: VNModules, p_loader: VNBundleLoader) -> void:
	modules = p_modules
	loader = p_loader


## Roda os passos 1 a 6. Devolve [code]false[/code] em erro fatal (o sinal
## [signal failed] já foi emitido). O título pode abrir depois do retorno, se a
## pergunta da primeira abertura esperar o jogador: confira [signal reached_title].
func run() -> bool:
	# 1. Configurações do jogador.
	modules.ui.load_settings()
	_done(STEP_SETTINGS)

	# 2. Bundle.
	if not loader.load_all():
		return _fatal(loader.error_code, loader.error_detail)
	modules.load_bundle(loader.bundle)
	modules.ui.set_licenses(loader.licenses)
	if loader.dir != VNBundleLoader.DEFAULT_DIR:
		# --vn-bundle: os assets vêm de <pasta>/assets/ (RT §2.1), pelo mesmo
		# mecanismo do assets_base do Preview.
		modules.assets.set_assets_base(loader.dir + "assets/")
	if not modules.ui.setting_changed.is_connected(_on_setting_changed):
		modules.ui.setting_changed.connect(_on_setting_changed)
	_apply_audio_settings()
	_apply_display_settings()
	_done(STEP_BUNDLE)

	# 3. Idioma.
	if not _load_locale(choose_locale(modules.ui.get_setting(&"locale"), OS.get_locale(), project())):
		return false
	_done(STEP_LOCALE)

	# 4. Perfil.
	var r := modules.saves.load_profile()
	profile_rejected = not r.ok
	_done(STEP_PROFILE)

	# 5. Plugins.
	modules.plugins.load_plugins(loader.plugins)
	_done(STEP_PLUGINS)

	# 6. sys.ui.*, pergunta da primeira abertura e título.
	_compute_sys_ui()
	_apply_content_filter(content_filter_enabled())
	if should_ask_content_filter():
		asked_content_filter = true
		modules.ui.confirm(ASK_TEXT, _on_content_filter_answer)
	else:
		_enter_title()
	return true


## [code]bundle.json → project[/code].
func project() -> Dictionary:
	return loader.bundle.get("project", {})


func is_censored_edition() -> bool:
	return String(project().get("content_filter", {}).get("edition", "standard")) == "censored"


# --- Passo 3: idioma ------------------------------------------------------------

## Idioma do jogo (RT §3.0 passo 3, UI Spec §8): o do jogador, se o projeto o
## tem; senão o do sistema ([param system], como [code]pt_BR[/code]) se o projeto
## o tem, exato ou pela língua; senão [code]default_locale[/code].
static func choose_locale(player: Variant, system: String, proj: Dictionary) -> String:
	var locales: Array = proj.get("locales", [])
	var default_locale := String(proj.get("default_locale", "en"))
	if player is String and locales.has(player):
		return player
	var sys := system.replace("_", "-")
	if locales.has(sys):
		return sys
	var lang := sys.get_slice("-", 0).to_lower()
	for l in locales:
		if String(l).get_slice("-", 0).to_lower() == lang:
			return l
	return default_locale


func _load_locale(wanted: String) -> bool:
	var default_locale := String(project().get("default_locale", "en"))
	var lang := wanted
	var s: Variant = loader.load_locale(lang)
	if s == null and loader.error_code == &"" and lang != default_locale:
		lang = default_locale   # idioma sem arquivo: usa default_locale
		s = loader.load_locale(lang)
	if loader.error_code != &"":
		return _fatal(loader.error_code, loader.error_detail)
	locale = lang
	strings = s if s is Dictionary else {}
	modules.state.set_system_value("sys.locale", locale)
	locale_changed.emit(locale, strings)
	return true


# --- Passo 6: sys.ui.* e modo stream ---------------------------------------------

func _compute_sys_ui() -> void:
	var proj := project()
	var gallery: Dictionary = proj.get("gallery", {})
	var sections: Array = gallery.get("sections", [])
	var values := {
		"sys.ui.has_save": modules.saves.has_save(),
		"sys.ui.in_game": false,
		"sys.ui.activity": false,
		"sys.ui.activity_skippable": false,
		"sys.ui.platform": platform_name(),
		"sys.ui.has_minigames": has_minigames(loader.bundle),
		"sys.ui.last_activity_outcome": "",
		"sys.ui.last_record_rank": 0,
		"sys.ui.has_gallery": not gallery.is_empty(),
		"sys.ui.gallery_endings": sections.has("endings"),
		"sys.ui.gallery_images": sections.has("images"),
		"sys.ui.gallery_music": sections.has("music"),
		"sys.ui.content_filter": content_filter_enabled(),
		"sys.ui.content_filter_available": not is_censored_edition() and has_marked_content(loader.bundle),
	}
	for id in values:
		modules.state.set_system_value(id, values[id])


## [code]sys.ui.platform[/code]: windows, linux, macos ou web.
static func platform_name() -> String:
	match OS.get_name():
		"Windows": return "windows"
		"macOS": return "macos"
		"Web": return "web"
	return "linux"


## Existe ao menos uma atividade com [code]free_play[/code]: a tela
## [code]minigames[/code] do bundle tem um botão [code]play_activity[/code]
## (o compilador a gera a partir delas, UI Spec §2).
static func has_minigames(bundle: Dictionary) -> bool:
	return _has_action(bundle.get("ui", {}).get("minigames", {}), "play_activity")


static func _has_action(v: Variant, action: String) -> bool:
	if v is Dictionary:
		if String(v.get("do", "")) == action:
			return true
		for k in v:
			if _has_action(v[k], action):
				return true
	elif v is Array:
		for x in v:
			if _has_action(x, action):
				return true
	return false


## O projeto tem conteúdo marcado para o modo stream (DM §10.4): assets com
## [code]censored[/code] ou passos de cena com [code]censor[/code] e
## [code]censored_*[/code].
static func has_marked_content(bundle: Dictionary) -> bool:
	for a in bundle.get("assets", {}).values():
		if a is Dictionary and a.has("censored"):
			return true
	return _has_censor_key(bundle.get("scenes", {}))


static func _has_censor_key(v: Variant) -> bool:
	if v is Dictionary:
		for k in v:
			if String(k).begins_with("censor") or _has_censor_key(v[k]):
				return true
	elif v is Array:
		for x in v:
			if _has_censor_key(x):
				return true
	return false


## Modo stream efetivo: sempre ligado na edição censurada (BS §5.4); senão a
## configuração do jogador, senão [code]project.content_filter.default[/code].
func content_filter_enabled() -> bool:
	if is_censored_edition():
		return true
	var v: Variant = modules.ui.get_setting(&"content_filter")
	if v is bool:
		return v
	return bool(project().get("content_filter", {}).get("default", false))


## A pergunta da primeira abertura vale: [code]ask_on_first_launch[/code], não
## é a edição censurada e o [code]settings.json[/code] ainda não tem
## [code]content_filter[/code] (RT §3.0 passo 6).
func should_ask_content_filter() -> bool:
	if is_censored_edition() or not bool(project().get("content_filter", {}).get("ask_on_first_launch", false)):
		return false
	var saved: Variant = modules.storage.read_json("settings.json") if modules.storage != null else null
	return not (saved is Dictionary and saved.has("content_filter"))


func _on_content_filter_answer(accepted: bool) -> void:
	# Grava sempre, mesmo igual ao padrão: o campo gravado marca a pergunta como feita.
	modules.ui.set_setting(&"content_filter", accepted)
	_enter_title()


func _enter_title() -> void:
	if _in_title:
		return
	_in_title = true
	modules.engine.enter_title()
	if not modules.ui.screen_stack().has(TITLE_SCREEN):
		modules.ui.open_screen(TITLE_SCREEN)
	if profile_rejected:
		modules.ui.show_message(VNBootMessages.text_path(VNBootMessages.G006))
	_done(STEP_TITLE)
	reached_title.emit()


# --- Configurações que o boot repassa ---------------------------------------------

func _setting(name: String) -> Variant:
	var v: Variant = modules.ui.get_setting(StringName(name))
	return DEFAULTS.get(name) if v == null else v


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	var s := String(setting)
	if s == "content_filter":
		var enabled := content_filter_enabled()
		modules.state.set_system_value("sys.ui.content_filter", enabled)
		_apply_content_filter(enabled)
		if VNPhase.is_in_game(modules.engine.phase()):
			modules.engine.content_filter_changed(enabled)
	elif s.begins_with("volume"):
		_apply_audio_settings()
	elif s in ["display_mode", "resolution", "vsync", "fps_limit_vn"]:
		_apply_display_settings()
	elif s == "locale" and value is String and value != locale:
		_load_locale(value)


func _apply_content_filter(enabled: bool) -> void:
	modules.stage.set_content_filter(enabled)
	modules.audio.set_content_filter(enabled)
	modules.assets.set_content_filter(enabled)


func _apply_audio_settings() -> void:
	var master := clampf(float(_setting("volume.master")), 0.0, 1.0)
	if AudioServer.bus_count > 0:
		AudioServer.set_bus_volume_db(0, linear_to_db(master) if master > 0.0 else -80.0)
	for ch in VNAudioManager.CHANNELS:
		modules.audio.set_channel_volume(ch, clampf(float(_setting("volume." + String(ch))), 0.0, 1.0))


func _apply_display_settings() -> void:
	var fps := int(_setting("fps_limit_vn"))
	if modules.plugins.current_activity().is_empty():
		Engine.max_fps = fps   # durante atividades vale fps_limit_activity (RT §5.3)
	if not apply_display:
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(_setting("vsync")) else DisplayServer.VSYNC_DISABLED)
	match String(_setting("display_mode")):
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res: Variant = _setting("resolution")
			if res is Array and res.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(res[0]), int(res[1])))


# --- Auxiliares -------------------------------------------------------------------

func _done(step: int) -> void:
	steps_done.append(step)


func _fatal(code: StringName, detail: String) -> bool:
	fatal_code = code
	fatal_detail = detail
	failed.emit(code, detail)
	return false
