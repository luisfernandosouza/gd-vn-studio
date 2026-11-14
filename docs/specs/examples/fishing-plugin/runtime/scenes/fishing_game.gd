# Lógica do minijogo. Não conhece a NarrativeAPI: recebe opções, RNG, textos e
# tema, e devolve { fish_count, score } pelo sinal finished.
#
# Regras do SDK seguidas aqui (Plugin SDK §2.4 e §5.7):
# - class_name começa com o namespace (Fishing...);
# - sorteios usam o VNRandom da atividade (handle.rng), nunca randi()/randf();
# - posições relativas ao tamanho do overlay (resolução do projeto), nunca fixas;
# - o tempo vem do delta, nunca do relógio do sistema;
# - input pela ação padrão vn_confirm (teclado, clique, toque, gamepad).
class_name FishingGame
extends Control

signal finished(result: Dictionary)
signal rare_fish_caught(species: String)

const BITE_WINDOW := {"easy": 1.2, "normal": 0.8, "hard": 0.5}   # segundos para fisgar
const RARE_SPECIES := ["peixe-lua", "atum-dourado", "enguia-azul"]

@onready var _fish_label: Label = $HUD/FishCount
@onready var _time_label: Label = $HUD/TimeLeft
@onready var _hint_label: Label = $Hint
@onready var _bobber: ColorRect = $Bobber

var _rng: VNRandom
var _i18n: VNI18nAPI
var _time_left := 60.0
var _window := 0.8
var _rare_chance := 0.05
var _until_bite := 0.0
var _bite_left := 0.0
var _fish := 0
var _score := 0
var _running := false


func setup(opts: Dictionary, rng: VNRandom, i18n: VNI18nAPI, theme_info: VNThemeInfo) -> void:
	_rng = rng
	_i18n = i18n
	_time_left = float(opts.duration_seconds)
	_window = BITE_WINDOW[opts.difficulty] + 0.1 * (int(opts.rod_level) - 1)
	_rare_chance = float(opts.rare_fish_chance)
	for label in [_fish_label, _time_label, _hint_label]:
		label.add_theme_font_override("font", theme_info.font(&"ui"))
		label.add_theme_color_override("font_color", theme_info.color(&"text"))
	_bobber.color = theme_info.color(&"accent")
	_hint_label.text = _i18n.text("runtime/tutorial/cast", "Press Space to cast the line") if opts.show_tutorial else ""
	_schedule_bite()
	_running = true
	_update_hud()


func abort() -> void:
	if _running:
		_running = false
		finished.emit({"aborted": true, "fish_count": _fish, "score": _score})


func _process(delta: float) -> void:
	if not _running:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_running = false
		finished.emit({"fish_count": _fish, "score": _score})
		return
	if _bite_left > 0.0:
		_bite_left -= delta
		if _bite_left <= 0.0:
			_schedule_bite()  # o peixe escapou
	else:
		_until_bite -= delta
		if _until_bite <= 0.0:
			_bite_left = _window
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if _running and event.is_action_pressed(&"vn_confirm"):
		get_viewport().set_input_as_handled()
		_hint_label.text = ""
		if _bite_left > 0.0:
			_catch()


func _catch() -> void:
	_fish += 1
	_score += 100 + int(_bite_left / _window * 100.0)   # fisgar rápido vale mais
	if _rng.randf() < _rare_chance:
		_score += 500
		rare_fish_caught.emit(RARE_SPECIES[_rng.randi_range(0, RARE_SPECIES.size() - 1)])
	_schedule_bite()


func _schedule_bite() -> void:
	_bite_left = 0.0
	_until_bite = 1.0 + _rng.randf() * 3.0


func _update_hud() -> void:
	_fish_label.text = _i18n.text("runtime/hud/fish_count", "Fish: {count}", {"count": _fish})
	_time_label.text = _i18n.text("runtime/hud/time_left", "Time: {seconds}s", {"seconds": ceili(_time_left)})
	var rest := size.y * 0.5 - _bobber.size.y * 0.5
	_bobber.position = Vector2(size.x * 0.5 - _bobber.size.x * 0.5, rest + (size.y * 0.022 if _bite_left > 0.0 else 0.0))
