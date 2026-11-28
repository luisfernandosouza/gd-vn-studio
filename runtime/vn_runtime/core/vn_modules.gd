class_name VNModules
extends RefCounted
## Registro dos módulos do runtime (RT §1).
##
## É por aqui que um módulo chama outro: [code]modules().state.apply_effects(...)[/code].
## O boot (M2-01) monta o registro com os módulos reais; os testes usam
## [code]VNFakeModules.create()[/code] (em [code]tests/fakes/[/code]) e trocam
## só o módulo que estão testando. As tarefas de integração (M1-12, M2-16)
## trocam os dublês pelos módulos reais.
##
## Regra de dependência (RT §1): só o State Manager escreve no Variable Manager;
## Narrative Engine, efeitos de cena, plugins e ações [code]effects[/code] de
## telas passam todos pelo State Manager. O Stage nunca altera variáveis, e
## ações de tela nunca escolhem nem pulam cenas.

const MODULE_IDS: Array[StringName] = [
	&"engine", &"scheduler", &"conditions", &"state", &"variables", &"events",
	&"plugins", &"saves", &"storage", &"stage", &"audio", &"ui", &"assets",
]

var engine: VNNarrativeEngine           ## Narrative Engine: fluxo da história
var scheduler: VNSceneScheduler         ## Scene Scheduler: seleção de cenas e capítulos
var conditions: VNConditionEvaluator    ## Condition Evaluator: condições e expressões (puro)
var state: VNStateManager               ## State Manager: única porta de escrita
var variables: VNVariableManager        ## Variable Manager: valores, defaults, escopos
var events: VNEventBus                  ## Event Bus: fila e entrega de eventos
var plugins: VNPluginHost               ## Plugin Host: plugins, permissões, atividades
var saves: VNSaveManager                ## Save Manager: saves, perfil, migração
var storage: VNStorage                  ## VNStorage do Save Manager (RT §8.5)
var stage: VNStage                      ## Stage: desenho e entrada do jogador
var audio: VNAudioManager               ## Audio Manager, parte do Stage (RT §1)
var ui: VNUIManager                     ## UI Manager: pilha de telas e settings.json
var assets: VNAssets                    ## VNAssets: resolve ids de asset em recursos

## RNG do jogo (RT §12.2, M1-08). Não é um [VNModule] nem está em [constant MODULE_IDS]: é um
## serviço sem dublê, o mesmo nos testes e no jogo. [method load_bundle] lê
## [code]settings.reproducible_rng[/code]; o Narrative Engine semeia com [method VNGameRng.new_game].
var rng: VNGameRng = VNGameRng.new()


## O módulo registrado com o id dado, ou [code]null[/code].
func get_module(id: StringName) -> VNModule:
	if not MODULE_IDS.has(id):
		return null
	return get(id) as VNModule


## Os módulos registrados, na ordem de [constant MODULE_IDS].
func all() -> Array[VNModule]:
	var out: Array[VNModule] = []
	for id in MODULE_IDS:
		var m := get_module(id)
		if m != null:
			out.append(m)
	return out


## Ids dos módulos ainda não registrados.
func missing() -> PackedStringArray:
	var out := PackedStringArray()
	for id in MODULE_IDS:
		if get_module(id) == null:
			out.append(String(id))
	return out


## Liga todos os módulos registrados a este registro.
func bind_all() -> void:
	for m in all():
		m.bind(self)


## Entrega o bundle a todos os módulos, na ordem de [constant MODULE_IDS].
func load_bundle(bundle: Dictionary) -> void:
	rng.configure_from_bundle(bundle)
	for m in all():
		m.load_bundle(bundle)


## Liga os módulos que desenham ao nó [param parent].
func attach_all(parent: Node) -> void:
	for m in all():
		m.attach(parent)


## Desfaz [method attach_all].
func detach_all() -> void:
	for m in all():
		m.detach()
