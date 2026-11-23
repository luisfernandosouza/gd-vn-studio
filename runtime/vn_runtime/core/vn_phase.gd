class_name VNPhase
extends RefCounted
## Estados do ciclo de vida do jogo (RT §3). Os mesmos nomes vão no campo
## [code]phase[/code] do Preview ([code]preview-protocol.schema.json[/code]).

const BOOT := &"BOOT"
const TITLE := &"TITLE"
const NEW_GAME := &"NEW_GAME"
const LOAD_GAME := &"LOAD_GAME"
const CHAPTER_ENTER := &"CHAPTER_ENTER"
const SELECTION_POINT := &"SELECTION_POINT"
const SCENE_RUNNING := &"SCENE_RUNNING"
const ACTIVITY := &"ACTIVITY"
const SCENE_END := &"SCENE_END"
const CHAPTER_EXIT := &"CHAPTER_EXIT"
const GAME_END := &"GAME_END"

const ALL: Array[StringName] = [
	BOOT, TITLE, NEW_GAME, LOAD_GAME, CHAPTER_ENTER, SELECTION_POINT,
	SCENE_RUNNING, ACTIVITY, SCENE_END, CHAPTER_EXIT, GAME_END,
]


## Há partida em andamento ([code]sys.ui.in_game[/code]).
static func is_in_game(phase: StringName) -> bool:
	return phase not in [BOOT, TITLE, GAME_END]
