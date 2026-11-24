class_name VNRuntimeAudioManager
extends VNAudioManager
## Audio Manager do runtime (tarefa M2-05): canais música, ambiente, efeitos e
## voz, volume por canal das configurações do jogador e legendas
## ([code]caption[/code] e [code]censored_caption[/code]).
##
## [b]Canais.[/b] Cada canal é um [VNAudioChannel] dentro do nó
## [code]VNAudio[/code] criado em [method attach]. Um nó [code]audio[/code]
## com [code]play[/code] em [constant MUSIC] ou [constant AMBIENT], ou com
## [code]loop[/code], põe o [b]som do canal[/b]: ele substitui o anterior (fade
## cruzado com [code]fade[/code]), vai para o save ([method snapshot]) e segue a
## regra de base do modo stream (RT §5.5). Um [code]play[/code] de
## [constant VOICE] sem laço também substitui a voz anterior, mas não vai para o
## save. Um [code]play[/code] de [constant SFX] sem laço é avulso: se sobrepõe
## aos outros efeitos. [code]loop[/code] ausente vale [code]true[/code] em
## música e ambiente e [code]false[/code] em efeitos e voz (DM §8);
## [code]fade[/code] em [code]stop[/code] é a duração do fade de saída.
##
## [b]Volume.[/b] O volume de um som é
## [code]volume.master × volume.<canal> × volume do nó[/code] (UI Spec §8),
## lidos do UI Manager ([method VNUIManager.get_setting]) e atualizados na hora
## por [signal VNUIManager.setting_changed]. Sem valor do jogador valem os
## padrões da UI Spec §8 (0,8; voz 1,0). [method set_channel_volume] também
## aceita [constant MASTER].
##
## [b]Legendas.[/b] Com [code]subtitles[/code] ligado, a legenda de um nó
## [code]audio[/code] aparece no [VNCaptionView] e sai por
## [signal VNAudioManager.caption_changed], traduzida pelo caminho
## [code]<cena>/<nó>[/code] (DM §9). No modo stream ela segue o asset: com
## [code]hide[/code] não aparece; com [code]replace_with[/code] mostra
## [code]censored_caption[/code] (caminho [code]…/censored[/code], senão o texto
## censurado do idioma-fonte) ou nada (RT §5.5). A legenda do som do canal fica
## enquanto ele toca; a de um som sem laço fica pela duração dele, no mínimo
## [constant CAPTION_MIN_SECONDS]. Desligar [code]subtitles[/code] apaga as
## legendas na hora; ligar mostra de novo as que ainda valem. Trocar de idioma
## retraduz.
##
## [b]Modo stream.[/b] Todo asset passa pelo [code]censored[/code] dele no
## momento de tocar; o estado guarda sempre o id original. Ao mudar o modo
## ([method set_content_filter]) e ao restaurar um save, cada canal toca o que
## vale no modo atual, do início da faixa e com o fade curto
## [constant SHORT_FADE]: o som do passo, a substituta, a base (passo
## [code]censor[/code] que não vale) ou silêncio.
##
## [b]Galeria.[/b] Um [code]play[/code] de um [code]audio_music[/code] em música
## ou ambiente marca o asset original em [code]profile.seen_assets[/code]
## ([method VNSaveManager.mark_asset_seen], RT §5.2), também ao restaurar um save.
##
## Sem [method attach] nada toca, mas o estado, o save e as legendas funcionam
## (é assim que os módulos lógicos testam).
##
## Specs: RT §5.2, §5.5, §8.2, §8.3 passo 7; DM §8 (nó [code]audio[/code]), §9,
## §10.4; Req §12; UI Spec §4 ([code]play_sfx[/code]), §8; Plugin SDK §5.6.

## Volume geral ([code]volume.master[/code]), aceito por [method set_channel_volume].
const MASTER := &"master"
## Fade curto da troca de modo stream e da restauração de um save (RT §5.5).
const SHORT_FADE := 0.3
## Tempo mínimo na tela da legenda de um som sem laço.
const CAPTION_MIN_SECONDS := 2.0
## Padrões da UI Spec §8 e de [code]save.schema.json → PlayerSettings.volume[/code].
const DEFAULT_VOLUMES := {&"master": 0.8, &"music": 0.8, &"ambient": 0.8, &"sfx": 0.8, &"voice": 1.0}

