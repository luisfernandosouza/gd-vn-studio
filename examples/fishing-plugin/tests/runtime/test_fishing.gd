# Testes do Fishing Minigame. Rodar com `vnplugin test` (Godot headless,
# relógio virtual, seed fixo). Plugin SDK §12.1.
extends VNPluginTest

const MANIFEST := "res://vn_plugins/fishing/plugin.json"
const EASY := {"difficulty": "easy", "duration_seconds": 30, "target_fish": 3}


func test_vence_quem_fisga_sempre() -> void:
	var h := VNTestHarness.new(MANIFEST, {"seed": 42})
	var input := VNScriptedInput.new().repeat(&"vn_confirm", 0.1)
	var r := await h.run_activity(&"fishing_game", EASY, input)
	assert_eq(r.outcome, &"won")
	assert_true(r.payload.fish_count >= 3)
	assert_eq(h.get_value("plugin.fishing.total_caught"), r.payload.fish_count)
	assert_eq(h.get_value("plugin.fishing.best_score"), r.payload.score)
	assert_true(h.emitted("fishing.completed"))


func test_perde_sem_input() -> void:
	var h := VNTestHarness.new(MANIFEST, {"seed": 42})
	var r := await h.run_activity(&"fishing_game", EASY)
	assert_eq(r.outcome, &"lost")
	assert_eq(r.payload, {"won": false, "fish_count": 0, "score": 0})
	assert_eq(h.get_value("plugin.fishing.total_caught"), 0)


func test_pular_usa_default_outcome_e_nao_emite_evento() -> void:
	var h := VNTestHarness.new(MANIFEST, {"seed": 42})
	var r := await h.skip_activity_after(&"fishing_game", EASY, 2.0)
	assert_eq(r.outcome, &"lost")
	assert_eq(r.payload, {})
	assert_false(h.emitted("fishing.completed"))


func test_nao_toca_variaveis_do_projeto() -> void:
	# O plugin não pediu variables.write: a cena é quem paga as moedas.
	var h := VNTestHarness.new(MANIFEST, {"seed": 7, "variables": {"global.player_money": 0}})
	await h.run_activity(&"fishing_game", EASY, VNScriptedInput.new().repeat(&"vn_confirm", 0.1))
	assert_eq(h.get_value("global.player_money"), 0)


func test_save_guarda_nivel_da_vara() -> void:
	var h := VNTestHarness.new(MANIFEST, {"seed": 42})
	await h.run_activity(&"fishing_game", EASY, VNScriptedInput.new().repeat(&"vn_confirm", 0.1))
	var data = h.save_plugin()
	assert_eq(data.rod_level, 2)
	var h2 := VNTestHarness.new(MANIFEST, {"seed": 42})
	h2.load_plugin(data)
	assert_eq(h2.save_plugin(), data)


func test_save_sem_dados_do_plugin_reinicia_o_estado() -> void:
	var h := VNTestHarness.new(MANIFEST, {"seed": 42})
	await h.run_activity(&"fishing_game", EASY, VNScriptedInput.new().repeat(&"vn_confirm", 0.1))
	h.load_plugin(null)   # save anterior à instalação do plugin
	assert_eq(h.save_plugin().rod_level, 1)


func test_textos_traduzidos_para_o_jogador() -> void:
	var h := VNTestHarness.new(MANIFEST, {"locale": "pt-BR"})
	var hud := h.plugin_context().i18n.text("runtime/hud/fish_count", "Fish: {count}", {"count": 2})
	assert_eq(hud, "Peixes: 2")
