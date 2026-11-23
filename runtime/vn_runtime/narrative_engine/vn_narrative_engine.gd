@abstract
class_name VNNarrativeEngine
extends VNModule
## Narrative Engine (RT §1): máquina de estados do jogo; executa nós;
## coordena os demais módulos. É a autoridade sobre o fluxo da história.
##
## É dirigido por sinais na thread principal e nunca bloqueia a frame (RT §10).
## Nós bloqueantes esperam o Stage ([signal VNStage.advanced],
## [signal VNStage.option_selected]) ou o Plugin Host
## ([signal VNPluginHost.activity_ended]). Ordem garantida: efeitos de um nó →
## drenagem de eventos → próximo nó.
##
## Specs: RT §3 (ciclo de vida, [VNPhase]), §3.1–§3.4, §5.1–§5.5, §8.1, §8.3
## passo 7, §9, §10; DM §8.2 (grafo de nós). Vetores: [code]conformance/flow.json[/code].
## Tarefa: M1-11 (e M3-04 para o nó plugin).

## Mudou o estado do jogo (RT §3).
signal phase_changed(phase: StringName, previous: StringName)

## Um nó começou a executar (para o Preview: [code]node.entered[/code], PP §4).
## Nós pulados pelo modo stream não emitem (RT §5.5).
signal node_entered(scene: String, node: String, node_type: StringName)

## Erro de conteúdo (RT §9): em debug/Preview o runtime pausa e mostra o
## overlay; em release só registra. [param context] traz
## [code]scene[/code], [code]node[/code] e, se houver, [code]variable[/code].
signal content_error(code: StringName, message: String, context: Dictionary)

## Limite de nós instantâneos seguidos sem um bloqueante (RT §5.2).
const MAX_INSTANT_NODES := 10000

## Tipos de salvamento de [method can_save] (RT §8.1).
const SAVE_MANUAL := &"manual"           ## pelo menu, rápido ou autosave comum
const SAVE_ACTIVITY := &"activity"       ## autosave de segurança antes de uma atividade
const SAVE_SCENE_START := &"scene_start" ## autosave no início da cena


func module_id() -> StringName:
	return &"engine"


# --- Estado -----------------------------------------------------------------

## Estado atual (um de [constant VNPhase.ALL]).
@abstract func phase() -> StringName

## Capítulo, cena e nó atuais (UUIDs); vazios quando não há.
@abstract func current_chapter() -> String
@abstract func current_scene() -> String
@abstract func current_node() -> String

## O estado permite escrita narrativa: não em [code]LOAD_GAME[/code] nem em
## [code]GAME_END[/code] (RT §6.2, verificação 2). O State Manager consulta.
@abstract func is_write_allowed() -> bool

## Dá para salvar agora com esse tipo de save (RT §8.1).
@abstract func can_save(kind: StringName = SAVE_MANUAL) -> bool

## A parte do save que é do Engine: [code]state.chapter[/code] e
## [code]state.scene[/code] sem [code]stage[/code] (que vem do Stage) e o
## backlog ([code]state.backlog[/code]).
@abstract func snapshot() -> Dictionary


# --- Ciclo de vida (RT §3) --------------------------------------------------

## Do boot para o título (RT §3.0 passo 6).
@abstract func enter_title() -> void

## Novo jogo (RT §3.1): defaults, perfil, histórico, plugins, evento, start_chapter.
@abstract func new_game() -> void

## Retoma de um save já restaurado nos outros módulos (RT §8.3 passo 7): se
## havia cena, reexecuta o nó salvo; senão, vai ao ponto de seleção.
## [param state] é o [code]state[/code] do save.
@abstract func resume_from_save(state: Dictionary) -> void

## Volta ao título, sem fim de jogo (ação return_to_title, UI Spec §4).
@abstract func return_to_title() -> void

## Pausa e retoma o fluxo (tela de pausa, UI Spec §12; preview.pause).
@abstract func set_paused(paused: bool) -> void
@abstract func is_paused() -> bool


# --- Entrada do jogador -----------------------------------------------------

## O jogador avançou a fala ([code]vn_advance[/code], automático ou pular).
@abstract func advance() -> void

## O jogador escolheu uma opção de [code]choice[/code] ou um hotspot ou a saída
## de [code]interact[/code] (RT §5.2). Recusa com [code]INVALID_STATE[/code] fora
## desses nós ou com opção desconhecida, invisível ou desabilitada.
@abstract func choose(option_id: String) -> VNResult

## O modo stream mudou (RT §5.5): a fala atual é mostrada de novo no novo
## modo, sem duplicar o backlog; o resto vale a partir do próximo nó.
@abstract func content_filter_changed(enabled: bool) -> void