## Tradução de uma legenda: [code]func(path: String, source: String) -> String[/code].
## Vazio usa as traduções de [method set_translations] e o idioma de
## [code]locale[/code]. A integração (M2-16) pode trocar por um serviço que
## também interpola.
var text_resolver: Callable

var _bundle_assets: Dictionary = {}
var _default_locale: String = ""
var _censored_edition: bool = false
var _translations: Dictionary = {}       # idioma → { caminho → texto }
var _volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var _subtitles: bool = true
var _content_filter: bool = false
var _state: Dictionary = {}              # canal → { asset, loop, volume, censor?, base? }
var _playing: Dictionary = {}            # canal → chave do som do canal que está tocando
var _captions: Dictionary = {}           # canal → { path, source, censored, asset, remaining }
var _shown: Dictionary = {}              # canal → legenda mostrada
var _ui_connected: VNUIManager = null

var _root: Node = null
var _channels: Dictionary = {}           # canal → VNAudioChannel
var _view: VNCaptionView = null


func bind(p_modules: VNModules) -> void:
	super.bind(p_modules)
	_connect_settings()


func load_bundle(bundle: Dictionary) -> void:
	_bundle_assets = bundle.get("assets", {})
	var project: Dictionary = bundle.get("project", {})
	_default_locale = String(project.get("default_locale", ""))
	var cf: Dictionary = project.get("content_filter", {})
	_censored_edition = cf.get("edition", "standard") == "censored"
	if _censored_edition:
		_content_filter = true
	_connect_settings()
	apply_settings()


## Traduções de um idioma ([code]narrative/locales/<idioma>.json → strings[/code]).
func set_translations(locale: String, strings: Dictionary) -> void:
	_translations[locale] = strings
	_refresh_captions()


func attach(parent: Node) -> void:
	detach()
	_root = _Ticker.new(step)
	_root.name = "VNAudio"
	for ch in CHANNELS:
		var c := VNAudioChannel.new(ch)
		c.main_finished.connect(_on_main_finished.bind(ch))
		_channels[ch] = c
		_root.add_child(c)
	_view = VNCaptionView.new()
	_root.add_child(_view)
	parent.add_child(_root)
	_apply_volumes()
	_playing.clear()
	for ch in _state:
		_sync_channel(ch, 0.0)
	for ch in _shown:
		_view.set_caption(ch, _shown[ch])


func detach() -> void:
	if _root != null and is_instance_valid(_root):
		if _root.get_parent() != null:
			_root.get_parent().remove_child(_root)
		_root.free()
	_root = null
	_channels.clear()
	_view = null
	_playing.clear()


## O [VNAudioChannel] do canal (depois de [method attach]).
func channel_node(channel: StringName) -> VNAudioChannel:
	return _channels.get(channel)


## A tela das legendas (depois de [method attach]).
func caption_view() -> VNCaptionView:
	return _view


## A legenda mostrada agora no canal ([code]""[/code] se nenhuma).
func current_caption(channel: StringName) -> String:
	return _shown.get(channel, "")


## O que se ouve em cada canal pela regra de base do modo stream, com os ids
## originais (o [code]stage.audio[/code] dos vetores da spec 08).
func audible() -> Dictionary:
	var out := {}
	for ch in _state:
		var e: Variant = _audible_entry(ch)
		if e != null:
			out[String(ch)] = String(e.asset)
	return out


# --- Nós de cena ------------------------------------------------------------

