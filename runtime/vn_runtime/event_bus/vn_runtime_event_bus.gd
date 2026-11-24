class_name VNRuntimeEventBus
extends VNEventBus
## Event Bus do runtime (RT §7; tarefa M1-09).
##
## [b]Fila.[/b] [method emit] confere o evento e o põe no fim da fila; nunca
## chama ouvintes na mesma pilha. [method drain] entrega em FIFO e não é
## reentrante: chamado de dentro de um ouvinte, devolve 0 e a drenagem em
## curso entrega o que foi enfileirado. Eventos emitidos por ouvintes durante a
## drenagem são "encadeados"; mais de [constant VNEventBus.MAX_CHAINED] numa
## mesma drenagem é erro (provável ciclo): a drenagem para, a fila é
## descartada e [signal delivery_failed] sai com [constant CHAIN_LIMIT].
##
## [b]Entrega.[/b] Para cada evento, na ordem: registra o nome em
## [code]history.events_since_selection[/code] (só [code]story.*[/code] e de
## plugin, RT §7.2), emite [signal VNEventBus.event_delivered] (Preview,
## [code]event.emitted[/code]) e chama os ouvintes cujo padrão casa, na ordem
## de assinatura. Uma assinatura feita durante a entrega de um evento só vale
## a partir do próximo; uma cancelada durante a entrega não recebe mais nada.
## Cada ouvinte recebe sua própria cópia do payload.
##
## [b]Conferências.[/b] Sempre: formato do nome ([code]common.schema.json →
## EventName[/code]), [code]sys.*[/code] só da tabela do RT §7.1 e com
## [code]source = "sys"[/code], [code]story.*[/code] só com
## [code]source = "story"[/code], e plugins fora de [code]sys[/code] e
## [code]story[/code]. Com [member validate_payloads] (padrão: build de debug,
## que inclui o Preview, RT §11): payload só com tipos JSON e conforme o schema
## declarado ([constant SYS_PAYLOAD_SCHEMAS] para [code]sys.*[/code],
## [code]project.events[/code] do bundle para [code]story.*[/code] e
## [method declare_plugin_events] para plugins). Evento sem schema declarado só
## tem os tipos conferidos (o aviso W015 é do validador). Em release, o payload
## não é conferido. Evento recusado não entra na fila.
##
## Erros de [method emit]: nome malformado, [code]sys.*[/code] fora da tabela e
## payload inválido dão [constant VNErrors.TYPE_MISMATCH]; namespace reservado
## com a origem errada dá [constant VNErrors.PERMISSION_DENIED]. Se o evento
## é de plugin estar no namespace dele e em [code]events.emits[/code] é
## conferido antes, pelo Plugin Host (Plugin SDK §7).

## A drenagem parou: [param error] traz o código ([constant CHAIN_LIMIT]) e
## a mensagem. Erro de conteúdo (RT §9): o Narrative Engine mostra o overlay
## em debug/Preview; em release só registra.
signal delivery_failed(error: VNResult)

## Código de [signal delivery_failed] quando passam de
## [constant VNEventBus.MAX_CHAINED] eventos encadeados.
const CHAIN_LIMIT := &"EVENT_CHAIN_LIMIT"

## Nome de evento ([code]common.schema.json → $defs/EventName[/code]).
const EVENT_NAME_PATTERN := "^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_.]*$"
## Padrão de assinatura ([code]plugin.schema.json → events.subscribes[/code]).
const SUBSCRIPTION_PATTERN := "^[a-z][a-z0-9_]*\\.([a-z0-9_.]*[a-z0-9_]|\\*|[a-z0-9_.]*\\.\\*)$"

## Schemas dos payloads [code]sys.*[/code] (RT §7.1). Os campos são os de
## [constant VNEventBus.SYS_EVENTS]; todos obrigatórios e nenhum a mais.
const SYS_PAYLOAD_SCHEMAS := {
	"sys.game_started": {"new_game": {"type": "boolean"}},
	"sys.chapter_started": {"chapter": {"type": "string"}, "entries": {"type": "integer", "minimum": 1}},
	"sys.chapter_ended": {"chapter": {"type": "string"}},
	"sys.scene_started": {"scene": {"type": "string"}, "chapter": {"type": "string"}},
	"sys.scene_ended": {"scene": {"type": "string"}, "chapter": {"type": "string"}},
	"sys.choice_made": {"scene": {"type": "string"}, "node": {"type": "string"}, "option": {"type": "string"}, "value": {"type": "string"}},
	"sys.activity_started": {"activity": {"type": "string"}, "scene": {"type": "string"}, "node": {"type": "string"}},
	"sys.activity_completed": {"activity": {"type": "string"}, "outcome": {"type": "string"}, "skipped": {"type": "boolean"}},
	"sys.game_saved": {"slot": {"type": "string"}, "autosave": {"type": "boolean"}},
	"sys.game_loaded": {"slot": {"type": "string"}},
	"sys.game_ended": {"ending": {"type": ["string", "null"]}},
	"sys.profile_reset": {},
	"sys.content_filter_changed": {"enabled": {"type": "boolean"}},
}

