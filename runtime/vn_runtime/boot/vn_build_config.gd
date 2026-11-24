class_name VNBuildConfig
extends RefCounted
## Constantes do build (Build System §4.4), lidas de
## [code]res://vn_runtime/build_config.gd[/code], que o Build System gera no
## staging. Sem esse arquivo (editor, desenvolvimento com
## [code]compile_bundle.py --godot[/code], testes) valem os padrões de
## desenvolvimento: sem chave de conteúdo, sem hashes a conferir além do
## [code]content_hash[/code] do próprio bundle e a chave fixa de debug para
## saves e perfil (RT §2.1, BS §11.1).
##
## Aceita os hashes como SRI ([code]sha256-…[/code]), hex ou bytes, e as
## chaves como bytes ou base64 (BS §5.1, "Representação de hashes").

const PATH := "res://vn_runtime/build_config.gd"

## Chave fixa de debug: 32 bytes zero (BS §11.1, RT §2.1).
static var DEBUG_SAVE_KEY: PackedByteArray = _zeros(32)

var present: bool = false            ## o build_config.gd existe
var build_id: String = ""
var runtime_version: String = ""
var debug_build: bool = true
var content_hash: String = ""        ## CONTENT_HASH, em SRI; vazio = não confere
var content_hashes: Dictionary = {}  ## caminho do .vnb (relativo a vn_content/) → hash em SRI
var content_key: PackedByteArray = PackedByteArray()
var save_key: PackedByteArray = PackedByteArray()
var save_tamper_policy: StringName = &"flag"


## Lê o build_config.gd do jogo, ou devolve a configuração de desenvolvimento.
static func load_default() -> VNBuildConfig:
	if ResourceLoader.exists(PATH):
		var script: Script = load(PATH)
		if script != null:
			return from_constants(script.get_script_constant_map())
	return development()


## Configuração de desenvolvimento (editor, debug sem build_config.gd).
static func development() -> VNBuildConfig:
	var c := VNBuildConfig.new()
	c.debug_build = OS.is_debug_build()
	c.save_key = DEBUG_SAVE_KEY
	return c


## Monta a partir do mapa de constantes do build_config.gd (ou de um
## dicionário com os mesmos nomes, nos testes).
static func from_constants(map: Dictionary) -> VNBuildConfig:
	var c := VNBuildConfig.new()
	c.present = true
	c.build_id = String(map.get("BUILD_ID", ""))
	c.runtime_version = String(map.get("RUNTIME_VERSION", ""))
	c.debug_build = bool(map.get("DEBUG_BUILD", false))
	c.content_hash = _sri(map.get("CONTENT_HASH", ""))
	var hashes: Variant = map.get("CONTENT_HASHES", {})
	if hashes is Dictionary:
		for k in hashes:
			c.content_hashes[normalize_path(String(k))] = _sri(hashes[k])
	c.content_key = _key(map.get("CONTENT_KEY", PackedByteArray()))
	c.save_key = _key(map.get("SAVE_KEY", PackedByteArray()))
	if c.save_key.is_empty() or c.debug_build:
		c.save_key = DEBUG_SAVE_KEY
	c.save_tamper_policy = StringName(String(map.get("SAVE_TAMPER_POLICY", "flag")))
	if c.debug_build:
		c.save_tamper_policy = &"flag"   # BS §11.1: debug força flag
	return c


## Hash esperado do arquivo ([code]narrative.vnb[/code], [code]locales/en.vnb[/code]…),
## ou vazio se o build não declara.
func expected_hash(rel_path: String) -> String:
	return content_hashes.get(normalize_path(rel_path), "")


## Caminho relativo a [code]vn_content/[/code]: aceita também o caminho
## [code]res://vn_content/…[/code] completo.
static func normalize_path(p: String) -> String:
	for prefix in ["res://vn_content/", "vn_content/"]:
		if p.begins_with(prefix):
			return p.substr(prefix.length())
	return p


static func _sri(v: Variant) -> String:
	var raw := VNCanonicalJSON.hash_bytes(v)
	return "" if raw.is_empty() else "sha256-" + Marshalls.raw_to_base64(raw)


static func _key(v: Variant) -> PackedByteArray:
	if v is PackedByteArray:
		return v
	if v is String and not String(v).is_empty():
		return Marshalls.base64_to_raw(v)
	return PackedByteArray()


static func _zeros(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(0)
	return b
