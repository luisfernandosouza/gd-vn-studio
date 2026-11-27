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

## O jogador trocou o idioma do jogo (Plugin SDK §5.7). [VNI18nAPI] repassa.
signal locale_changed(locale: String)


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


# --- Idioma, aparência e modo stream (M3-03; Plugin SDK §5.6–§5.7) -----------

## Idioma atual do jogo, ex.: [code]"pt-BR"[/code].
func get_locale() -> String:
	return "en"


## Texto-fonte de uma chave [code]runtime/…[/code] do plugin, na ordem do
## Plugin SDK §5.7: tradução do projeto ([code]plugin/<namespace>/runtime/…[/code]
## em [code]locales/[/code]), [code]plugin_locales[locale][/code],
## [code]plugin_locales[default_locale][/code]. Vazio se nenhuma tem a chave
## (o [VNI18nAPI] usa o [code]fallback[/code] do código).
func lookup_text(_plugin_namespace: StringName, _key: String) -> String:
	return ""


## Interpola [param args] em [param template] como o texto do projeto (RT §12.1):
## [code]{nome}[/code], [code]{{[/code] e [code]}}[/code] literais, números pela
## tabela do idioma, marcação do DM §9.1. O Plugin Host usa o formatador do
## runtime; a implementação padrão cobre só a troca de chaves e as chaves literais
## (números com [code]str()[/code]).
func format_text(template: String, args: Dictionary) -> String:
	var out := ""
	var i := 0
	var n := template.length()
	while i < n:
		var c := template[i]
		if c == "{" and i + 1 < n and template[i + 1] == "{":
			out += "{"
			i += 2
		elif c == "}" and i + 1 < n and template[i + 1] == "}":
			out += "}"
			i += 2
		elif c == "{":
			var close := template.find("}", i + 1)
			var key := template.substr(i + 1, close - i - 1) if close > 0 else ""
			if close > 0 and args.has(key):
				out += str(args[key])
				i = close + 1
			else:
				out += c
				i += 1
		else:
			out += c
			i += 1
	return out


## Modo stream ligado (RT §5.5). Na edição censurada, sempre [code]true[/code].
func content_filter_enabled() -> bool:
	return false


## [code]project.json → settings.resolution[/code].
func theme_resolution() -> Vector2i:
	return Vector2i(1920, 1080)


## [param role]: [code]&"dialogue"[/code], [code]&"name"[/code], [code]&"ui"[/code].
func theme_font(_role: StringName) -> Font:
	return null


func theme_font_size(_role: StringName) -> int:
	return 0


## [param role]: [code]&"text"[/code], [code]&"accent"[/code], [code]&"panel"[/code], [code]&"disabled"[/code].
func theme_color(_role: StringName) -> Color:
	return Color.WHITE


# --- RNG (RT §12.2) -----------------------------------------------------------

## Fluxo de [code]ctx.rng[/code] do plugin. Com [code]settings.reproducible_rng[/code],
## o host devolve [code]VNRandom.new(VNGameRng.plugin_stream(namespace))[/code]
## (PCG32 do runtime, M1-08); sem ela, o RNG comum do motor (o padrão).
func create_rng(_plugin_namespace: StringName) -> VNRandom:
	return VNRandom.new()


# --- Personagens, assets, áudio e overlays (Plugin SDK §5.6) ------------------

## [code]{ id, name (localizado), color, expressions }[/code], ou vazio se não existe.
func character_data(_character_id: String) -> Dictionary:
	return {}


func character_ids() -> PackedStringArray:
	return PackedStringArray()


## O asset foi escolhido pelo autor num campo [code]vn-asset[/code] da config ou
## dos params do plugin: pode ser carregado e tocado sem [code]assets.read[/code]
## (Plugin SDK §4.4).
func is_author_chosen_asset(_asset_id: String) -> bool:
	return false


## Carrega um asset do projeto já pelo filtro do modo stream (RT §5.5):
## [code]replace_with[/code] devolve a substituta, [code]hide[/code] devolve
## [code]null[/code], assim como um id inexistente.
func load_asset(_asset_id: String) -> Resource:
	return null


## Toca [param asset] (id do projeto, com o filtro do modo stream, ou
## [code]res://vn_plugins/<ns>/…[/code]) no canal [code]sfx[/code] ou
## [code]ambient[/code]. [code]null[/code] se não toca (asset oculto pelo filtro,
## inexistente). O runtime para os sons do plugin ao fim de cada atividade.
func play_sound(_asset: String, _channel: StringName, _volume: float) -> VNSound:
	return null


## Para todos os sons do plugin.
func stop_sounds(_fade: float) -> void:
	pass


## Põe [param node] na [code]CanvasLayer[/code] do plugin, acima da UI narrativa.
## [code]false[/code] se não foi possível.
func add_overlay(_node: Node) -> bool:
	return false


## Tira [param node] da camada do plugin (quem chama o libera).
func remove_overlay(_node: Node) -> void:
	pass
