extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.get_node("UserSettings").tutorial_completed = false # Capture named preparation pages independently of local profile.
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	var capture_mode := OS.get_environment("CONSOLE_CAPTURE_MODE")
	if capture_mode in ["preparation", "settings", "generation", "tutorial", "background"]:
		shell.get_node("StartButton").emit_signal("pressed")
		var count := 1 if capture_mode == "settings" else 5 if capture_mode == "generation" else 3 if capture_mode == "tutorial" else 2 if capture_mode == "background" else 4
		for step in range(count):
			if shell.get_node("GameCRTSlot/Preparation").stage == "tutorial":
				shell.get_node("GameCRTSlot/Preparation").tutorial.skip()
			shell.get_node("GameCRTSlot/Preparation").advance()
		if capture_mode == "tutorial":
			var trainer: Control = shell.get_node("GameCRTSlot/Preparation").tutorial
			trainer.perform("scan")
			trainer.perform("select")
		await create_timer(0.7, true).timeout
	elif capture_mode in ["harbor", "game", "damage", "archive", "library", "guide-return", "sortie", "flight-nav"]:
		shell.get_node("StartButton").emit_signal("pressed")
		for step in range(7):
			if shell.get_node("GameCRTSlot/Preparation").stage == "tutorial":
				shell.get_node("GameCRTSlot/Preparation").tutorial.skip()
			shell.get_node("GameCRTSlot/Preparation").advance()
		var harbor: Control = shell.get_node("GameCRTSlot/Harbor")
		if capture_mode == "harbor":
			harbor.navigation.cast_off()
			harbor.navigation.set_command(0.0, 6.0)
			harbor.advance_navigation(30.0)
			harbor.toggle_pause()
		else:
			harbor.navigation.cast_off()
			harbor.navigation.set_command(0.0, 10.0)
			harbor.advance_navigation(100.0)
		if capture_mode == "damage":
			var world: Node = root.get_node("WorldState")
			var clock: Node = root.get_node("WorldClock")
			var mission: Node = root.get_node("MissionController")
			world.set_ship_command(42.0, 22.0)
			clock.advance(1000.0)
			world.set_ship_command(42.0, 0.0)
			clock.advance(10.0)
			mission.start_damage_control()
		if capture_mode == "guide-return":
			var mission: Node = root.get_node("MissionController")
			mission.prepare_sortie()
			mission.launch_sortie()
			root.get_node("WorldClock").advance(5)
			mission.begin_return()
			mission.aircraft_fuel_seconds = 110
			shell.get_node("GameCRTSlot").get_child(0)._refresh_ui()
		if capture_mode == "archive":
			shell.get_node("GameCRTSlot").get_child(0).toggle_archive()
		if capture_mode == "library":
			shell.get_node("GameCRTSlot").get_child(0).toggle_unit_library()
		if capture_mode == "sortie":
			root.get_node("MissionController").prepare_sortie()
			root.get_node("MissionController").set_sortie_ship_standby(true)
		if capture_mode == "flight-nav":
			var mission: Node = root.get_node("MissionController")
			mission.prepare_sortie()
			mission.set_sortie_ship_standby(true)
			mission.launch_sortie()
			root.get_node("WorldClock").advance(5)
			mission.set_aircraft_waypoint(mission.aircraft_position_km + Vector2(8, -8))
			root.get_node("WorldClock").advance(70)
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
