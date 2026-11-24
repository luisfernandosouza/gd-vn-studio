extends SceneTree
## Testes do Save Manager e do VNStorage (tarefa M2-10; RT §8, BS §8.3).
##
##   godot --headless --path runtime --script res://tests/save_manager/test_save_manager.gd
##
## Usa o Save Manager real com os dublês dos outros módulos. Lê
## docs/specs/examples/demo-save.json e docs/specs/conformance/canonical.json
## pelo caminho relativo ao projeto. Sai com 1 se algo falhar.

const SPECS := "res://../docs/specs/"
const DEMO_PROJECT := "seaside_story"
const CHAPTER := "019a7a00-03e8-7e8e-9f34-b5a38f4a780b"
const SCENE := "019a7a00-1388-7f6b-b667-94bbd1305982"
const NODE := "019a7a00-3a98-732b-89dd-170487226b34"

var _passed := 0
var _failed := 0


func _init() -> void:
	for t in [
		"jcs_vetores_canonical", "jcs_numeros_e_estabilidade",
		"storage_memoria", "storage_user", "storage_pasta_janela", "storage_pasta_painel",
		"demo_save_carrega_e_retoma", "save_adulterado_liga_save_modified",
		"save_adulterado_reject", "save_adulterado_ignore", "release_recusa_chave_de_debug",
		"save_de_outro_projeto_ou_formato", "save_e_load_no_no_certo", "save_fora_de_ponto_de_save",
		"autosave_rodizio_e_configuracao", "continuar_e_lista", "apagar_slot",
		"perfil_assinado_e_debounce", "perfil_adulterado", "reset_perfil", "recordes",
	]:
		_run(t)
	print("%d/%d testes do Save Manager passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	# Erro de script faz call() devolver null: conta como falha.
	var res: Variant = call("test_" + test)
	var err: String = res if res is String else "erro de script (veja o log)"
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Montagem -----------------------------------------------------------------

func _bundle(autosave: String = "selection_point") -> Dictionary:
	return {
		"content_hash": "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		"project": {"id": DEMO_PROJECT, "version": "0.1.0", "settings": {"autosave": autosave}},
	}


## Registro com dublês, o Save Manager real e o armazenamento em memória.
func _setup(options: Dictionary = {}, autosave: String = "selection_point") -> VNModules:
	var m := VNFakeModules.create()
	var saves := VNRuntimeSaveManager.new()
	saves.configure(options)
	m.saves = saves
	m.storage = VNMemoryStorage.new()
	m.bind_all()
	saves.load_bundle(_bundle(autosave))
	var vars: FakeVariableManager = m.variables
	vars.define("global.player_money", &"integer", 30)
	vars.define("global.fishing_won", &"boolean", false)
	vars.define("global.fishing_skill", &"integer", 0)
	vars.define("character.alice.affection", &"integer", 0)
	vars.define("character.alice.met", &"boolean", false)
	vars.define("chapter.days_passed", &"integer", 0)
	vars.define("plugin.fishing.total_caught", &"integer", 0)
	vars.define("sys.save_modified", &"boolean", false, &"session", true)
	vars.define("global.ng_plus", &"integer", 0, &"profile")
	return m


func _demo_save_text() -> String:
	return FileAccess.get_file_as_string(SPECS + "examples/demo-save.json")


func _put(m: VNModules, path: String, data: Variant) -> void:
	m.storage.write_text(path, data if data is String else JSON.stringify(data))


func _in_scene(m: VNModules) -> void:
	var e: FakeNarrativeEngine = m.engine
	e.chapter = CHAPTER
	e.goto_node(SCENE, NODE)
	e.set_phase(VNPhase.SCENE_RUNNING)


# --- JSON canônico ------------------------------------------------------------

func test_jcs_vetores_canonical() -> String:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPECS + "conformance/canonical.json"))
	var n := 0
	for c: Dictionary in doc.cases:
		if c.kind == "canonical":
			# O leitor de JSON do Godot erra números de 17+ algarismos e
			# decimais muito longos; o serializador confere sobre o texto esperado.
			var parsed: Variant = JSON.parse_string(c.expect.text)
			if VNCanonicalJson.stringify(parsed) != c.expect.text:
				return "%s: %s" % [c.id, VNCanonicalJson.stringify(parsed)]
			if VNCanonicalJson.hash_sri(parsed) != c.expect.hash:
				return "%s: hash" % c.id
			if c.id != "numbers_rfc8785" and VNCanonicalJson.stringify(JSON.parse_string(c.json)) != c.expect.text:
				return "%s: a partir da entrada" % c.id
		else:
			var key := VNCanonicalJson.debug_key() if not c.has("key") else String(c.key).hex_decode()
			var data: Dictionary = JSON.parse_string(c.json)
			if VNCanonicalJson.signature(data, key) != c.expect.integrity:
				return "%s: %s" % [c.id, VNCanonicalJson.signature(data, key)]
		n += 1
	return "" if n == doc.cases.size() and n >= 7 else "casos: %d" % n


