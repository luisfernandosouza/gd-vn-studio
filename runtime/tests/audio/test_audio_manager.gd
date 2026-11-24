extends SceneTree
## Testes do Audio Manager (tarefa M2-05): canais, volumes das configurações,
## legendas e modo stream, contra os dublês dos outros módulos e as fixtures
## [code]dialogue[/code] e [code]stream[/code] (M0-08).
##
##   python3 runtime/tests/fixtures/generate.py
##   godot --headless --path runtime --import
##   godot --headless --path runtime --script res://tests/audio/test_audio_manager.gd
##
## Sai com 1 se algo falhar.

const FIXTURES := "res://tests/fixtures/bundles/"
const FLOW_VECTORS := "res://../docs/specs/conformance/flow.json"

var _passed := 0
var _failed := 0
var _root: Node


func _initialize() -> void:
	_root = Node.new()
	_root.name = "TestRoot"
	root.add_child(_root)
	# O nó só entra na árvore no primeiro quadro; os players precisam dela.
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	for t in [
		"contrato", "loop_padrao_por_canal", "volumes_das_configuracoes",
		"volume_por_canal_isolado", "fade_cruzado_e_stop", "sfx_avulsos_se_sobrepoem",
		"legendas_com_subtitles", "legenda_traduzida_e_troca_de_idioma",
		"legenda_de_sfx_some_sozinha", "legenda_modo_stream", "modo_stream_troca_o_som",
		"vetores_modo_stream", "snapshot_e_restore", "galeria_marca_musica",
		"play_avulso_e_plugin", "edicao_censurada",
	]:
		_run(t)
	print("%d/%d testes do Audio Manager passaram." % [_passed, _passed + _failed])
	_root.free()
	# Alguns quadros para a árvore e o AudioServer liberarem os players e os
	# playbacks antes de sair (senão o Godot acusa recursos vivos no fim).
	for i in 5:
		await process_frame
	await create_timer(0.2).timeout
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	var err: String = call("test_" + test)
	if err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", err)


# --- Montagem ---------------------------------------------------------------

## Registro com dublês, o Audio Manager real ligado ao bundle da fixture e,
## com [param attached], na árvore.
func _setup(bundle_name: String = "dialogue", attached: bool = true, settings: Dictionary = {}) -> Dictionary:
	var m := VNFakeModules.create()
	var au := VNRuntimeAudioManager.new()
	m.audio = au
	m.bind_all()
	var bundle: Dictionary = _read_json(FIXTURES + bundle_name + "/bundle.json")
	var fa := m.assets as FakeAssets
	fa.load_bundle(bundle)
	for id: String in bundle.assets:
		var a: Dictionary = bundle.assets[id]
		var path := String(a.path).replace("res://vn_content/assets/", FIXTURES + bundle_name + "/assets/")
		if a.type.begins_with("audio") and ResourceLoader.exists(path):
			fa.resources[id] = load(path)
		if a.has("censored"):
			fa.censored[id] = a.censored
	(m.ui as FakeUIManager).settings = settings.duplicate()
	(m.engine as FakeNarrativeEngine).goto_node(_first_scene(bundle), "")
	au.load_bundle(bundle)
	for f in DirAccess.get_files_at(FIXTURES + bundle_name + "/locales"):
		var loc: Dictionary = _read_json(FIXTURES + bundle_name + "/locales/" + f)
		au.set_translations(String(loc.locale), loc.strings)
	if attached:
		au.attach(_root)
	return {"m": m, "au": au, "bundle": bundle}


func _teardown(ctx: Dictionary) -> void:
	(ctx.au as VNRuntimeAudioManager).detach()


func _first_scene(bundle: Dictionary) -> String:
	return String(bundle.scenes.keys()[0])


## O nó [code]audio[/code] da fixture com este asset e ação.
func _audio_node(ctx: Dictionary, asset: String, action: String = "play") -> Dictionary:
	for sid: String in ctx.bundle.scenes:
		for n: Dictionary in ctx.bundle.scenes[sid].nodes:
			if n.type == "audio" and n.action == action and String(n.get("asset", "")) == asset:
				return n
	return {}


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _vol(au: VNRuntimeAudioManager, ch: StringName) -> float:
	var c := au.channel_node(ch)
	var p := c.main_player()
	if p == null and not c.players().is_empty():
		p = c.players()[0]
	return c.effective_volume(p) if p != null else -1.0


# --- Testes -----------------------------------------------------------------

