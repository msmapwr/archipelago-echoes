extends Node

const Preferences = preload("res://scripts/core/game_preferences.gd")
const SETTINGS_PATH := "user://preferences.cfg"
var preferences = Preferences.new()
var settings_path: String = SETTINGS_PATH

func _ready() -> void:
	preferences.load_from(SETTINGS_PATH)
	preferences.apply()

func save_and_apply(candidate: RefCounted) -> bool:
	if not candidate.save_to(settings_path):
		return false
	preferences = candidate
	preferences.apply()
	return true
