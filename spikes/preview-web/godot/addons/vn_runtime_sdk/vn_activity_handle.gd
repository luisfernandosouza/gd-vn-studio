class_name VNActivityHandle
extends RefCounted

signal completed(outcome: StringName, payload: Dictionary)

var mode: StringName
var rng: VNRandom
var _active := true

func _init(p_mode: StringName = &"story", seed_value: int = 0) -> void:
	mode = p_mode
	rng = VNRandom.new(seed_value)

func is_active() -> bool:
	return _active

func complete(outcome: StringName, payload: Dictionary = {}) -> void:
	_active = false
	completed.emit(outcome, payload)

func fail(message: String) -> void:
	_active = false
	push_error(message)
	completed.emit(&"failed", {"message": message})
