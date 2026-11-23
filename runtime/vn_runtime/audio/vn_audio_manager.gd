@abstract
class_name VNAudioManager
extends VNModule
## Audio Manager: a parte de áudio do Stage (RT §1, "Stage (UI/Audio/Asset
## Manager)"). Tem contrato próprio para que o áudio (M2-05) e o palco (M2-02)
## andem em paralelo em pastas separadas.
##
## Canais [constant MUSIC], [constant AMBIENT], [constant SFX] e
## [constant VOICE] (nó [code]audio[/code], [code]scene.schema.json[/code]),
## com volume por canal das configurações do jogador (UI Spec §8). Recursos vêm
## de [VNAssets], já resolvidos pelo modo stream. Nunca altera variáveis.
##
## Specs: RT §5.2 (nó audio, galeria de música), §5.5 (canal com base),
## §8.2; Req §12 ([code]subtitles[/code], [code]caption[/code]); UI Spec §4
## ([code]play_sfx[/code]), §8; Plugin SDK §5.6 ([code]VNAudioAPI[/code]);
## [code]save.schema.json → Stage.audio[/code]. Tarefas: M2-05, M2-12.

## Legenda a mostrar ([code]caption[/code] ou [code]censored_caption[/code]),
## já no idioma atual; vazio apaga. Só com [code]subtitles[/code] ligado.
signal caption_changed(channel: StringName, text: String)

const MUSIC := &"music"
const AMBIENT := &"ambient"
const SFX := &"sfx"
const VOICE := &"voice"
const CHANNELS: Array[StringName] = [MUSIC, AMBIENT, SFX, VOICE]


func module_id() -> StringName:
	return &"audio"


## Nó [code]audio[/code] da cena: [code]action[/code] ([code]play[/code],
## [code]stop[/code]…), [code]channel[/code], [code]asset[/code],
## [code]loop[/code], [code]volume[/code], [code]fade[/code],
## [code]caption[/code] e [code]censor[/code].
@abstract func run_audio_node(node: Dictionary) -> void

## Toca um som avulso, fora dos nós da cena: a ação [code]play_sfx[/code] de
## tela (UI Spec §4) e o [code]VNAudioAPI.play[/code] do Runtime SDK (Plugin
## SDK §5.6). [param asset] é um id de asset do projeto (passa pelo modo
## stream) ou um caminho [code]res://vn_plugins/<ns>/…[/code] do plugin. O
## volume do canal se aplica por cima de [param volume]. Devolve o player
## (o [code]VNSound[/code] do SDK o envolve), ou [code]null[/code] se o som não toca.
@abstract func play(asset: String, channel: StringName = SFX, volume: float = 1.0) -> AudioStreamPlayer

## Para um canal, com fade em segundos.
@abstract func stop_channel(channel: StringName, fade: float = 0.0) -> void

## Para todos os canais.
@abstract func stop_all(fade: float = 0.0) -> void

## Volume do canal, linear de 0 a 1 (configurações do jogador).
@abstract func set_channel_volume(channel: StringName, volume: float) -> void
@abstract func get_channel_volume(channel: StringName) -> float

## O que toca em cada canal, no formato [code]save.schema.json → Stage.audio[/code].
@abstract func snapshot() -> Dictionary

## Restaura os canais de um save (RT §8.3 passo 7).
@abstract func restore(audio: Dictionary) -> void

## Troca para a substituta ou silencia, com fade curto, do início da faixa (RT §5.5).
@abstract func set_content_filter(enabled: bool) -> void
