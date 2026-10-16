extends Node

# Developer diagnostics are separate from player-visible intelligence and archives.
const SCHEMA_VERSION := 1
const LEVELS := {"debug": 10, "info": 20, "warning": 30, "error": 40, "off": 100}
var session_id := ""
var log_path := ""
var sequence := 0
var scenario_sequence := 0
var enabled := false
var _file: FileAccess
var _threshold := 10
var _snapshot_elapsed := 0.0
var _budget_bytes := 32 * 1024 * 1024
var _closed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var level := OS.get_environment("ECHO_DEBUG_LEVEL").to_lower()
	if level.is_empty(): level = "debug" if OS.is_debug_build() else "info"
	_threshold = LEVELS.get(level, 10)
	if _threshold == 100: return
	var directory := OS.get_environment("ECHO_DEBUG_DIR")
	if directory.is_empty(): directory = ProjectSettings.globalize_path("user://debug")
	if not directory.is_absolute_path():
		push_warning("[DebugLog] ECHO_DEBUG_DIR must be absolute; using user://debug")
		directory = ProjectSettings.globalize_path("user://debug")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_warning("[DebugLog] cannot create diagnostic directory; gameplay continues")
		return
	var limit := OS.get_environment("ECHO_DEBUG_MAX_MB")
	if limit.is_valid_int(): _budget_bytes = clampi(limit.to_int(), 1, 1024) * 1024 * 1024
	session_id = "%s-%d-%d" % [Time.get_datetime_string_from_system(true).replace(":", "-"), OS.get_process_id(), Time.get_ticks_usec()]
	log_path = directory.path_join("echo-%s.jsonl" % session_id)
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_warning("[DebugLog] cannot open diagnostic file; gameplay continues")
		return
	enabled = true
	write("info", "session_start", {"engine": Engine.get_version_info().string, "project": ProjectSettings.get_setting("application/config/name"), "debug_build": OS.is_debug_build(), "pid": OS.get_process_id(), "level": level, "budget_bytes": _budget_bytes})
	print("[DebugLog] " + log_path)
	get_tree().node_added.connect(_watch_node)
	call_deferred("checkpoint", "autoload_ready")

func _watch_node(node: Node) -> void:
	if node is BaseButton:
		var path := str(node.get_path())
		var label: String = node.text if node is Button else node.get_class()
		node.pressed.connect(_button_pressed.bind(node, path, label))
	if node is OptionButton:
		node.item_selected.connect(_option_selected.bind(node, str(node.get_path())))

func _button_pressed(button: BaseButton, path: String, fallback_label: String) -> void:
	write("info", "ui_button_pressed", {"node": path, "label": button.text if is_instance_valid(button) and button is Button else fallback_label}, true)

func _option_selected(index: int, button: OptionButton, path: String) -> void:
	write("info", "ui_option_selected", {"node": path, "index": index, "label": button.get_item_text(index) if is_instance_valid(button) and index >= 0 and index < button.item_count else "unavailable"}, true)

func _input(input_event: InputEvent) -> void:
	if input_event is InputEventKey and input_event.pressed and not input_event.echo and input_event.keycode in [KEY_1, KEY_2, KEY_F1, KEY_F2, KEY_F3, KEY_SPACE, KEY_ESCAPE]:
		write("info", "input_key", {"key": OS.get_keycode_string(input_event.keycode)}, true)
		if input_event.keycode == KEY_F3:
			checkpoint("manual_F3")
			print("[DebugLog] manual checkpoint / " + log_path)

func _process(delta: float) -> void:
	if not enabled: return
	_snapshot_elapsed += delta
	if _snapshot_elapsed >= 2.0:
		_snapshot_elapsed = 0
		checkpoint("periodic")

func _exit_tree() -> void:
	close()

func close() -> void:
	if _closed: return
	write("info", "session_end", {"reason": "tree_exit"})
	_closed = true
	enabled = false
	if _file != null:
		_file.flush()
		_file.close()
		_file = null

func event(event_data: Dictionary) -> void:
	if event_data.get("kind", "") == "scenario_started": scenario_sequence += 1
	write("info", "event." + str(event_data.get("kind", "unknown")), event_data.get("details", {}), true, float(event_data.get("simulation_seconds", -1)))

func action_result(accepted: bool, message: String) -> void:
	write("info" if accepted else "warning", "action_accepted" if accepted else "action_rejected", {"message": message, "stack": get_stack()}, true)

func checkpoint(reason: String) -> void:
	write("debug", "checkpoint", {"reason": reason}, true)