func test_jcs_numeros_e_estabilidade() -> String:
	var cases := [[0.1, "0.1"], [-2.5, "-2.5"], [1e21, "1e+21"], [1e20, "100000000000000000000"], [1e-7, "1e-7"],
		[123.0, "123"], [0.000001, "0.000001"], [-0.0, "0"], [1.7976931348623157e308, "1.7976931348623157e+308"]]
	for c in cases:
		if VNCanonicalJson.number(c[0]) != c[1]:
			return "%s → %s" % [c[1], VNCanonicalJson.number(c[0])]
	if VNCanonicalJson.stringify(42) != "42" or VNCanonicalJson.stringify(&"a\u0001") != "\"a\\u0001\"":
		return "int ou StringName"
	var data := {"x": 333333333.3333333, "y": 0.30000000000000004, "z": [1, 2.5, "ä"]}
	var stable: Variant = VNCanonicalJson.stabilize(data)
	if VNCanonicalJson.stringify(JSON.parse_string(VNCanonicalJson.stringify(stable))) != VNCanonicalJson.stringify(stable):
		return "stabilize não chegou a um ponto fixo"
	return ""


# --- VNStorage ----------------------------------------------------------------

func _storage_contract(s: VNStorage) -> String:
	var written: Array = []
	var deleted: Array = []
	s.file_written.connect(func(p, _d): written.append(p))
	s.file_deleted.connect(func(p): deleted.append(p))
	if s.write_text("../fora.json", "x") != ERR_INVALID_PARAMETER or s.write_text("/abs.json", "x") != ERR_INVALID_PARAMETER:
		return "aceitou caminho inválido"
	if s.write_json("saves/slot_2.json", {"a": 1}) != OK or s.write_text("saves/slot_1.json", "um") != OK:
		return "não gravou"
	if s.write_text("profile.json", "p") != OK:
		return "não gravou na raiz"
	if not s.exists("saves/slot_1.json") or s.read_text("saves/slot_1.json") != "um":
		return "não leu"
	if s.read_json("saves/slot_2.json").get("a") != 1.0:
		return "read_json"
	if s.list("saves") != PackedStringArray(["saves/slot_1.json", "saves/slot_2.json"]):
		return "list: %s" % s.list("saves")
	if not s.list("").has("profile.json") or s.list("").has("saves/slot_1.json"):
		return "list da raiz: %s" % s.list("")
	if s.rename("profile.json", "profile.rejected.json") != OK or s.exists("profile.json") or s.read_text("profile.rejected.json") != "p":
		return "rename"
	if s.delete("saves/slot_1.json") != OK or s.exists("saves/slot_1.json") or s.delete("saves/slot_1.json") != ERR_FILE_NOT_FOUND:
		return "delete"
	if s.read_bytes("nada.json").size() != 0 or s.read_json("nada.json") != null:
		return "arquivo ausente"
	if not written.has("saves/slot_2.json") or not deleted.has("saves/slot_1.json"):
		return "sinais: %s %s" % [written, deleted]
	return ""


