class_name VNBootMessages
extends RefCounted
## Mensagens do runtime para o jogador (BS §13.1), pelo caminho de texto
## [code]runtime/message/<código em minúsculas>[/code].
##
## G001 e G002 acontecem antes de haver bundle e idioma carregados, então o
## boot as traduz pelo preset ([code]res://vn_runtime/presets/classic/locales/[/code],
## cópia gerada das specs) e, sem ele, pelos textos embutidos aqui (inglês e
## português, os do BS §13.1). As demais vão pelo UI Manager, com o idioma do jogo.

const G001 := &"G001"  ## bundle ausente, não decodifica ou versão incompatível
const G002 := &"G002"  ## hash de um arquivo do bundle não confere
const G003 := &"G003"  ## save modificado com save_tamper: reject
const G004 := &"G004"  ## save de versão incompatível
const G005 := &"G005"  ## falha ao gravar save ou perfil
const G006 := &"G006"  ## perfil modificado com save_tamper: reject

const PRESET_LOCALES := "res://vn_runtime/presets/classic/locales/"

const _BUILTIN := {
	"en": {
		"runtime/message/g001": "The game content is corrupted or from an incompatible version. Please reinstall the game.",
		"runtime/message/g002": "The game files are corrupted. Please reinstall the game.",
		"runtime/confirm/ok": "OK",
	},
	"pt-BR": {
		"runtime/message/g001": "O conteúdo do jogo está corrompido ou é de uma versão incompatível. Reinstale o jogo.",
		"runtime/message/g002": "Os arquivos do jogo estão corrompidos. Reinstale o jogo.",
		"runtime/confirm/ok": "OK",
	},
}


## Caminho de texto da mensagem ([code]G002[/code] → [code]runtime/message/g002[/code]).
static func text_path(code: StringName) -> String:
	return "runtime/message/" + String(code).to_lower()


## Texto da mensagem fatal no idioma [param locale] (código BCP 47 ou do
## sistema, como [code]pt_BR[/code]), pelo preset, senão embutido, senão em inglês.
static func fatal_text(code: StringName, locale: String) -> String:
	var path := text_path(code)
	for lang in _candidates(locale):
		var file := PRESET_LOCALES + lang + ".json"
		if FileAccess.file_exists(file):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
			if data is Dictionary and data.get("strings") is Dictionary and data.strings.has(path):
				return data.strings[path]
		if _BUILTIN.has(lang) and _BUILTIN[lang].has(path):
			return _BUILTIN[lang][path]
	return _BUILTIN.en.get(path, String(code))


## Idiomas a tentar para [param locale]: ele mesmo em BCP 47, a língua sem
## região e, por último, inglês.
static func _candidates(locale: String) -> PackedStringArray:
	var out := PackedStringArray()
	var l := locale.replace("_", "-")
	if not l.is_empty():
		out.append(l)
		if l.contains("-"):
			out.append(l.get_slice("-", 0))
	out.append("en")
	return out
