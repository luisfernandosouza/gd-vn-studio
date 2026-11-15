class_name VNI18nAPI
extends RefCounted

var strings: Dictionary

func _init(p_strings: Dictionary = {}) -> void:
	strings = p_strings

func text(key: String, fallback: String = "", params: Dictionary = {}) -> String:
	return str(strings.get(key, fallback)).format(params)