func test_contrato() -> String:
	var base: GDScript = load("res://vn_runtime/audio/vn_audio_manager.gd")
	var impl: GDScript = load("res://vn_runtime/audio/vn_runtime_audio_manager.gd")
	if impl.is_abstract() or impl.get_base_script() != base:
		return "VNRuntimeAudioManager deve estender VNAudioManager e ser concreto"
	if VNRuntimeAudioManager.new().module_id() != &"audio":
		return "module_id"
	return ""


func test_loop_padrao_por_canal() -> String:
	var ctx := _setup()
	var au: VNRuntimeAudioManager = ctx.au
	au.run_audio_node({"id": "n1", "type": "audio", "action": "play", "channel": "music", "asset": "music/loop_a"})
	au.run_audio_node({"id": "n2", "type": "audio", "action": "play", "channel": "ambient", "asset": "music/loop_b"})
	au.run_audio_node({"id": "n3", "type": "audio", "action": "play", "channel": "sfx", "asset": "sfx/click"})
	au.run_audio_node({"id": "n4", "type": "audio", "action": "play", "channel": "voice", "asset": "voice/probe_001"})
	var snap := au.snapshot()
	_teardown(ctx)
	if snap.keys().size() != 2 or not snap.music.loop or not snap.ambient.loop:
		return "música e ambiente em laço no save, efeito e voz fora: %s" % snap
	return ""


func test_volumes_das_configuracoes() -> String:
	var ctx := _setup("dialogue", true, {"volume.master": 0.5, "volume.music": 0.4})
	var au: VNRuntimeAudioManager = ctx.au
	var ui: FakeUIManager = ctx.m.ui
	au.run_audio_node({"id": "n1", "action": "play", "channel": "music", "asset": "music/loop_a", "volume": 0.5})
	var v := _vol(au, &"music")
	if not _approx(v, 0.5 * 0.4 * 0.5):
		_teardown(ctx)
		return "volume inicial %f" % v
	var db := au.channel_node(&"music").main_player().volume_db
	if not _approx(db, linear_to_db(0.1)):
		_teardown(ctx)
		return "volume_db %f" % db
	ui.set_setting(&"volume.music", 1.0)
	v = _vol(au, &"music")
	if not _approx(v, 0.25):
		_teardown(ctx)
		return "mudar volume.music não valeu na hora: %f" % v
	ui.set_setting(&"volume.master", 0.0)
	v = _vol(au, &"music")
	var muted := au.channel_node(&"music").main_player().volume_db
	_teardown(ctx)
	if v != 0.0 or muted > -79.0:
		return "volume.master 0 deveria silenciar: %f / %f dB" % [v, muted]
	if not _approx(au.get_channel_volume(&"music"), 1.0) or au.get_channel_volume(&"master") != 0.0:
		return "get_channel_volume"
	return ""


func test_volume_por_canal_isolado() -> String:
	var ctx := _setup()
	var au: VNRuntimeAudioManager = ctx.au
	if not _approx(au.get_channel_volume(&"sfx"), 0.8) or not _approx(au.get_channel_volume(&"voice"), 1.0):
		_teardown(ctx)
		return "padrões da UI Spec §8"
	au.run_audio_node({"id": "a", "action": "play", "channel": "music", "asset": "music/loop_a"})
	au.run_audio_node({"id": "b", "action": "play", "channel": "ambient", "asset": "music/loop_b"})
	au.run_audio_node({"id": "c", "action": "play", "channel": "voice", "asset": "voice/probe_001"})
	au.run_audio_node({"id": "d", "action": "play", "channel": "sfx", "asset": "sfx/click"})
	var before := {}
	for ch in VNAudioManager.CHANNELS:
		before[ch] = _vol(au, ch)
	for ch in VNAudioManager.CHANNELS:
		(ctx.m.ui as FakeUIManager).set_setting(StringName("volume." + String(ch)), 0.25)
		for other in VNAudioManager.CHANNELS:
			var expect: float = 0.8 * 0.25 if other == ch else before[other]
			if not _approx(_vol(au, other), expect):
				_teardown(ctx)
				return "volume.%s mexeu em %s (%f, esperado %f)" % [ch, other, _vol(au, other), expect]
		(ctx.m.ui as FakeUIManager).set_setting(StringName("volume." + String(ch)), DEFAULT_OF(ch))
	_teardown(ctx)
	return ""


static func DEFAULT_OF(ch: StringName) -> float:
	return float(VNRuntimeAudioManager.DEFAULT_VOLUMES[ch])


