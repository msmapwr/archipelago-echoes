extends SceneTree

const Preferences = preload("res://scripts/core/game_preferences.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "user://qa_preferences_%d.cfg" % Time.get_ticks_usec()
	var preferences = Preferences.new()
	preferences.master_volume = 37
	preferences.window_preset = 0
	preferences.reduced_crt = true
	_check(preferences.save_to(path), "preferences are saved")
	var restored = Preferences.new()
	_check(restored.load_from(path) and restored.master_volume == 37 and restored.window_preset == 0 and restored.reduced_crt, "saved preferences round trip")
	preferences.master_volume = 55
	_check(preferences.save_to(path) and restored.load_from(path) and restored.master_volume == 55, "atomic replacement works on existing preferences")
	var bytes := FileAccess.get_file_as_string(path)
	preferences.master_volume = 101
	_check(not preferences.save_to(path) and FileAccess.get_file_as_string(path) == bytes, "invalid settings preserve existing file")
	var bad_path := path + ".invalid"
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_string("[settings]\nversion=99\nmaster_volume=100\n")
	file.close()
	_check(not restored.load_from(bad_path) and restored.master_volume == 55, "unsupported settings version preserves current configuration")
	var world: Node = root.get_node("WorldState")
	var mission: Node = root.get_node("MissionController")
	_check(world.load_first_scenario(12345), "chosen seed generates a valid map")
	var islands: String = str(world.map.islands)
	world.load_first_scenario(12345)
	_check(str(world.map.islands) == islands, "same seed recreates island layout")
	world.load_first_scenario(54321)
	_check(str(world.map.islands) != islands, "different seed changes island layout")
	var old_map: RefCounted = world.map
	_check(not world.load_first_scenario(-1) and world.map == old_map and world.scenario_seed == 54321, "invalid generation preserves last valid map")
	mission.restart_scenario()
	_check(world.scenario_seed == 54321 and world.map.seed == 54321, "mission restart preserves generated seed")
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	shell.get_node("StartButton").emit_signal("pressed")
	var prep: Control = shell.get_node("GameCRTSlot/Preparation")
	prep.advance()
	_check(prep.stage == "settings" and prep.settings_form.visible and not prep.body.visible, "settings page exposes functional controls")
	var settings: Node = root.get_node("UserSettings")
	var original_preferences: RefCounted = settings.preferences
	var original_path: String = settings.settings_path
	settings.settings_path = path
	prep.volume_input.value = 42
	prep.reduced_input.button_pressed = true
	prep.apply_button.emit_signal("pressed")
	_check(settings.preferences.master_volume == 42 and "已应用" in prep.settings_status.text, "settings UI applies and saves candidate")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.42) and not AudioServer.is_bus_mute(0), "settings apply actual master bus volume")
	var loaded = Preferences.new()
	_check(loaded.load_from(path) and loaded.master_volume == 42, "UI settings are persisted")
	prep.defaults_button.emit_signal("pressed")
	_check(prep.volume_input.value == 80 and settings.preferences.master_volume == 42, "restore defaults remains a draft until applied")
	settings.settings_path = "user://qa_missing_directory_%d/preferences.cfg" % Time.get_ticks_usec()
	prep.apply_button.emit_signal("pressed")
	_check(settings.preferences.master_volume == 42 and "失败" in prep.settings_status.text, "failed settings save does not apply or replace configuration")
	settings.settings_path = original_path
	settings.preferences = original_preferences
	original_preferences.apply()
	for step in range(4):
		prep.advance()
	_check(prep.stage == "generation" and prep.generation_ready and paused, "generation validates world while simulation is frozen")
	prep.seed_input.value = 270930
	_check(not prep.generation_ready and prep.advance_button.disabled, "seed edits invalidate completion")
	prep.advance()
	_check(prep.stage == "generation", "unbuilt seed cannot enter harbor")
	prep.generate_button.emit_signal("pressed")
	_check(prep.generation_ready and world.scenario_seed == 270930, "generate action commits selected seed")
	prep.seed_input.get_line_edit().text = "270931"
	prep.advance()
	_check(prep.stage == "generation" and not prep.generation_ready, "uncommitted seed text cannot bypass generation")
	prep.seed_input.value = 270930
	prep.generate_button.emit_signal("pressed")
	var data: Node = root.get_node("DataManager")
	data.errors.append("qa_generation_failure")
	prep.generate_button.emit_signal("pressed")
	_check(not prep.generation_ready and prep.advance_button.disabled and "失败" in prep.generation_status.text, "generation failure offers visible retry and blocks progression")
	data.errors.erase("qa_generation_failure")
	prep.generate_button.emit_signal("pressed")
	prep.advance()
	prep.advance()
	var harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	harbor.navigation.cast_off()
	harbor.navigation.set_command(0, 10)
	harbor.advance_navigation(100)
	_check(shell.session_stage == "mission" and world.scenario_seed == 270930 and world.map.seed == 270930, "departure retains generated world")
	await process_frame
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(bad_path)
	if failures.is_empty():
		print("Settings and generation smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
