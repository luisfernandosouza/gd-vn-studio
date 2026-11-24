class_name VNUISettings
extends RefCounted
## Configurações do jogador (UI Spec §8; RT §3.0 passo 1, §8.5;
## [code]save.schema.json → PlayerSettings[/code]).
##
## Guarda só o que o jogador mudou ([code]settings.json[/code]); o valor
## efetivo vem do jogador, senão de [code]project.json → settings[/code], senão
## do padrão do runtime. Os nomes são os de [code]bind[/code]/[code]set_setting[/code]
## ([code]volume.music[/code], [code]display_mode[/code]…).

## Configuração → tipo ([code]number[/code], [code]integer[/code],
## [code]boolean[/code], [code]enum[/code], [code]size[/code], [code]locale[/code]).
const TYPES := {
	"volume.master": "number", "volume.music": "number", "volume.ambient": "number",
	"volume.sfx": "number", "volume.voice": "number",
	"display_mode": "enum", "resolution": "size", "vsync": "boolean",
	"fps_limit_vn": "integer", "fps_limit_activity": "integer",
	"text_speed": "number", "auto_delay": "number", "skip_unread": "boolean",
	"locale": "locale", "text_scale": "number", "reduce_motion": "boolean",
	"subtitles": "boolean", "high_contrast": "boolean", "show_hotspots": "boolean",
	"content_filter": "boolean",
}

## Limites dos números (PlayerSettings).
const RANGES := {
	"volume.master": [0.0, 1.0], "volume.music": [0.0, 1.0], "volume.ambient": [0.0, 1.0],
	"volume.sfx": [0.0, 1.0], "volume.voice": [0.0, 1.0],
	"fps_limit_vn": [0, 360], "fps_limit_activity": [0, 360],
	"text_speed": [0.0, INF], "auto_delay": [0.0, INF], "text_scale": [0.8, 2.0],
}

const DISPLAY_MODES: Array[String] = ["windowed", "fullscreen", "borderless"]
const FPS_OPTIONS: Array[int] = [30, 60, 120, 144, 0]

## Padrões do runtime (UI Spec §8).
const DEFAULTS := {
	"text_speed": 40.0, "auto_delay": 1.5, "skip_unread": false,
	"display_mode": "windowed", "vsync": true, "fps_limit_vn": 60, "fps_limit_activity": 0,
	"volume.master": 0.8, "volume.music": 0.8, "volume.ambient": 0.8, "volume.sfx": 0.8,
	"volume.voice": 1.0, "text_scale": 1.0, "reduce_motion": false, "high_contrast": false,
	"show_hotspots": false, "subtitles": true, "content_filter": false,
}

## Resoluções oferecidas quando o projeto não lista nenhuma.
const DEFAULT_RESOLUTIONS := [[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]]

## Campos gravados pelo jogador, na forma do arquivo ([code]volume[/code] aninhado).
var player: Dictionary = {}
## [code]bundle.project[/code].
var project: Dictionary = {}
## Idioma do sistema ([method OS.get_locale]), trocável nos testes.
var system_locale: String = ""
## Tamanho do monitor, para filtrar resoluções; [code]Vector2i.ZERO[/code] = sem filtro.
var screen_size: Vector2i = Vector2i.ZERO


func is_censored_edition() -> bool:
	return String(project.get("content_filter", {}).get("edition", "standard")) == "censored"


## Idiomas do jogo ([code]project.locales[/code]).
func locales() -> PackedStringArray:
	var out := PackedStringArray()
	for l in project.get("locales", []):
		out.append(String(l))
	var d := String(project.get("default_locale", ""))
	if out.is_empty() and not d.is_empty():
		out.append(d)
	return out


## Resoluções oferecidas, filtradas pelo tamanho do monitor.
func resolutions() -> Array:
	var display: Dictionary = project.get("settings", {}).get("display", {})
	var all: Array = display.get("resolutions", DEFAULT_RESOLUTIONS)
	var out: Array = []
	for r in all:
		var v := [int(r[0]), int(r[1])]
		if screen_size == Vector2i.ZERO or (v[0] <= screen_size.x and v[1] <= screen_size.y):
			out.append(v)
	if out.is_empty() and not all.is_empty():
		out.append([int(all[0][0]), int(all[0][1])])
	return out


