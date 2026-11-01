extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var clock = root.get_node("WorldClock")
	clock.set_physics_process(false)
	if not clock.set_time_scale(50): quit(1); return
	var main = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	for i in range(40): main.radar._capture_echo("contact.alpha")
	if main.radar._echoes.size() != 1: quit(1); return
	main.queue_free()
	await process_frame
	clock.set_time_scale(1)
	print("Playtest feedback smoke passed")
	quit(0)
