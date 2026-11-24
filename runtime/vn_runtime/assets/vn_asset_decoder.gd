class_name VNAssetDecoder
extends RefCounted
## Cria o recurso de um asset a partir dos bytes do arquivo do autor, aplicando
## as opções que o import do Godot aplicaria no build (PP §1.3, BS §6.2).
##
## É o "carregador de bytes" do Preview: o Preview não passa pelo import do
## editor (D18), então o [VNAssetsLoader] lê os bytes e chama [method decode].
## O resultado DEVE ser o mesmo do jogo exportado; só podem diferir a
## compressão, o tempo de carga e a memória (PP §1.3). Os testes em
## [code]tests/assets/[/code] comparam, pixel a pixel, a textura daqui com a
## que o import do Godot gera do mesmo arquivo.
##
## Opções de import (BS §6.2, com o bloco [code]import[/code] do asset por cima,
## campo a campo):
## [br]- Imagens ([code]background[/code], [code]sprite[/code], [code]image[/code]):
##   [code]mipmaps/generate[/code] (padrão desligado), [code]process/fix_alpha_border[/code]
##   (padrão ligado, como no import), [code]process/premult_alpha[/code],
##   [code]process/size_limit[/code], [code]svg/scale[/code] (padrão 1).
##   [code]compress/*[/code] é ignorado: o Preview usa os bytes originais.
## [br]- Música ([code]audio_music[/code]): [code]loop[/code] ligado; [code]loop_offset[/code].
##   WAV de música vira OGG com laço no build, então aqui o WAV toca em laço do
##   começo ao fim ([code]edit/loop_mode[/code] e as outras opções [code]edit/*[/code]
##   do import de WAV valem se vierem em [code]import[/code]).
## [br]- Fontes: as propriedades de [FontFile] com o mesmo nome da opção de import
##   ([code]antialiasing[/code], [code]hinting[/code], [code]subpixel_positioning[/code],
##   [code]multichannel_signed_distance_field[/code], [code]msdf_pixel_range[/code],
##   [code]msdf_size[/code], [code]generate_mipmaps[/code], [code]force_autohinter[/code],
##   [code]allow_system_fallback[/code], [code]oversampling[/code],
##   [code]disable_embedded_bitmaps[/code], [code]keep_rounding_remainders[/code],
##   [code]modulate_color_glyphs[/code]).
##
## [code]nine_slice[/code] não é opção de import: no jogo e no Preview a textura é
## a mesma, e as margens vão no metadado [constant META_NINE_SLICE] do recurso,
## posto pelo [VNAssetsLoader] nos dois modos.
##
## Specs: PP §1.3; BS §6.2; DM §10.1. Tarefa: M4-07.

## Metadado com as margens [code]nine_slice[/code] ([PackedInt32Array] [code][esquerda, topo, direita, base][/code]).
const META_NINE_SLICE := &"vn_nine_slice"

const IMAGE_TYPES := ["background", "sprite", "image"]
const AUDIO_TYPES := ["audio_music", "audio_sfx", "audio_voice"]
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "svg"]
const AUDIO_EXTS := ["ogg", "mp3", "wav"]
const FONT_EXTS := ["ttf", "otf", "woff", "woff2", "pfb", "pfm"]

## Opções de import de fonte copiadas como propriedades do [FontFile].
const FONT_PROPS := [
	"antialiasing", "hinting", "subpixel_positioning", "multichannel_signed_distance_field",
	"msdf_pixel_range", "msdf_size", "generate_mipmaps", "force_autohinter",
	"allow_system_fallback", "oversampling", "disable_embedded_bitmaps",
	"keep_rounding_remainders", "modulate_color_glyphs",
]

## Último erro de [method decode], em linguagem simples; vazio se deu certo.
var last_error := ""


## O recurso dos [param bytes] do arquivo [param path] (só a extensão importa),
## do tipo [param type] de [code]assets.json[/code], com as opções de
## [param import_options]. [code]null[/code] se o formato não é aceito ou os
## bytes não decodificam ([member last_error] diz por quê).
func decode(bytes: PackedByteArray, path: String, type: String, import_options: Dictionary = {}) -> Resource:
	last_error = ""
	var ext := path.get_extension().to_lower()
	if bytes.is_empty():
		return _fail("arquivo vazio ou não encontrado: %s" % path)
	if ext in IMAGE_EXTS and (type in IMAGE_TYPES or type.is_empty()):
		return decode_texture(bytes, ext, import_options)
	if ext in AUDIO_EXTS and (type in AUDIO_TYPES or type.is_empty()):
		return decode_audio(bytes, ext, type, import_options)
	if ext in FONT_EXTS and (type == "font" or type.is_empty()):
		return decode_font(bytes, import_options)
	return _fail("formato %s não é carregado pelo runtime para o tipo %s" % [ext, type])


