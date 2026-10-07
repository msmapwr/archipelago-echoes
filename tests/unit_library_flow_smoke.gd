extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var mission: Node = root.get_node("MissionController")
	var game: Node = root.get_node("GameManager")
	mission.restart_scenario()
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	game.set_paused(false)
	main.toggle_unit_library()
	check(paused and main.unit_library.visible, "library pauses simulation")
	var before: float = root.get_node("WorldClock").elapsed_seconds
	root.get_node("WorldClock").advance(10)
	check(root.get_node("WorldClock").elapsed_seconds == before, "library freezes world")
	main.toggle_archive()
	check(not main.archive.visible, "modal archive cannot steal pause ownership")
	main.close_unit_library()
	check(not paused, "close resumes library-owned pause")
	game.set_paused(true)
	main.toggle_unit_library()
	main.close_unit_library()
	check(paused, "close preserves existing pause")
	game.set_paused(false)
	main._on_contact_selected(mission.CONTACT_ID)
	check(not main.contact_icon.visible, "unknown target details do not disclose shape")
	mission.scan()
	mission.scan()
	mission.identify_contact()
	main._refresh_ui()
	check(main.contact_icon.visible, "confirmed selected target gets structural preview")
	main.toggle_unit_library()
	game.mode = "settlement"
	main.close_unit_library()
	check(paused, "ending remains paused")
	if failures.is_empty():
		print("Unit library flow smoke passed")
		quit(0)
	else:
		for failure in failures: printerr(failure)
		quit(1)

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
