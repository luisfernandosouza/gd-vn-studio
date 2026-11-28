class_name VNRuntimeNarrativeEngine
extends VNNarrativeEngine
## Narrative Engine real (tarefa M1-11): ciclo de vida do jogo (RT §3), laço de nós (§5.2),
## atividades de plugin (§5.3) e fim de cena (§5.4).
##
## Implementa o contrato [VNNarrativeEngine] (M0-07) sobre o registro [VNModules]: escreve só pelo
## State Manager, escolhe cenas só pelo Scheduler e desenha só pelo Stage. É dirigido por sinais
## ([signal VNStage.advanced], [signal VNStage.option_selected], [signal VNPluginHost.activity_ended]),
## sem laço bloqueante: cada nó instantâneo é executado dentro de um [code]while[/code] que para no
## primeiro nó bloqueante (RT §10). Ordem garantida: efeitos de um nó → drenagem de eventos → próximo nó.
##
## Escolhas onde a spec é omissa estão na descrição do PR do M1-11 e marcadas com "(escolha)" abaixo.

## Entradas guardadas no backlog do save (escolha: o RT §8.2 diz só "limitado pelo runtime").
const BACKLOG_LIMIT := 100

const _WAIT_LINE := &"line"
const _WAIT_CHOICE := &"choice"
const _WAIT_INTERACT := &"interact"
const _WAIT_TIMER := &"wait"

## Devolvido por um executor de nó que parou num nó bloqueante.
const _BLOCK := "<<block>>"
## Devolvido por um executor de nó que já encerrou ou redirecionou o fluxo (fim de cena, erro).
const _STOP := "<<stop>>"

var _phase: StringName = VNPhase.BOOT
var _paused := false
var _bundle: Dictionary = {}
var _project: Dictionary = {}
var _chapter := ""
var _chapter_entered_at := 0
var _scene := ""
var _node := ""
var _scene_def: Dictionary = {}
var _index: Dictionary = {}              # id do nó → posição em nodes[]
var _waiting: StringName = &""
var _filter := false                     # modo stream (RT §5.5)
var _backlog: Array[Dictionary] = []
var _used_hotspots: Array[String] = []
var _options: Dictionary = {}            # id → {option, enabled} do choice/interact atual
var _exit_option: Dictionary = {}        # saída do interact atual
var _resuming := false                   # reexecução ao carregar: não repete o backlog (RT §8.3 passo 7)
var _save_window: StringName = &""       # tipo de save liberado durante autosave (RT §8.1)
var _wait_token := 0
var _wait_pending_resume := false
var _text := VNUIText.new()


# --- Ligação ------------------------------------------------------------------------------------

func bind(p_modules: VNModules) -> void:
	super.bind(p_modules)
	if p_modules == null:
		return
	if p_modules.stage != null and not p_modules.stage.advanced.is_connected(advance):
		p_modules.stage.advanced.connect(advance)
		p_modules.stage.option_selected.connect(_on_option_selected)
	if p_modules.plugins != null and not p_modules.plugins.activity_ended.is_connected(_on_activity_ended):
		p_modules.plugins.activity_ended.connect(_on_activity_ended)


func load_bundle(bundle: Dictionary) -> void:
	_bundle = bundle
	_project = bundle.get("project", {})
	_text.number_formats = _project.get("settings", {}).get("number_formats", {})
	_text.locale = String(_project.get("default_locale", "en"))


## Idioma e traduções do texto das cenas (caminho → texto; RT §3.0 passo 3). Sem tradução vale o
## texto do idioma-fonte, que está no próprio nó (DM §9).
func set_locale(locale: String, strings: Dictionary = {}) -> void:
	_text.locale = locale
	_text.strings = strings


## Texto do caminho (ou [param raw], o do idioma-fonte) com a interpolação feita. O leitor de variáveis
## só existe durante a chamada: guardá-lo no [VNUIText] formaria um ciclo de referências com o Engine.
func _t(path: String, raw: String) -> String:
	_text.reader = _read_variable
	var s := _text.text(path, raw)
	_text.reader = Callable()
	return s


func _read_variable(id: String) -> Variant:
	var vars := modules().variables
	return vars.read(id) if vars.has(id) else null


# --- Estado -------------------------------------------------------------------------------------

func phase() -> StringName:
	return _phase


func current_chapter() -> String:
	return _chapter