## Textura de PNG, JPG, WebP ou SVG (rasterizado na escala [code]svg/scale[/code]).
func decode_texture(bytes: PackedByteArray, ext: String, opts: Dictionary = {}) -> Texture2D:
	var img := decode_image(bytes, ext, opts)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## A [Image] como o import do Godot a deixaria antes de comprimir.
func decode_image(bytes: PackedByteArray, ext: String, opts: Dictionary = {}) -> Image:
	var img := Image.new()
	var err := OK
	match ext:
		"png": err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
		"svg": err = img.load_svg_from_buffer(bytes, float(opts.get("svg/scale", 1.0)))
		_: err = ERR_FILE_UNRECOGNIZED
	if err != OK or img.is_empty():
		_fail("não foi possível ler a imagem %s (erro %d)" % [ext, err])
		return null
	# Mesma ordem do ResourceImporterTexture: limite de tamanho, borda alfa, premultiplicar, mipmaps.
	var size_limit := int(opts.get("process/size_limit", 0))
	if size_limit > 0 and (img.get_width() > size_limit or img.get_height() > size_limit):
		var w := img.get_width()
		var h := img.get_height()
		if w >= h:
			img.resize(size_limit, maxi(1, int(round(float(h) * size_limit / w))), Image.INTERPOLATE_CUBIC)
		else:
			img.resize(maxi(1, int(round(float(w) * size_limit / h))), size_limit, Image.INTERPOLATE_CUBIC)
	if bool(opts.get("process/fix_alpha_border", true)) and img.detect_alpha() != Image.ALPHA_NONE:
		img.fix_alpha_edges()
	if bool(opts.get("process/premult_alpha", false)):
		img.premultiply_alpha()
	if bool(opts.get("mipmaps/generate", false)):
		img.generate_mipmaps()
	return img


## Música, efeito ou voz. Música toca em laço (BS §6.2), salvo [code]import.loop: false[/code].
func decode_audio(bytes: PackedByteArray, ext: String, type: String, opts: Dictionary = {}) -> AudioStream:
	var loop := bool(opts.get("loop", type == "audio_music"))
	match ext:
		"ogg":
			# Confere a assinatura antes: o Godot registra ERROR ao decodificar lixo.
			if bytes.size() < 4 or bytes.slice(0, 4).get_string_from_ascii() != "OggS":
				return _fail("o arquivo não é um OGG Vorbis")
			var s := AudioStreamOggVorbis.load_from_buffer(bytes)
			if s == null:
				return _fail("não foi possível ler o OGG")
			s.loop = loop
			s.loop_offset = float(opts.get("loop_offset", 0.0))
			return s
		"mp3":
			var s := AudioStreamMP3.load_from_buffer(bytes)
			if s == null:
				return _fail("não foi possível ler o MP3")
			s.loop = loop
			s.loop_offset = float(opts.get("loop_offset", 0.0))
			return s
		"wav":
			var wav_opts := {}
			for k in opts:
				if String(k).contains("/"):
					wav_opts[k] = opts[k]
			if loop and not wav_opts.has("edit/loop_mode"):
				wav_opts["edit/loop_mode"] = 2  # Forward, do começo ao fim
				wav_opts["edit/loop_begin"] = 0
				wav_opts["edit/loop_end"] = -1
			var s := AudioStreamWAV.load_from_buffer(bytes, wav_opts)
			if s == null:
				return _fail("não foi possível ler o WAV")
			return s
	return _fail("formato de áudio %s não aceito" % ext)


## Fonte TTF/OTF com as opções de import que são propriedades do [FontFile].
func decode_font(bytes: PackedByteArray, opts: Dictionary = {}) -> FontFile:
	var f := FontFile.new()
	f.data = bytes
	if f.get_font_name().is_empty() and f.get_face_count() == 0:
		return _fail("não foi possível ler a fonte")
	# Padrões do import de fonte do Godot (ResourceImporterDynamicFont), que diferem dos do FontFile.new().
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.multichannel_signed_distance_field = false
	f.msdf_pixel_range = 8
	f.msdf_size = 48
	for k in FONT_PROPS:
		if opts.has(k):
			f.set(k, opts[k])
	return f


func _fail(msg: String) -> Variant:
	last_error = msg
	return null
