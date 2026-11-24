class_name VNBundleLoader
extends RefCounted
## Lê o bundle narrativo (RT §2, §2.1, §3.0 passo 2; BS §5.2, §8.2).
##
## Duas formas, na mesma pasta ([constant DEFAULT_DIR] ou a de
## [code]--vn-bundle[/code]):
## [br]- [b]canônica em JSON[/b] ([code]bundle.json[/code],
## [code]locales/<lang>.json[/code], [code]plugins.json[/code],
## [code]licenses.json[/code]): só em builds de debug e no editor
## ([member allow_json]), e só se houver [code]bundle.json[/code];
## [br]- [b].vnb[/b] ([code]narrative.vnb[/code], [code]locales/<lang>.vnb[/code],
## [code]plugins.vnb[/code], [code]licenses.vnb[/code]): cabeçalho
## [code]VNB1[/code], corpo Zstandard, cifrado com AES-256-CBC quando a flag 0
## está ligada (BS §5.2).
##
## Falhas viram os códigos do BS §13.1 em [member error_code]:
## [constant VNBootMessages.G001] (ausente, não decodifica, versão de formato,
## [code]format_version[/code] MAJOR não suportado, caminho de asset fora de
## [code]res://[/code]) e [constant VNBootMessages.G002] (hash diferente do
## cabeçalho, do [code]build_config[/code] ou do [code]content_hash[/code]).
##
## O [code]content_hash[/code] é recalculado sobre o texto lido: o bundle
## gravado pelo compilador já é JSON canônico, então basta tirar o campo
## [code]content_hash[/code] do texto e calcular o SHA-256. Se o texto não está
## na forma canônica (editado à mão, com espaços), o hash é recalculado pelo
## [VNCanonicalJSON] sobre os valores lidos. Esse segundo caminho depende do
## leitor de JSON do Godot, que pode errar o último bit de números com mais de
## 17 dígitos; o compilador nunca grava números assim.

const DEFAULT_DIR := "res://vn_content/"
const SUPPORTED_FORMAT_MAJOR := 1    ## format_version do Data Model aceito (RT §2)
const SUPPORTED_BUNDLE_VERSION := 1  ## bundle_version de bundle.schema.json

const VNB_MAGIC := "VNB1"
const VNB_VERSION := 1
const VNB_HEADER_SIZE := 60
const VNB_FLAG_ENCRYPTED := 1

const FORM_JSON := &"json"
const FORM_VNB := &"vnb"

## Pasta do bundle, terminada em "/".
var dir: String = DEFAULT_DIR
var config: VNBuildConfig
## Aceita a forma canônica em JSON (debug e editor, RT §2.1).
var allow_json: bool = OS.is_debug_build()

var form: StringName = &""
var bundle: Dictionary = {}
var plugins: Dictionary = {}
var licenses: Dictionary = {}

## &"" sem erro; senão G001 ou G002.
var error_code: StringName = &""
## Detalhe para o log (nunca mostrado ao jogador).
var error_detail: String = ""


func _init(p_dir: String = DEFAULT_DIR, p_config: VNBuildConfig = null) -> void:
	dir = p_dir if p_dir.ends_with("/") else p_dir + "/"
	config = p_config if p_config != null else VNBuildConfig.load_default()


## Lê bundle, plugins e licenças. Devolve [code]false[/code] com
## [member error_code] preenchido se o jogo não pode seguir.
func load_all() -> bool:
	error_code = &""
	error_detail = ""
	if allow_json and FileAccess.file_exists(dir + "bundle.json"):
		form = FORM_JSON
	elif FileAccess.file_exists(dir + "narrative.vnb"):
		form = FORM_VNB
	else:
		return _fail(VNBootMessages.G001, "bundle ausente em %s" % dir)

	var doc := _read_doc("bundle", "narrative")
	if doc.is_empty():
		return false
	var data: Variant = doc.data
	if not data is Dictionary:
		return _fail(VNBootMessages.G001, "bundle não é um objeto JSON")
	bundle = data
	if not _check_bundle(doc.text):
		return false

	doc = _read_doc("plugins", "plugins")
	if doc.is_empty():
		return false
	if not (doc.data is Dictionary and doc.data.get("plugins") is Dictionary):
		return _fail(VNBootMessages.G001, "plugins inválido")
	plugins = doc.data

	licenses = {}
	if _exists("licenses", "licenses") or config.expected_hash("licenses.vnb") != "":
		doc = _read_doc("licenses", "licenses")
		if doc.is_empty():
			return false
		licenses = doc.data if doc.data is Dictionary else {}
	return true