func current_scene() -> String:
	return _scene


func current_node() -> String:
	return _node


func is_write_allowed() -> bool:
	return _phase not in [VNPhase.LOAD_GAME, VNPhase.GAME_END]


func can_save(kind: StringName = SAVE_MANUAL) -> bool:
	if _save_window == kind:
		return true
	if kind != SAVE_MANUAL:
		return false
	return _phase == VNPhase.SELECTION_POINT or (_phase == VNPhase.SCENE_RUNNING and _waiting in [_WAIT_LINE, _WAIT_CHOICE, _WAIT_INTERACT])


func snapshot() -> Dictionary:
	var scene: Variant = null
	if not _scene.is_empty():
		scene = {"id": _scene, "node": _node, "used_hotspots": _used_hotspots.duplicate()}
	return {
		"chapter": null if _chapter.is_empty() else {"id": _chapter, "entered_at": _chapter_entered_at},
		"scene": scene,
		"backlog": _backlog.duplicate(true),
	}


func _set_phase(p: StringName) -> void:
	if p == _phase:
		return
	var prev := _phase
	_phase = p
	phase_changed.emit(p, prev)


# --- Ciclo de vida (RT §3) ----------------------------------------------------------------------

func enter_title() -> void:
	_reset_run()
	_set_phase(VNPhase.TITLE)


func new_game() -> void:
	var m := modules()
	_reset_run()
	_set_phase(VNPhase.NEW_GAME)
	m.variables.reset_game()                                   # 1
	m.variables.apply_profile(m.saves.profile().get("variables", {}))   # 2
	m.scheduler.reset_history()                                # 3 (o RNG reproduzível é do M1-08)
	m.plugins.notify_game_started(true)                        # 4
	_emit_sys("sys.game_started", {"new_game": true})          # 5
	_enter_chapter(String(_project.get("start_chapter", "")))  # 6


func resume_from_save(state: Dictionary) -> void:
	var m := modules()
	_reset_run()
	_set_phase(VNPhase.LOAD_GAME)
	_backlog.assign(state.get("backlog", []))
	var chapter: Variant = state.get("chapter")
	if not (chapter is Dictionary) or not _bundle.get("chapters", {}).has(String(chapter.id)):
		# RT §8.4: capítulo que não existe mais → entra no start_chapter, com o histórico mantido.
		m.variables.exit_scene()
		m.variables.exit_chapter()
		_enter_chapter(String(_project.get("start_chapter", "")))
		return
	_chapter = String(chapter.id)
	_chapter_entered_at = int(chapter.get("entered_at", 0))
	var scene: Variant = state.get("scene")
	if not (scene is Dictionary) or not _bundle.get("scenes", {}).has(String(scene.id)):
		m.variables.exit_scene()    # cena que não existe mais: volta ao ponto de seleção (RT §8.4)
		_selection_point("")
		return
	_load_scene(String(scene.id))
	for h in scene.get("used_hotspots", []):
		_used_hotspots.append(String(h))
	var node := String(scene.get("node", ""))
	if not _index.has(node):
		# RT §8.4: nó que não existe mais → recomeça a cena do início, com scene.* zeradas.
		_used_hotspots.clear()
		m.variables.exit_scene()
		m.variables.enter_scene(_scene)
		node = String(_scene_def.get("start", ""))
	_set_phase(VNPhase.SCENE_RUNNING)
	_resuming = true
	_run(node)
	_resuming = false


func return_to_title() -> void:
	var m := modules()
	var was_in_game := VNPhase.is_in_game(_phase)
	if _phase == VNPhase.ACTIVITY:
		m.plugins.cancel_activity(VNPluginHost.STATUS_CANCELLED)   # handle encerrado sem outcome (RT §5.3 passo 7)
	if was_in_game:
		m.plugins.notify_game_ended()   # (escolha) o jogo da sessão termina para os plugins, sem sys.game_ended
	_teardown_scene_state()
	m.variables.exit_chapter()
	_reset_run()
	_set_phase(VNPhase.TITLE)


func set_paused(paused: bool) -> void:
	_paused = paused
	if not paused and _wait_pending_resume:
		_wait_pending_resume = false
		_finish_wait()


func is_paused() -> bool:
	return _paused


