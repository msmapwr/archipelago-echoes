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
	_check(not paused and shell.started, "Start enters playable state")
	_check(not menu_crt.visible and not shell.get_node("StartButton").visible, "menu gives way to game CRT")
	var slot: Control = shell.get_node("GameCRTSlot")
	_check(slot.visible and slot.get_child_count() == 1, "previous CRT is mounted in central slot")
	_check(slot.get_child_count() == 1 and slot.get_child(0).has_node("ScreenContainer/ScreenViewport/Terminal"), "existing terminal remains accessible")
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
