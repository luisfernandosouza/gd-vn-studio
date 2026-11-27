class_name VNBacklog
extends RefCounted
## Histórico de falas (tarefa M2-03; RT §5.2 "line", §8.2, §8.5; UI Spec §3.1
## [code]backlog_list[/code]; [code]save.schema.json → state.backlog[/code]).
##
## Guarda o caminho do texto e os valores interpolados, não o texto pronto:
## trocar de idioma ou atualizar o jogo se reflete no histórico (RT §8.2). O
## Narrative Engine (M1-11) usa esta classe: [method record] a cada fala
## mostrada e [method snapshot]/[method restore] no save. Quem desenha o
## histórico é o elemento [code]backlog_list[/code] do UI Manager, que lê
## [code]engine.snapshot().backlog[/code].

## Entradas guardadas no máximo (o runtime limita, o schema não fixa o valor).
## O preset [code]classic[/code] mostra até 200 ([code]backlog_list.max_items[/code]).
const DEFAULT_LIMIT := 200

var limit: int = DEFAULT_LIMIT
var _entries: Array[Dictionary] = []


## Registra uma fala. [param path] é o caminho do texto
## ([code]<cena>/<nó>[/code], ou [code]<cena>/<nó>/<opção>[/code] para a
## escolha feita); [param speaker] o id da personagem (vazio: narração);
## [param vars] os valores interpolados na hora da fala.
##
## Com [param redisplay], a fala só está sendo mostrada de novo (carregar um
## save, trocar o modo stream, RT §5.5 e §8.3 passo 7): se a última entrada já
## é esse caminho, nada é duplicado.
func record(path: String, speaker: String = "", vars: Dictionary = {}, redisplay: bool = false) -> void:
	if redisplay and not _entries.is_empty() and _entries[-1].path == path:
		return
	var e := {"path": path}
	if not speaker.is_empty():
		e["speaker"] = speaker
	if not vars.is_empty():
		e["vars"] = vars.duplicate(true)
	_entries.append(e)
	_trim()


func size() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()


## Cópia das entradas, da mais antiga à mais recente, no formato do save.
func snapshot() -> Array:
	return _entries.duplicate(true)


## As últimas [param count] entradas (Preview: [code]preview.get_state[/code]
## devolve 50, Preview Protocol §4).
func last(count: int) -> Array:
	var from := maxi(0, _entries.size() - count)
	return _entries.slice(from).duplicate(true)


## Restaura do save. Entradas sem [code]path[/code] são descartadas; o que
## passa do limite perde as mais antigas.
func restore(entries: Variant) -> void:
	_entries.clear()
	if entries is Array:
		for e in entries:
			if e is Dictionary and e.get("path") is String and not String(e.path).is_empty():
				var copy := {"path": String(e.path)}
				if e.get("speaker") is String and not String(e.speaker).is_empty():
					copy["speaker"] = String(e.speaker)
				if e.get("vars") is Dictionary and not (e.vars as Dictionary).is_empty():
					copy["vars"] = (e.vars as Dictionary).duplicate(true)
				_entries.append(copy)
	_trim()


func _trim() -> void:
	var excess := _entries.size() - maxi(1, limit)
	if excess > 0:
		_entries = _entries.slice(excess)