## Zera o que é da partida (não toca nas variáveis: quem chama decide).
func _reset_run() -> void:
	_chapter = ""
	_scene = ""
	_node = ""
	_scene_def = {}
	_index = {}
	_waiting = &""
	_backlog.clear()
	_used_hotspots.clear()
	_options.clear()
	_exit_option = {}
	_wait_token += 1
	_wait_pending_resume = false


## Tira o palco, o áudio e os eventos pendentes (fim de jogo, volta ao título).
func _teardown_scene_state() -> void:
	var m := modules()
	m.events.clear_queue()
	m.stage.clear()
	m.audio.stop_all()
	m.variables.exit_scene()


# --- Capítulos (RT §3.2–§3.3) -------------------------------------------------------------------

func _enter_chapter(chapter_id: String) -> void:
	var m := modules()
	if not _bundle.get("chapters", {}).has(chapter_id):
		_content_error(&"CHAPTER_NOT_FOUND", "capítulo inexistente: %s" % chapter_id)
		_game_end(null)
		return
	_set_phase(VNPhase.CHAPTER_ENTER)
	_chapter = chapter_id
	_chapter_entered_at = m.scheduler.selection_count()
	m.variables.enter_chapter(chapter_id)                      # 1
	var entries := m.scheduler.enter_chapter(chapter_id)       # 2 e 3 (sys.chapter.id vem do Variable Manager)
	_emit_sys("sys.chapter_started", {"chapter": chapter_id, "entries": entries})   # 4
	var entry: Variant = _bundle.chapters[chapter_id].get("entry_scene")
	if entry != null and not String(entry).is_empty():          # 5
		m.scheduler.start_direct(String(entry))
		_start_scene(String(entry))
	else:
		_selection_point("")


func _chapter_exit() -> void:
	var m := modules()
	_set_phase(VNPhase.CHAPTER_EXIT)
	m.scheduler.complete_chapter(_chapter)                      # 1
	_emit_sys("sys.chapter_ended", {"chapter": _chapter})
	var next := m.scheduler.next_chapter(_chapter)              # 2, antes de descartar chapter.*
	m.variables.exit_chapter()                                  # 3
	if next.is_empty():
		_game_end(null)
	else:
		_enter_chapter(next)


## Fim de jogo (RT §3.4). [param ending] é o id do final ou [code]null[/code].
func _game_end(ending: Variant) -> void:
	var m := modules()
	_set_phase(VNPhase.GAME_END)
	var ending_id := "" if ending == null else String(ending)
	if not ending_id.is_empty():
		m.saves.record_ending(ending_id)
		m.state.set_system_value("sys.endings.%s" % ending_id, true)
	m.saves.flush_profile()    # na hora, sem esperar o debounce (RT §3.4, §8.5)
	_emit_sys("sys.game_ended", {"ending": null if ending_id.is_empty() else ending_id})
	m.plugins.notify_game_ended()
	_teardown_scene_state()
	m.variables.exit_chapter()
	_reset_run()
	_set_phase(VNPhase.TITLE)


# --- Ponto de seleção e cenas (RT §4.1, §5.1, §5.4) ---------------------------------------------

func _selection_point(request: String) -> void:
	var m := modules()
	_set_phase(VNPhase.SELECTION_POINT)
	_scene = ""
	_node = ""
	_waiting = &""
	m.saves.autosave(VNSaveManager.AUTOSAVE_SETTINGS)
	var decision := m.scheduler.select(request)
	match StringName(decision.get("action", "")):
		VNSceneScheduler.ACTION_START_SCENE:
			_start_scene(String(decision.chosen))
		VNSceneScheduler.ACTION_EXIT_CHAPTER:
			_chapter_exit()
		_:
			_game_end(null)    # end_game (on_exhausted: end_game ou nenhum próximo capítulo)


func _load_scene(scene_id: String) -> void:
	_scene = scene_id
	_scene_def = _bundle.scenes[scene_id]
	_index.clear()
	var nodes: Array = _scene_def.get("nodes", [])
	for i in nodes.size():
		_index[String(nodes[i].id)] = i
	_used_hotspots.clear()


