extends VNSdkTest
## M3-03: idioma, tema, modo stream, personagens, assets, áudio, overlays e RNG
## (Plugin SDK §5.6–§5.7, RT §5.5, §12.2).

const ALL_CAPS: Array[StringName] = [
	VNRuntimeSDK.CAP_CHARACTERS_READ, VNRuntimeSDK.CAP_ASSETS_READ,
	VNRuntimeSDK.CAP_AUDIO_PLAY, VNRuntimeSDK.CAP_UI_OVERLAY,
]


func _ctx(caps: Array[StringName] = [], bridge: FakePluginBridge = null) -> VNPluginContext:
	if bridge == null:
		bridge = FakePluginBridge.new()
	bridge.capabilities = caps
	return VNPluginContext.create(bridge, &"vnstudio.fishing", &"fishing")


func _ints(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(int(v))
	return out


# --- i18n --------------------------------------------------------------------

func test_i18n_ordem_de_busca_e_fallback() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([], b)
	eq(ctx.i18n.text("runtime/hud/fish_count", "Fish: {count}", {"count": 3}), "Fish: 3", "fallback do código")
	b.texts["fishing:runtime/hud/fish_count"] = "Peixes: {count}"
	eq(ctx.i18n.text("runtime/hud/fish_count", "Fish: {count}", {"count": 2}), "Peixes: 2", "texto do projeto/manifesto")
	eq(b.logs.size(), 0, "sem aviso com chave runtime/")


func test_i18n_chaves_literais_e_argumento_faltando() -> void:
	var ctx := _ctx()
	eq(ctx.i18n.text("runtime/x", "{{{n}}} de {total}", {"n": 1}), "{1} de {total}", "{{ }} literais e chave sem valor")


func test_i18n_chave_fora_de_runtime_avisa() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([], b)
	eq(ctx.i18n.text("hud/x", "X"), "X", "usa o fallback")
	eq(b.logs.size(), 1, "aviso W016")


func test_i18n_locale_e_sinal() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([], b)
	var seen: Array[String] = []
	ctx.i18n.locale_changed.connect(func(l: String) -> void: seen.append(l))
	eq(ctx.i18n.locale, "en", "locale inicial")
	b.set_locale("pt-BR")
	eq(ctx.i18n.locale, "pt-BR", "locale depois da troca")
	eq(seen, ["pt-BR"] as Array[String], "sinal repassado")


# --- tema e modo stream ----------------------------------------------------------

func test_tema_somente_leitura_com_papeis() -> void:
	var b := FakePluginBridge.new()
	b.colors[&"accent"] = Color.RED
	b.font_sizes[&"ui"] = 28
	var ctx := _ctx([], b)
	eq(ctx.theme.resolution, Vector2i(1280, 720), "resolution")
	eq(ctx.theme.color(&"accent"), Color.RED, "color accent")
	eq(ctx.theme.font_size(&"ui"), 28, "font_size ui")
	eq(ctx.theme.font_size(&"inexistente"), 0, "papel desconhecido: tamanho")
	eq(ctx.theme.color(&"inexistente"), Color.WHITE, "papel desconhecido: cor")
	check(ctx.theme.font(&"inexistente") == null, "papel desconhecido: fonte")


func test_content_filter_segue_a_ponte_e_nao_aceita_escrita() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([], b)
	eq(ctx.content_filter, false, "desligado")
	b.stream_mode = true
	eq(ctx.content_filter, true, "ligado")
	ctx.content_filter = false
	eq(ctx.content_filter, true, "escrita ignorada")
	eq(b.logs.size(), 1, "escrita avisa")


# --- personagens e assets -------------------------------------------------------------

func test_personagens_exigem_capacidade() -> void:
	var b := FakePluginBridge.new()
	b.characters["alice"] = {"id": "alice", "name": "Alice", "color": "#ff0000", "expressions": ["neutral"]}
	var ctx := _ctx([], b)
	eq(ctx.characters.get_character("alice"), {}, "sem capacidade")
	eq(ctx.characters.list_characters().size(), 0, "lista sem capacidade")
	eq(b.denied.size(), 2, "dois avisos de permissão")
	ctx = _ctx([VNRuntimeSDK.CAP_CHARACTERS_READ], b)
	eq(ctx.characters.get_character("alice").name, "Alice", "com capacidade")
	eq(ctx.characters.get_character("zed"), {}, "id desconhecido")
	eq(ctx.characters.list_characters(), PackedStringArray(["alice"]), "lista")
	var copy := ctx.characters.get_character("alice")
	copy.name = "X"
	eq(b.characters["alice"].name, "Alice", "devolve cópia")


func test_assets_capacidade_escolha_do_autor_e_filtro() -> void:
	var b := FakePluginBridge.new()
	var res := Resource.new()
	b.assets["sfx_rare"] = res
	b.assets["nsfw_cg"] = Resource.new()
	var ctx := _ctx([], b)
	check(ctx.assets.load_asset("sfx_rare") == null, "sem capacidade")
	eq(b.denied.size(), 1, "aviso de permissão")
	b.chosen_assets.append("sfx_rare")
	check(ctx.assets.load_asset("sfx_rare") == res, "escolhido pelo autor dispensa assets.read")
	ctx = _ctx([VNRuntimeSDK.CAP_ASSETS_READ], b)
	check(ctx.assets.load_asset("sfx_rare") == res, "com capacidade")
	b.hidden_assets.append("nsfw_cg")
	check(ctx.assets.load_asset("nsfw_cg") == null, "censored.hide devolve null")
	check(ctx.assets.load_asset("res://x.tres") == null, "res:// não passa por aqui")


# --- áudio --------------------------------------------------------------------------------

func test_audio_exige_capacidade_e_canal() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([], b)
	check(ctx.audio.play("res://vn_plugins/fishing/a.ogg") == null, "sem audio.play")
	eq(b.denied[0].capability, VNRuntimeSDK.CAP_AUDIO_PLAY, "capacidade avisada")
	ctx = _ctx([VNRuntimeSDK.CAP_AUDIO_PLAY], b)
	check(ctx.audio.play("res://vn_plugins/fishing/a.ogg", &"music") == null, "canal music recusado")
	check(ctx.audio.play("res://vn_plugins/outro/a.ogg") == null, "recurso de outro plugin")
	var s := ctx.audio.play("res://vn_plugins/fishing/a.ogg", &"ambient", 2.5)
	check(s != null and s.is_playing(), "toca")
	eq(b.played, [{"asset": "res://vn_plugins/fishing/a.ogg", "channel": &"ambient", "volume": 1.0}] as Array[Dictionary], "volume limitado a 1")
	s.stop(0.2)
	check(not s.is_playing(), "stop")


func test_audio_asset_do_projeto_pede_assets_read_ou_escolha() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([VNRuntimeSDK.CAP_AUDIO_PLAY], b)
	check(ctx.audio.play("sfx_rare") == null, "sem assets.read")
	eq(b.denied[0].capability, VNRuntimeSDK.CAP_ASSETS_READ, "pede assets.read")
	b.chosen_assets.append("sfx_rare")
	check(ctx.audio.play("sfx_rare") != null, "escolhido pelo autor toca só com audio.play")
	b.hidden_assets.append("sfx_rare")
	check(ctx.audio.play("sfx_rare") == null, "censored.hide não toca")


func test_audio_stop_all() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([VNRuntimeSDK.CAP_AUDIO_PLAY], b)
	ctx.audio.stop_all(-1.0)
	ctx.audio.stop_all(0.5)
	eq(b.stopped_all, [0.0, 0.5] as Array[float], "fades")
	ctx = _ctx([], b)
	ctx.audio.stop_all()
	eq(b.denied.size(), 1, "sem capacidade")


func test_som_sem_host_e_inerte() -> void:
	var s := VNSound.new()
	s.stop()
	check(not s.is_playing(), "inerte")


# --- overlays -------------------------------------------------------------------------------

func _scene() -> PackedScene:
	var root := Control.new()
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


func test_overlay_push_e_pop() -> void:
	var b := FakePluginBridge.new()
	var ctx := _ctx([], b)
	check(ctx.ui.push_overlay(_scene()) == null, "sem ui.overlay")
	eq(b.denied.size(), 1, "aviso de permissão")
	ctx = _ctx([VNRuntimeSDK.CAP_UI_OVERLAY], b)
	check(ctx.ui.push_overlay(null) == null, "cena nula")
	var node := ctx.ui.push_overlay(_scene())
	check(node is Control, "instancia a cena")
	eq((node as Control).anchor_right, 1.0, "ancorado ao retângulo todo")
	eq(b.overlays.size(), 1, "entrou na camada")
	var stranger := Control.new()
	ctx.ui.pop_overlay(stranger)
	stranger.free()
	eq(b.logs.size() > 0, true, "pop de nó alheio avisa")
	eq(b.overlays.size(), 1, "nó alheio não sai")
	ctx.ui.pop_overlay(node)
	eq(b.overlays.size(), 0, "saiu da camada")
	check(node.is_queued_for_deletion(), "liberado")
	node.free()


func test_overlay_sem_camada_no_host() -> void:
	var b := FakePluginBridge.new()
	b.overlay_ok = false
	var ctx := _ctx([VNRuntimeSDK.CAP_UI_OVERLAY], b)
	check(ctx.ui.push_overlay(_scene()) == null, "host sem camada")


# --- RNG ------------------------------------------------------------------------------------------

func test_ctx_rng_vem_da_ponte() -> void:
	var b := FakePluginBridge.new()
	var fixed := VNRandom.pcg32(42)
	b.rngs[&"fishing"] = fixed
	var ctx := _ctx([], b)
	check(ctx.rng == fixed, "fluxo do host")
	check(ctx.rng.is_reproducible(), "reproduzível")
	check(not VNRandom.new().is_reproducible(), "padrão é o motor")


func test_pcg32_confere_com_os_vetores_de_conformidade() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../../docs/specs/conformance/rng.json")
	var f := FileAccess.open(path, FileAccess.READ)
	check(f != null, "abriu rng.json")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	var n := 0
	for c in doc.cases:
		var expect: Dictionary = c.expect
		match c.op:
			"sequence":
				var r := VNRandom.pcg32(VNRandom.seed_from_hex(c.seed))
				var got: Array = []
				for i in int(c.count):
					got.append(r._next_u32())
				eq(got, _ints(expect.values), "%s: valores" % c.id)
				eq(r.get_state_hex(), expect.state_after, "%s: estado" % c.id)
			"random_int":
				var r := VNRandom.pcg32(VNRandom.seed_from_hex(c.seed))
				var got: Array = []
				for i in int(c.count):
					got.append(r.randi_range(int(c.min), int(c.max)))
				eq(got, _ints(expect.values), "%s: random_int" % c.id)
			"activity_seed":
				var s := VNRandom.activity_seed(VNRandom.seed_from_hex(c.seed), int(c.selection_count), c.node, int(c.activity_index))
				eq(VNRandom.seed_to_hex(s), expect.seed, "%s: semente" % c.id)
			"plugin_seed":
				var s := VNRandom.plugin_seed(VNRandom.seed_from_hex(c.seed), c.namespace)
				eq(VNRandom.seed_to_hex(s), expect.seed, "%s: semente" % c.id)
			_:
				continue
		n += 1
	check(n >= 8, "todos os casos rodaram (%d)" % n)


func test_pcg32_estado_vai_e_volta_pelo_save() -> void:
	var a := VNRandom.pcg32(7)
	a.randi_range(1, 100)
	var saved := a.get_state_hex()
	var next_a := a.randi_range(1, 1000000)
	var b := VNRandom.pcg32(999)
	b.set_state_hex(saved)
	eq(b.randi_range(1, 1000000), next_a, "retoma a sequência")
	var plain := VNRandom.new()
	eq(plain.get_state_hex(), "", "motor comum não tem estado")


# --- Aceite da M3-03: o fishing de exemplo só usa APIs do SDK ---------------------------------

func test_fishing_de_exemplo_usa_so_apis_do_sdk() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../../docs/specs/examples/fishing-plugin/runtime")
	var ctx := _ctx()
	var re := RegEx.create_from_string("\\b_ctx\\.(\\w+)(?:\\.(\\w+))?")
	var used := 0
	for rel in ["src/fishing_plugin.gd", "scenes/fishing_game.gd"]:
		var f := FileAccess.open(dir.path_join(rel), FileAccess.READ)
		check(f != null, "abriu %s" % rel)
		if f == null:
			continue
		for m in re.search_all(f.get_as_text()):
			var member := m.get_string(1)
			var sub := m.get_string(2)
			var value: Variant = ctx.get(member)
			check(member in ctx, "ctx.%s existe" % member)
			if sub != "" and value is Object:
				var obj: Object = value
				check(obj.has_method(sub) or sub in obj, "ctx.%s.%s existe" % [member, sub])
			used += 1
	check(used >= 8, "encontrou os usos (%d)" % used)
	# APIs usadas por fishing_game.gd através dos parâmetros de setup().
	for m in ["text"]:
		check(ctx.i18n.has_method(m), "i18n.%s" % m)
	for m in ["font", "color"]:
		check(ctx.theme.has_method(m), "theme.%s" % m)
	for m in ["randf", "randi_range"]:
		check(ctx.rng.has_method(m), "rng.%s" % m)
