extends SceneTree
## Testes da caixa de diálogo, da digitação, dos modos automático e pular e do
## histórico (tarefa M2-03; RT §5.2, §8.5, §10.1; DM §9.1).
##
##   godot --headless --path runtime --script res://tests/stage/test_dialog.gd
##
## O Stage real roda contra os dublês dos outros módulos. O tempo é simulado
## chamando [code]_process(delta)[/code] da caixa; a entrada, com eventos de
## teclado entregues a [code]_unhandled_input[/code]. Sai com 1 se algo falhar.

const DEMO := "../docs/specs/examples/demo-project"
const ALICE := "019a7a00-0bb8-7dc0-b468-e39508f1443d"

var _passed := 0
var _failed := 0
var _host: SubViewport = null
var _advanced := 0


func _initialize() -> void:
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	for t in [
		"marcacao_separa_visivel", "marcacao_colchetes_e_invalidas", "linha_do_tempo_pausa_e_speed",
		"reduce_motion_ignora_speed", "velocidade_zero_mostra_tudo", "demo_todas_as_falas_analisam",
		"backlog_registra_e_limita", "backlog_nao_duplica_ao_reexibir", "backlog_restaura_do_save",
		"digita_na_velocidade", "advance_completa_depois_avanca", "pause_atrasa_o_texto",
		"plaquinha_e_cor_da_personagem", "narracao_sem_plaquinha", "automatico_conta_do_fim_da_digitacao",
		"automatico_espera_a_voz", "pular_so_lido", "pular_para_em_nao_lido", "pular_nao_lido_ligado",
		"segurar_vn_skip", "esconder_caixa", "tela_aberta_bloqueia", "entrada_so_teclado",
		"engine_pausado_bloqueia", "atalhos_auto_e_backlog", "clear_esconde_a_caixa",
	]:
		_run(t)
	print("%d/%d testes da caixa de diálogo passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	Input.action_release(&"vn_skip")
	var res: Variant = call("test_" + test)
	var err: String = res if res is String else "o teste não devolveu resultado (erro de script)"
	if _host != null:
		_host.free()
		_host = null
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Montagem ---------------------------------------------------------------

func _read_json(rel: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://").path_join(DEMO).path_join(rel)
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null


func _make(settings := {}) -> VNModules:
	var m := VNFakeModules.create()
	m.stage = VNRuntimeStage.new()
	m.bind_all()
	var project: Dictionary = _read_json("project.json")
	var theme: Dictionary = _read_json("theme.json")
	var bundle := {"assets": {}, "characters": {ALICE: _read_json("characters/alice.json")}, "sets": {}, "project": project, "theme": theme}
	m.stage.load_bundle(bundle)
	var ui := m.ui as FakeUIManager
	ui.settings = {"text_speed": 40.0, "auto_delay": 1.5, "skip_unread": false}
	for k in settings:
		ui.settings[k] = settings[k]
	_host = SubViewport.new()
	_host.size = Vector2i(1920, 1080)
	root.add_child(_host)
	m.stage.attach(_host)
	_advanced = 0
	m.stage.advanced.connect(func(): _advanced += 1)
	return m


func _box(m: VNModules) -> VNDialogBox:
	return (m.stage as VNRuntimeStage).dialog_box()


func _tick(box: VNDialogBox, seconds: float, step := 0.05) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		box._process(step)
		t += step


func _key(code: Key, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


# --- Marcação e linha do tempo (puros) ----------------------------------------

func test_marcacao_separa_visivel() -> String:
	var s := VNTextScript.parse("Olá [b]mundo[/b][pause=0.5] [speed=2]rápido[/speed] [color=#ff0000]fim[/color]")
	if s.plain != "Olá mundo rápido fim":
		return "plain: '%s'" % s.plain
	if s.bbcode != "Olá [b]mundo[/b] rápido [color=#ff0000]fim[/color]":
		return "bbcode: '%s'" % s.bbcode
	if s.pauses.size() != 1 or s.pauses[0].at != 9 or not is_equal_approx(s.pauses[0].seconds, 0.5):
		return "pausas: %s" % [s.pauses]
	if s.speeds.size() != 1 or s.speeds[0].from != 10 or s.speeds[0].to != 16 or s.speeds[0].mult != 2.0:
		return "velocidades: %s" % [s.speeds]
	return ""


func test_marcacao_colchetes_e_invalidas() -> String:
	var s := VNTextScript.parse("a [[b]] [pause=abc]c [speed=0]d[/speed] [nada]e [speed=50]f")
	if s.plain != "a [b] c d e f":
		return "plain: '%s'" % s.plain
	if not s.pauses.is_empty():
		return "pausa inválida deveria ser ignorada: %s" % [s.pauses]
	# [speed=50] sem fechar vale até o fim, limitado a 10
	if s.speeds.size() != 1 or s.speeds[0].mult != VNTextScript.SPEED_MAX or s.speeds[0].to != s.plain.length():
		return "velocidade aberta: %s" % [s.speeds]
	var p := VNTextScript.parse("[pause=99]x")
	if p.pauses[0].seconds != VNTextScript.PAUSE_MAX:
		return "pausa deveria ser limitada a 10 s"
	return ""


func test_linha_do_tempo_pausa_e_speed() -> String:
	var s := VNTextScript.parse("ab[pause=1]cd")
	var tl := s.timeline(10.0)
	var want := [0.1, 0.2, 1.3, 1.4]
	for i in range(4):
		if not is_equal_approx(tl[i], want[i]):
			return "tempo do caractere %d: %f (esperado %f)" % [i, tl[i], want[i]]
	if VNTextScript.visible_at(tl, 0.25, 4) != 2 or VNTextScript.visible_at(tl, 1.0, 4) != 2:
		return "a pausa deveria segurar em 2 caracteres"
	if VNTextScript.visible_at(tl, 1.3, 4) != 3:
		return "em 1,3 s deveriam ter aparecido 3"
	var f := VNTextScript.parse("[speed=2]ab[/speed]cd").timeline(10.0)
	if not is_equal_approx(f[1], 0.1) or not is_equal_approx(f[3], 0.3):
		return "speed=2 dobra a velocidade só no trecho: %s" % [f]
	if not is_equal_approx(VNTextScript.parse("ab[pause=2]").duration(10.0), 2.2):
		return "pausa no fim conta na duração"
	return ""


func test_reduce_motion_ignora_speed() -> String:
	var s := VNTextScript.parse("[speed=2]ab[/speed][pause=1]c")
	var tl := s.timeline(10.0, false)
	if not is_equal_approx(tl[1], 0.2):
		return "com reduce_motion o speed não vale: %s" % [tl]
	if not is_equal_approx(tl[2], 1.3):
		return "[pause] continua valendo: %s" % [tl]
	return ""


func test_velocidade_zero_mostra_tudo() -> String:
	var s := VNTextScript.parse("abc[pause=2]")
	if not s.timeline(0.0).is_empty() or s.duration(0.0) != 0.0:
		return "text_speed 0 mostra a fala inteira de uma vez"
	return ""


func test_demo_todas_as_falas_analisam() -> String:
	var dir := "scenes"
	var count := 0
	for chapter in DirAccess.get_directories_at(ProjectSettings.globalize_path("res://").path_join(DEMO).path_join(dir)):
		for f in DirAccess.get_files_at(ProjectSettings.globalize_path("res://").path_join(DEMO).path_join(dir).path_join(chapter)):
			var scene: Dictionary = _read_json("%s/%s/%s" % [dir, chapter, f])
			var nodes: Variant = scene.get("nodes", [])
			for n in (nodes.values() if nodes is Dictionary else nodes):
				if n.get("type") == "line" and n.get("text") is String:
					var s := VNTextScript.parse(n.text)
					count += 1
					if s.length() == 0 and not String(n.text).is_empty():
						return "fala sem texto visível: %s" % n.text
	return "" if count > 0 else "nenhuma fala da demo encontrada"


# --- Histórico ----------------------------------------------------------------

func test_backlog_registra_e_limita() -> String:
	var b := VNBacklog.new()
	b.limit = 3
	for i in range(5):
		b.record("s/n%d" % i, ALICE if i % 2 == 0 else "", {"global.x": i} if i == 4 else {})
	var snap := b.snapshot()
	if snap.size() != 3 or snap[0].path != "s/n2" or snap[2].path != "s/n4":
		return "limite: %s" % [snap]
	if snap[0].get("speaker") != ALICE or snap[1].has("speaker") or snap[2].vars != {"global.x": 4}:
		return "campos: %s" % [snap]
	if b.last(2).size() != 2 or b.last(2)[0].path != "s/n3":
		return "last(2): %s" % [b.last(2)]
	snap[0]["path"] = "alterado"
	if b.snapshot()[0].path != "s/n2":
		return "snapshot deveria ser cópia"
	return ""


func test_backlog_nao_duplica_ao_reexibir() -> String:
	var b := VNBacklog.new()
	b.record("s/a")
	b.record("s/b")
	b.record("s/b", "", {}, true)   # fala mostrada de novo (stream ou carga)
	b.record("s/a", "", {}, true)   # outra fala: entra
	if b.size() != 3:
		return "esperava 3 entradas, há %d" % b.size()
	return ""


func test_backlog_restaura_do_save() -> String:
	var b := VNBacklog.new()
	b.restore([{"path": "s/a", "speaker": ALICE, "vars": {"global.x": 1}}, {"sem": "path"}, "lixo", {"path": ""}, {"path": "s/b", "speaker": null}])
	var snap := b.snapshot()
	if snap.size() != 2 or snap[1].has("speaker") or snap[0].vars != {"global.x": 1}:
		return "restore: %s" % [snap]
	b.restore(null)
	return "" if b.size() == 0 else "restore(null) deveria esvaziar"


# --- Caixa de diálogo ---------------------------------------------------------

func test_digita_na_velocidade() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "0123456789", "speaker": ALICE})
	if box.visible_characters() != 0 or not box.is_typing():
		return "deveria começar vazia e digitando"
	_tick(box, 0.11, 0.01)
	if box.visible_characters() != 4:
		return "a 40 cps, em 0,11 s deveriam aparecer 4, apareceram %d" % box.visible_characters()
	_tick(box, 0.2)
	if box.is_typing() or box.visible_characters() != 10:
		return "em 0,3 s a fala deveria estar completa (%d)" % box.visible_characters()
	return ""


func test_advance_completa_depois_avanca() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "uma fala bem longa para digitar", "speaker": ALICE})
	_tick(box, 0.1)
	box.advance_input()
	if box.is_typing() or box.visible_characters() != box.full_text().length() or _advanced != 0:
		return "o primeiro vn_advance só completa a fala"
	box.advance_input()
	if _advanced != 1:
		return "o segundo vn_advance avança (%d)" % _advanced
	box.advance_input()
	if _advanced != 1:
		return "sem fala na caixa o avanço não repete"
	return ""


