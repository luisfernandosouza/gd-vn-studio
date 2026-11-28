extends SceneTree
## Ida e volta do .vnb entre o compilador TypeScript e o runtime (tarefa M5-03; BS §5.2, §8.2).
##
##   node cli/scripts/vnb_roundtrip.mjs prepare <pasta>
##   godot --headless --path runtime --script res://tests/boot/test_vnb_roundtrip.gd -- --vnb-dir <pasta>
##   node cli/scripts/vnb_roundtrip.mjs check <pasta>
##
## 1. Lê <pasta>/release/ (cifrado) e <pasta>/debug/ (sem cifra), gravados pelo TypeScript, com o
##    VNBundleLoader e o build_config do release, e confere que o JSON decodificado é o de <pasta>/json/.
## 2. Grava em <pasta>/godot/ os .vnb do JSON de <pasta>/json/ com a mesma chave (o passo `check` do
##    TypeScript lê esses arquivos).
## 3. Mede decifrar e descomprimir o maior .vnb (BS §15, item 4). No Web a medição é manual; aqui
##    fica o número do Godot nativo.
## Sai com 1 se algo falhar.

var _dir := ""
var _failures: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--vnb-dir")
	if i < 0 or i + 1 >= args.size():
		push_error("uso: -- --vnb-dir <pasta>")
		quit(2)
		return
	_dir = args[i + 1].trim_suffix("/") + "/"
	var cfg_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_dir + "build_config.json"))
	var config := VNBuildConfig.from_constants(cfg_json)
	if config.content_key.size() != 32:
		_fail("CONTENT_KEY não tem 32 bytes")
	_read_all("release/", config, true)
	_read_all("debug/", config, false)
	_write_all(config)
	_measure(config)
	for f in _failures:
		print("FALHOU  ", f)
	print("ida e volta .vnb: %s" % ("ok" if _failures.is_empty() else "%d falhas" % _failures.size()))
	quit(1 if not _failures.is_empty() else 0)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _json_files() -> Dictionary:
	var out := {}
	out["bundle.json"] = "narrative.vnb"
	out["plugins.json"] = "plugins.vnb"
	out["licenses.json"] = "licenses.vnb"
	for f in DirAccess.get_files_at(_dir + "json/locales"):
		out["locales/" + f] = "locales/" + f.get_basename() + ".vnb"
	return out


func _read_all(sub: String, config: VNBuildConfig, encrypted: bool) -> void:
	var loader := VNBundleLoader.new(_dir + sub, config)
	loader.allow_json = false
	if not loader.load_all():
		_fail("%s: %s %s" % [sub, loader.error_code, loader.error_detail])
		return
	for json_name in _json_files():
		var rel: String = _json_files()[json_name]
		var raw := FileAccess.get_file_as_bytes(_dir + sub + rel)
		var flags := raw.decode_u16(6)
		if bool(flags & 1) != encrypted:
			_fail("%s%s: flag de cifra %d" % [sub, rel, flags])
		var json := loader.decode_vnb(raw, rel)
		if json.is_empty():
			_fail("%s%s: %s %s" % [sub, rel, loader.error_code, loader.error_detail])
			continue
		if json != FileAccess.get_file_as_bytes(_dir + "json/" + json_name):
			_fail("%s%s: JSON diferente do compilado" % [sub, rel])
	for lang in DirAccess.get_files_at(_dir + "json/locales"):
		var l := lang.get_basename()
		if loader.load_locale(l) == null:
			_fail("%s: idioma %s não carregou" % [sub, l])
	print("TS → Godot ok: ", sub)


func _write_all(config: VNBuildConfig) -> void:
	DirAccess.make_dir_recursive_absolute(_dir + "godot/locales")
	var files := _json_files()
	for json_name in files:
		var json := FileAccess.get_file_as_bytes(_dir + "json/" + json_name)
		var f := FileAccess.open(_dir + "godot/" + files[json_name], FileAccess.WRITE)
		f.store_buffer(_encode(json, config.content_key))
		f.close()


## .vnb cifrado (BS §5.2): Zstandard, padding PKCS#7, AES-256-CBC com IV aleatório.
func _encode(json: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	var body := json.compress(FileAccess.COMPRESSION_ZSTD)
	var iv := Crypto.new().generate_random_bytes(16)
	var pad := 16 - body.size() % 16
	for i in pad:
		body.append(pad)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	body = aes.update(body)
	aes.finish()
	var out := "VNB1".to_ascii_buffer()
	out.resize(60)
	out.encode_u16(4, 1)
	out.encode_u16(6, 1)
	var h := VNCanonicalJSON.sha256(json)
	for i in 32:
		out[8 + i] = h[i]
	out.encode_u32(40, json.size())
	for i in 16:
		out[44 + i] = iv[i]
	out.append_array(body)
	return out


func _measure(config: VNBuildConfig) -> void:
	var biggest := ""
	var size := 0
	for rel in _json_files().values():
		var n := FileAccess.get_file_as_bytes(_dir + "release/" + rel).size()
		if n > size:
			size = n
			biggest = rel
	var loader := VNBundleLoader.new(_dir + "release/", config)
	var raw := FileAccess.get_file_as_bytes(_dir + "release/" + biggest)
	var t0 := Time.get_ticks_usec()
	var json := loader.decode_vnb(raw, biggest)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("medição: %s, %d bytes cifrados → %d bytes de JSON em %.2f ms (decifrar + descomprimir + SHA-256)" % [biggest, size, json.size(), ms])

	# Arquivo de ~10 MB (BS §15 item 4), se o TypeScript o gerou.
	if FileAccess.file_exists(_dir + "big.vnb"):
		var big := FileAccess.get_file_as_bytes(_dir + "big.vnb")
		var best := 1e12
		for i in 5:
			var t := Time.get_ticks_usec()
			var j := loader.decode_vnb(big, "big.vnb")
			best = minf(best, (Time.get_ticks_usec() - t) / 1000.0)
			if j.is_empty():
				_fail("big.vnb: %s %s" % [loader.error_code, loader.error_detail])
				return
		print("medição: big.vnb, %d bytes cifrados → %d bytes de JSON em %.1f ms (melhor de 5)" % [big.size(), j_size(loader, big), best])


func j_size(loader: VNBundleLoader, big: PackedByteArray) -> int:
	return loader.decode_vnb(big, "big.vnb").size()
