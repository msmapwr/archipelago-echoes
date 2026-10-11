extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func records(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("diagnostic file readable: " + path)
		return result
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty(): continue
		var value = JSON.parse_string(line)
		check(value is Dictionary, "each flushed line is valid JSON")
		if value is Dictionary: result.append(value)
	return result

func run() -> void:
	var logger = root.get_node("DebugLog")
	var mission = root.get_node("MissionController")
	var clock = root.get_node("WorldClock")
	var bus = root.get_node("EventBus")
	check(logger.enabled and not logger.log_path.is_empty(), "debug session starts with persistent file")
	mission.restart_scenario()
	var ammo: int = mission.ship_ammo
	var health: float = mission.ship_health
	var elapsed: float = clock.elapsed_seconds
	var history_count: int = bus.history.size()
	logger.checkpoint("smoke_before")
	check(mission.ship_ammo == ammo and mission.ship_health == health and clock.elapsed_seconds == elapsed and bus.history.size() == history_count, "checkpoint does not mutate gameplay or player archive")
	check(not mission.fire_ship_gun(), "ordinary rejected action exercised")
	var details := {"order_id": "debug.order", "shot_id": "debug.shot", "position": Vector2(3, -4), "nested": [Vector2(1, 2)]}
	bus.record("diagnostic_fixture", details, 123.25)
	details.position = Vector2.ZERO
	check(bus.history.back().details.position == Vector2(3, -4), "diagnostics preserve original independent event snapshot")
	paused = true
	logger._process(2.1)
	check(clock.elapsed_seconds == elapsed and paused, "wall-time checkpoint preserves paused simulation")
	logger.checkpoint("smoke_paused")
	paused = false
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	current_scene = main
	check(logger.snapshot().ui.scene_file_path == "res://scenes/main/crt_main.tscn", "active scene is included in diagnostic snapshot")
	main._button("RadarActions/NextSweep").pressed.emit()
	main.ammunition_selector.item_selected.emit(2)
	main.toggle_archive()
	main.close_archive()
	var disappearing := Button.new()
	disappearing.name = "RemovedOnClick"
	disappearing.text = "removed fixture"
	disappearing.pressed.connect(func() -> void: root.remove_child(disappearing))
	root.add_child(disappearing)
	disappearing.pressed.emit()
	disappearing.free()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_F3
	logger._input(key)
	current_scene = null
	main.queue_free()
	await process_frame
	var values := records(logger.log_path)
	var last_sequence := 0
	var rejected := false
	var fixture := false
	var paused_snapshot := false
	var button_seen := false
	var option_seen := false
	var archive_seen := false
	var manual_seen := false
	var removed_seen := false
	for value in values:
		check(value.schema_version == 1 and value.sequence > last_sequence and value.session_id == logger.session_id, "session/schema/sequence are stable and increasing")
		last_sequence = value.sequence
		if value.kind == "action_rejected":
			rejected = value.details.message.contains("确认") and value.has("state") and not value.details.stack.is_empty()
		if value.kind == "event.diagnostic_fixture":
			fixture = value.simulation_seconds == 123.25 and value.details.position.x == 3 and value.details.position.y == -4 and value.details.nested[0].y == 2
		if value.kind == "checkpoint" and value.details.reason == "smoke_paused": paused_snapshot = value.state.paused
		if value.kind == "ui_button_pressed": button_seen = true
		if value.kind == "ui_button_pressed" and value.details.node.ends_with("RemovedOnClick"): removed_seen = true
		if value.kind == "ui_option_selected": option_seen = true
		if value.kind == "ui_archive_opened": archive_seen = true
		if value.kind == "checkpoint" and value.details.reason == "manual_F3": manual_seen = true
	check(rejected, "rejection has reason, call stack and authoritative state")
	check(fixture, "event preserves precise simulation time and recursive vector JSON")
	check(paused_snapshot and button_seen and option_seen and archive_seen and manual_seen, "pause/UI/options/archive/manual checkpoint are observable")
	check(removed_seen, "button removed by prior handler still logs cached path safely")
	logger.close()
	logger.close()
	values = records(logger.log_path)
	check(values.back().kind == "session_end" and not logger.enabled, "normal close is flushed and idempotent")
	var old_level := OS.get_environment("ECHO_DEBUG_LEVEL")
	OS.set_environment("ECHO_DEBUG_LEVEL", "off")
	var disabled = load("res://scripts/core/debug_log.gd").new()
	root.add_child(disabled)
	check(not disabled.enabled and disabled.log_path.is_empty(), "off mode produces no diagnostic file")
	disabled.queue_free()
	await process_frame
	OS.set_environment("ECHO_DEBUG_LEVEL", "debug")
	var old_directory := OS.get_environment("ECHO_DEBUG_DIR")
	OS.set_environment("ECHO_DEBUG_DIR", logger.log_path)
	var unwritable = load("res://scripts/core/debug_log.gd").new()
	root.add_child(unwritable)
	check(not unwritable.enabled and mission.ship_health == health, "directory failure disables diagnostics without changing game")
	unwritable.queue_free()
	await process_frame
	OS.set_environment("ECHO_DEBUG_DIR", old_directory)
	var bounded = load("res://scripts/core/debug_log.gd").new()
	root.add_child(bounded)
	bounded._budget_bytes = 1024
	bounded.write("info", "budget_fixture", {"payload": "x".repeat(2048)})
	check(not bounded.enabled and records(bounded.log_path).back().kind == "log_budget_exhausted", "budget terminates recording with explicit final record")
	bounded.queue_free()
	await process_frame
	OS.set_environment("ECHO_DEBUG_LEVEL", old_level)
	if failures.is_empty():
		print("Debug log smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)
