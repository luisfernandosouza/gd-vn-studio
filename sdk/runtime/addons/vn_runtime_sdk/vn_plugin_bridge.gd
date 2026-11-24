class_name VNPluginBridge
extends RefCounted
## Ponte entre as fachadas do Runtime SDK e quem hospeda o plugin.
##
## Uma ponte por plugin. No jogo, o Plugin Host do runtime (M3-01) a implementa
## sobre os módulos do M0-07: permissões em [code]VNPluginHost[/code]
## ([code]has_capability[/code], [code]can_read_variable[/code],
## [code]can_write_variable[/code], [code]can_request_scene[/code],
## [code]can_emit[/code]), escrita no State Manager com
## [code]VNStateManager.plugin_caller(namespace)[/code], eventos no Event Bus com
## o id do plugin como [code]source[/code] e [code]owner[/code], pedidos de cena
## em [code]VNSceneScheduler.request[/code]. Nos testes de plugin, o
## [code]VNTestHarness[/code] (M3-07) dá a sua.
##
## O addon não conhece as classes do runtime: só esta interface. A implementação
## padrão é a de um plugin sem nada concedido e sem jogo, e cada método é
## sobrescrito por quem hospeda. As fachadas conferem capacidade e thread antes
## de chamar a ponte; a ponte confere o resto (permissão efetiva, existência,
## estado do jogo, modo livre).

## Mudanças aplicadas pelo State Manager ([code]state_changed[/code], RT §6.4),
## sem filtro. [VNVariableAPI] repassa só as variáveis legíveis pelo plugin.
signal state_changed(changes: Array[Dictionary])


# --- Permissões (Plugin SDK §4) ----------------------------------------------

## A capacidade foi pedida e concedida (Plugin SDK §4.1–§4.2).
func has_capability(_capability: StringName) -> bool:
	return false


## Permissão efetiva de leitura de [param variable] (pedido ∩ concessão ∩ aceite,
## DM §4.6). Só é perguntada para variáveis de fora do namespace do plugin e
## depois de [code]variables.read[/code].
func can_read_variable(_variable: String) -> bool:
	return false


## O plugin pode emitir [param event_name]: no próprio namespace e declarado em
## [code]events.emits[/code] (Plugin SDK §7).
func can_emit(_event_name: String) -> bool:
	return false


## O plugin pode ouvir [param pattern] ([code]events.subscribes[/code] do
## manifesto, Plugin SDK §7). Padrão: sim.
func can_subscribe(_pattern: String) -> bool:
	return true


## A cena está em [code]grants.scenes[/code] do plugin (Plugin SDK §5.5).
func can_request_scene(_scene_id: String) -> bool:
	return false


## Chamada recusada por falta de permissão: registrar no log do plugin, avisar o
## Studio ([code]plugin.permission_denied { plugin, capability, call }[/code],
## RT §11) e contar para o estado [i]faulted[/i] (Plugin SDK §5.2, RT §9).
func permission_denied(_capability: StringName, _call: String) -> void:
	pass


## Erro do plugin que não é de permissão ([code]WRONG_THREAD[/code], uso
## inválido): registrar e contar para [i]faulted[/i] (RT §9).
func report_error(_error: StringName, _message: String) -> void:
	pass


## Escreve no log do plugin. [param level] é [code]&"debug"[/code],
## [code]&"info"[/code], [code]&"warn"[/code] ou [code]&"error"[/code].
func write_log(_level: StringName, _message: String) -> void:
	pass


# --- Variáveis (State Manager / Variable Manager; RT §6) ---------------------

## A variável existe no bundle (ids já qualificados).
func variable_exists(_variable: String) -> bool:
	return false


## Valor atual, ou [param fallback] (RT §6.2: leituras conferem 1, 3, 5 e permissão).
func read_value(_variable: String, fallback: Variant = null) -> Variant:
	return fallback


## Definição pública: [code]{ id, type, default, min?, max?, values?, max_length?, persistence }[/code],
## sem valores de outros escopos (Plugin SDK §5.3). Vazio se não existe.
func get_definition(_variable: String) -> Dictionary:
	return {}


## Valida e aplica, tudo ou nada, como uma transação do State Manager com o
## chamador [code]plugin:<namespace>[/code] (RT §6.1–§6.3). [param ops] no
## formato do DM §6.2 ([code]{ op, variable, value? }[/code], ids qualificados);
## [param expectations] são [code]{ variable, value }[/code]. Uma escrita
## isolada chega como transação de uma operação.
func commit(_ops: Array[Dictionary], _expectations: Array[Dictionary]) -> VNResult:
	return VNResult.failure(VNRuntimeSDK.INVALID_STATE, "sem jogo")


# --- Eventos (Event Bus; RT §7) ----------------------------------------------

## Enfileira o evento com [code]source[/code] = id do plugin (RT §7.2).
func emit_event(_name: String, _payload: Dictionary) -> VNResult:
	return VNResult.failure(VNRuntimeSDK.INVALID_STATE, "sem jogo")


## Assina [param pattern] com o plugin como dono; devolve o id (≥ 1) ou 0.
func subscribe(_pattern: String, _callback: Callable) -> int:
	return 0


func unsubscribe(_subscription_id: int) -> void:
	pass


# --- Cenas (Scene Scheduler; RT §4.3) ----------------------------------------

## Guarda o pedido para o próximo ponto de seleção (Plugin SDK §5.5).
func request_scene(_scene_id: String) -> VNResult:
	return VNResult.failure(VNRuntimeSDK.INVALID_STATE, "sem jogo")
