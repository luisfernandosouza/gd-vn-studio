@abstract
class_name VNSaveManager
extends VNModule
## Save Manager (RT §1): snapshot, restauração, perfil e migração de saves.
## É a autoridade sobre o formato do save ([code]save.schema.json[/code]).
##
## Grava e lê só pelo [VNStorage] ([code]modules().storage[/code], RT §8.5).
## Monta o save juntando as partes de cada módulo: variáveis
## ([method VNVariableManager.save_values]), capítulo, cena e backlog
## ([method VNNarrativeEngine.snapshot]), palco ([method VNStage.snapshot] e
## [method VNAudioManager.snapshot]), histórico
## ([method VNSceneScheduler.get_history]) e plugins
## ([method VNPluginHost.save_data]); assina com HMAC (BS §8.3).
##
## Slots ([constant QUICK], [code]slot_<n>[/code] de 1 a 99,
## [code]auto_<n>[/code] de 1 a 3) viram [code]saves/<slot>.json[/code], com a
## miniatura em [code]saves/<slot>.png[/code].
##
## Specs: RT §3.0 passo 4, §3.4, §5.2 (galeria), §8.1–§8.5; BS §8.3;
## [code]save.schema.json[/code] ([code]Profile[/code]); Plugin SDK §9, §9.1.
## Tarefas: M2-10, M2-11, M2-13, M3-05, M3-06.

## Um save foi gravado (o Engine emite [code]sys.game_saved[/code]).
signal saved(slot: StringName, autosave: bool)
## O perfil mudou na memória (será gravado com debounce).
signal profile_changed()

const QUICK := &"quick"
const MAX_MANUAL_SLOTS := 99
const AUTOSAVE_SLOTS := 3

## Motivos de [method autosave].
const AUTOSAVE_SETTINGS := &"settings"       ## settings.autosave (pontos de seleção)
const AUTOSAVE_ACTIVITY := &"activity"       ## antes de cada atividade, sempre (RT §5.3 passo 3)
const AUTOSAVE_SCENE_START := &"scene_start" ## início da cena (RT §8.1)


func module_id() -> StringName:
	return &"saves"


## Slot manual [code]slot_<n>[/code] (n = 1 a 99).
static func manual_slot(n: int) -> StringName:
	return StringName("slot_%d" % n)


## Slot de autosave [code]auto_<n>[/code] (n = 1 a 3).
static func auto_slot(n: int) -> StringName:
	return StringName("auto_%d" % n)


## Caminho do save no VNStorage.
static func slot_path(slot: StringName) -> String:
	return "saves/%s.json" % slot


## Caminho da miniatura no VNStorage (320 × 180).
static func thumbnail_path(slot: StringName) -> String:
	return "saves/%s.png" % slot


# --- Saves ------------------------------------------------------------------

## Grava no slot (manual ou rápido). Recusa com [code]INVALID_STATE[/code]
## fora dos pontos do RT §8.1 ([method VNNarrativeEngine.can_save]).
@abstract func save(slot: StringName, label: String = "") -> VNResult

## Autosave no próximo slot do rodízio. O motivo
## [constant AUTOSAVE_ACTIVITY] vale mesmo com [code]settings.autosave: off[/code].
@abstract func autosave(reason: StringName) -> VNResult

## Carrega o slot (RT §8.3): valida, confere a assinatura e a política de
## [code]save_tamper[/code], restaura os módulos na ordem dos passos 2 a 6 e
## entrega a retomada ao [method VNNarrativeEngine.resume_from_save].
@abstract func load_slot(slot: StringName) -> VNResult

## O save mais recente entre todos os slots, rápido e autosaves ([code]continue[/code]); vazio se não há.
@abstract func latest_slot() -> StringName

## Resumo dos saves existentes, para as telas: [code]{ slot, label, created_at,
## thumbnail, thumbnail_sensitive }[/code], em ordem de slot.
@abstract func list_slots() -> Array[Dictionary]

@abstract func delete_slot(slot: StringName) -> Error

## Existe ao menos um save ([code]sys.ui.has_save[/code]).
@abstract func has_save() -> bool

## O dicionário do save no formato do schema, sem restaurar nada (Preview, testes).
@abstract func build_save(label: String = "") -> Dictionary


# --- Perfil (RT §8.5; save.schema.json → Profile) ---------------------------

## Lê e confere [code]profile.json[/code] (RT §3.0 passo 4). Assinatura
## inválida com [code]reject[/code]: guarda como [code]profile.rejected.json[/code],
## começa vazio e devolve [code]ok = false[/code].
@abstract func load_profile() -> VNResult

## O perfil atual na memória.
@abstract func profile() -> Dictionary

## Grava [code]profile.json[/code] agora (fim de jogo, RT §3.4, e ao sair).
@abstract func flush_profile() -> Error

## Grava com debounce: em cada ponto de seleção, ao fim do jogo e ao sair (RT §8.5).
@abstract func mark_profile_dirty() -> void

## Ação reset_profile: apaga e recria o perfil vazio; os saves ficam (RT §8.5).
@abstract func reset_profile() -> VNResult

## Final visto (RT §3.4), texto lido (hash curto do caminho) e asset visto
## (galeria, RT §5.2). Todos vão para o perfil com debounce, exceto o final,
## que o Engine grava na hora com [method flush_profile].
@abstract func record_ending(ending_id: String) -> void
@abstract func mark_text_seen(text_path: String) -> void
@abstract func is_text_seen(text_path: String) -> bool
@abstract func mark_asset_seen(asset_id: String) -> void

## Dados de perfil e recordes de um plugin (Plugin SDK §9.1). O
## [code]VNProfileAPI[/code] do SDK é a fachada.
@abstract func get_plugin_profile_data(plugin: StringName) -> Variant
@abstract func set_plugin_profile_data(plugin: StringName, data: Variant) -> VNResult
@abstract func submit_record(plugin: StringName, board: StringName, score: float, meta: Dictionary = {}) -> int
@abstract func get_records(plugin: StringName, board: StringName) -> Array[Dictionary]
