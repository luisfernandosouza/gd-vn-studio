extends SceneTree
## Testes do boot (tarefa M2-01; RT §2, §2.1, §3.0; BS §5.1, §5.2, §8.2, §13.1).
##
##   python3 runtime/tests/fixtures/generate.py
##   godot --headless --path runtime --import
##   godot --headless --path runtime --script res://tests/boot/test_boot.gd
##
## numbers.json: pares (double em hex little-endian, texto esperado) gerados com
## docs/specs/tools/conformance.py → js_number_to_string, para doubles aleatórios e casos de borda.
##
## Usa os bundles das fixtures (M0-08) e os dublês do M0-07. Os bundles
## corrompidos e os .vnb são montados em user://vn_boot_tests/. Sai com 1 se
## algo falhar.

const FIXTURES := "res://tests/fixtures/bundles/"
const WORK := "user://vn_boot_tests/"
const CANONICAL := "res://../docs/specs/conformance/canonical.json"
const NUMBERS := "res://tests/boot/numbers.json"

## Vetores de canonical.json cujo texto de entrada o leitor de JSON do Godot
## não lê exatamente (dígitos além de 17, frações com muitos zeros): a
## formatação desses números é conferida por numbers.json, com os doubles exatos.
const GODOT_PARSE_LIMITED := ["numbers_rfc8785"]

var _passed := 0
var _failed := 0


class RejectingSaves extends FakeSaveManager:
	func load_profile() -> VNResult:
		super.load_profile()
		return VNResult.failure(&"REJECTED", "perfil recusado")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(WORK)
	for t in [
		"jcs_vetores_canonical", "jcs_numeros_exatos", "jcs_hmac",
		"fixtures_carregam_e_conferem", "boot_chega_ao_titulo", "ordem_dos_passos",
		"idioma_escolhido", "idioma_do_jogador_e_sem_arquivo", "sys_ui",
		"pergunta_da_primeira_abertura", "edicao_censurada_nao_pergunta",
		"modo_stream_repassado", "perfil_recusado_mostra_g006", "vn_bundle_assets_base",
		"bundle_ausente_g001", "json_invalido_g001", "conteudo_alterado_g002",
		"format_version_nao_suportado_g001", "asset_fora_de_res_g001",
		"plugins_ausente_g001", "boot_fatal_nao_abre_titulo",
		"vnb_sem_cifra", "vnb_cifrado", "vnb_hash_do_build_config_g002",
		"vnb_cabecalho_alterado_g002", "vnb_versao_desconhecida_g001",
		"vnb_sem_chave_g001", "vnb_content_hash_do_build_g002", "vnb_idioma_alterado_g002",
	]:
		_run(t)
	print("%d/%d testes do boot passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	var err: String = call("test_" + test)
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Auxiliares ---------------------------------------------------------------

func _modules(settings: Dictionary = {}) -> VNModules:
	var m := VNFakeModules.create()
	if not settings.is_empty():
		m.storage.write_json("settings.json", settings)
	return m


func _boot(fixture: String, m: VNModules = null) -> VNBoot:
	if m == null:
		m = _modules()
	var b := VNBoot.new(m, VNBundleLoader.new(FIXTURES + fixture + "/", VNBuildConfig.development()))
	b.apply_display = false
	b.run()
	return b


func _sys(b: VNBoot, id: String) -> Variant:
	var last: Variant = null
	for c in b.modules.state.calls:
		if c.method == &"set_system_value" and c.args[0] == id:
			last = c.args[1]
	return last


## Copia um bundle das fixtures (só os JSON) para WORK/<nome>/ e devolve a pasta.
func _copy_fixture(fixture: String, name: String) -> String:
	var src := FIXTURES + fixture + "/"
	var dst := WORK + name + "/"
	_rm_tree(dst)
	DirAccess.make_dir_recursive_absolute(dst + "locales")
	for f in ["bundle.json", "plugins.json", "licenses.json"]:
		_write(dst + f, FileAccess.get_file_as_bytes(src + f))
	for f in DirAccess.get_files_at(src + "locales"):
		_write(dst + "locales/" + f, FileAccess.get_file_as_bytes(src + "locales/" + f))
	return dst


func _rm_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm_tree(dir + sub + "/")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)


