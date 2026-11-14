# Fishing Minigame: entrypoint de runtime (Runtime SDK ^1.0.0).
#
# Regra do plugin de referência: o minijogo devolve o resultado e a CENA decide
# o que ele vale na história (on_result.effects). Por isso o plugin não pede
# variables.read, variables.write nem transactions; ele só escreve nas próprias
# variáveis (plugin.fishing.*), que não exigem capacidade.
extends VNRuntimePlugin

const FishingGameScene := preload("res://vn_plugins/fishing/runtime/scenes/fishing_game.tscn")

var _ctx: VNPluginContext
var _game: FishingGame = null

# Estado interno de gameplay: vai para o save opaco (save.data), não para variáveis.
var _rod_level := 1
var _tutorial_seen := false


func _vn_init(ctx: VNPluginContext) -> void:
	_ctx = ctx


func _vn_game_started(is_new_game: bool) -> void:
	if is_new_game:
		_rod_level = 1
		_tutorial_seen = false


func _vn_start_activity(activity_id: StringName, params: Dictionary, handle: VNActivityHandle) -> void:
	if activity_id != &"fishing_game":
		handle.fail("atividade desconhecida: %s" % activity_id)
		return

	_game = _ctx.ui.push_overlay(FishingGameScene) as FishingGame
	_game.rare_fish_caught.connect(_on_rare_fish_caught)
	_game.setup({
		"difficulty": params.difficulty,
		"duration_seconds": params.duration_seconds,   # default do schema já aplicado
		"rod_level": _rod_level,
		"rare_fish_chance": _ctx.config.rare_fish_chance,
		"show_tutorial": _ctx.config.show_tutorial and not _tutorial_seen,
	}, handle.rng, _ctx.i18n, _ctx.theme)   # fluxo de RNG próprio da atividade

	var r: Dictionary = await _game.finished
	_close_game()

	if not handle.is_active():
		return  # o jogador pulou: o runtime já completou com default_outcome

	_tutorial_seen = true
	var fish_count: int = r.fish_count
	var score: int = r.score
	var won := fish_count >= int(params.target_fish)

	# Recordes valem na história e no modo livre (Plugin SDK §9.1).
	_ctx.profile.submit_record(&"high_scores", score, {"difficulty": params.difficulty, "fish": fish_count})
	# best_score é variável de perfil: gravável também no modo livre.
	if score > int(_ctx.narrative.variables.get_value("~best_score", 0)):
		_ctx.narrative.variables.set_value("~best_score", score)

	if handle.mode == &"story":
		# Só na história: estado da partida e eventos (no modo livre seriam recusados).
		_ctx.narrative.variables.add_value("~total_caught", fish_count)
		if won and _rod_level < 3:
			_rod_level += 1
		_ctx.narrative.events.emit("fishing.completed", {"fish_count": fish_count, "score": score})
	handle.complete(&"won" if won else &"lost", {"won": won, "fish_count": fish_count, "score": score})


func _vn_cancel_activity(_handle: VNActivityHandle) -> void:
	if _game != null:
		_game.abort()  # emite finished; _vn_start_activity fecha o overlay e sai


func _vn_save() -> Variant:
	return {"rod_level": _rod_level, "tutorial_seen": _tutorial_seen}


func _vn_load(data: Variant) -> void:
	# data é null quando o save não tem dados deste plugin (ex.: save anterior à
	# instalação). Nesse caso o plugin volta ao estado inicial (Plugin SDK §5.1).
	if data == null:
		data = {}
	_rod_level = int(data.get("rod_level", 1))
	_tutorial_seen = bool(data.get("tutorial_seen", false))


func _vn_migrate_save_data(data: Variant, _from_version: int) -> Variant:
	return data  # save.data_version 1: nada a migrar ainda


func _on_rare_fish_caught(species: String) -> void:
	# No modo livre o emit é só registrado no log (Plugin SDK §6.1).
	_ctx.narrative.events.emit("fishing.rare_fish_caught", {"species": species})
	_ctx.audio.play("res://vn_plugins/fishing/runtime/assets/rare_fish.ogg")  # sfx curto: o handle não é guardado


func _close_game() -> void:
	if _game != null:
		_ctx.ui.pop_overlay(_game)
		_game = null