func run_audio_node(node: Dictionary) -> void:
	var ch := StringName(String(node.get("channel", "")))
	if not CHANNELS.has(ch):
		push_warning("Audio: canal desconhecido '%s' no nó %s." % [ch, node.get("id", "?")])
		return
	if String(node.get("action", "play")) != "play":
		stop_channel(ch, float(node.get("fade", 0.0)))
		return
	var asset := String(node.get("asset", ""))
	if asset.is_empty():
		push_warning("Audio: play sem asset no nó %s." % node.get("id", "?"))
		return
	var loop := bool(node.get("loop", ch == MUSIC or ch == AMBIENT))
	var volume := clampf(float(node.get("volume", 1.0)), 0.0, 1.0)
	var fade := maxf(float(node.get("fade", 0.0)), 0.0)
	var entry := {"asset": asset, "loop": loop, "volume": volume}
	var tracked := loop or ch == MUSIC or ch == AMBIENT

	if tracked:
		var censor := String(node.get("censor", ""))
		if not censor.is_empty():
			entry["censor"] = censor
			var prev: Variant = _state.get(ch)
			if prev != null:
				if prev.has("censor"):
					if prev.has("base"):
						entry["base"] = (prev.base as Dictionary).duplicate()
				else:
					entry["base"] = {"asset": prev.asset, "loop": prev.loop, "volume": prev.volume}
		_state[ch] = entry
		_sync_channel(ch, fade, true)
	else:
		_state.erase(ch)
		_playing.erase(ch)
		var c := channel_node(ch)
		if c != null:
			var stream := _load_stream(_resolve(asset))
			if ch == SFX:
				c.play_one_shot(stream, volume)
			else:
				c.play_main(stream, false, volume, fade)

	if (ch == MUSIC or ch == AMBIENT) and _asset_type(asset) == "audio_music":
		_mark_seen(asset)

	_set_caption_from_node(ch, node, asset, tracked)


## Lê o caminho da legenda e guarda os textos do nó; com o canal sem legenda,
## apaga a anterior.
func _set_caption_from_node(ch: StringName, node: Dictionary, asset: String, tracked: bool) -> void:
	if not node.has("caption") and not node.has("censored_caption"):
		_captions.erase(ch)
		_refresh_caption(ch)
		return
	var scene := String(node.get("scene", ""))
	if scene.is_empty() and modules() != null and modules().engine != null:
		scene = modules().engine.current_scene()
	var remaining := -1.0
	if not tracked or not bool(_state.get(ch, {}).get("loop", true)):
		remaining = maxf(_stream_length(_resolve(asset)), CAPTION_MIN_SECONDS)
	_captions[ch] = {
		"path": "%s/%s" % [scene, node.get("id", "")],
		"source": String(node.get("caption", "")),
		"censored": node.get("censored_caption"),
		"asset": asset,
		"remaining": remaining,
	}
	_refresh_caption(ch)


# --- Sons avulsos (play_sfx, VNAudioAPI) -------------------------------------

func play(asset: String, channel: StringName = SFX, volume: float = 1.0) -> AudioStreamPlayer:
	var c := channel_node(channel)
	if c == null:
		return null
	var stream: AudioStream
	if asset.begins_with("res://"):
		stream = load(asset) as AudioStream if ResourceLoader.exists(asset) else null
	else:
		var id := _resolve(asset)
		if id.is_empty():
			return null
		stream = _load_stream(id)
	if stream == null:
		push_warning("Audio: som '%s' não encontrado." % asset)
		return null
	return c.play_one_shot(stream, volume)


func stop_channel(channel: StringName, fade: float = 0.0) -> void:
	_state.erase(channel)
	_playing.erase(channel)
	var c := channel_node(channel)
	if c != null:
		c.stop_all(fade)
	_captions.erase(channel)
	_refresh_caption(channel)


func stop_all(fade: float = 0.0) -> void:
	for ch in CHANNELS:
		stop_channel(ch, fade)


# --- Volumes ----------------------------------------------------------------

func set_channel_volume(channel: StringName, volume: float) -> void:
	if channel != MASTER and not CHANNELS.has(channel):
		push_warning("Audio: canal desconhecido '%s'." % channel)
		return
	_volumes[channel] = clampf(volume, 0.0, 1.0)
	_apply_volumes()


func get_channel_volume(channel: StringName) -> float:
	return float(_volumes.get(channel, 1.0))


## Lê do UI Manager os volumes, [code]subtitles[/code] e o idioma. Chamado em
## [method load_bundle]; depois as mudanças chegam por
## [signal VNUIManager.setting_changed].
func apply_settings() -> void:
	var ui := _ui()
	for ch: StringName in DEFAULT_VOLUMES:
		var v: Variant = ui.get_setting(StringName("volume." + String(ch))) if ui != null else null
		_volumes[ch] = clampf(float(v), 0.0, 1.0) if v is float or v is int else float(DEFAULT_VOLUMES[ch])
	var sub: Variant = ui.get_setting(&"subtitles") if ui != null else null
	_subtitles = bool(sub) if sub is bool else true
	_apply_volumes()
	_refresh_captions()


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	var s := String(setting)
	if s.begins_with("volume."):
		var ch := StringName(s.trim_prefix("volume."))
		if value is float or value is int:
			set_channel_volume(ch, float(value))
		else:
			apply_settings()
	elif s == "subtitles":
		_subtitles = bool(value) if value is bool else true
		_refresh_captions()
	elif s == "locale":
		_refresh_captions()