## Valor efetivo da configuração.
func get_value(setting: String) -> Variant:
	if setting == "content_filter" and is_censored_edition():
		return true
	var p: Variant = _player_value(setting)
	if p != null:
		return p
	return project_default(setting)


## O jogador gravou um valor para a configuração.
func is_player_set(setting: String) -> bool:
	return _player_value(setting) != null


## Padrão do projeto, senão do runtime.
func project_default(setting: String) -> Variant:
	var s: Dictionary = project.get("settings", {})
	var display: Dictionary = s.get("display", {})
	match setting:
		"locale":
			var ls := locales()
			var sys := system_locale
			if ls.has(sys):
				return sys
			var base := sys.get_slice("_", 0).get_slice("-", 0)
			for l in ls:
				if l == base:
					return l
			return String(project.get("default_locale", ls[0] if not ls.is_empty() else "en"))
		"resolution":
			var rs := resolutions()
			if not rs.is_empty():
				return rs[0]
			var base_res: Array = s.get("resolution", [1920, 1080])
			return [int(base_res[0]), int(base_res[1])]
		"text_speed", "auto_delay":
			if s.has(setting):
				return float(s[setting])
		"display_mode", "vsync":
			if display.has(setting):
				return display[setting]
		"fps_limit_vn", "fps_limit_activity":
			if display.has(setting):
				return int(display[setting])
		"content_filter":
			return bool(project.get("content_filter", {}).get("default", false))
	return DEFAULTS.get(setting)


## Confere o valor contra o schema; devolve [code][ok, valor normalizado][/code].
func normalize(setting: String, value: Variant) -> Array:
	if not TYPES.has(setting):
		return [false, null]
	match String(TYPES[setting]):
		"number":
			if not (value is int or value is float) or value is bool:
				return [false, null]
			var f := float(value)
			var rg: Array = RANGES.get(setting, [-INF, INF])
			if not is_finite(f) or f < rg[0] or f > rg[1]:
				return [false, null]
			return [true, f]
		"integer":
			if not (value is int or value is float) or value is bool:
				return [false, null]
			if value is float and (not is_finite(value) or value != floor(value)):
				return [false, null]
			var i := int(value)
			var rg: Array = RANGES.get(setting, [-INF, INF])
			if i < rg[0] or i > rg[1]:
				return [false, null]
			return [true, i]
		"boolean":
			return [value is bool, value if value is bool else null]
		"enum":
			return [value is String and DISPLAY_MODES.has(value), value]
		"locale":
			return [value is String and locales().has(value), value]
		"size":
			if not value is Array or value.size() != 2:
				return [false, null]
			for x in value:
				if not (x is int or x is float) or x is bool or float(x) < 1.0 or float(x) != floor(float(x)):
					return [false, null]
			return [true, [int(value[0]), int(value[1])]]
	return [false, null]


## Grava o valor do jogador (já normalizado).
func set_player_value(setting: String, value: Variant) -> void:
	if setting.begins_with("volume."):
		var vol: Dictionary = player.get("volume", {})
		vol[setting.trim_prefix("volume.")] = value
		player["volume"] = vol
	else:
		player[setting] = value


## Lê [code]settings.json[/code]. Devolve [code]false[/code] se o conteúdo é
## inválido (o chamador o renomeia para [code]settings.json.bad[/code]).
func load_player(data: Variant) -> bool:
	player = {}
	if data == null:
		return true
	if not data is Dictionary:
		return false
	var parsed := {}
	for key in data:
		if key == "volume":
			if not data.volume is Dictionary:
				return false
			for ch in data.volume:
				var r := normalize("volume." + String(ch), data.volume[ch])
				if not r[0]:
					return false
				var vol: Dictionary = parsed.get("volume", {})
				vol[ch] = r[1]
				parsed["volume"] = vol
		else:
			var r := normalize(String(key), data[key])
			if not r[0]:
				# Idioma que o build não tem mais não invalida o arquivo: só é ignorado.
				if key == "locale" and data[key] is String:
					continue
				return false
			parsed[key] = r[1]
	player = parsed
	return true


func _player_value(setting: String) -> Variant:
	if setting.begins_with("volume."):
		return player.get("volume", {}).get(setting.trim_prefix("volume."))
	return player.get(setting)