func test_fade_cruzado_e_stop() -> String:
	var ctx := _setup("dialogue", true, {"volume.master": 1.0})
	var au: VNRuntimeAudioManager = ctx.au
	var c := au.channel_node(&"music")
	au.run_audio_node(_audio_node(ctx, "music/loop_a"))   # fade 1
	var p1 := c.main_player()
	if not _approx(c.effective_volume(p1), 0.0):
		_teardown(ctx)
		return "fade de entrada começa em silêncio"
	au.step(0.5)
	if not _approx(c.effective_volume(p1), 0.8 * 0.5):
		_teardown(ctx)
		return "meio do fade: %f" % c.effective_volume(p1)
	au.step(0.5)
	au.run_audio_node({"id": "x", "action": "play", "channel": "music", "asset": "music/loop_b", "fade": 2.0})
	var p2 := c.main_player()
	au.step(1.0)
	if not (_approx(c.effective_volume(p1), 0.4) and _approx(c.effective_volume(p2), 0.4)):
		_teardown(ctx)
		return "fade cruzado: %f / %f" % [c.effective_volume(p1), c.effective_volume(p2)]
	au.step(1.0)
	if c.players().size() != 1 or c.players()[0] != p2:
		_teardown(ctx)
		return "a faixa anterior deveria sair ao fim do fade"
	au.run_audio_node(_audio_node(ctx, "", "stop"))   # fade 0.5
	if not au.snapshot().is_empty():
		_teardown(ctx)
		return "stop tira o canal do save na hora"
	au.step(0.25)
	if not _approx(c.effective_volume(p2), 0.4):
		_teardown(ctx)
		return "fade de saída: %f" % c.effective_volume(p2)
	au.step(0.25)
	var active := c.is_active()
	_teardown(ctx)
	return "o canal deveria silenciar ao fim do fade" if active else ""


func test_sfx_avulsos_se_sobrepoem() -> String:
	var ctx := _setup()
	var au: VNRuntimeAudioManager = ctx.au
	au.run_audio_node({"id": "a", "action": "play", "channel": "sfx", "asset": "sfx/click"})
	au.run_audio_node({"id": "b", "action": "play", "channel": "sfx", "asset": "sfx/chime"})
	var n := au.channel_node(&"sfx").players().size()
	au.run_audio_node({"id": "c", "action": "play", "channel": "voice", "asset": "voice/probe_001"})
	au.run_audio_node({"id": "d", "action": "play", "channel": "voice", "asset": "voice/probe_001"})
	var nv := au.channel_node(&"voice").players().size()
	_teardown(ctx)
	if n != 2:
		return "efeitos se sobrepõem: %d" % n
	if nv != 1:
		return "uma voz nova substitui a anterior: %d" % nv
	return ""


func test_legendas_com_subtitles() -> String:
	var ctx := _setup()
	var au: VNRuntimeAudioManager = ctx.au
	var got: Array = []
	au.caption_changed.connect(func(ch, t): got.append([ch, t]))
	var node := _audio_node(ctx, "sfx/click")   # caption "(click)"
	au.run_audio_node(node)
	if au.current_caption(&"sfx") != "(click)" or au.caption_view().caption(&"sfx") != "(click)":
		_teardown(ctx)
		return "legenda não apareceu: '%s'" % au.current_caption(&"sfx")
	if got != [[&"sfx", "(click)"]]:
		_teardown(ctx)
		return "sinal: %s" % [got]
	(ctx.m.ui as FakeUIManager).set_setting(&"subtitles", false)
	if au.current_caption(&"sfx") != "" or au.caption_view().caption(&"sfx") != "":
		_teardown(ctx)
		return "subtitles desligado deveria apagar"
	au.run_audio_node(node)
	if au.current_caption(&"sfx") != "":
		_teardown(ctx)
		return "sem subtitles, nenhuma legenda nova"
	(ctx.m.ui as FakeUIManager).set_setting(&"subtitles", true)
	var back := au.current_caption(&"sfx")
	_teardown(ctx)
	if back != "(click)":
		return "ligar subtitles mostra de novo a legenda que ainda vale"
	return ""


func test_legenda_traduzida_e_troca_de_idioma() -> String:
	var ctx := _setup("dialogue", true, {"locale": "pt-BR"})
	var au: VNRuntimeAudioManager = ctx.au
	au.run_audio_node({"id": "m", "action": "play", "channel": "music", "asset": "music/loop_a", "caption": "[waves]"})
	var node := _audio_node(ctx, "sfx/click")
	au.run_audio_node(node)
	if au.current_caption(&"sfx") != "(clique)":
		_teardown(ctx)
		return "tradução pt-BR: '%s'" % au.current_caption(&"sfx")
	if au.current_caption(&"music") != "[waves]":
		_teardown(ctx)
		return "sem tradução, o texto do idioma-fonte"
	(ctx.m.ui as FakeUIManager).set_setting(&"locale", "en")
	var en := au.current_caption(&"sfx")
	_teardown(ctx)
	return "" if en == "(click)" else "trocar de idioma retraduz: '%s'" % en