func _clean_dir(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for sub in ["saves/", ""]:
		var d := DirAccess.open(abs_dir + sub)
		if d != null:
			for f in d.get_files():
				DirAccess.remove_absolute(abs_dir + sub + f)
	DirAccess.remove_absolute(abs_dir + "saves")
	DirAccess.remove_absolute(abs_dir)


func test_storage_memoria() -> String:
	var s := VNMemoryStorage.new()
	return "kind" if s.kind() != VNStorage.KIND_MEMORY else _storage_contract(s)


func test_storage_user() -> String:
	var s := VNUserStorage.new()
	if s.kind() != VNStorage.KIND_USER or s.root() != "user://":
		return "kind/raiz"
	# O contrato numa subpasta de user:// para não tocar nos dados do projeto.
	var dir := OS.get_user_data_dir().path_join("vn_test_storage") + "/"
	_clean_dir(dir)
	var err := _storage_contract(VNFileStorage.new("user://vn_test_storage", VNStorage.KIND_USER))
	_clean_dir(dir)
	return err


func test_storage_pasta_janela() -> String:
	var dir := OS.get_user_data_dir().path_join("vn_test_folder") + "/"
	_clean_dir(dir)
	var s := VNFolderStorage.new(dir)
	if s.kind() != VNStorage.KIND_FOLDER or s.is_panel_mode():
		return "kind/modo"
	var err := _storage_contract(s)
	if err.is_empty() and not FileAccess.file_exists(dir + "saves/slot_2.json"):
		err = "não gravou na pasta"
	_clean_dir(dir)
	return err


func test_storage_pasta_painel() -> String:
	var s := VNFolderStorage.new()
	if not s.is_panel_mode():
		return "modo"
	s.seed_files({"settings.json": "{}".to_utf8_buffer()})
	if s.read_text("settings.json") != "{}":
		return "seed_files"
	return _storage_contract(s)


# --- Carregamento -------------------------------------------------------------

func test_demo_save_carrega_e_retoma() -> String:
	var m := _setup()
	_put(m, "saves/slot_1.json", _demo_save_text())
	var r := m.saves.load_slot(&"slot_1")
	if not r.ok:
		return "load: %s" % r.message
	var e: FakeNarrativeEngine = m.engine
	if e.count_calls(&"resume_from_save") != 1:
		return "não retomou"
	# O demo-save foi feito num ponto de seleção: retoma no capítulo, sem cena.
	if e.phase() != VNPhase.SELECTION_POINT or e.current_chapter() != CHAPTER or not e.current_scene().is_empty():
		return "retomou em %s/%s/%s" % [e.phase(), e.current_chapter(), e.current_scene()]
	var vars: FakeVariableManager = m.variables
	if vars.read("global.player_money") != 130:
		return "variáveis: %s" % vars.read("global.player_money")
	if vars.read("sys.save_modified") != false:
		return "sys.save_modified ligado num save válido"
	var sch: FakeSceneScheduler = m.scheduler
	if int(sch.get_history().get("selection_count", -1)) != 2:
		return "histórico"
	var plugins: FakePluginHost = m.plugins
	if not plugins.save_data().has("fishing"):
		return "dados do plugin"
	var events: FakeEventBus = m.events
	var names := events.delivered_names()
	if names.find("sys.game_started") < 0 or names.find("sys.game_loaded") < names.find("sys.game_started"):
		return "eventos: %s" % names
	# Ordem do RT §8.3: variáveis → histórico → plugins → eventos → retomada.
	if vars.count_calls(&"reset_game") != 1 or vars.count_calls(&"enter_chapter") != 1:
		return "variáveis não reiniciadas"
	return ""


func _tampered_demo() -> String:
	return _demo_save_text().replace("\"global.player_money\": 130", "\"global.player_money\": 99999")


func test_save_adulterado_liga_save_modified() -> String:
	var m := _setup()
	if _tampered_demo() == _demo_save_text():
		return "não adulterou"
	_put(m, "saves/slot_1.json", _tampered_demo())
	var r := m.saves.load_slot(&"slot_1")
	if not r.ok:
		return "flag deveria carregar"
	if m.variables.read("sys.save_modified") != true:
		return "sys.save_modified desligado"
	# Carregar um save válido depois desliga de novo.
	_put(m, "saves/slot_2.json", _demo_save_text())
	m.saves.load_slot(&"slot_2")
	return "" if m.variables.read("sys.save_modified") == false else "continuou ligado"


func test_save_adulterado_reject() -> String:
	var m := _setup({"save_tamper": "reject", "debug_build": false})
	_put(m, "saves/slot_1.json", _tampered_demo())
	var r := m.saves.load_slot(&"slot_1")
	var ui: FakeUIManager = m.ui
	if r.ok or m.engine.count_calls(&"resume_from_save") != 0:
		return "carregou"
	if not ui.messages.has("runtime/message/g003"):
		return "sem G003: %s" % ui.messages
	# Em build de debug a política vira flag (BS §11.1).
	var d := _setup({"save_tamper": "reject", "debug_build": true})
	_put(d, "saves/slot_1.json", _tampered_demo())
	return "" if d.saves.load_slot(&"slot_1").ok and d.variables.read("sys.save_modified") == true else "debug não virou flag"


func test_save_adulterado_ignore() -> String:
	var m := _setup({"save_tamper": "ignore", "debug_build": false})
	_put(m, "saves/slot_1.json", _tampered_demo())
	var r := m.saves.load_slot(&"slot_1")
	return "" if r.ok and m.variables.read("sys.save_modified") == false else "ignore"


func test_release_recusa_chave_de_debug() -> String:
	var key := PackedByteArray()
	for i in 32:
		key.append(i)
	var m := _setup({"save_key": key, "save_tamper": "flag", "debug_build": false})
	_put(m, "saves/slot_1.json", _demo_save_text())
	if not m.saves.load_slot(&"slot_1").ok or m.variables.read("sys.save_modified") != true:
		return "assinatura de debug aceita no release"
	# Gravado com a chave do release, confere.
	_in_scene(m)
	m.saves.save(&"slot_2")
	m.saves.load_slot(&"slot_2")
	return "" if m.variables.read("sys.save_modified") == false else "save do próprio release marcado"


func test_save_de_outro_projeto_ou_formato() -> String:
	var m := _setup()
	_put(m, "saves/slot_1.json", _demo_save_text().replace("seaside_story", "outro_jogo"))
	_put(m, "saves/slot_2.json", _demo_save_text().replace("\"save_format\": \"1.0.0\"", "\"save_format\": \"2.0.0\""))
	_put(m, "saves/slot_3.json", "{ não é json")
	for slot in [&"slot_1", &"slot_2", &"slot_3"]:
		if m.saves.load_slot(slot).ok:
			return "carregou %s" % slot
	var ui: FakeUIManager = m.ui
	if ui.messages.count("runtime/message/g004") != 3:
		return "G004: %s" % ui.messages
	return "" if not m.saves.load_slot(&"slot_9").ok else "carregou slot vazio"


# --- Gravação -----------------------------------------------------------------

func test_save_e_load_no_no_certo() -> String:
	var m := _setup()
	_in_scene(m)
	m.variables.store("global.player_money", 77)
	var stage: FakeStage = m.stage
	stage.restore({"background": "bg_beach", "characters": [{"id": "alice", "expression": "smile", "position": "left"}]})
	var audio: FakeAudioManager = m.audio
	audio.restore({"music": {"asset": "bgm_sea", "loop": true}})
	var emitted: Array = []
	m.saves.saved.connect(func(slot, auto): emitted.append([slot, auto]))
	var r := m.saves.save(&"slot_1", "Praia")
	if not r.ok:
		return "save: %s" % r.message
	if emitted != [[&"slot_1", false]]:
		return "sinal saved: %s" % emitted
	var data: Dictionary = m.storage.read_json("saves/slot_1.json")
	if not VNCanonicalJson.verify(data, VNCanonicalJson.debug_key()):
		return "assinatura"
	if m.storage.read_text("saves/slot_1.json") != VNCanonicalJson.stringify(data):
		return "arquivo não está em JSON canônico"
	if data.project.id != DEMO_PROJECT or data.project.get("content_hash", "").is_empty() or data.save_format != "1.0.0":
		return "cabeçalho: %s" % data.project
	if data.thumbnail != "saves/slot_1.png":
		return "miniatura: %s" % data.get("thumbnail")
	var png := Image.new()
	if png.load_png_from_buffer(m.storage.read_bytes("saves/slot_1.png")) != OK or png.get_size() != Vector2i(320, 180):
		return "png da miniatura"
	if data.state.scene.node != NODE or data.state.scene.stage.background != "bg_beach" or data.state.scene.stage.audio.music.asset != "bgm_sea":
		return "cena/palco: %s" % data.state.scene
	# Muda tudo e carrega de volta.
	m.engine.return_to_title()
	stage.clear()
	audio.stop_all()
	m.variables.store("global.player_money", 1)
	if not m.saves.load_slot(&"slot_1").ok:
		return "load"
	var e: FakeNarrativeEngine = m.engine
	if e.current_scene() != SCENE or e.current_node() != NODE or e.phase() != VNPhase.SCENE_RUNNING:
		return "retomou em %s/%s" % [e.current_scene(), e.current_node()]
	if stage.background != "bg_beach" or not audio.playing.has(&"music"):
		return "palco não restaurado"
	if m.variables.read("global.player_money") != 77:
		return "variável: %s" % m.variables.read("global.player_money")
	var vars: FakeVariableManager = m.variables
	if vars.count_calls(&"enter_scene") < 1:
		return "scene.* não instanciadas"
	return "" if m.variables.read("sys.save_modified") == false else "save próprio marcado como modificado"


func test_save_fora_de_ponto_de_save() -> String:
	var m := _setup()
	_in_scene(m)
	var e: FakeNarrativeEngine = m.engine
	e.save_allowed = false
	if m.saves.save(&"slot_1").ok or m.storage.exists("saves/slot_1.json"):
		return "salvou fora de ponto de save"
	e.save_allowed = true
	if m.saves.save(&"auto_1").ok or m.saves.save(&"slot_100").ok or m.saves.save(&"slot_01").ok:
		return "aceitou slot inválido"
	return "" if m.saves.save(VNSaveManager.QUICK).ok and m.storage.exists("saves/quick.json") else "quick"


func test_autosave_rodizio_e_configuracao() -> String:
	var m := _setup()
	_in_scene(m)
	var slots: Array = []
	m.saves.saved.connect(func(slot, auto): slots.append([slot, auto]))
	for i in 4:
		if not m.saves.autosave(VNSaveManager.AUTOSAVE_SETTINGS).ok:
			return "autosave %d" % i
		OS.delay_msec(3)
	var got := slots.map(func(s): return s[0])
	if got != [&"auto_1", &"auto_2", &"auto_3", &"auto_1"] or not slots[0][1]:
		return "rodízio: %s" % [slots]
	# Com settings.autosave: off, só o de atividade grava (RT §5.3 passo 3).
	var off := _setup({}, "off")
	_in_scene(off)
	off.saves.autosave(VNSaveManager.AUTOSAVE_SETTINGS)
	off.saves.autosave(VNSaveManager.AUTOSAVE_SCENE_START)
	if off.saves.has_save():
		return "autosave com off"
	if not off.saves.autosave(VNSaveManager.AUTOSAVE_ACTIVITY).ok or not off.storage.exists("saves/auto_1.json"):
		return "autosave de atividade"
	var at_start := _setup({}, "scene_start")
	_in_scene(at_start)
	at_start.saves.autosave(VNSaveManager.AUTOSAVE_SETTINGS)
	if at_start.saves.has_save():
		return "scene_start gravou no ponto de seleção"
	at_start.saves.autosave(VNSaveManager.AUTOSAVE_SCENE_START)
	return "" if at_start.saves.has_save() else "scene_start não gravou"


func test_continuar_e_lista() -> String:
	var m := _setup()
	if m.saves.has_save() or m.saves.latest_slot() != &"":
		return "sem saves"
	_in_scene(m)
	m.saves.save(&"slot_10", "dez")
	OS.delay_msec(5)
	m.saves.save(&"slot_2", "dois")
	OS.delay_msec(5)
	m.saves.autosave(VNSaveManager.AUTOSAVE_SETTINGS)
	if m.saves.latest_slot() != &"auto_1":
		return "latest: %s" % m.saves.latest_slot()
	OS.delay_msec(5)
	m.saves.save(VNSaveManager.QUICK)
	if m.saves.latest_slot() != VNSaveManager.QUICK:
		return "latest depois do quick: %s" % m.saves.latest_slot()
	m.storage.write_text("saves/lixo.json", "{}")
	var list := m.saves.list_slots()
	var order := list.map(func(e): return e.slot)
	if order != [&"quick", &"slot_2", &"slot_10", &"auto_1"]:
		return "ordem: %s" % [order]
	if list[2].label != "dez" or list[2].thumbnail != "saves/slot_10.png" or list[2].thumbnail_sensitive:
		return "resumo: %s" % list[2]
	return ""


func test_apagar_slot() -> String:
	var m := _setup()
	_in_scene(m)
	m.saves.save(&"slot_1")
	if m.saves.delete_slot(&"slot_1") != OK:
		return "delete"
	if m.storage.exists("saves/slot_1.json") or m.storage.exists("saves/slot_1.png"):
		return "sobrou arquivo"
	return "" if m.saves.delete_slot(&"slot_1") == ERR_FILE_NOT_FOUND and not m.saves.has_save() else "apagar de novo"


# --- Perfil -------------------------------------------------------------------

func test_perfil_assinado_e_debounce() -> String:
	var m := _setup()
	var saves: VNRuntimeSaveManager = m.saves
	if not saves.load_profile().ok:
		return "perfil vazio"
	saves.record_ending("festival_ending")
	saves.mark_text_seen("a/b")
	saves.mark_asset_seen("cg_beach")
	saves.mark_asset_seen("cg_beach")
	m.variables.store("global.ng_plus", 2)
	if not saves.is_profile_dirty() or m.storage.exists("profile.json"):
		return "gravou sem debounce"
	# Ponto de seleção grava (RT §8.5).
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.SELECTION_POINT)
	if saves.is_profile_dirty() or not m.storage.exists("profile.json"):
		return "não gravou no ponto de seleção"
	var data: Dictionary = m.storage.read_json("profile.json")
	if not VNCanonicalJson.verify(data, VNCanonicalJson.debug_key()):
		return "assinatura do perfil"
	if data.project_id != DEMO_PROJECT or data.variables.get("global.ng_plus") != 2.0 or data.seen_assets != ["cg_beach"]:
		return "conteúdo: %s" % data
	if data.seen_text[0] != "a/b".sha256_text().left(16):
		return "seen_text"
	# Outro jogo lendo o mesmo perfil.
	var m2 := _setup()
	m2.storage = m.storage
	m2.bind_all()
	if not m2.saves.load_profile().ok:
		return "releitura"
	if not m2.saves.is_text_seen("a/b") or m2.saves.is_text_seen("a/c"):
		return "is_text_seen"
	if m2.variables.read("global.ng_plus") != 2.0:
		return "variáveis profile não aplicadas"
	return "" if m2.variables.read("sys.save_modified") == false else "perfil válido marcado"