func test_pause_atrasa_o_texto() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "abcd[pause=1]efgh"})
	_tick(box, 0.5)
	if box.visible_characters() != 4:
		return "durante a pausa ficam 4 caracteres (%d)" % box.visible_characters()
	_tick(box, 0.7)
	if box.visible_characters() <= 4:
		return "depois da pausa a digitação segue"
	return ""


func test_plaquinha_e_cor_da_personagem() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "Oi", "speaker": ALICE})
	if not box.plate_visible() or box.name_text() != "Alice":
		return "plaquinha: '%s'" % box.name_text()
	var label := box.get_node("NamePlate/Name") as Label
	if label.get_theme_color(&"font_color") != Color.html("#e05a7a"):
		return "a plaquinha deveria usar a cor da personagem (use_character_color da demo)"
	return ""


func test_narracao_sem_plaquinha() -> String:
	var m := _make()
	m.stage.show_line({"text": "Ventava."})
	return "" if not _box(m).plate_visible() else "narração não tem plaquinha"


func test_automatico_conta_do_fim_da_digitacao() -> String:
	var m := _make({"auto_delay": 1.0})
	var box := _box(m)
	(m.ui as FakeUIManager).auto_mode = true
	m.stage.show_line({"text": "0123456789"})   # 0,25 s para digitar
	_tick(box, 0.9)
	if _advanced != 0:
		return "o atraso conta a partir do fim da digitação, não do começo"
	_tick(box, 0.3)
	if _advanced != 1:
		return "depois de auto_delay a fala avança (%d)" % _advanced
	return ""