func test_legenda_de_sfx_some_sozinha() -> String:
	var ctx := _setup()
	var au: VNRuntimeAudioManager = ctx.au
	au.run_audio_node(_audio_node(ctx, "sfx/click"))
	au.run_audio_node({"id": "m", "action": "play", "channel": "music", "asset": "music/loop_a", "caption": "[music]"})
	au.step(VNRuntimeAudioManager.CAPTION_MIN_SECONDS - 0.1)
	if au.current_caption(&"sfx") == "":
		_teardown(ctx)
		return "a legenda de efeito fica no mínimo CAPTION_MIN_SECONDS"
	au.step(0.2)
	var sfx := au.current_caption(&"sfx")
	var music := au.current_caption(&"music")
	au.stop_channel(&"music")
	var after_stop := au.current_caption(&"music")
	_teardown(ctx)
	if sfx != "":
		return "a legenda do efeito deveria sumir"
	if music != "[music]":
		return "a legenda da música em laço fica enquanto ela toca"
	return "" if after_stop == "" else "stop apaga a legenda"


func test_legenda_modo_stream() -> String:
	var ctx := _setup("stream")
	var au: VNRuntimeAudioManager = ctx.au
	var chime := _audio_node(ctx, "sfx/chime")   # replace_with click, censored_caption "(click)"
	var noise := _audio_node(ctx, "sfx/noise")   # hide
	au.run_audio_node(chime)
	var off := au.current_caption(&"sfx")
	au.set_content_filter(true)
	(ctx.m.assets as FakeAssets).set_content_filter(true)
	var on := au.current_caption(&"sfx")
	au.run_audio_node(noise)
	var hidden := au.current_caption(&"sfx")
	var noise_players := au.channel_node(&"sfx").players().size()
	au.run_audio_node({"id": "z", "action": "play", "channel": "sfx", "asset": "sfx/chime", "caption": "(chime)"})
	var no_censored := au.current_caption(&"sfx")
	_teardown(ctx)
	if off != "(chime)":
		return "modo desligado: '%s'" % off
	if on != "(click)":
		return "replace_with mostra censored_caption: '%s'" % on
	if hidden != "":
		return "hide não mostra legenda"
	if noise_players != 1:
		return "hide não toca o som (%d players)" % noise_players
	return "" if no_censored == "" else "replace_with sem censored_caption não mostra nada"


func test_modo_stream_troca_o_som() -> String:
	var ctx := _setup("stream")
	var au: VNRuntimeAudioManager = ctx.au
	var fa: FakeAssets = ctx.m.assets
	var c := au.channel_node(&"ambient")
	au.run_audio_node({"id": "a", "action": "play", "channel": "ambient", "asset": "sfx/chime"})
	var p1 := c.main_player()
	if p1.stream != fa.resources["sfx/chime"] and not (p1.stream is AudioStreamWAV):
		_teardown(ctx)
		return "som original"
	au.set_content_filter(true)
	var p2 := c.main_player()
	var replaced := p2 != p1 and p2.get_playback_position() < 0.05
	au.step(VNRuntimeAudioManager.SHORT_FADE)
	au.set_content_filter(true)   # sem mudança: não reinicia
	var same := c.main_player() == p2
	au.run_audio_node({"id": "b", "action": "play", "channel": "ambient", "asset": "sfx/noise"})
	var hidden := c.main_player() == null
	var snap := au.snapshot()
	au.set_content_filter(false)
	var back := c.main_player() != null
	_teardown(ctx)
	if not replaced:
		return "ligar o modo troca para a substituta, do início"
	if not same:
		return "mesmo modo não reinicia o som"
	if not hidden:
		return "hide silencia o canal"
	if snap.ambient.asset != "sfx/noise":
		return "o save guarda o id original"
	return "" if back else "desligar o modo volta o som original"