func _apply_volumes() -> void:
	var master := float(_volumes.get(MASTER, 1.0))
	for ch: StringName in _channels:
		(_channels[ch] as VNAudioChannel).player_volume = master * float(_volumes.get(ch, 1.0))


# --- Save -------------------------------------------------------------------

func snapshot() -> Dictionary:
	var out := {}
	for ch in _state:
		out[String(ch)] = (_state[ch] as Dictionary).duplicate(true)
	return out


func restore(audio: Dictionary) -> void:
	for ch in CHANNELS:
		var c := channel_node(ch)
		if c != null:
			c.stop_all(0.0)
	_state.clear()
	_playing.clear()
	_captions.clear()
	for key in audio:
		var ch := StringName(String(key))
		var e: Variant = audio[key]
		if not CHANNELS.has(ch) or not (e is Dictionary) or not e.has("asset"):
			push_warning("Audio: canal '%s' do save ignorado." % key)
			continue
		var entry := {
			"asset": String(e.asset),
			"loop": bool(e.get("loop", ch == MUSIC or ch == AMBIENT)),
			"volume": clampf(float(e.get("volume", 1.0)), 0.0, 1.0),
		}
		if e.has("censor"):
			entry["censor"] = String(e.censor)
		if e.get("base") is Dictionary and e.base.has("asset"):
			entry["base"] = {
				"asset": String(e.base.asset),
				"loop": bool(e.base.get("loop", ch == MUSIC or ch == AMBIENT)),
				"volume": clampf(float(e.base.get("volume", 1.0)), 0.0, 1.0),
			}
		_state[ch] = entry
		_sync_channel(ch, SHORT_FADE, true)
		var shown: Variant = _audible_entry(ch)
		if shown != null and (ch == MUSIC or ch == AMBIENT) and _asset_type(shown.asset) == "audio_music":
			_mark_seen(shown.asset)
	_refresh_captions()


# --- Modo stream ------------------------------------------------------------

func set_content_filter(enabled: bool) -> void:
	if _censored_edition:
		enabled = true
	if enabled == _content_filter:
		return
	_content_filter = enabled
	for ch in _state.keys():
		_sync_channel(ch, SHORT_FADE)
	_refresh_captions()


func is_content_filter_enabled() -> bool:
	return _content_filter


# --- Laço -------------------------------------------------------------------

## Avança fades e o tempo das legendas de sons sem laço. Chamado a cada quadro
## pelo nó [code]VNAudio[/code]; os testes chamam à mão.
func step(delta: float) -> void:
	for c: VNAudioChannel in _channels.values():
		c.step(delta)
	for ch: StringName in _captions.keys():
		var cap: Dictionary = _captions[ch]
		if float(cap.remaining) < 0.0:
			continue
		cap.remaining = float(cap.remaining) - delta
		if float(cap.remaining) <= 0.0:
			_captions.erase(ch)
			_refresh_caption(ch)


func _on_main_finished(ch: StringName) -> void:
	# Som do canal sem laço chegou ao fim: sai do palco (e do save).
	if _state.has(ch) and not bool(_state[ch].loop):
		_state.erase(ch)
	_playing.erase(ch)


# --- Internos ---------------------------------------------------------------

## Toca no canal o que vale no modo atual. Só reinicia se o som mudou (ou com
## [param force], quando um nó acabou de pôr o som).
func _sync_channel(ch: StringName, fade: float, force: bool = false) -> void:
	var e: Variant = _audible_entry(ch)
	var id := _resolve(String(e.asset)) if e != null else ""
	var key := "" if id.is_empty() else "%s|%s|%s" % [id, e.loop, e.volume]
	if not force and _playing.get(ch, "") == key:
		return
	_playing[ch] = key
	var c := channel_node(ch)
	if c == null:
		return
	if key.is_empty():
		c.stop_main(fade)
	else:
		var stream := _load_stream(id)
		if stream == null:
			push_warning("Audio: som '%s' não encontrado." % id)
			c.stop_main(fade)
		else:
			c.play_main(stream, bool(e.loop), float(e.volume), fade)


