extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var mission: Node = root.get_node("MissionController")
	var clock: Node = root.get_node("WorldClock")
	mission.restart_scenario()
	var scene: PackedScene = load("res://scenes/main/crt_main.tscn")
	var main: Control = scene.instantiate()
	root.add_child(main)
	var capture_mode := OS.get_environment("CRT_CAPTURE_MODE")
	if capture_mode == "flight" or capture_mode == "settlement":
		mission.prepare_sortie()
		mission.launch_sortie()
		clock.advance(5.0)
		clock.advance(240.0)
		mission.perform_recon()
		if capture_mode == "settlement":
			mission.begin_return()
			clock.advance(250.0)
			mission.land_aircraft()
			mission.complete_mission()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var output := OS.get_environment("CRT_CAPTURE_PATH")
	if output.is_empty():
		printerr("Set CRT_CAPTURE_PATH to an absolute PNG path")
		quit(1)
		return
	var result := image.save_png(output)
	if result != OK:
		printerr("CRT capture failed: %d" % result)
		quit(1)
		return
	print("CRT capture saved: " + output)
	quit(0)