func _start_scene(scene_id: String) -> void:
	var m := modules()
	if not _bundle.get("scenes", {}).has(scene_id):
		_content_error(&"SCENE_NOT_FOUND", "cena inexistente: %s" % scene_id)
		_selection_point("")
		return
	_set_phase(VNPhase.SCENE_RUNNING)
	_load_scene(scene_id)
	m.variables.enter_scene(scene_id)                           # 1 (sys.scene.id vem do Variable Manager)
	_emit_sys("sys.scene_started", {"scene": scene_id, "chapter": _chapter})   # 2
	_save_window = SAVE_SCENE_START
	m.saves.autosave(VNSaveManager.AUTOSAVE_SCENE_START)        # RT §8.1: antes do primeiro nó
	_save_window = &""
	_run(String(_scene_def.get("start", "")))                   # 3


func _finish_scene(then: Variant, ending: Variant = null) -> void:
	var m := modules()
	var done := _scene
	m.scheduler.complete_scene(done)                            # 1
	_emit_sys("sys.scene_ended", {"scene": done, "chapter": _chapter})   # 2
	m.variables.exit_scene()                                    # 3
	m.stage.clear_interaction()
	_scene = ""
	_node = ""
	_scene_def = {}
	_index.clear()
	_waiting = &""
	if then is Dictionary:                                      # 4
		_selection_point(String(then.get("scene", "")))
		return
	match String(then):
		"end_chapter":
			_chapter_exit()
		"end_game":
			_game_end(ending)
		_:
			_selection_point("")


# --- Laço de nós (RT §5.2) ----------------------------------------------------------------------

## Executa nós a partir de [param node_id] até um bloqueante, o fim da cena ou um erro.
func _run(node_id: String) -> void:
	var m := modules()
	var cur := node_id
	var count := 0
	while true:
		if cur.is_empty():
			_finish_scene("schedule")   # fim do grafo sem [code]end[/code] (RT §4.4)
			return
		if not _index.has(cur):
			_content_error(&"NODE_NOT_FOUND", "nó inexistente: %s" % cur)
			_finish_scene("schedule")
			return
		count += 1
		if count > MAX_INSTANT_NODES:
			_content_error(&"INSTANT_LOOP", "mais de %d nós instantâneos seguidos (jump circular?)" % MAX_INSTANT_NODES)
			_finish_scene("schedule")
			return
		var node: Dictionary = _scene_def.nodes[_index[cur]]
		if _skipped_by_filter(node):    # RT §5.5: nem evento de entrada, nem palco
			cur = _next_of(node)
			continue
		_node = cur
		node_entered.emit(_scene, cur, StringName(node.get("type", "")))
		var result := _exec(node)
		m.events.drain()
		if result == _BLOCK or result == _STOP:
			return
		cur = result


## O nó que segue [param node]: [code]next[/code] ou o seguinte do array ("" no último).
func _next_of(node: Dictionary) -> String:
	var n: Variant = node.get("next")
	if n != null and not String(n).is_empty():
		return String(n)
	var i: int = _index[String(node.id)] + 1
	var nodes: Array = _scene_def.nodes
	return String(nodes[i].id) if i < nodes.size() else ""


func _goto_or_next(node: Dictionary, target: Variant) -> String:
	return String(target) if target != null and not String(target).is_empty() else _next_of(node)


func _exec(node: Dictionary) -> String:
	match String(node.get("type", "")):
		"line":
			return _exec_line(node)
		"choice", "interact":
			return _exec_choice(node)
		"effects":
			return _exec_effects(node)
		"branch":
			return _exec_branch(node)
		"jump":
			return _goto_or_next(node, node.get("goto"))
		"background":
			modules().stage.set_background(node)
		"show":
			modules().stage.show_character(node)
		"hide":
			modules().stage.hide_character(node)
		"audio":
			modules().audio.run_audio_node(node)
		"wait":
			return _exec_wait(node)
		"emit":
			return _exec_emit(node)
		"plugin":
			return _exec_plugin(node)
		"end":
			_finish_scene(node.get("then", "schedule"), node.get("ending"))
			return _STOP
		_:
			_content_error(&"UNKNOWN_NODE_TYPE", "tipo de nó desconhecido: %s" % node.get("type"))
	return _next_of(node)


# --- line ---------------------------------------------------------------------------------------

func _exec_line(node: Dictionary) -> String:
	_waiting = _WAIT_LINE
	_present_line(node, not _resuming)
	return _BLOCK


