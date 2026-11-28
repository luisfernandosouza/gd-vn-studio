class_name FakeUIManager
extends VNUIManager
## Dublê do UI Manager: pilha de ids e configurações num dicionário. Ações
## [code]effects[/code] e [code]emit[/code] vão de verdade ao State Manager e
## ao Event Bus do registro; as demais só são registradas.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

var stack: PackedStringArray = []
var hud_visible: bool = false
var settings: Dictionary = {}
## Resposta automática de confirm().
var confirm_answer: bool = true
var messages: PackedStringArray = []
## Modo automático e pular, como no UI Manager real (ações toggle_auto/toggle_skip).
var auto_mode: bool = false
var skip_mode: bool = false


func set_play_mode(auto: bool, skip: bool) -> void:
	_rec(&"set_play_mode", [auto, skip])
	auto_mode = auto
	skip_mode = skip


func open_screen(screen_id: String) -> VNResult:
	_rec(&"open_screen", [screen_id])
	stack.append(screen_id)
	screens_changed.emit(stack)
	return VNResult.success()


func close_screen() -> void:
	_rec(&"close_screen")
	if not stack.is_empty():
		stack.remove_at(stack.size() - 1)
		screens_changed.emit(stack)


func close_all() -> void:
	stack.clear()
	screens_changed.emit(stack)


func screen_stack() -> PackedStringArray:
	return stack


func set_hud_visible(visible: bool) -> void:
	hud_visible = visible


func run_actions(actions: Array, context: Dictionary = {}) -> VNResult:
	_rec(&"run_actions", [actions, context])
	for a in actions:
		match String(a.get("do", "")):
			"effects":
				var r := modules().state.apply_effects(a.get("effects", []), {}, VNStateManager.CALLER_UI)
				if not r.ok:
					return r
			"emit":
				modules().events.emit(String(a.event), a.get("payload", {}), VNEventBus.SOURCE_STORY)
			"toggle_auto":
				auto_mode = not auto_mode
			"toggle_skip":
				skip_mode = not skip_mode
			"open_backlog":
				open_screen("backlog")
			"open_screen":
				open_screen(String(a.screen))
			"close_screen", "back":
				close_screen()
			"set_setting":
				set_setting(StringName(a.setting), a.value)
	return VNResult.success()


func confirm(text_path: String, on_answer: Callable) -> void:
	_rec(&"confirm", [text_path])
	on_answer.call(confirm_answer)


func show_message(text_path: String) -> void:
	messages.append(text_path)


func load_settings() -> void:
	_rec(&"load_settings")
	var data: Variant = modules().storage.read_json("settings.json") if modules() != null and modules().storage != null else null
	settings = data if data is Dictionary else {}


func get_setting(setting: StringName) -> Variant:
	return settings.get(String(setting))


func set_setting(setting: StringName, value: Variant) -> VNResult:
	_rec(&"set_setting", [setting, value])
	settings[String(setting)] = value
	if modules() != null and modules().storage != null:
		modules().storage.write_json("settings.json", settings)
	setting_changed.emit(setting, value)
	return VNResult.success()
