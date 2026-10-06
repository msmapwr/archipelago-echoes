extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	var capture_mode := OS.get_environment("CONSOLE_CAPTURE_MODE")
	if capture_mode == "preparation":
		shell.get_node("StartButton").emit_signal("pressed")
		for step in range(4):
			shell.get_node("GameCRTSlot/Preparation").advance()
		await create_timer(0.7, true).timeout
	elif capture_mode == "game" or capture_mode == "damage":
		shell.get_node("StartButton").emit_signal("pressed")
		for step in range(7):
			shell.get_node("GameCRTSlot/Preparation").advance()
		if capture_mode == "damage":
			var world: Node = root.get_node("WorldState")
			var clock: Node = root.get_node("WorldClock")
			var mission: Node = root.get_node("MissionController")
			world.set_ship_command(42.0, 22.0)
			clock.advance(1000.0)
			world.set_ship_command(42.0, 0.0)
			clock.advance(10.0)
			mission.start_damage_control()
	else:
		await create_timer(2.3, true).timeout
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("CONSOLE_CAPTURE_PATH")
	if output.is_empty():
		printerr("Set CONSOLE_CAPTURE_PATH to an absolute PNG path")
		quit(1)
		return
	var result := root.get_texture().get_image().save_png(output)
	if result != OK:
		printerr("Console capture failed: %d" % result)
		quit(1)
		return
	print("Console capture saved: " + output)
	quit(0)
