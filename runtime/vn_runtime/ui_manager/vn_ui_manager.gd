@abstract
class_name VNUIManager
extends VNModule
## UI Manager (RT §1): pilha de telas ([code]ui/*.json[/code]), ações de
## botões e configurações do jogador. É a autoridade sobre as telas abertas e
## sobre [code]settings.json[/code] (gravado pelo [VNStorage]).
##
## Desenha o HUD na camada [constant VNLayers.HUD] e a pilha na
## [constant VNLayers.SCREENS] (RT §1.1). Ações [code]effects[/code] passam pelo
## State Manager com [constant VNStateManager.CALLER_UI] e [code]emit[/code]
## pelo Event Bus; ações nunca escolhem nem pulam cenas (UI Spec §4). Abrir a
## pausa ou uma tela própria durante o jogo pausa o Narrative Engine, exceto a
## [code]hud[/code] (UI Spec §12).
##
## Specs: UI Spec §2–§4, §8 ([code]PlayerSettings[/code]), §12; RT §1, §1.1,
## §3.0 passos 1 e 6, §10.1; [code]ui-screen.schema.json[/code],
## [code]save.schema.json → PlayerSettings[/code].
## Tarefas: M2-06, M2-07, M2-09, M2-11, M2-15.

## A pilha mudou; [param screens] vai da base ao topo.
signal screens_changed(screens: PackedStringArray)
## Uma configuração do jogador mudou (inclusive [code]content_filter[/code],
## que o runtime repassa ao Stage, ao Audio, a VNAssets e ao Engine).
signal setting_changed(setting: StringName, value: Variant)


func module_id() -> StringName:
	return &"ui"


# --- Pilha de telas ---------------------------------------------------------

## Empilha a tela (id de [code]bundle.json → ui[/code]).
@abstract func open_screen(screen_id: String) -> VNResult

## Desempilha a tela do topo ([code]close_screen[/code]/[code]back[/code], [code]vn_cancel[/code]).
@abstract func close_screen() -> void

## Fecha todas as telas da pilha (o HUD fica, se estiver em jogo).
@abstract func close_all() -> void

## Ids da pilha, da base ao topo.
@abstract func screen_stack() -> PackedStringArray

## Mostra ou esconde a tela [code]hud[/code].
@abstract func set_hud_visible(visible: bool) -> void

## Executa uma lista de ações (UI Spec §4), em ordem, com [code]if[/code]/[code]else[/code].
## [param context] diz de onde veio: [code]{ screen, element }[/code].
@abstract func run_actions(actions: Array, context: Dictionary = {}) -> VNResult

## Caixa de confirmação do tema (camada [constant VNLayers.SYSTEM]); devolve a
## resposta por [param on_answer] ([code]func(accepted: bool)[/code]).
@abstract func confirm(text_path: String, on_answer: Callable) -> void

## Mensagem bloqueante [code]runtime/message/*[/code] (RT §3.0, BS §13.1).
@abstract func show_message(text_path: String) -> void


# --- Licenças (licenses.json; BS §4.5) ---------------------------------------

## Entrega o [code]licenses.json[/code] do bundle (o boot chama no passo 2).
## Quem não mostra licenças ignora.
func set_licenses(_licenses: Dictionary) -> void:
	pass


# --- Configurações do jogador (settings.json; UI Spec §8) -------------------

## Lê [code]settings.json[/code] (RT §3.0 passo 1): arquivo inválido vira
## [code]settings.json.bad[/code] e valem os padrões.
@abstract func load_settings() -> void

## Valor efetivo: o do jogador, senão [code]project.json → settings[/code],
## senão o padrão do runtime.
@abstract func get_setting(setting: StringName) -> Variant

## Muda e grava só os campos que o jogador mudou (RT §8.5). Valor fora do
## schema é recusado com [code]TYPE_MISMATCH[/code].
@abstract func set_setting(setting: StringName, value: Variant) -> VNResult