func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## Regrava bundle.json com uma mudança e o content_hash recalculado.
func _rewrite_bundle(dir: String, change: Callable) -> void:
	var b: Dictionary = JSON.parse_string(_text(dir + "bundle.json"))
	change.call(b)
	b["content_hash"] = VNCanonicalJSON.content_hash(b)
	_write(dir + "bundle.json", VNCanonicalJSON.stringify(b).to_utf8_buffer())


func _load(dir: String, config: VNBuildConfig = null) -> VNBundleLoader:
	var l := VNBundleLoader.new(dir, config if config != null else VNBuildConfig.development())
	l.load_all()
	return l


func _expect_code(l: VNBundleLoader, code: StringName) -> String:
	if l.error_code != code:
		return "esperava %s, veio '%s' (%s)" % [code, l.error_code, l.error_detail]
	return ""


## .vnb (BS §5.2) do texto JSON, cifrado se [param key] tiver 32 bytes.
static func encode_vnb(json_bytes: PackedByteArray, key: PackedByteArray = PackedByteArray(), version: int = 1) -> PackedByteArray:
	var body := json_bytes.compress(FileAccess.COMPRESSION_ZSTD)
	var iv := PackedByteArray()
	iv.resize(16)
	iv.fill(0)
	var flags := 0
	if key.size() == 32:
		flags = 1
		iv = Crypto.new().generate_random_bytes(16)
		var pad := 16 - body.size() % 16
		for i in pad:
			body.append(pad)
		var aes := AESContext.new()
		aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
		body = aes.update(body)
		aes.finish()
	var out := "VNB1".to_ascii_buffer()
	out.resize(60)
	out.encode_u16(4, version)
	out.encode_u16(6, flags)
	var h := VNCanonicalJSON.sha256(json_bytes)
	for i in 32:
		out[8 + i] = h[i]
	out.encode_u32(40, json_bytes.size())
	for i in 16:
		out[44 + i] = iv[i]
	out.append_array(body)
	return out


## Monta WORK/<nome>/ na forma .vnb a partir de uma fixture. Devolve os hashes
## de cada arquivo (para o CONTENT_HASHES).
func _make_vnb(fixture: String, name: String, key: PackedByteArray = PackedByteArray()) -> Dictionary:
	var src := FIXTURES + fixture + "/"
	var dst := WORK + name + "/"
	_rm_tree(dst)
	DirAccess.make_dir_recursive_absolute(dst + "locales")
	var hashes := {}
	var pairs := {"bundle.json": "narrative.vnb", "plugins.json": "plugins.vnb", "licenses.json": "licenses.vnb"}
	for f in DirAccess.get_files_at(src + "locales"):
		pairs["locales/" + f] = "locales/" + f.get_basename() + ".vnb"
	for json_name in pairs:
		var data := FileAccess.get_file_as_bytes(src + json_name)
		_write(dst + pairs[json_name], encode_vnb(data, key))
		hashes[pairs[json_name]] = VNCanonicalJSON.sri(data)
	return hashes


# --- JCS ----------------------------------------------------------------------

func test_jcs_vetores_canonical() -> String:
	var d: Dictionary = JSON.parse_string(_text(CANONICAL))
	for c in d.cases:
		if c.kind != "canonical" or GODOT_PARSE_LIMITED.has(c.id):
			continue
		var v: Variant = JSON.parse_string(c.json)
		var t := VNCanonicalJSON.stringify(v)
		if t != c.expect.text:
			return "%s: %s ≠ %s" % [c.id, t, c.expect.text]
		if VNCanonicalJSON.hash_of(v) != c.expect.hash:
			return "%s: hash" % c.id
	# O texto esperado do vetor de números volta igual (está na forma mais curta).
	for c in d.cases:
		if GODOT_PARSE_LIMITED.has(c.id):
			var again := VNCanonicalJSON.stringify(JSON.parse_string(c.expect.text))
			if again != c.expect.text:
				return "%s: o texto canônico não é estável: %s" % [c.id, again]
	return ""


