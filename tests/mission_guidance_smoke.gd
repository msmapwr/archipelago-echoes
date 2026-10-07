extends SceneTree

const Guidance = preload("res://scripts/core/mission_guidance.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("UserSettings").tutorial_completed = false # First-run preparation fixture; no persistent write.
	_check(Guidance.project({}).stage == "search", "no observations directs active search")
	_check(Guidance.project({"scans": 1, "contact_visible": false}).next.contains("回波中断"), "lost contact supplies recovery direction")
	_check(Guidance.project({"identified": true}).stage == "sortie", "identification alone does not claim mission success")
	_check(Guidance.project({"mode": "configuration"}).stage == "configure", "configuration and transfer are distinct stages")
	_check(Guidance.project({"mode": "switching", "switch_seconds": 3.5}).next.contains("3.5"), "transfer shows actual remaining time")
	_check(Guidance.project({"mode": "cockpit", "contact_distance": 4}).stage == "recon", "unidentified air contact requires recon")
	_check(Guidance.project({"mode": "cockpit", "identified": true}).stage == "return", "identified contact directs return without a kill requirement")
	var landing := {"mode": "returning", "ship_afloat": true, "ship_distance": 2.0, "airfield_distance": 5.0, "ship_speed": 12.0}
	_check(Guidance.project(landing).can_land, "ship landing includes 2 km and 12 knot boundaries")
	landing.ship_speed = 12.1
	landing.airfield_distance = 1.0
	_check(not Guidance.project(landing).can_land, "high-speed ship has the same precedence as real landing even near airfield")
	landing.ship_distance = 2.01
	_check(Guidance.project(landing).can_land, "outside ship window permits nearby airfield")
	landing.ship_afloat = false
	_check(Guidance.project(landing).can_land, "sunken ship does not prevent valid airfield recovery")
	var warning := Guidance.project({"mode": "cockpit", "airborne": true, "flight_speed": 100.0, "fuel_seconds": 60.0, "ship_distance": 20.0, "ship_speed": 0.0})
	_check(warning.warning.contains("燃油警报") and warning.return_seconds > 60, "fuel warning compares remaining endurance against actual recovery estimate")
	_check(Guidance.project({"mode": "bridge", "recovered": true}).stage == "identify", "early ship recovery can complete missing identification")
	_check(Guidance.project({"mode": "recovered", "recovered": true}).stage == "incomplete", "early airfield recovery explains unmet objective")
	_check(Guidance.project({"mode": "campaign_failed", "death_reason": "fuel_exhausted"}).next.contains("燃油耗尽"), "failure explains recorded cause")
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	shell.get_node("StartButton").emit_signal("pressed")
	for step in range(7):
		var prep: Control = shell.get_node("GameCRTSlot/Preparation")
		if prep.stage == "tutorial":
			prep.tutorial.skip()
		prep.advance()
	var harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	harbor.navigation.cast_off()
	harbor.navigation.set_command(0, 10)
	harbor.advance_navigation(100)
	var main: Control = shell.get_node("GameCRTSlot").get_child(0)
	var mission: Node = root.get_node("MissionController")
	var game: Node = root.get_node("GameManager")
	var clock: Node = root.get_node("WorldClock")
	var world: Node = root.get_node("WorldState")
	world.set_ship_command(0, 0)
	await process_frame
	_check(main.guidance.stage == "identify", "live task shows first observed objective")
	var footer: Control = main.terminal.get_node("Footer")
	footer.get_node("TimeScale").emit_signal("pressed")
	var health: float = mission.ship_health
	var ammo: int = mission.ship_ammo
	await _click_button(main, footer.get_node("CommandArchive"))
	var seconds: float = clock.elapsed_seconds
	var task: Resource = root.get_node("DataManager").definitions[game.current_task_id]
	_check(paused and main.archive.visible and main.archive.content.text.contains(task.objective), "archive opens actual task briefing and pauses live simulation")
	clock.advance(100)
	_check(clock.elapsed_seconds == seconds and mission.ship_health == health and mission.ship_ammo == ammo, "archive freezes time and combat resources")
	main.archive.tabs[1].emit_signal("pressed")
	_check(main.archive.content.text.contains("待完成") and main.archive.content.text.contains("海域种子"), "progress tab shows real objectives and generated seed")
	main.archive.tabs[2].emit_signal("pressed")
	_check(main.archive.content.text.contains("命令已接收") and main.archive.content.text.contains("离港线"), "history includes command and departure with simulation timestamps")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	space.pressed = true
	if DisplayServer.get_name() == "headless":
		main._input(space)
	else:
		Input.parse_input_event(space)
		await process_frame
		var space_release: InputEventKey = space.duplicate()
		space_release.pressed = false
		Input.parse_input_event(space_release)
	_check(paused and main.archive.visible, "space does not resume simulation behind archive")
	main.archive.cycle_focus(false)
	_check(main.archive.tabs.has(main.archive.get_viewport().gui_get_focus_owner()), "archive focus stays within its controls")
	await _press_escape(main)
	_check(not paused and clock.time_scale == 10, "close restores running state and original compression")
	clock.set_time_scale(1)
	main._toggle_pause()
	main.toggle_archive()
	main.close_archive()
	_check(paused, "opening while already paused preserves manual pause")
	main._toggle_pause()
	mission.scan()
	mission.identify_contact()
	_check(main.guidance.stage == "sortie", "live identification updates next objective")
	mission.prepare_sortie()
	mission.launch_sortie()
	_check(main.guidance.stage == "transfer" and mission.sorties_launched == 0, "configuration alone does not complete launch milestone")
	clock.advance(5)
	_check(mission.sorties_launched == 1 and main.guidance.milestones[2], "actual launch completes sortie milestone")
	mission.begin_return()
	_check(main.guidance.stage == "recover" and main.guidance.can_land, "return at home shows actual landing readiness")
	mission.land_aircraft()
	_check(main.guidance.stage == "report", "recovery directs report submission")
	mission.complete_mission()
	_check(main.guidance.stage == "complete" and main.guidance.milestones[4], "settlement updates final objective")
	main.toggle_archive()
	main.close_archive()
	main._toggle_pause()
	_check(paused, "archive close and pause control cannot restart ended world")
	main._on_restart_pressed()
	_check(not paused and mission.sorties_launched == 0 and game.last_death_reason.is_empty() and main.guidance.stage == "identify", "restart resets milestones, cause and guide")
	_check(root.get_node("EventBus").history[0].simulation_seconds == 0.0, "new scenario log begins at its own zero time")
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)
	mission.begin_return()
	mission.set_aircraft_destination("airfield")
	mission.aircraft_position_km = mission.airfield_position_km
	mission.land_aircraft()
	_check(game.mode == "recovered" and main.guidance.stage == "incomplete" and main._button("PhaseActions/MainMenu").visible and main._button("PhaseActions/Restart").visible, "unidentified airfield recovery provides actual restart and menu exits")
	main._on_restart_pressed()
	game.report_player_death("fuel_exhausted")
	_check(main.guidance.stage == "failed" and main.objective_hint.text.contains("燃油耗尽"), "live failure presents recorded cause")
	main.toggle_archive()
	main.close_archive()
	_check(paused, "failure archive cannot resume world")
	await process_frame
	_check(main.objective_hint.get_global_rect().end.y <= main.terminal.get_node("Content").get_global_rect().position.y, "fixed objective does not overlap playable controls")
	_check(footer.get_global_rect().end.x <= main.terminal.size.x and footer.get_node("Help").get_global_rect().end.x <= main.terminal.size.x, "persistent archive entry fits CRT footer")
	main.menu_requested.emit()
	await process_frame
	if failures.is_empty():
		print("Mission guidance and archive smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _click_button(main: Control, button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.emit_signal("pressed")
		return
	# Containers settle over deferred frames after dynamically built controls are hidden.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var logical: Vector2 = main.get_node("ScreenContainer").global_position + button.get_global_rect().get_center()
	click.position = logical * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	click.global_position = click.position
	Input.parse_input_event(click)
	await process_frame
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func _press_escape(main: Control) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	if DisplayServer.get_name() == "headless":
		main._input(key)
	else:
		Input.parse_input_event(key)
		await process_frame
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