func test_automatico_espera_a_voz() -> String:
	var m := _make({"auto_delay": 0.5})
	var box := _box(m)
	(m.ui as FakeUIManager).auto_mode = true
	m.stage.show_line({"text": "oi", "voice": "voz/alice_01"})
	var played := (m.audio as FakeAudioManager).calls.filter(func(c): return c.method == &"play")
	if played.size() != 1 or played[0].args[0] != "voz/alice_01" or played[0].args[1] != VNAudioManager.VOICE:
		return "a voz deveria tocar no canal voice: %s" % [played]
	# O dublê não devolve player; liga um à caixa como o Audio Manager real faria.
	var player := AudioStreamPlayer.new()
	_host.add_child(player)
	box._voice = player
	box._voice_done = false
	player.finished.connect(func(): box._voice_done = true, CONNECT_ONE_SHOT)
	_tick(box, 1.5)
	if _advanced != 0:
		return "com a voz tocando o modo automático espera"
	player.finished.emit()
	_tick(box, 0.4)
	if _advanced != 0:
		return "auto_delay conta a partir do fim da voz"
	_tick(box, 0.3)
	return "" if _advanced == 1 else "acabou a voz: avança depois de auto_delay (%d)" % _advanced


func test_pular_so_lido() -> String:
	var m := _make()
	var box := _box(m)
	(m.ui as FakeUIManager).skip_mode = true
	m.stage.show_line({"text": "uma fala longa que seria digitada devagar", "seen": true})
	_tick(box, 0.1)
	if _advanced != 1 or box.is_typing():
		return "pular avança a fala lida sem esperar a digitação (%d)" % _advanced
	return ""