## Mostra a fala. [param record] controla o backlog e o [code]seen_text[/code] (uma vez por fala).
func _present_line(node: Dictionary, record: bool) -> void:
	var m := modules()
	var path := "%s/%s" % [_scene, node.id]
	var censored := _filter and node.has("censored_text")
	var raw := String(node.get("censored_text") if censored else node.get("text", ""))
	var shown := _t(path + "/censored" if censored else path, raw)
	m.stage.show_line({
		"text": shown, "speaker": node.get("speaker"), "voice": node.get("voice"),
		"expression": node.get("expression"), "text_path": path,
	})
	if record:
		_backlog.append({"path": path, "speaker": node.get("speaker"), "vars": _interpolated_values(raw)})
		if _backlog.size() > BACKLOG_LIMIT:
			_backlog.pop_front()
		m.saves.mark_text_seen(path)   # sempre o caminho do texto original (RT §5.5)


## Valores das variáveis interpoladas em [param raw], para o backlog (RT §8.2).
func _interpolated_values(raw: String) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.length():
		if raw.substr(i, 2) in ["{{", "}}"]:
			i += 2
		elif raw[i] == "{":
			var close := raw.find("}", i)
			if close < 0:
				break
			var id := raw.substr(i + 1, close - i - 1).strip_edges()
			var v: Variant = _read_variable(id)
			if v != null:
				out[id] = v
			i = close + 1
		else:
			i += 1
	return out


func advance() -> void:
	if _paused or _phase != VNPhase.SCENE_RUNNING:
		return
	var node: Dictionary = _scene_def.nodes[_index[_node]] if _index.has(_node) else {}
	if _waiting == _WAIT_LINE:
		_waiting = &""
		_run(_next_of(node))
	elif _waiting == _WAIT_TIMER and bool(node.get("skippable", true)):
		_finish_wait()


# --- choice e interact --------------------------------------------------------------------------

func _exec_choice(node: Dictionary) -> String:
	if not _present_choice(node):
		return _next_of(node)    # sem opção visível: segue next (DM §8.2)
	return _BLOCK


## Avalia [code]visible_if[/code]/[code]enabled_if[/code] uma vez e mostra as opções. Falso se nenhuma é visível.
func _present_choice(node: Dictionary) -> bool:
	var m := modules()
	var is_interact := String(node.type) == "interact"
	var items: Array = node.get("hotspots" if is_interact else "options", [])
	var shown: Array[Dictionary] = []
	_options.clear()
	_exit_option = {}
	for item in items:
		if is_interact and item.get("once", false) and _used_hotspots.has(String(item.id)):
			continue
		if not _cond(item.get("visible_if")):
			continue
		var enabled := _cond(item.get("enabled_if"))
		var base := "%s/%s/%s" % [_scene, node.id, item.id]
		var label := _option_text(item, base, "label" if is_interact else "text")
		var entry := {"id": String(item.id), "text": label, "enabled": enabled}
		if is_interact:
			entry = {"id": String(item.id), "label": label, "area": item.get("area"), "cursor": item.get("cursor"), "highlight": item.get("highlight"), "enabled": enabled}
		shown.append(entry)
		_options[String(item.id)] = {"option": item, "enabled": enabled}
	if is_interact and node.get("exit") is Dictionary:
		var ex: Dictionary = node.exit
		_exit_option = {"id": "exit", "label": _option_text(ex, "%s/%s/exit" % [_scene, node.id], "label"), "enabled": true}
		_options["exit"] = {"option": ex, "enabled": true}
	if shown.is_empty() and _exit_option.is_empty():
		return false
	_waiting = _WAIT_INTERACT if is_interact else _WAIT_CHOICE
	var prompt_path := "%s/%s" % [_scene, node.id]
	var prompt_raw := String(node.get("censored_prompt") if _filter and node.has("censored_prompt") else node.get("prompt", ""))
	var prompt := _t(prompt_path + "/censored" if _filter and node.has("censored_prompt") else prompt_path, prompt_raw) if not prompt_raw.is_empty() else ""
	if is_interact:
		m.stage.show_hotspots(shown, _exit_option)
	else:
		m.stage.show_choices(prompt, shown)
	return true


func _option_text(item: Dictionary, base_path: String, key: String) -> String:
	var censored := _filter and item.has("censored_" + key)
	var raw := String(item.get("censored_" + key) if censored else item.get(key, ""))
	return _t(base_path + "/censored" if censored else base_path, raw)


func _on_option_selected(option_id: String) -> void:
	choose(option_id)