## A entrada que vale no modo atual: a do passo, a base (passo [code]censor[/code]
## que não vale) ou [code]null[/code] (silêncio).
func _audible_entry(ch: StringName) -> Variant:
	var e: Variant = _state.get(ch)
	if e == null:
		return null
	if e.has("censor") and not _censor_applies(String(e.censor)):
		return e.get("base")
	return e


func _censor_applies(censor: String) -> bool:
	match censor:
		"skip": return not _content_filter
		"only": return _content_filter
	return true


## O id que toca no modo atual: o original, o de [code]replace_with[/code] ou
## vazio ([code]hide[/code]).
func _resolve(asset_id: String) -> String:
	if not _content_filter:
		return asset_id
	if _bundle_assets.is_empty() and modules() != null and modules().assets != null:
		return modules().assets.resolve_id(asset_id)
	var censored: Variant = (_bundle_assets.get(asset_id, {}) as Dictionary).get("censored")
	if not (censored is Dictionary):
		return asset_id
	if bool(censored.get("hide", false)):
		return ""
	return String(censored.get("replace_with", asset_id))


func _load_stream(asset_id: String) -> AudioStream:
	if asset_id.is_empty():
		return null
	var res: Resource = null
	if modules() != null and modules().assets != null:
		res = modules().assets.load_asset(asset_id)
	if res == null and _bundle_assets.has(asset_id):
		var path := String(_bundle_assets[asset_id].get("path", ""))
		if ResourceLoader.exists(path):
			res = load(path)
	return res as AudioStream


func _stream_length(asset_id: String) -> float:
	var s := _load_stream(asset_id)
	return s.get_length() if s != null else 0.0


func _asset_type(asset_id: String) -> String:
	return String((_bundle_assets.get(asset_id, {}) as Dictionary).get("type", ""))


func _mark_seen(asset_id: String) -> void:
	if modules() != null and modules().saves != null:
		modules().saves.mark_asset_seen(asset_id)


func _ui() -> VNUIManager:
	return modules().ui if modules() != null else null


func _connect_settings() -> void:
	var ui := _ui()
	if ui == null or ui == _ui_connected:
		return
	if _ui_connected != null and _ui_connected.setting_changed.is_connected(_on_setting_changed):
		_ui_connected.setting_changed.disconnect(_on_setting_changed)
	ui.setting_changed.connect(_on_setting_changed)
	_ui_connected = ui


func _current_locale() -> String:
	var ui := _ui()
	var loc: Variant = ui.get_setting(&"locale") if ui != null else null
	return String(loc) if loc is String and not String(loc).is_empty() else _default_locale


func _translate(path: String, source: String) -> String:
	if text_resolver.is_valid():
		return String(text_resolver.call(path, source))
	var loc := _current_locale()
	if loc != _default_locale and _translations.has(loc):
		var strings: Dictionary = _translations[loc]
		if strings.has(path):
			return String(strings[path])
	return source


## A legenda que vale agora no canal (RT §5.5: segue o asset).
func _caption_text(ch: StringName) -> String:
	if not _subtitles or not _captions.has(ch):
		return ""
	var cap: Dictionary = _captions[ch]
	var asset := String(cap.asset)
	var id := _resolve(asset)
	if id.is_empty():
		return ""
	if id != asset:
		if cap.censored == null or String(cap.censored).is_empty():
			return ""
		return _translate(String(cap.path) + "/censored", String(cap.censored))
	return _translate(String(cap.path), String(cap.source))


func _refresh_caption(ch: StringName) -> void:
	var text := _caption_text(ch)
	if text == String(_shown.get(ch, "")):
		return
	if text.is_empty():
		_shown.erase(ch)
	else:
		_shown[ch] = text
	if _view != null:
		_view.set_caption(ch, text)
	caption_changed.emit(ch, text)


func _refresh_captions() -> void:
	for ch in CHANNELS:
		_refresh_caption(ch)


## Nó que chama [method step] a cada quadro, também com o jogo pausado (a
## música continua no menu de pausa).
class _Ticker extends Node:
	var _tick: Callable

	func _init(tick: Callable) -> void:
		_tick = tick
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		if _tick.is_valid():
			_tick.call(delta)
