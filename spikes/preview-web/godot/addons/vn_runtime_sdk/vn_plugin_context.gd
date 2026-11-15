class_name VNPluginContext
extends RefCounted

class UI:
	var root: Control
	func push_overlay(packed: PackedScene) -> Node:
		var n := packed.instantiate()
		root.add_child(n)
		return n
	func pop_overlay(n: Node) -> void:
		n.queue_free()

class Variables:
	var store: Dictionary
	func get_value(id: String, default_value = null):
		return store.get("plugin.fishing." + id.trim_prefix("~"), default_value)
	func set_value(id: String, v) -> void:
		store["plugin.fishing." + id.trim_prefix("~")] = v
	func add_value(id: String, v) -> void:
		set_value(id, get_value(id, 0) + v)

class Events:
	func emit(name: String, payload: Dictionary = {}) -> void:
		print("[evento] ", name, " ", payload)

class Narrative:
	var variables := Variables.new()
	var events := Events.new()

class Profile:
	func submit_record(_board: StringName, _score: float, _meta: Dictionary = {}) -> int:
		return 1

class Audio:
	func play(_asset: String) -> void:
		pass

var ui := UI.new()
var narrative := Narrative.new()
var profile := Profile.new()
var audio := Audio.new()
var config: Dictionary
var i18n: VNI18nAPI
var theme := VNThemeInfo.new()

static func create(root: Control, p_config: Dictionary, vars: Dictionary, strings: Dictionary) -> VNPluginContext:
	var c := VNPluginContext.new()
	c.ui.root = root
	c.config = p_config
	c.narrative.variables.store = vars
	c.i18n = VNI18nAPI.new(strings)
	return c