func test_pular_para_em_nao_lido() -> String:
	var m := _make()
	var box := _box(m)
	var ui := m.ui as FakeUIManager
	ui.skip_mode = true
	m.stage.show_line({"text": "texto novo", "seen": false})
	_tick(box, 0.5)
	if _advanced != 0:
		return "pular não passa por texto não lido"
	if ui.skip_mode:
		return "o modo pular deveria desligar no texto não lido"
	return "" if not box.is_typing() and box.visible_characters() == 10 else "a fala segue normal (digita e espera)"


func test_pular_nao_lido_ligado() -> String:
	var m := _make({"skip_unread": true})
	var box := _box(m)
	(m.ui as FakeUIManager).skip_mode = true
	m.stage.show_line({"text": "texto novo", "seen": false})
	_tick(box, 0.1)
	return "" if _advanced == 1 else "com skip_unread ligado pula também o não lido"


func test_segurar_vn_skip() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "fala lida", "seen": true})
	Input.action_press(&"vn_skip")
	_tick(box, 0.1)
	Input.action_release(&"vn_skip")
	if _advanced != 1:
		return "segurar vn_skip pula a fala lida"
	m.stage.show_line({"text": "fala nova", "seen": false})
	Input.action_press(&"vn_skip")
	_tick(box, 0.5)
	Input.action_release(&"vn_skip")
	return "" if _advanced == 1 else "segurar vn_skip para no texto não lido"


func test_esconder_caixa() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "oi"})
	box._unhandled_input(_key(KEY_H))
	if not (m.stage as VNRuntimeStage).is_textbox_hidden():
		return "H esconde a caixa"
	box.advance_input()
	if (m.stage as VNRuntimeStage).is_textbox_hidden() or _advanced != 0:
		return "com a caixa escondida, vn_advance só a mostra"
	(m.ui as FakeUIManager).auto_mode = true
	m.stage.set_textbox_hidden(true)
	_tick(box, 5.0)
	return "" if _advanced == 0 else "o modo automático não avança com a caixa escondida"


func test_tela_aberta_bloqueia() -> String:
	var m := _make()
	var box := _box(m)
	var ui := m.ui as FakeUIManager
	m.stage.show_line({"text": "oi", "seen": true})
	ui.open_screen("pause")
	box._unhandled_input(_key(KEY_ENTER))
	ui.skip_mode = true
	ui.auto_mode = true
	_tick(box, 2.0)
	if _advanced != 0 or not box.is_typing() and box.visible_characters() == 0:
		return "com uma tela aberta nada avança (%d)" % _advanced
	ui.close_screen()
	_tick(box, 0.2)
	return "" if _advanced == 1 else "fechada a tela, volta a andar (%d)" % _advanced


func test_entrada_so_teclado() -> String:
	var m := _make()
	var box := _box(m)
	for action in [&"vn_advance", &"vn_skip", &"vn_auto", &"vn_hide", &"vn_backlog"]:
		var has_key := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				has_key = true
		if not has_key:
			return "%s não tem tecla" % action
	m.stage.show_line({"text": "uma fala"})
	box._unhandled_input(_key(KEY_SPACE))    # completa
	box._unhandled_input(_key(KEY_ENTER))    # avança
	return "" if _advanced == 1 else "Espaço e Enter avançam (%d)" % _advanced


func test_engine_pausado_bloqueia() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "oi"})
	(m.engine as FakeNarrativeEngine).paused = true
	box._unhandled_input(_key(KEY_ENTER))
	return "" if box.is_typing() and _advanced == 0 else "pausado, a entrada não age"


func test_atalhos_auto_e_backlog() -> String:
	var m := _make()
	var box := _box(m)
	var ui := m.ui as FakeUIManager
	m.stage.show_line({"text": "oi"})
	box._unhandled_input(_key(KEY_A))
	if not ui.auto_mode:
		return "A liga o modo automático"
	box._unhandled_input(_key(KEY_L))
	if ui.screen_stack() != PackedStringArray(["backlog"]):
		return "L abre o backlog: %s" % [ui.screen_stack()]
	return ""


func test_clear_esconde_a_caixa() -> String:
	var m := _make()
	var box := _box(m)
	m.stage.show_line({"text": "oi"})
	if not box.visible:
		return "a caixa aparece com a fala"
	m.stage.clear_interaction()
	if box.visible or box.is_waiting():
		return "clear_interaction esconde a caixa e esquece a fala"
	return ""