func test_jcs_numeros_exatos() -> String:
	var d: Array = JSON.parse_string(_text(NUMBERS))
	for pair in d:
		var x: float = String(pair[0]).hex_decode().decode_double(0)
		var s := VNCanonicalJSON.number_to_string(x)
		if s != pair[1]:
			return "double %s: %s ≠ %s" % [pair[0], s, pair[1]]
	if VNCanonicalJSON.number_to_string(-0.0) != "0" or VNCanonicalJSON.stringify(7) != "7":
		return "-0 ou int"
	return ""


func test_jcs_hmac() -> String:
	var d: Dictionary = JSON.parse_string(_text(CANONICAL))
	for c in d.cases:
		if c.kind != "hmac":
			continue
		var got := VNCanonicalJSON.hmac_integrity(JSON.parse_string(c.json), String(c.key).hex_decode())
		if got != c.expect.integrity:
			return "%s: %s" % [c.id, got]
	return ""


# --- Fixtures e boot com dublês -----------------------------------------------

func test_fixtures_carregam_e_conferem() -> String:
	var index: Variant = JSON.parse_string(_text(FIXTURES + "index.json"))
	if not index is Dictionary:
		return "rode python3 runtime/tests/fixtures/generate.py antes"
	var names := DirAccess.get_directories_at(FIXTURES)
	if names.size() < 7:
		return "fixtures incompletas: %s" % names
	for n in names:
		var l := _load(FIXTURES + n + "/")
		if l.error_code != &"":
			return "%s: %s (%s)" % [n, l.error_code, l.error_detail]
		if l.form != VNBundleLoader.FORM_JSON or l.plugins.is_empty():
			return "%s: forma %s" % [n, l.form]
		# O caminho pelos valores (texto não canônico) dá o mesmo hash.
		if VNCanonicalJSON.content_hash(l.bundle) != l.bundle.content_hash:
			return "%s: content_hash pelos valores difere" % n
	return ""


func test_boot_chega_ao_titulo() -> String:
	var b := _boot("dialogue")
	var m := b.modules
	if b.fatal_code != &"":
		return "falhou: %s %s" % [b.fatal_code, b.fatal_detail]
	if m.ui.screen_stack() != PackedStringArray(["title"]):
		return "pilha %s" % m.ui.screen_stack()
	if m.engine.phase() != VNPhase.TITLE:
		return "fase %s" % m.engine.phase()
	if m.plugins.count_calls(&"load_plugins") != 1 or m.ui.count_calls(&"load_settings") != 1:
		return "plugins ou settings não carregados"
	if m.ui.messages.size() != 0:
		return "mensagem inesperada %s" % m.ui.messages
	return ""


func test_ordem_dos_passos() -> String:
	var b := _boot("activity")
	if b.steps_done != PackedInt32Array([1, 2, 3, 4, 5, 6]):
		return "passos %s" % b.steps_done
	# Nenhum evento antes do passo 6 (RT §3.0): o boot não emite nada.
	if b.modules.events.count_calls(&"emit") != 0:
		return "o boot emitiu eventos"
	if b.modules.plugins.loaded_plugins() != PackedStringArray(b.loader.plugins.plugins.keys()) or b.loader.plugins.plugins.is_empty():
		return "plugins %s" % b.modules.plugins.loaded_plugins()
	return ""


func test_idioma_escolhido() -> String:
	var proj := {"locales": ["en", "pt-BR"], "default_locale": "en"}
	var cases := [
		[null, "pt_BR", "pt-BR"], [null, "pt_PT", "pt-BR"], [null, "ja_JP", "en"],
		["en", "pt_BR", "en"], ["fr", "de_DE", "en"], [null, "en_US", "en"],
	]
	for c in cases:
		var got := VNBoot.choose_locale(c[0], c[1], proj)
		if got != c[2]:
			return "%s/%s → %s (esperava %s)" % [c[0], c[1], got, c[2]]
	return ""


func test_idioma_do_jogador_e_sem_arquivo() -> String:
	var b := _boot("dialogue", _modules({"locale": "pt-BR"}))
	if b.locale != "pt-BR" or _sys(b, "sys.locale") != "pt-BR" or b.strings.is_empty():
		return "pt-BR: %s %s" % [b.locale, _sys(b, "sys.locale")]
	# Idioma do projeto sem arquivo: usa default_locale.
	var dir := _copy_fixture("dialogue", "sem_idioma")
	DirAccess.remove_absolute(dir + "locales/pt-BR.json")
	var m := _modules({"locale": "pt-BR"})
	var b2 := VNBoot.new(m, VNBundleLoader.new(dir, VNBuildConfig.development()))
	b2.apply_display = false
	b2.run()
	if b2.fatal_code != &"" or b2.locale != b2.project().default_locale:
		return "sem arquivo: %s %s" % [b2.locale, b2.fatal_code]
	return ""


