class_name FakeEventBus
extends VNEventBus
## Dublê do Event Bus: fila FIFO entregue só em drain(), padrões com * no fim,
## registro no histórico do Scheduler para eventos que não são sys.*.

## Chamadas recebidas, na ordem: [{ "method": StringName, "args": Array }].
var calls: Array[Dictionary] = []


func _rec(method: StringName, args: Array = []) -> void:
	calls.append({"method": method, "args": args})


## Quantas vezes o método foi chamado.
func count_calls(method: StringName) -> int:
	return calls.filter(func(c): return c.method == method).size()

## Eventos entregues: [{ name, payload, source }].
var delivered: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _subs: Dictionary = {}   # id → { pattern, callback, owner }
var _next_id: int = 1


func emit(name: String, payload: Dictionary = {}, source: String = SOURCE_STORY) -> VNResult:
	_rec(&"emit", [name, payload, source])
	_queue.append({"name": name, "payload": payload, "source": source})
	return VNResult.success()


func on(pattern: String, callback: Callable, owner: StringName = &"") -> int:
	var id := _next_id
	_next_id += 1
	_subs[id] = {"pattern": pattern, "callback": callback, "owner": owner}
	return id


func off(subscription_id: int) -> void:
	_subs.erase(subscription_id)


func off_owner(owner: StringName) -> void:
	for id in _subs.keys():
		if _subs[id].owner == owner:
			_subs.erase(id)


func drain() -> int:
	var count := 0
	while not _queue.is_empty() and count < MAX_CHAINED:
		var ev: Dictionary = _queue.pop_front()
		count += 1
		delivered.append(ev)
		if not ev.name.begins_with("sys.") and modules() != null and modules().scheduler != null:
			modules().scheduler.record_event(ev.name)
		event_delivered.emit(ev.name, ev.payload, ev.source)
		for id in _subs.keys():
			var sub: Dictionary = _subs.get(id, {})
			if not sub.is_empty() and _matches(sub.pattern, ev.name):
				sub.callback.call(ev.name, ev.payload, ev.source)
	return count


func pending_count() -> int:
	return _queue.size()


func clear_queue() -> void:
	_queue.clear()


## Nomes dos eventos entregues, na ordem.
func delivered_names() -> PackedStringArray:
	return PackedStringArray(delivered.map(func(e): return e.name))


static func _matches(pattern: String, name: String) -> bool:
	if pattern.ends_with("*"):
		return name.begins_with(pattern.left(-1))
	return pattern == name
