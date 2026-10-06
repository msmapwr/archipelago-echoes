extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	if OS.get_environment("CONSOLE_CAPTURE_MODE") == "game":
		shell.get_node("StartButton").emit_signal("pressed")
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