func test_sys_ui() -> String:
	var b := _boot("gallery")
	var expect := {
		"sys.ui.has_gallery": true, "sys.ui.gallery_endings": true, "sys.ui.in_game": false,
		"sys.ui.has_save": false, "sys.ui.platform": VNBoot.platform_name(),
		"sys.ui.content_filter": false, "sys.ui.last_record_rank": 0,
	}
	for id in expect:
		if _sys(b, id) != expect[id]:
			return "%s = %s" % [id, _sys(b, id)]
	var d := _boot("dialogue")
	if _sys(d, "sys.ui.has_gallery") != false:
		return "dialogue não tem galeria"
	var s := _boot("stream")
	if _sys(s, "sys.ui.content_filter_available") != true:
		return "stream deveria ter content_filter_available"
	if _sys(d, "sys.ui.content_filter_available") != false and not VNBoot.has_marked_content(d.loader.bundle):
		return "dialogue: content_filter_available"
	return ""


func test_pergunta_da_primeira_abertura() -> String:
	var m := _modules()
	m.ui.confirm_answer = false
	var b := _boot("stream", m)
	if not b.asked_content_filter or m.ui.count_calls(&"confirm") != 1:
		return "não perguntou"
	if m.ui.calls.filter(func(c): return c.method == &"confirm")[0].args[0] != VNBoot.ASK_TEXT:
		return "texto da pergunta"
	# A resposta é gravada mesmo igual ao padrão (false).
	var saved: Variant = m.storage.read_json("settings.json")
	if not (saved is Dictionary and saved.get("content_filter") == false):
		return "settings.json %s" % saved
	if m.ui.screen_stack() != PackedStringArray(["title"]):
		return "título depois da pergunta: %s" % m.ui.screen_stack()
	# Na segunda abertura, com o campo gravado, não pergunta.
	var m2 := _modules(saved)
	var b2 := _boot("stream", m2)
	if b2.asked_content_filter or m2.ui.count_calls(&"confirm") != 0:
		return "perguntou de novo"
	return ""


func test_edicao_censurada_nao_pergunta() -> String:
	var b := _boot("stream_censored")
	if b.asked_content_filter:
		return "perguntou na edição censurada"
	if not b.content_filter_enabled() or not b.modules.stage.content_filter:
		return "modo stream deveria estar ligado"
	if _sys(b, "sys.ui.content_filter_available") != false:
		return "content_filter_available na edição censurada"
	return ""


func test_modo_stream_repassado() -> String:
	var m := _modules({"content_filter": false})
	var b := _boot("stream", m)
	m.ui.set_setting(&"content_filter", true)
	if not (m.stage.content_filter and m.audio.content_filter and m.assets.content_filter):
		return "não repassou ao Stage/Audio/VNAssets"
	if _sys(b, "sys.ui.content_filter") != true:
		return "sys.ui.content_filter"
	m.ui.set_setting(&"volume.music", 0.25)
	if not is_equal_approx(m.audio.get_channel_volume(VNAudioManager.MUSIC), 0.25):
		return "volume não repassado"
	return ""


func test_perfil_recusado_mostra_g006() -> String:
	var m := _modules()
	m.saves = RejectingSaves.new()
	m.bind_all()
	var b := _boot("dialogue", m)
	if not b.profile_rejected or m.ui.messages != PackedStringArray(["runtime/message/g006"]):
		return "mensagens %s" % m.ui.messages
	if m.ui.screen_stack() != PackedStringArray(["title"]):
		return "título"
	return ""


func test_vn_bundle_assets_base() -> String:
	var b := _boot("set")
	if b.modules.assets.assets_base != FIXTURES + "set/assets/":
		return "assets_base %s" % b.modules.assets.assets_base
	return ""


# --- Bundle corrompido ------------------------------------------------------------