## O arquivo do idioma existe no bundle.
func has_locale(lang: String) -> bool:
	return _exists("locales/" + lang, "locales/" + lang)


## [code]strings[/code] do idioma (bundle-locale.schema.json), ou
## [code]null[/code] se o idioma não tem arquivo. Um arquivo que existe e não
## decodifica ou não confere preenche [member error_code] e devolve [code]null[/code].
func load_locale(lang: String) -> Variant:
	if not has_locale(lang):
		return null
	var doc := _read_doc("locales/" + lang, "locales/" + lang)
	if doc.is_empty():
		return null
	if not (doc.data is Dictionary and doc.data.get("strings") is Dictionary):
		_fail(VNBootMessages.G001, "idioma %s inválido" % lang)
		return null
	return doc.data.strings


## Caminho de um arquivo do bundle nesta pasta, na forma lida.
func path_of(json_name: String, vnb_name: String) -> String:
	return dir + (json_name + ".json" if form == FORM_JSON else vnb_name + ".vnb")


# --- Conferências -------------------------------------------------------------

func _check_bundle(text: String) -> bool:
	if int(bundle.get("bundle_version", 0)) != SUPPORTED_BUNDLE_VERSION:
		return _fail(VNBootMessages.G001, "bundle_version %s não suportado" % bundle.get("bundle_version"))
	var major := format_major(bundle.get("format_version"))
	if major != SUPPORTED_FORMAT_MAJOR:
		return _fail(VNBootMessages.G001, "format_version %s não suportado" % bundle.get("format_version"))
	var declared: Variant = bundle.get("content_hash")
	if not declared is String or VNCanonicalJSON.hash_bytes(declared).is_empty():
		return _fail(VNBootMessages.G001, "bundle sem content_hash")
	if not content_hash_matches(text, bundle):
		return _fail(VNBootMessages.G002, "content_hash não confere com o conteúdo")
	if config.content_hash != "" and config.content_hash != declared:
		return _fail(VNBootMessages.G002, "content_hash diferente do build_config")
	var assets: Variant = bundle.get("assets", {})
	if not assets is Dictionary:
		return _fail(VNBootMessages.G001, "assets inválido")
	for id in assets:
		var a: Variant = assets[id]
		if not (a is Dictionary and String(a.get("path", "")).begins_with("res://")):
			return _fail(VNBootMessages.G001, "asset %s com caminho fora de res://" % id)
	return true


## MAJOR de um SemVer ([code]"1.2.0"[/code] → 1); -1 se não é SemVer.
static func format_major(v: Variant) -> int:
	if not v is String:
		return -1
	var parts := String(v).split(".")
	if parts.size() < 3 or not parts[0].is_valid_int():
		return -1
	return parts[0].to_int()


## O [code]content_hash[/code] declarado em [param parsed] confere com o
## conteúdo (RT §2): pelo texto canônico sem o campo ou, se o texto não está na
## forma canônica, pelo [VNCanonicalJSON] sobre os valores.
static func content_hash_matches(text: String, parsed: Dictionary) -> bool:
	var declared := String(parsed.get("content_hash", ""))
	var needle := ",\"content_hash\":" + VNCanonicalJSON.quote(declared)
	if text.count(needle) == 1:
		if VNCanonicalJSON.sri(text.replace(needle, "").to_utf8_buffer()) == declared:
			return true
	return VNCanonicalJSON.content_hash(parsed) == declared


