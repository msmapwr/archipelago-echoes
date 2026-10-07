extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var library: Control = load("res://scenes/unit_showcase.tscn").instantiate()
	root.add_child(library)
	library.family_picker.select(OS.get_environment("ICON_FAMILY_INDEX").to_int())
	library.refresh()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("ICON_CAPTURE_PATH")
	var error := root.get_texture().get_image().save_png(path)
	print("Icon capture: ", error_string(error))
	quit(error)