func test_bundle_ausente_g001() -> String:
	return _expect_code(_load(WORK + "nao_existe/"), VNBootMessages.G001)


func test_json_invalido_g001() -> String:
	var dir := _copy_fixture("dialogue", "json_invalido")
	_write(dir + "bundle.json", (_text(dir + "bundle.json").substr(0, 500)).to_utf8_buffer())
	return _expect_code(_load(dir), VNBootMessages.G001)


func test_conteudo_alterado_g002() -> String:
	var dir := _copy_fixture("dialogue", "alterado")
	var t := _text(dir + "bundle.json")
	if not t.contains("\"start_chapter\":\""):
		return "fixture sem start_chapter"
	_write(dir + "bundle.json", t.replace("\"format_version\":\"1.0.0\"", "\"format_version\":\"1.0.1\"").to_utf8_buffer())
	var err := _expect_code(_load(dir), VNBootMessages.G002)
	if err != "":
		return err
	# Também com o texto fora da forma canônica (espaços): confere pelos valores.
	var dir2 := _copy_fixture("dialogue", "alterado_espacos")
	var b: Dictionary = JSON.parse_string(_text(dir2 + "bundle.json"))
	var ok_text := JSON.stringify(b, "  ")
	_write(dir2 + "bundle.json", ok_text.to_utf8_buffer())
	err = _expect_code(_load(dir2), &"")
	if err != "":
		return "texto com espaços e conteúdo igual deveria passar: " + err
	b.project.title = "Outro"
	_write(dir2 + "bundle.json", JSON.stringify(b, "  ").to_utf8_buffer())
	return _expect_code(_load(dir2), VNBootMessages.G002)


func test_format_version_nao_suportado_g001() -> String:
	var dir := _copy_fixture("dialogue", "format_2")
	_rewrite_bundle(dir, func(b): b.format_version = "2.0.0")
	return _expect_code(_load(dir), VNBootMessages.G001)


func test_asset_fora_de_res_g001() -> String:
	var dir := _copy_fixture("dialogue", "asset_fora")
	_rewrite_bundle(dir, func(b):
		var id: String = b.assets.keys()[0]
		b.assets[id].path = "assets/x.png")
	return _expect_code(_load(dir), VNBootMessages.G001)


func test_plugins_ausente_g001() -> String:
	var dir := _copy_fixture("dialogue", "sem_plugins")
	DirAccess.remove_absolute(dir + "plugins.json")
	return _expect_code(_load(dir), VNBootMessages.G001)


func test_boot_fatal_nao_abre_titulo() -> String:
	var dir := _copy_fixture("dialogue", "fatal")
	_write(dir + "bundle.json", _text(dir + "bundle.json").replace("res://", "res:/").to_utf8_buffer())
	var m := _modules()
	var b := VNBoot.new(m, VNBundleLoader.new(dir, VNBuildConfig.development()))
	b.apply_display = false
	var got: Array = []
	b.failed.connect(func(code, _d): got.append(code))
	if b.run():
		return "run() deveria devolver false"
	if got != [VNBootMessages.G002] or b.fatal_code != VNBootMessages.G002:
		return "sinal %s" % [got]
	if not m.ui.screen_stack().is_empty() or m.plugins.count_calls(&"load_plugins") != 0:
		return "seguiu depois do erro fatal"
	if VNBootMessages.fatal_text(VNBootMessages.G002, "pt_BR") != "Os arquivos do jogo estão corrompidos. Reinstale o jogo.":
		return "texto pt-BR do G002"
	return ""


# --- .vnb -----------------------------------------------------------------------

func _vnb_config(hashes: Dictionary, key: PackedByteArray = PackedByteArray(), content_hash: Variant = null) -> VNBuildConfig:
	return VNBuildConfig.from_constants({
		"BUILD_ID": "teste", "DEBUG_BUILD": false, "CONTENT_HASHES": hashes,
		"CONTENT_KEY": key, "CONTENT_HASH": content_hash if content_hash != null else "",
	})


func _key() -> PackedByteArray:
	var k := PackedByteArray()
	for i in 32:
		k.append(i * 7 % 256)
	return k