# --- Leitura dos arquivos -----------------------------------------------------

func _exists(json_name: String, vnb_name: String) -> bool:
	return FileAccess.file_exists(path_of(json_name, vnb_name))


## { data, text } ou vazio (com error_code preenchido).
func _read_doc(json_name: String, vnb_name: String) -> Dictionary:
	var path := path_of(json_name, vnb_name)
	if not FileAccess.file_exists(path):
		_fail(VNBootMessages.G001, "arquivo ausente: %s" % path)
		return {}
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty() and FileAccess.get_open_error() != OK:
		_fail(VNBootMessages.G001, "não foi possível ler %s" % path)
		return {}
	var json_bytes := raw
	if form == FORM_VNB:
		json_bytes = decode_vnb(raw, vnb_name + ".vnb")
		if json_bytes.is_empty():
			return {}
	var text := json_bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail(VNBootMessages.G001, "%s não é JSON válido (linha %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return {"data": json.data, "text": text}


## JSON de um [code].vnb[/code] (BS §5.2), conferido pelo hash do cabeçalho e
## pelo [code]CONTENT_HASHES[/code] do build (BS §8.2). Vazio em erro.
func decode_vnb(raw: PackedByteArray, rel_path: String) -> PackedByteArray:
	if raw.size() < VNB_HEADER_SIZE or raw.slice(0, 4).get_string_from_ascii() != VNB_MAGIC:
		_fail(VNBootMessages.G001, "%s: cabeçalho .vnb inválido" % rel_path)
		return PackedByteArray()
	var version := raw.decode_u16(4)
	if version != VNB_VERSION:
		_fail(VNBootMessages.G001, "%s: versão de formato .vnb %d desconhecida" % [rel_path, version])
		return PackedByteArray()
	var flags := raw.decode_u16(6)
	var header_hash := raw.slice(8, 40)
	var size := raw.decode_u32(40)
	var iv := raw.slice(44, 60)
	var body := raw.slice(VNB_HEADER_SIZE)
	if flags & VNB_FLAG_ENCRYPTED:
		body = _decrypt(body, iv)
		if body.is_empty():
			_fail(VNBootMessages.G001, "%s: não foi possível decifrar" % rel_path)
			return PackedByteArray()
	var json_bytes := body.decompress(size, FileAccess.COMPRESSION_ZSTD) if size > 0 else PackedByteArray()
	if json_bytes.size() != size or size == 0:
		_fail(VNBootMessages.G001, "%s: corpo não descomprime" % rel_path)
		return PackedByteArray()
	var actual := VNCanonicalJSON.sha256(json_bytes)
	if actual != header_hash:
		_fail(VNBootMessages.G002, "%s: hash diferente do cabeçalho" % rel_path)
		return PackedByteArray()
	var expected := config.expected_hash(rel_path)
	if expected != "" and VNCanonicalJSON.hash_bytes(expected) != actual:
		_fail(VNBootMessages.G002, "%s: hash diferente do build_config" % rel_path)
		return PackedByteArray()
	return json_bytes


func _decrypt(body: PackedByteArray, iv: PackedByteArray) -> PackedByteArray:
	if config.content_key.size() != 32 or body.is_empty() or body.size() % 16 != 0:
		return PackedByteArray()
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_DECRYPT, config.content_key, iv) != OK:
		return PackedByteArray()
	var plain := aes.update(body)
	aes.finish()
	var pad := plain[-1] if not plain.is_empty() else 0
	if pad < 1 or pad > 16 or pad > plain.size():
		return PackedByteArray()
	for i in range(plain.size() - pad, plain.size()):
		if plain[i] != pad:
			return PackedByteArray()
	return plain.slice(0, plain.size() - pad)


func _fail(code: StringName, detail: String) -> bool:
	if error_code == &"":
		error_code = code
		error_detail = detail
	return false
