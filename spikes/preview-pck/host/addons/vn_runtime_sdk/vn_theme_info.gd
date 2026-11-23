class_name VNThemeInfo
extends RefCounted

const COLORS := {&"text": Color(0.95, 0.95, 0.95), &"accent": Color(0.95, 0.55, 0.2)}

func font(_name: StringName) -> Font:
	return ThemeDB.fallback_font

func color(name: StringName) -> Color:
	return COLORS.get(name, Color.WHITE)
