class_name VNRuntimePlugin
extends RefCounted

func _vn_init(_ctx) -> void: pass
func _vn_game_started(_is_new_game: bool) -> void: pass
func _vn_start_activity(_activity_id: StringName, _params: Dictionary, _handle) -> void: pass
func _vn_cancel_activity(_handle) -> void: pass
func _vn_save() -> Variant: return null
func _vn_load(_data: Variant) -> void: pass