func test_perfil_adulterado() -> String:
	var m := _setup()
	m.saves.load_profile()
	m.saves.record_ending("festival_ending")
	m.saves.flush_profile()
	var text := m.storage.read_text("profile.json").replace("festival_ending", "secret_ending")
	m.storage.write_text("profile.json", text)
	var flag := _setup()
	flag.storage = m.storage
	flag.bind_all()
	if not flag.saves.load_profile().ok or flag.variables.read("sys.save_modified") != true:
		return "flag"
	var rej := _setup({"save_tamper": "reject", "debug_build": false})
	rej.storage = m.storage
	rej.bind_all()
	var r := rej.saves.load_profile()
	if r.ok or r.message != "runtime/message/g006":
		return "reject: %s %s" % [r.ok, r.message]
	if m.storage.exists("profile.json") or m.storage.read_text("profile.rejected.json") != text:
		return "não guardou profile.rejected.json"
	if not rej.saves.profile().endings.is_empty():
		return "perfil não começou vazio"
	# Ilegível: o mesmo, sem a mensagem.
	m.storage.write_text("profile.json", "{")
	var bad := _setup()
	bad.storage = m.storage
	bad.bind_all()
	r = bad.saves.load_profile()
	return "" if not r.ok and r.message.is_empty() and m.storage.read_text("profile.rejected.json") == "{" else "ilegível"