func test_vnb_sem_cifra() -> String:
	var hashes := _make_vnb("dialogue", "vnb_plain")
	var l := _load(WORK + "vnb_plain/", _vnb_config(hashes))
	if l.error_code != &"" or l.form != VNBundleLoader.FORM_VNB:
		return "%s %s" % [l.error_code, l.error_detail]
	if l.load_locale("pt-BR") == null or l.licenses.is_empty():
		return "idioma ou licenças"
	return ""


func test_vnb_cifrado() -> String:
	var hashes := _make_vnb("activity", "vnb_aes", _key())
	var bundle: Dictionary = JSON.parse_string(_text(FIXTURES + "activity/bundle.json"))
	var l := _load(WORK + "vnb_aes/", _vnb_config(hashes, _key(), bundle.content_hash))
	if l.error_code != &"":
		return "%s %s" % [l.error_code, l.error_detail]
	if l.bundle.content_hash != bundle.content_hash:
		return "bundle diferente"
	# Boot inteiro com dublês a partir do .vnb.
	var m := _modules()
	var b := VNBoot.new(m, VNBundleLoader.new(WORK + "vnb_aes/", _vnb_config(hashes, _key())))
	b.apply_display = false
	b.run()
	if m.ui.screen_stack() != PackedStringArray(["title"]):
		return "boot do .vnb: %s %s" % [b.fatal_code, b.fatal_detail]
	return ""


func test_vnb_hash_do_build_config_g002() -> String:
	var hashes := _make_vnb("dialogue", "vnb_cfg")
	hashes["plugins.vnb"] = VNCanonicalJSON.sri("outro".to_utf8_buffer())
	return _expect_code(_load(WORK + "vnb_cfg/", _vnb_config(hashes)), VNBootMessages.G002)


func test_vnb_cabecalho_alterado_g002() -> String:
	var hashes := _make_vnb("dialogue", "vnb_hdr")
	var p := WORK + "vnb_hdr/narrative.vnb"
	var raw := FileAccess.get_file_as_bytes(p)
	raw[8] = raw[8] ^ 0xFF
	_write(p, raw)
	return _expect_code(_load(WORK + "vnb_hdr/", _vnb_config({})), VNBootMessages.G002)


func test_vnb_versao_desconhecida_g001() -> String:
	_make_vnb("dialogue", "vnb_v2")
	var p := WORK + "vnb_v2/narrative.vnb"
	var raw := FileAccess.get_file_as_bytes(p)
	raw.encode_u16(4, 2)
	_write(p, raw)
	var err := _expect_code(_load(WORK + "vnb_v2/", _vnb_config({})), VNBootMessages.G001)
	if err != "":
		return err
	# Corpo que não descomprime também é G001.
	_make_vnb("dialogue", "vnb_corpo")
	p = WORK + "vnb_corpo/narrative.vnb"
	raw = FileAccess.get_file_as_bytes(p)
	for i in range(60, mini(raw.size(), 90)):
		raw[i] = 0
	_write(p, raw)
	return _expect_code(_load(WORK + "vnb_corpo/", _vnb_config({})), VNBootMessages.G001)


func test_vnb_sem_chave_g001() -> String:
	_make_vnb("dialogue", "vnb_nokey", _key())
	return _expect_code(_load(WORK + "vnb_nokey/", _vnb_config({})), VNBootMessages.G001)


func test_vnb_content_hash_do_build_g002() -> String:
	var hashes := _make_vnb("dialogue", "vnb_ch")
	return _expect_code(_load(WORK + "vnb_ch/", _vnb_config(hashes, PackedByteArray(), VNCanonicalJSON.sri("x".to_utf8_buffer()))), VNBootMessages.G002)


func test_vnb_idioma_alterado_g002() -> String:
	var hashes := _make_vnb("dialogue", "vnb_loc")
	# Troca o arquivo inteiro do idioma (consistente em si) pelo de outro idioma.
	DirAccess.copy_absolute(WORK + "vnb_loc/locales/pt-BR.vnb", WORK + "vnb_loc/locales/en.vnb")
	var l := VNBundleLoader.new(WORK + "vnb_loc/", _vnb_config(hashes))
	if not l.load_all():
		return "bundle: %s" % l.error_detail
	if l.load_locale("en") != null:
		return "o idioma trocado deveria ser recusado"
	return _expect_code(l, VNBootMessages.G002)