## Confere tipos JSON e schema dos payloads em [method emit]. Padrão: só no
## build de debug (inclui o Preview); o boot pode ligar ou desligar.
var validate_payloads: bool = OS.is_debug_build()

## Registra no log ([method @GlobalScope.push_error]) quando a drenagem para.
## Os testes desligam para checar o caminho de erro sem sujar o log.
var log_errors: bool = true

## Último erro de [signal delivery_failed], ou [code]null[/code].
var last_error: VNResult = null

var _queue: Array[Dictionary] = []          # { name, payload, source }
var _subs: Dictionary = {}                  # id → { pattern, callback, owner }; ordem de inserção
var _next_sub_id: int = 1
var _schemas: Dictionary = {}               # nome → schema do payload (story.* e plugins)
var _plugin_events: Dictionary = {}         # owner → PackedStringArray de nomes declarados
var _draining := false
var _name_re := RegEx.create_from_string(EVENT_NAME_PATTERN)
var _sub_re := RegEx.create_from_string(SUBSCRIPTION_PATTERN)


# --- Bundle e declarações ----------------------------------------------------

## Lê os schemas de [code]project.events[/code] ([code]bundle.schema.json[/code]).
## Recarregar o bundle troca os de [code]story.*[/code] e mantém os de plugins.
func load_bundle(bundle: Dictionary) -> void:
	for name in _schemas.keys():
		if String(name).begins_with("story."):
			_schemas.erase(name)
	var project: Dictionary = bundle.get("project", {})
	for ev in project.get("events", []):
		if ev is Dictionary and ev.has("name") and ev.get("payload") is Dictionary:
			_schemas[String(ev.name)] = ev.payload


## Registra os schemas de [code]events.emits[/code] do manifesto de um plugin
## (Plugin SDK §7). Chamado pelo Plugin Host ao carregar o plugin; chamar de
## novo para o mesmo [param owner] troca as declarações dele.
func declare_plugin_events(owner: StringName, emits: Array) -> void:
	for name in _plugin_events.get(owner, PackedStringArray()):
		_schemas.erase(name)
	var names := PackedStringArray()
	for ev in emits:
		if ev is Dictionary and ev.has("name"):
			names.append(String(ev.name))
			if ev.get("payload") is Dictionary:
				_schemas[String(ev.name)] = ev.payload
	_plugin_events[owner] = names


## Schema do payload de [param name], ou [code]null[/code] se não há.
func payload_schema(name: String) -> Variant:
	if SYS_PAYLOAD_SCHEMAS.has(name):
		var props: Dictionary = SYS_PAYLOAD_SCHEMAS[name]
		return {"type": "object", "required": props.keys(), "additionalProperties": false, "properties": props}
	return _schemas.get(name)


# --- Contrato ----------------------------------------------------------------

func emit(name: String, payload: Dictionary = {}, source: String = SOURCE_STORY) -> VNResult:
	var err := check(name, payload, source)
	if not err.ok:
		return err
	_queue.append({"name": name, "payload": payload.duplicate(true), "source": source})
	return VNResult.success()