func choose(option_id: String) -> VNResult:
	var m := modules()
	if _paused or _phase != VNPhase.SCENE_RUNNING or _waiting not in [_WAIT_CHOICE, _WAIT_INTERACT]:
		return VNResult.failure(VNErrors.INVALID_STATE, "nenhuma escolha em andamento")
	if not _options.has(option_id):
		return VNResult.failure(VNErrors.INVALID_STATE, "opção desconhecida ou invisível: %s" % option_id)
	if not _options[option_id].enabled:
		return VNResult.failure(VNErrors.INVALID_STATE, "opção desabilitada: %s" % option_id)
	var node: Dictionary = _scene_def.nodes[_index[_node]]
	var item: Dictionary = _options[option_id].option
	var is_exit: bool = option_id == "exit" and node.get("exit") is Dictionary and item == node.exit
	_waiting = &""
	_options.clear()
	m.stage.clear_interaction()
	if not is_exit:
		if String(node.type) == "interact" and item.get("once", false) and not _used_hotspots.has(option_id):
			_used_hotspots.append(option_id)
		# Efeitos da opção e record numa única transação; se falhar por restrição, a cena segue (RT §5.2).
		var value: Variant = item.get("value", option_id)
		var extra: Array[Dictionary] = []
		if node.get("record") != null:
			extra.append({"op": "set", "variable": String(node.record), "value": value})
		var effects: Array = item.get("effects", [])
		if not effects.is_empty() or not extra.is_empty():
			_report_effects(m.state.apply_effects(effects, {}, VNStateManager.CALLER_CONTENT, extra))
		_emit_sys("sys.choice_made", {"scene": _scene, "node": String(node.id), "option": option_id, "value": value})
	_run(_goto_or_next(node, item.get("goto")))
	return VNResult.success()


# --- effects, branch, emit ----------------------------------------------------------------------

func _exec_effects(node: Dictionary) -> String:
	var r := modules().state.apply_effects(node.get("effects", []))
	if r.ok:
		return _next_of(node)
	if r.error == VNErrors.CONSTRAINT_VIOLATION:    # lógica de jogo: vai para on_fail, se houver (DM §6.2)
		return _goto_or_next(node, node.get("on_fail"))
	_report_effects(r)
	return _next_of(node)


func _exec_branch(node: Dictionary) -> String:
	for c in node.get("cases", []):
		if _cond(c.get("conditions")):
			return _goto_or_next(node, c.get("goto"))
	return _goto_or_next(node, node.get("else"))


func _exec_emit(node: Dictionary) -> String:
	var m := modules()
	var payload := {}
	for key in node.get("payload", {}):
		var r := m.conditions.evaluate_expression(node.payload[key], {}, &"", true)
		if not r.ok:
			_content_error(r.error, r.message)
			return _next_of(node)    # RT §9: em release o nó é pulado
		payload[key] = r.value
	m.events.emit(String(node.event), payload, VNEventBus.SOURCE_STORY)
	return _next_of(node)


# --- wait ---------------------------------------------------------------------------------------

func _exec_wait(node: Dictionary) -> String:
	var seconds := float(node.get("seconds", 0.0))
	var tree := Engine.get_main_loop() as SceneTree
	if seconds <= 0.0 or tree == null:
		return _next_of(node)
	_waiting = _WAIT_TIMER
	_wait_token += 1
	tree.create_timer(seconds).timeout.connect(_on_wait_timeout.bind(_wait_token))
	return _BLOCK


func _on_wait_timeout(token: int) -> void:
	if token != _wait_token or _waiting != _WAIT_TIMER:
		return
	if _paused:
		_wait_pending_resume = true    # a pausa congela o tempo da cena; retoma ao despausar
		return
	_finish_wait()


func _finish_wait() -> void:
	_wait_token += 1
	_waiting = &""
	_run(_next_of(_scene_def.nodes[_index[_node]]))


# --- plugin (RT §5.3) ---------------------------------------------------------------------------

