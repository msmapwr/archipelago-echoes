extends Node

const Preferences = preload("res://scripts/core/game_preferences.gd")
const SETTINGS_PATH := "user://preferences.cfg"
var preferences = Preferences.new()
var settings_path: String = SETTINGS_PATH
var tutorial_progress_path: String = "user://tutorial_progress.cfg"
var tutorial_completed: bool = false
var skip_tutorial_by_default: bool = true
var tutorial_progress_error: String = ""

func _ready() -> void:
	preferences.load_from(SETTINGS_PATH)
	preferences.apply()
	load_tutorial_progress()

func load_tutorial_progress() -> bool:
	tutorial_progress_error = ""
	if not FileAccess.file_exists(tutorial_progress_path):
		tutorial_completed = false
		return true
	var config := ConfigFile.new()
	if config.load(tutorial_progress_path) != OK or config.get_value("tutorial", "version", 0) != 1 or typeof(config.get_value("tutorial", "completed", false)) != TYPE_BOOL:
		tutorial_progress_error = "教程记录无法读取；仍可手动打开新手教程。"
		tutorial_completed = false
		return false
	tutorial_completed = config.get_value("tutorial", "completed", false)
	return true

func mark_tutorial_completed() -> bool:
	if tutorial_completed:
		return true
	var config := ConfigFile.new()
	config.set_value("tutorial", "version", 1)
	config.set_value("tutorial", "completed", true)
	var pending := tutorial_progress_path + ".tmp"
	if config.save(pending) != OK or DirAccess.rename_absolute(pending, tutorial_progress_path) != OK:
		tutorial_progress_error = "教程记录保存失败；本次可继续，仍可手动打开教程。"
		return false
	tutorial_completed = true
	tutorial_progress_error = ""
	return true

func save_and_apply(candidate: RefCounted) -> bool:
	if not candidate.save_to(settings_path):
		return false
	preferences = candidate
	preferences.apply()
	return true
