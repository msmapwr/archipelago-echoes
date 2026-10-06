extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	var clock: Node = root.get_node("WorldClock")
	await process_frame
	_check(paused, "menu pauses simulation")
	_check(ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "window keeps 16:9 aspect")
	_check(is_equal_approx(shell.size.x / shell.size.y, 16.0 / 9.0), "shell is 16:9")
	var menu_crt: Control = shell.get_node("MenuCRT")
	_check(is_equal_approx(menu_crt.size.x / menu_crt.size.y, 16.0 / 9.0), "main CRT is 16:9")
	_check(shell.get_node("GameCRTSlot").get_child_count() == 0, "game CRT is not loaded before Start")
	_check(shell.get_node("StartButton").visible, "Start is visible")
	var buttons: Array[Node] = []
	_collect_buttons(shell, buttons)
	_check(buttons.size() == 1 and buttons[0] == shell.get_node("StartButton"), "menu has one button")
	var seconds_before: float = clock.elapsed_seconds
	await process_frame
	_check(is_equal_approx(clock.elapsed_seconds, seconds_before), "world time remains stopped in menu")
	if DisplayServer.get_name() == "headless":
		shell.get_node("StartButton").emit_signal("pressed")
	else:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		var logical_position: Vector2 = shell.get_node("StartButton").get_global_rect().get_center()
		click.position = logical_position * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
		click.global_position = click.position
		Input.parse_input_event(click)
		await process_frame
		var release: InputEventMouseButton = click.duplicate()
		release.pressed = false
		Input.parse_input_event(release)
	await process_frame
	_check(paused and not shell.started and shell.session_stage == "opening", "Start enters preparation without starting simulation")
	var preparation: Control = shell.get_node("GameCRTSlot/Preparation")
	shell._enter_mission()
	_check(not shell.started and shell.session_stage == "opening", "mission cannot start before orders and harbor confirmation")
	var stages := ["opening", "settings", "background", "tutorial", "orders", "generation", "harbor"]
	for stage in stages:
		_check(preparation.stage == stage and shell.session_stage == stage, "preparation follows %s" % stage)
		_check(paused and is_equal_approx(clock.elapsed_seconds, seconds_before), "preparation keeps world time frozen")
		if stage == "harbor":
			var data: Node = root.get_node("DataManager")
			data.errors.append("session_flow_test: unavailable scenario")
			preparation.advance_button.emit_signal("pressed")
			_check(paused and not shell.started and shell.session_stage == "harbor" and "失败" in preparation.body.text, "loading error keeps player in preparation with a recovery path")
			data.errors.erase("session_flow_test: unavailable scenario")
		preparation.advance_button.emit_signal("pressed")
	var harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	await process_frame
	_check(harbor.menu_button.get_global_rect().end.y <= harbor.get_global_rect().position.y + 678.0, "harbor controls fit within CRT glass")
	_check(paused and not shell.started and shell.session_stage == "harbor_navigation", "harbor driving precedes mission simulation")
	shell._enter_mission()
	_check(not shell.started, "mission cannot start until actual gate crossing")
	var mission: Node = root.get_node("MissionController")
	var health_before: float = mission.ship_health
	var enemy_before: Vector2 = root.get_node("WorldState").contact_position_km
	harbor.advance_navigation(10.0)
	_check(harbor.navigation.position_km == Vector2.ZERO, "mooring prevents movement")
	harbor.cast_off_button.emit_signal("pressed")
	harbor.command_buttons[2].emit_signal("pressed")
	_check(harbor.navigation.speed_knots == 2.0, "throttle button controls harbor vessel")
	harbor.toggle_pause()
	harbor.advance_navigation(100.0)
	_check(harbor.navigation.position_km == Vector2.ZERO, "harbor pause freezes navigation")
	harbor.toggle_pause()
	harbor.advance_navigation(10.0)
	_check(paused and clock.elapsed_seconds == seconds_before and mission.ship_health == health_before and root.get_node("WorldState").contact_position_km == enemy_before, "harbor does not advance sea combat or mission clock")
	harbor.navigation.set_command(0.0, 10.0)
	harbor.advance_navigation(100.0)
	_check(not paused and shell.started and shell.session_stage == "mission", "departure enters playable state")
	var world: Node = root.get_node("WorldState")
	_check(world.ship_position_km.is_equal_approx(world.map.ship_start_km + Vector2(0, -0.32)) and world.ship_speed_knots == 10.0 and world.ship_heading_degrees == 0.0, "sea mission preserves departure position, heading and speed")
	_check(not menu_crt.visible and not shell.get_node("StartButton").visible, "menu gives way to game CRT")
	var slot: Control = shell.get_node("GameCRTSlot")
	_check(slot.visible and slot.get_child_count() == 1, "previous CRT is mounted in central slot")
	_check(slot.get_child_count() == 1 and slot.get_child(0).has_node("ScreenContainer/ScreenViewport/Terminal"), "existing terminal remains accessible")
	var game: Node = root.get_node("GameManager")
	game.report_player_death("session_flow_test")
	var menu_action: Button = slot.get_child(0).get_node("ScreenContainer/ScreenViewport/Terminal/Content/DetailsFrame/DetailsScroll/Details/PhaseActions/MainMenu")
	_check(shell.session_stage == "failed" and menu_action.visible, "failure exposes return to menu")
	menu_action.emit_signal("pressed")
	await process_frame
	_check(paused and not shell.started and shell.session_stage == "menu" and slot.get_child_count() == 0, "return cleans mission screen and pauses world")
	shell.get_node("StartButton").emit_signal("pressed")
	_check(shell.session_stage == "opening", "new session starts preparation from the beginning")
	shell.get_node("GameCRTSlot/Preparation").menu_requested.emit()
	await process_frame
	_check(shell.session_stage == "menu" and slot.get_child_count() == 0, "preparation can be cancelled")
	shell.get_node("StartButton").emit_signal("pressed")
	for step in range(7):
		shell.get_node("GameCRTSlot/Preparation").advance()
	var cancelled_harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	cancelled_harbor.navigation.cast_off()
	cancelled_harbor.navigation.set_command(0, 6)
	cancelled_harbor.advance_navigation(10)
	cancelled_harbor.menu_button.emit_signal("pressed")
	await process_frame
	_check(paused and shell.session_stage == "menu" and slot.get_child_count() == 0, "harbor cancellation removes navigation and keeps world frozen")
	shell.get_node("StartButton").emit_signal("pressed")
	for step in range(7):
		shell.get_node("GameCRTSlot/Preparation").advance()
	var fresh_harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	_check(fresh_harbor.navigation.moored and fresh_harbor.navigation.position_km == Vector2.ZERO and fresh_harbor.navigation.speed_knots == 0, "new harbor session clears prior voyage")
	fresh_harbor.menu_button.emit_signal("pressed")
	if failures.is_empty():
		print("Console menu smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _collect_buttons(node: Node, buttons: Array[Node]) -> void:
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		_collect_buttons(child, buttons)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
