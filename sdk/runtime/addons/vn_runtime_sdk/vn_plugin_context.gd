class_name VNPluginContext
extends RefCounted
## Contexto entregue ao plugin em [method VNRuntimePlugin._vn_init] (Plugin SDK §5.2).
##
## O Plugin Host monta um contexto por plugin com [method create]. Todos os
## serviços existem sempre; os que dependem de uma capacidade não concedida não
## fazem nada (ver [VNPluginService]).
##
## Diferença de nome em relação ao texto original da spec: o namespace fica em
## [member plugin_namespace], porque [code]namespace[/code] é palavra reservada do
## GDScript (Plugin SDK §5.2).

var plugin_id: StringName = &""          ## "vnstudio.fishing"
var plugin_namespace: StringName = &""   ## "fishing"
var config: Dictionary = {}              ## config do projeto, já validada e com defaults (Plugin SDK §8)
var narrative: VNNarrativeAPI            ## variáveis, eventos e transações (§5.3)
var characters: VNCharacterAPI          ## characters.read (§5.6)
var scenes: VNSceneAPI                   ## scenes.request (§5.5)
var assets: VNAssetAPI                   ## assets.read (§5.6)
var audio: VNAudioAPI                    ## audio.play (§5.6)
var ui: VNUIAPI                          ## ui.overlay (§5.6)
var profile: VNProfileAPI                ## profile.data (§9.1)
var rng: VNRandom                        ## fluxo do plugin fora de atividades (RT §12.2); na atividade, handle.rng
var i18n: VNI18nAPI                      ## idioma do jogo e textos runtime/ do plugin (§5.7)
var theme: VNThemeInfo                   ## aparência do projeto, somente leitura (§5.7)
## Modo stream ligado (§5.6; RT §5.5), somente leitura: atribuir só avisa o log.
## Na edição censurada vale sempre [code]true[/code]. Para reagir a uma mudança durante
## a atividade, assine [code]sys.content_filter_changed[/code].
var content_filter: bool:
	get:
		return _bridge.content_filter_enabled()
	set(_value):
		_bridge.write_log(&"warn", "ctx.content_filter é somente leitura")
var log: VNLogger                        ## log do plugin

var _bridge: VNPluginBridge


## Monta o contexto de um plugin sobre a [param bridge] do host.
## [param p_config] já vem validada e com os defaults do [code]config_schema[/code].
static func create(bridge: VNPluginBridge, p_plugin_id: StringName, p_namespace: StringName, p_config: Dictionary = {}) -> VNPluginContext:
	var ctx := VNPluginContext.new()
	ctx._bridge = bridge
	ctx.plugin_id = p_plugin_id
	ctx.plugin_namespace = p_namespace
	ctx.config = p_config
	ctx.narrative = VNNarrativeAPI.new(bridge, p_namespace)
	ctx.characters = VNCharacterAPI.new(bridge, p_namespace)
	ctx.scenes = VNSceneAPI.new(bridge, p_namespace)
	ctx.assets = VNAssetAPI.new(bridge, p_namespace)
	ctx.audio = VNAudioAPI.new(bridge, p_namespace)
	ctx.ui = VNUIAPI.new(bridge, p_namespace)
	ctx.profile = VNProfileAPI.new(bridge, p_namespace)
	ctx.rng = bridge.create_rng(p_namespace)
	ctx.i18n = VNI18nAPI.new(bridge, p_namespace)
	ctx.theme = VNThemeInfo.new(bridge)
	ctx.log = VNLogger.new(bridge, p_namespace)
	return ctx
