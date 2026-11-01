extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var WorldClock = root.get_node("WorldClock")
	var DataManager = root.get_node("DataManager")
	WorldClock.set_physics_process(false)
	var old = WorldClock.elapsed_seconds
	for value in [NAN, INF, -1.0]:
		if WorldClock.advance(value) or WorldClock.elapsed_seconds != old: quit(1); return
	var ship = DataManager.definitions["ship.haven"]
	if DataManager.reload(PackedStringArray(["res://data/missing.tres"])): quit(1); return
	if DataManager.definitions.get("ship.haven") != ship: quit(1); return
	var shell = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	if shell.startup_failure.is_empty() or not paused: quit(1); return
	shell.get_node("StartButton").emit_signal("pressed")
	if not shell.startup_failure.is_empty() or shell.session_stage != "menu": quit(1); return
	shell.get_node("StartButton").emit_signal("pressed")
	if shell.get_node_or_null("GameCRTSlot/Preparation") == null: quit(1); return
	shell.queue_free()
	await process_frame
	print("M0 foundation smoke passed")
	quit(0)