func write(level: String, kind: String, details: Dictionary = {}, include_state: bool = false, simulation_seconds: float = -1.0) -> void:
	if not enabled or _closed or LEVELS.get(level, 20) < _threshold: return
	sequence += 1
	var clock := get_node_or_null("/root/WorldClock")
	var seconds: float = simulation_seconds if simulation_seconds >= 0 else float(clock.elapsed_seconds) if clock != null else 0.0
	var record := {"schema_version": SCHEMA_VERSION, "session_id": session_id, "scenario_sequence": scenario_sequence, "sequence": sequence, "utc": Time.get_datetime_string_from_system(true), "monotonic_msec": Time.get_ticks_msec(), "simulation_seconds": seconds, "level": level, "kind": kind, "details": _json_value(details)}
	if include_state: record.state = snapshot()
	_file.store_line(JSON.stringify(record))
	_file.flush() # Preserve the latest command if the engine crashes.
	if _file.get_error() != OK:
		enabled = false
		push_warning("[DebugLog] diagnostic write failed; gameplay continues")
	elif _file.get_position() >= _budget_bytes:
		sequence += 1
		record.sequence = sequence
		record.level = "warning"
		record.kind = "log_budget_exhausted"
		record.details = {"budget_bytes": _budget_bytes}
		record.erase("state")
		_file.store_line(JSON.stringify(record))
		_file.flush()
		enabled = false
		push_warning("[DebugLog] session log budget reached; recording stopped")

func snapshot() -> Dictionary:
	var result := {"paused": get_tree().paused, "fps": Engine.get_frames_per_second(), "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}
	var scene := get_tree().current_scene
	if scene == null: scene = get_node_or_null("/root/ConsoleShell")
	if scene != null and scene.is_inside_tree():
		var ui := {"scene_file_path": scene.scene_file_path, "views": []}
		var slot := scene.get_node_or_null("GameCRTSlot")
		if slot != null:
			for view in slot.get_children():
				ui.views.append(str(view.name))
				if view.name == "Preparation": ui.preparation_stage = view.get("stage")
				if view.name == "Harbor":
					var navigation = view.get("navigation")
					if navigation != null:
						ui.harbor = {"position_km": _json_value(navigation.position_km), "heading_degrees": navigation.heading_degrees, "speed_knots": navigation.speed_knots, "elapsed_seconds": navigation.elapsed_seconds, "moored": navigation.moored, "departed": navigation.departed, "message": navigation.message}
		result.ui = ui
	var fields := {
		"UserSettings": ["tutorial_completed", "skip_tutorial_by_default", "tutorial_progress_error"],
		"GameManager": ["mode", "player_alive", "ship_afloat", "target_identified", "player_recovered", "recovery_site", "task_settled", "last_death_reason"],
		"WorldClock": ["elapsed_seconds", "time_scale"],
		"WorldState": ["scenario_seed", "ship_position_km", "ship_heading_degrees", "ship_speed_knots", "contact_position_km", "ship_draft_m", "ship_grounded", "last_navigation_impact"],
		"MissionController": ["ship_health", "enemy_health", "enemy_alive", "enemy_heading_degrees", "enemy_speed_knots", "enemy_tracking_ship", "radar_emitting", "contact_visible", "contact_scan_count", "last_contact_position_km", "last_contact_seconds", "fire_control_target_id", "fire_control_order_id", "fire_control_aim_mode", "fire_control_locked", "lock_status", "selected_mount_id", "selected_ammunition_id", "ship_ammo", "next_ship_fire_seconds", "turret_heading_degrees", "fire_control_correction_km", "repair_teams", "repair_seconds_remaining", "projectiles", "last_gun_impact", "aircraft_airborne", "aircraft_position_km", "aircraft_fuel_seconds", "aircraft_destination", "sorties_launched", "switch_seconds_remaining", "last_message"]}
	for node_name in fields:
		var node := get_node_or_null("/root/" + node_name)
		if node == null or not node.is_node_ready():
			result[node_name] = {"ready": false}
			continue
		var values := {}
		for field in fields[node_name]: values[field] = _json_value(node.get(field))
		if node_name == "UserSettings": values.preferences = {"master_volume": node.preferences.master_volume, "window_preset": node.preferences.window_preset, "reduced_crt": node.preferences.reduced_crt}
		if node_name == "MissionController":
			values.gun_groups = _json_value(node.gun_groups())
			values.enemy_navigation = {"withdrawing": node._enemy_navigation.withdrawing, "threat_known": node._enemy_navigation.threat_known, "threat_position_km": _json_value(node._enemy_navigation.threat_position_km), "blocked": node.enemy_navigation_blocked, "observed_maneuver": node.contact_maneuver_status()}
		result[node_name] = values
	return result

func _json_value(value: Variant) -> Variant:
	if value is Vector2: return {"x": _json_value(value.x), "y": _json_value(value.y)}
	if value is Dictionary:
		var converted := {}
		for key in value: converted[str(key)] = _json_value(value[key])
		return converted
	if value is Array or value is PackedStringArray:
		var converted: Array = []
		for item in value: converted.append(_json_value(item))
		return converted
	if value is float and not is_finite(value): return str(value)
	return value