func test_reset_perfil() -> String:
	var m := _setup()
	m.saves.load_profile()
	m.saves.record_ending("festival_ending")
	m.variables.store("global.ng_plus", 3)
	m.saves.flush_profile()
	_in_scene(m)
	if m.saves.reset_profile().ok:
		return "aceitou durante a partida (U004)"
	m.engine.return_to_title()
	if not m.saves.reset_profile().ok:
		return "recusou no título"
	if m.storage.exists("profile.json") or not m.saves.profile().endings.is_empty():
		return "perfil não apagado"
	if m.variables.read("global.ng_plus") != 0:
		return "variável profile não voltou ao padrão"
	var events: FakeEventBus = m.events
	events.drain()
	return "" if events.delivered_names().has("sys.profile_reset") else "sem sys.profile_reset"


func test_recordes() -> String:
	var m := _setup()
	var saves: VNRuntimeSaveManager = m.saves
	saves.load_profile()
	saves.set_record_board(&"fishing", &"time", &"asc", 2)
	if saves.submit_record(&"fishing", &"time", 30.0) != 1 or saves.submit_record(&"fishing", &"time", 20.0) != 1:
		return "posições"
	if saves.submit_record(&"fishing", &"time", 30.0) != 0:
		return "empate deveria ficar com a mais antiga"
	if saves.submit_record(&"fishing", &"time", 25.0, {"d": "hard"}) != 2:
		return "inserção no meio"
	var rec := saves.get_records(&"fishing", &"time")
	if rec.size() != 2 or rec[0].score != 20.0 or rec[1].meta.d != "hard":
		return "quadro: %s" % [rec]
	if saves.submit_record(&"fishing", &"catch", 5.0) != 1 or saves.submit_record(&"fishing", &"catch", 9.0) != 1:
		return "desc padrão"
	saves.set_plugin_profile_data(&"fishing", {"rod": 2})
	return "" if saves.get_plugin_profile_data(&"fishing").rod == 2 and saves.is_profile_dirty() else "dados de perfil"