## Os nós audio dos vetores de modo stream da spec 08 (flow.json), com o
## stage.audio esperado depois de cada mudança de modo.
func test_vetores_modo_stream() -> String:
	var flow: Variant = _read_json(FLOW_VECTORS)
	if flow == null:
		return "não achei %s" % FLOW_VECTORS
	var checked := 0
	for case: Dictionary in flow.cases:
		if not String(case.id).begins_with("modo_stream"):
			continue
		var m := VNFakeModules.create()
		var au := VNRuntimeAudioManager.new()
		m.audio = au
		m.bind_all()
		for n: Dictionary in case.scene.nodes:
			if n.type == "audio":
				au.run_audio_node(n)
		var expects: Array = case.expect.trace.filter(func(t): return t is Dictionary and t.has("stage"))
		var i := 0
		for input: Variant in case.inputs:
			if input is Dictionary and input.has("content_filter"):
				au.set_content_filter(bool(input.content_filter))
				var want: Dictionary = expects[i].stage.audio
				i += 1
				if au.audible() != want:
					return "%s: %s, esperado %s" % [case.id, au.audible(), want]
				checked += 1
	return "" if checked >= 5 else "poucos casos conferidos: %d" % checked


func test_snapshot_e_restore() -> String:
	var ctx := _setup()
	var au: VNRuntimeAudioManager = ctx.au
	au.run_audio_node({"id": "a", "action": "play", "channel": "music", "asset": "music/loop_a", "volume": 0.5})
	au.run_audio_node({"id": "b", "action": "play", "channel": "music", "asset": "music/loop_b", "censor": "skip"})
	var snap := au.snapshot()
	var want := {"music": {"asset": "music/loop_b", "loop": true, "volume": 1.0, "censor": "skip",
		"base": {"asset": "music/loop_a", "loop": true, "volume": 0.5}}}
	if snap != want:
		_teardown(ctx)
		return "snapshot: %s" % snap
	au.stop_all()
	au.set_content_filter(true)
	au.restore(snap)
	var c := au.channel_node(&"music")
	var playing_base := c.main_player() != null
	var audible := au.audible()
	var snap2 := au.snapshot()
	_teardown(ctx)
	if not playing_base:
		return "restore deveria tocar a base"
	if audible != {"music": "music/loop_a"}:
		return "restore no modo ligado mostra a base: %s" % audible
	return "" if snap2 == want else "o save restaurado guarda a marca e a base"


func test_galeria_marca_musica() -> String:
	var ctx := _setup("stream", false)
	var au: VNRuntimeAudioManager = ctx.au
	var saves: FakeSaveManager = ctx.m.saves
	au.run_audio_node({"id": "a", "action": "play", "channel": "music", "asset": "music/loop_a"})
	au.run_audio_node({"id": "b", "action": "play", "channel": "sfx", "asset": "sfx/click"})
	au.run_audio_node({"id": "c", "action": "play", "channel": "ambient", "asset": "sfx/chime"})
	var seen: Array = saves.profile().get("seen_assets", []).duplicate()
	au.restore({"ambient": {"asset": "music/loop_b", "loop": true, "volume": 1.0}})
	var seen2: Array = saves.profile().get("seen_assets", [])
	if seen != ["music/loop_a"]:
		return "só audio_music em música/ambiente conta: %s" % [seen]
	return "" if seen2.has("music/loop_b") else "a música restaurada também conta"


func test_play_avulso_e_plugin() -> String:
	var ctx := _setup("stream")
	var au: VNRuntimeAudioManager = ctx.au
	(ctx.m.ui as FakeUIManager).set_setting(&"volume.sfx", 0.5)
	var p := au.play("sfx/click", &"sfx", 0.5)
	var ok_vol := p != null and _approx(au.channel_node(&"sfx").effective_volume(p), 0.8 * 0.5 * 0.5)
	var plugin_ok := au.play(FIXTURES + "stream/assets/audio/sfx/click.wav") != null
	au.set_content_filter(true)
	var hidden := au.play("sfx/noise")
	var missing := au.play("nao/existe")
	au.stop_channel(&"sfx")
	var stopped := au.channel_node(&"sfx").players().is_empty()
	_teardown(ctx)
	var detached := VNRuntimeAudioManager.new().play("sfx/click")
	if not ok_vol:
		return "play aplica o volume do canal sobre o do pedido"
	if not plugin_ok:
		return "caminho res:// do plugin"
	if hidden != null or missing != null:
		return "hide e id inexistente não tocam"
	if not stopped:
		return "stop_channel para os avulsos"
	return "" if detached == null else "sem attach, play devolve null"


func test_edicao_censurada() -> String:
	var m := VNFakeModules.create()
	var au := VNRuntimeAudioManager.new()
	m.audio = au
	m.bind_all()
	au.load_bundle({"assets": {}, "project": {"default_locale": "en", "content_filter": {"edition": "censored"}}})
	au.set_content_filter(false)
	return "" if au.is_content_filter_enabled() else "na edição censurada o modo fica sempre ligado"