func _exec_plugin(node: Dictionary) -> String:
	var m := modules()
	var activity := String(node.activity)
	var ns := StringName(activity.get_slice(".", 0))
	if not m.plugins.is_loaded(ns):    # 1: ausente, desabilitado ou faulted
		_content_error(&"PLUGIN_UNAVAILABLE", "plugin indisponível: %s" % ns)
		return _goto_or_next(node, node.get("on_error"))
	_save_window = SAVE_ACTIVITY       # 3: autosave de segurança, sempre (RT §8.1)
	m.saves.autosave(VNSaveManager.AUTOSAVE_ACTIVITY)
	_save_window = &""
	_emit_sys("sys.activity_started", {"activity": activity, "scene": _scene, "node": String(node.id)})   # 4
	_set_phase(VNPhase.ACTIVITY)
	var r := m.plugins.start_activity(StringName(activity), node.get("params", {}), VNPluginHost.MODE_STORY)
	if not r.ok:
		_set_phase(VNPhase.SCENE_RUNNING)
		_content_error(r.error, r.message)
		return _goto_or_next(node, node.get("on_error"))
	return _BLOCK


func _on_activity_ended(status: StringName, outcome: StringName, payload: Dictionary) -> void:
	if _phase != VNPhase.ACTIVITY or not _index.has(_node) or status == VNPluginHost.STATUS_CANCELLED:
		return    # modo livre, ou atividade cancelada pelo return_to_title (sem outcome nem desvio)
	var m := modules()
	var node: Dictionary = _scene_def.nodes[_index[_node]]
	var on_result: Dictionary = node.get("on_result", {})
	_set_phase(VNPhase.SCENE_RUNNING)
	var target: String
	match status:
		VNPluginHost.STATUS_COMPLETED, VNPluginHost.STATUS_SKIPPED:
			var skipped := status == VNPluginHost.STATUS_SKIPPED
			if not skipped and not on_result.get("effects", []).is_empty():    # no pulo, só o desvio (RT §5.3 passo 7)
				_report_effects(m.state.apply_effects(on_result.effects, {"result": payload}))
			_emit_sys("sys.activity_completed", {"activity": String(node.activity), "outcome": String(outcome), "skipped": skipped})
			target = _goto_or_next(node, on_result.get("outcomes", {}).get(String(outcome)))
		_:    # failed (plugin com erro ou timeout) ou cancelled sem o jogador ter saído
			_content_error(&"ACTIVITY_FAILED", "atividade %s terminou com %s" % [node.activity, status])
			target = _goto_or_next(node, node.get("on_error"))
	_run(target)


# --- Modo stream (RT §5.5) ----------------------------------------------------------------------

## Passo [code]skip[/code] com o modo ligado ou [code]only[/code] com ele desligado: não executa.
func _skipped_by_filter(node: Dictionary) -> bool:
	match String(node.get("censor", "")):
		"skip":
			return _filter
		"only":
			return not _filter
	return false


func content_filter_changed(enabled: bool) -> void:
	_filter = enabled
	if _phase != VNPhase.SCENE_RUNNING or not _index.has(_node):
		return
	var node: Dictionary = _scene_def.nodes[_index[_node]]
	# A fala atual é mostrada de novo no novo modo, sem duplicar o backlog; o resto vale do próximo nó.
	if _waiting == _WAIT_LINE:
		_present_line(node, false)
	elif _waiting in [_WAIT_CHOICE, _WAIT_INTERACT]:
		_present_choice(node)


# --- Utilitários --------------------------------------------------------------------------------

func _emit_sys(name: String, payload: Dictionary) -> void:
	var m := modules()
	m.events.emit(name, payload, VNEventBus.SOURCE_SYS)
	m.events.drain()


## Condição com a escrita bloqueada durante a avaliação (RT §6.2, verificação 2). Erro vale falso (RT §9).
func _cond(conditions: Variant) -> bool:
	if conditions == null:
		return true
	var m := modules()
	m.state.set_evaluating(true)
	var r := m.conditions.evaluate_conditions(conditions)
	m.state.set_evaluating(false)
	if not r.ok:
		_content_error(r.error, r.message)
		return false
	return bool(r.value)


## Resultado de efeitos: restrição é lógica de jogo, o resto é erro de conteúdo (RT §9).
func _report_effects(r: VNResult) -> void:
	if not r.ok and r.error != VNErrors.CONSTRAINT_VIOLATION:
		_content_error(r.error, r.message)


func _content_error(code: StringName, message: String, context: Dictionary = {}) -> void:
	var ctx := {"scene": _scene, "node": _node}
	ctx.merge(context, true)
	push_warning("[%s] %s (cena %s, nó %s)" % [code, message, _scene, _node])
	content_error.emit(code, message, ctx)
