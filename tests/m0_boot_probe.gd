extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var shell = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	if shell.startup_failure.is_empty() or not paused: quit(1); return
	var source := OS.get_environment("M0_REPAIR_RESOURCE")
	if source.is_empty(): quit(1); return
	var file := FileAccess.open("res://data/ships/escort_carrier.tres", FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(source))
	file.close()
	shell.get_node("StartButton").emit_signal("pressed")
	if not shell.startup_failure.is_empty(): quit(1); return
	print("M0 boot recovery probe passed")
	quit(0)
