@abstract
class_name VNStage
extends VNModule
## Stage (RT §1): desenho e entrada do jogador; sets e seus hotspots
## cosméticos. É a autoridade sobre a apresentação e **nunca** altera
## variáveis nem escolhe cenas: só avisa o Narrative Engine por sinais.
##
## Desenha nas camadas fixas de [VNLayers] (RT §1.1), criadas em
## [method attach]: cenário (0), personagens (10), hotspots de
## [code]interact[/code] (15), overlays de plugin (20) e caixa de texto (30). O
## HUD e as telas (40, 50) são do UI Manager; a atividade (60) é do Plugin
## Host; o sistema (100) é compartilhado. Posições e tamanhos em pixels da
## resolução base, com [code]stretch_mode = canvas_items[/code] e
## [code]stretch_aspect = expand[/code] (RT §1.1, DM §10.2). Os recursos vêm de
## [VNAssets]; o áudio é do [VNAudioManager].
##
## Specs: RT §1.1, §5.2 (nós de Stage, digitação, galeria), §5.5 (modo stream
## e base por item), §8.2, §8.3 passo 7, §8.5 (miniatura); DM §10.1, §10.2;
## UI Spec §5, §6; [code]save.schema.json → Stage[/code].
## Tarefas: M2-02, M2-03, M2-04, M2-08, M2-12.

## O jogador avançou a fala ([code]vn_advance[/code], ou auto/pular).
signal advanced()
## O jogador escolheu uma opção de [code]choice[/code], um hotspot ou a
## saída ([code]exit[/code]) de [code]interact[/code].
signal option_selected(option_id: String)
## Terminou a transição visual do alvo ([code]&"background"[/code] ou o id da personagem).
signal transition_finished(target: StringName)


func module_id() -> StringName:
	return &"stage"


## O [CanvasLayer] de uma camada de [VNLayers] (depois de [method attach]),
## para o UI Manager e o Plugin Host porem os seus nós.
@abstract func get_layer(layer: int) -> CanvasLayer


# --- Palco (nós background, show, hide; RT §5.2) ----------------------------

## Nó [code]background[/code] ([code]asset[/code] ou [code]set[/code]), com a
## transição e a marca [code]censor[/code] do passo (RT §5.5).
@abstract func set_background(node: Dictionary) -> void

## Nó [code]show[/code]: personagem, expressão, posição, âncora, escala, z e transição.
@abstract func show_character(node: Dictionary) -> void

## Nó [code]hide[/code].
@abstract func hide_character(node: Dictionary) -> void

## Há transição em andamento no alvo: o próximo comando de Stage no mesmo alvo espera (RT §5.2).
@abstract func is_busy(target: StringName) -> bool

## Tira tudo do palco (fim de jogo, volta ao título).
@abstract func clear() -> void


# --- Texto e escolhas (camada 30) e hotspots (camada 15) --------------------

## Mostra uma fala já resolvida: [code]{ text, speaker?, voice?, text_path }[/code]
## ([code]text[/code] já interpolado, no idioma e no modo atuais). Digita a
## [code]text_speed[/code]; o primeiro [code]vn_advance[/code] completa, o segundo
## emite [signal advanced].
@abstract func show_line(line: Dictionary) -> void

## Mostra as opções de [code]choice[/code]: [code][{ id, text, enabled }][/code],
## só as visíveis. A escolha sai por [signal option_selected].
@abstract func show_choices(prompt: String, options: Array[Dictionary]) -> void

## Mostra os hotspots de [code]interact[/code] (UI Spec §6):
## [code][{ id, label, rect | polygon, enabled }][/code] e a saída, se houver.
@abstract func show_hotspots(hotspots: Array[Dictionary], exit_option: Dictionary = {}) -> void

## Esconde caixa de texto, escolhas e hotspots.
@abstract func clear_interaction() -> void

## Esconde ou mostra a caixa de texto ([code]vn_hide[/code]).
@abstract func set_textbox_hidden(hidden: bool) -> void


# --- Modo stream, save e miniatura ------------------------------------------

## Redesenha o palco no novo modo, sem transição, pela regra de base por item (RT §5.5).
@abstract func set_content_filter(enabled: bool) -> void

## O palco no formato [code]save.schema.json → Stage[/code], sem
## [code]audio[/code] (que vem do [VNAudioManager]), com os ids originais.
@abstract func snapshot() -> Dictionary

## Restaura o palco de um save (RT §8.3 passo 7), já no modo atual.
@abstract func restore(stage: Dictionary) -> void

## O quadro do jogo sem UI (camadas 0 a 20, RT §8.5), para a miniatura.
@abstract func capture_thumbnail() -> Image

## O palco mostra algum asset com [code]censored[/code] com o modo desligado
## ([code]thumbnail_sensitive[/code], RT §8.5).
@abstract func is_showing_sensitive() -> bool