## As conferências de [method emit], sem enfileirar.
func check(name: String, payload: Dictionary = {}, source: String = SOURCE_STORY) -> VNResult:
	if _name_re.search(name) == null:
		return VNResult.failure(VNErrors.TYPE_MISMATCH, "nome de evento inválido: \"%s\"" % name)
	var ns := name.get_slice(".", 0)
	if ns == "sys":
		if source != SOURCE_SYS:
			return VNResult.failure(VNErrors.PERMISSION_DENIED, "só o runtime emite %s (origem \"%s\")" % [name, source])
		if not SYS_EVENTS.has(name):
			return VNResult.failure(VNErrors.TYPE_MISMATCH, "evento sys.* fora da tabela do RT §7.1: %s" % name)
	elif source == SOURCE_SYS:
		return VNResult.failure(VNErrors.PERMISSION_DENIED, "a origem \"sys\" só emite sys.* (veio %s)" % name)
	elif ns == "story":
		if source != SOURCE_STORY:
			return VNResult.failure(VNErrors.PERMISSION_DENIED, "story.* é do conteúdo (origem \"%s\")" % source)
	elif source == SOURCE_STORY or source.is_empty():
		return VNResult.failure(VNErrors.PERMISSION_DENIED, "%s é de plugin; a origem deve ser o id do plugin" % name)
	if validate_payloads:
		var detail := VNPayloadSchema.json_type_error(payload)
		if detail.is_empty():
			var schema: Variant = payload_schema(name)
			if schema != null:
				detail = VNPayloadSchema.validate(payload, schema)
		if not detail.is_empty():
			return VNResult.failure(VNErrors.TYPE_MISMATCH, "%s: %s" % [name, detail])
	return VNResult.success()


## Devolve 0 se o padrão ou o callback forem inválidos.
func on(pattern: String, callback: Callable, owner: StringName = &"") -> int:
	if _sub_re.search(pattern) == null or not callback.is_valid():
		return 0
	var id := _next_sub_id
	_next_sub_id += 1
	_subs[id] = {"pattern": pattern, "callback": callback, "owner": owner}
	return id


func off(subscription_id: int) -> void:
	_subs.erase(subscription_id)


func off_owner(owner: StringName) -> void:
	for id in _subs.keys():
		if _subs[id].owner == owner:
			_subs.erase(id)


## Remove todas as assinaturas, de todos os donos (fim do runtime, testes).
## Ouvintes que capturam o próprio bus formam ciclo de [RefCounted]; isto o desfaz.
func off_all() -> void:
	_subs.clear()


func drain() -> int:
	if _draining:
		return 0
	_draining = true
	var delivered := 0
	var roots := _queue.size()   # o que já estava na fila não é encadeado
	while not _queue.is_empty():
		if delivered >= roots and delivered - roots >= MAX_CHAINED:
			_fail_chain(delivered, roots)
			break
		var ev: Dictionary = _queue.pop_front()
		delivered += 1
		_deliver(ev)
	_draining = false
	return delivered


func pending_count() -> int:
	return _queue.size()


func clear_queue() -> void:
	_queue.clear()


# --- Consultas ---------------------------------------------------------------

## Quantas assinaturas ativas (todas, ou só as de [param owner]).
func subscription_count(owner: Variant = null) -> int:
	if owner == null:
		return _subs.size()
	return _subs.values().filter(func(s): return s.owner == StringName(owner)).size()


## A drenagem está em curso?
func is_draining() -> bool:
	return _draining


## [param pattern] casa com [param name]? [code]*[/code] só no fim
## ([code]"story.*"[/code] casa com [code]"story.a.b"[/code], não com [code]"story"[/code]).
static func matches(pattern: String, name: String) -> bool:
	if pattern.ends_with("*"):
		return name.begins_with(pattern.left(-1))
	return pattern == name


# --- Interno -----------------------------------------------------------------

func _deliver(ev: Dictionary) -> void:
	var name: String = ev.name
	if not name.begins_with("sys."):
		var m := modules()
		if m != null and m.scheduler != null:
			m.scheduler.record_event(name)
	event_delivered.emit(name, ev.payload.duplicate(true), ev.source)
	for id in _subs.keys():   # cópia das chaves: assinaturas novas só no próximo evento
		var sub: Dictionary = _subs.get(id, {})
		if sub.is_empty() or not matches(sub.pattern, name):
			continue
		var cb: Callable = sub.callback
		if not cb.is_valid():   # dono liberado
			_subs.erase(id)
			continue
		cb.call(name, ev.payload.duplicate(true), ev.source)


func _fail_chain(delivered: int, roots: int) -> void:
	var dropped := _queue.size()
	var next_name: String = _queue[0].name
	_queue.clear()
	last_error = VNResult.failure(CHAIN_LIMIT,
		"mais de %d eventos encadeados numa drenagem (provável ciclo, RT §7.2): %d entregues, %d na fila inicial, %d descartados; o próximo seria %s"
		% [MAX_CHAINED, delivered, roots, dropped, next_name])
	if log_errors:
		push_error("Event Bus: " + last_error.message)
	delivery_failed.emit(last_error)
