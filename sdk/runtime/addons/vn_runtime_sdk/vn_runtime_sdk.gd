class_name VNRuntimeSDK
extends RefCounted
## Constantes e utilitários do Runtime SDK (Plugin SDK §4.2, §5).
##
## O addon é copiado para cada projeto de plugin por [code]vnplugin doctor --fix[/code]
## e vai junto do runtime ([code]res://addons/vn_runtime_sdk/[/code]). Ele não depende
## de nenhuma classe do runtime: as fachadas ([VNNarrativeAPI], [VNEventAPI],
## [VNSceneAPI]…) falam só com uma [VNPluginBridge], que o Plugin Host do runtime
## implementa (M3-01) e que o [code]VNTestHarness[/code] imita (M3-07).

## Versão do Runtime SDK (SemVer próprio, ADD §10; [code]sdk.runtime[/code] do manifesto).
const VERSION := "1.0.0-dev"

# --- Capacidades de runtime (Plugin SDK §4.2) --------------------------------

const CAP_VARIABLES_READ := &"variables.read"
const CAP_VARIABLES_WRITE := &"variables.write"
const CAP_TRANSACTIONS := &"transactions"
const CAP_EVENTS_EMIT := &"events.emit"
const CAP_EVENTS_SUBSCRIBE := &"events.subscribe"
const CAP_CHARACTERS_READ := &"characters.read"
const CAP_SCENES_REQUEST := &"scenes.request"
const CAP_SAVE_DATA := &"save.data"
const CAP_PROFILE_DATA := &"profile.data"
const CAP_ASSETS_READ := &"assets.read"
const CAP_AUDIO_PLAY := &"audio.play"
const CAP_UI_OVERLAY := &"ui.overlay"
const CAP_INPUT_CAPTURE := &"input.capture"

const CAPABILITIES: Array[StringName] = [
	CAP_VARIABLES_READ, CAP_VARIABLES_WRITE, CAP_TRANSACTIONS, CAP_EVENTS_EMIT,
	CAP_EVENTS_SUBSCRIBE, CAP_CHARACTERS_READ, CAP_SCENES_REQUEST, CAP_SAVE_DATA,
	CAP_PROFILE_DATA, CAP_ASSETS_READ, CAP_AUDIO_PLAY, CAP_UI_OVERLAY, CAP_INPUT_CAPTURE,
]

# --- Códigos de erro de VNResult (RT §6.2, Plugin SDK §5.2, §6.1) -------------
# Os mesmos valores de VNErrors do runtime; repetidos aqui porque o addon roda
# sozinho nos projetos de plugin.

const WRONG_THREAD := &"WRONG_THREAD"
const INVALID_STATE := &"INVALID_STATE"
const VARIABLE_NOT_FOUND := &"VARIABLE_NOT_FOUND"
const READ_ONLY := &"READ_ONLY"
const SCOPE_INACTIVE := &"SCOPE_INACTIVE"
const PERMISSION_DENIED := &"PERMISSION_DENIED"
const TYPE_MISMATCH := &"TYPE_MISMATCH"
const OUT_OF_RANGE := &"OUT_OF_RANGE"
const CONSTRAINT_VIOLATION := &"CONSTRAINT_VIOLATION"
const CONFLICT := &"CONFLICT"

## Maior inteiro exato (RT §12.1).
const MAX_SAFE_INTEGER := 9007199254740991


## A chamada vem da thread principal do Godot (RT §6.1, verificação 1 do §6.2).
static func on_main_thread() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()


## Expande o atalho [code]~chave[/code] para [code]plugin.<namespace>.chave[/code]
## (Plugin SDK §5.3). Outros ids voltam como estão.
static func qualify(id: String, plugin_namespace: StringName) -> String:
	if id.begins_with("~"):
		return "plugin.%s.%s" % [plugin_namespace, id.substr(1)]
	return id


## A variável é do próprio plugin ([code]plugin.<namespace>.*[/code]); essas não
## precisam de capacidade (Plugin SDK §4.2).
static func is_own_variable(id: String, plugin_namespace: StringName) -> bool:
	return id.begins_with("plugin.%s." % plugin_namespace)


## Padrão de evento válido: nome com pontos, [code]*[/code] só no fim
## ([code]"story.*"[/code], [code]"sys.scene_ended"[/code], [code]"*"[/code]; Plugin SDK §5.4, §7).
static func is_valid_event_pattern(pattern: String) -> bool:
	if pattern.is_empty():
		return false
	var star := pattern.find("*")
	if star >= 0 and star != pattern.length() - 1:
		return false
	if star > 0 and pattern[star - 1] != ".":
		return false
	return true


## [param name] casa com [param pattern] (prefixo antes do [code]*[/code] final, ou igual).
static func event_matches(pattern: String, name: String) -> bool:
	if pattern.ends_with("*"):
		return name.begins_with(pattern.substr(0, pattern.length() - 1))
	return name == pattern


## Quantidade numérica de [code]add[/code]/[code]subtract[/code]: um valor inteiro
## vai como [int], para não transformar variáveis [code]integer[/code] em
## [code]number[/code] (RT §12.1); o resto vai como [float].
static func normalize_amount(amount: float) -> Variant:
	if is_finite(amount) and amount == floorf(amount) and absf(amount) <= MAX_SAFE_INTEGER:
		return int(amount)
	return amount
