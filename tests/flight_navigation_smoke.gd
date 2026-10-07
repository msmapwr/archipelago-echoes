extends SceneTree

const Guidance = preload("res://scripts/core/mission_guidance.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("UserSettings").tutorial_completed = false # First-run preparation fixture; no persistent write.
	var mission: Node = root.get_node("MissionController")
	var clock: Node = root.get_node("WorldClock")
	var world: Node = root.get_node("WorldState")
	var game: Node = root.get_node("GameManager")
	mission.restart_scenario()
	_check(not mission.set_aircraft_waypoint(Vector2(30, 50)), "grounded player cannot command flight waypoint")
	_launch(mission, clock)
	_check(not mission.set_aircraft_waypoint(Vector2(NAN, 40)) and not mission.set_aircraft_waypoint(Vector2(-1, 40)), "invalid waypoint rejected without resource changes")
	var waypoint: Vector2 = mission.aircraft_position_km + Vector2(10, 0)
	var fuel: float = mission.aircraft_fuel_seconds
	_check(mission.set_aircraft_waypoint(waypoint), "valid waypoint can be ordered")
	var solution: Dictionary = mission.navigation_solution()
	_check(is_equal_approx(solution.eta_seconds, 10.0 / (mission.aircraft_speed_knots * mission.KNOT_TO_KM_PER_SECOND)) and solution.reachable, "waypoint ETA uses real speed and current fuel")
	_check(mission.aircraft_fuel_seconds == fuel, "navigation planning does not refill or consume fuel")
	clock.advance(solution.eta_seconds + 1)
	_check(mission.aircraft_position_km.distance_to(waypoint) < 0.001 and mission.aircraft_fuel_seconds < fuel, "navigator arrives without overshoot and burns fuel")
	_check(_events("aircraft_navigation_arrived") == 1, "arrival recorded once")
	clock.advance(10)
	_check(_events("aircraft_navigation_arrived") == 1 and mission.aircraft_position_km == waypoint, "prototype holding point still consumes fuel without event spam")
	paused = true
	fuel = mission.aircraft_fuel_seconds
	_check(mission.set_aircraft_waypoint(waypoint + Vector2(2, 0)), "paused navigation command can be queued")
	clock.advance(50)
	_check(mission.aircraft_position_km == waypoint and mission.aircraft_fuel_seconds == fuel, "paused navigation preserves position and fuel")
	paused = false
	_check(mission.set_aircraft_heading(180) and mission.aircraft_destination == "manual", "manual heading cancels waypoint navigation")
	clock.advance(1)
	_check(mission.aircraft_position_km.y > waypoint.y, "manual flight follows chosen heading")
	mission.set_aircraft_destination("airfield")
	_check(mission.begin_return() and mission.aircraft_destination == "airfield", "return preserves selected airport while carrier exists")
	mission.cancel_return()
	_check(not mission.begin_return("invalid") and game.mode == "cockpit", "invalid recovery choice cannot enter return")
	mission.begin_return("ship")
	game.report_ship_sunk()
	clock.advance(1)
	_check(game.player_alive and mission.aircraft_destination == "airfield" and _events("aircraft_navigation_diverted") == 1, "ship loss diverts airborne return without resurrecting carrier")
	clock.advance(1)
	_check(_events("aircraft_navigation_diverted") == 1, "diversion is not repeated each tick")
	mission.aircraft_fuel_seconds = 121
	clock.advance(2)
	clock.advance(1)
	_check(_events("aircraft_fuel_warning") == 1, "two minute warning fires once")
	clock.advance(90)
	_check(_events("aircraft_fuel_warning") == 2, "thirty second warning escalates once")
	clock.advance(30)
	_check(game.mode == "campaign_failed" and not mission.aircraft_airborne and not mission.set_aircraft_waypoint(waypoint), "fuel exhaustion still ends flight and forbids navigation")
	mission.restart_scenario()
	_check(_events("aircraft_fuel_warning") == 0 and mission.aircraft_waypoint_km == Vector2.ZERO, "retry clears route and warning state")
	_launch(mission, clock)
	# Explicit airport selection must work even inside a fast carrier's window.
	mission.airfield_position_km = world.ship_position_km
	world.set_ship_command(0, 22)
	mission.set_aircraft_destination("airfield")
	mission.begin_return()
	var overlap := {"mode": "returning", "destination": "airfield", "ship_afloat": true, "ship_speed": 22, "ship_distance": 0, "airfield_distance": 0}
	_check(Guidance.project(overlap).can_land and mission.land_aircraft() and game.recovery_site == "friendly_airfield", "chosen airport has matching guidance and actual recovery in overlapping windows")
	mission.restart_scenario()
	_launch(mission, clock)
	mission.airfield_position_km = world.ship_position_km
	world.set_ship_command(0, 22)
	mission.begin_return("ship")
	overlap.destination = "ship"
	_check(not Guidance.project(overlap).can_land and not mission.land_aircraft() and mission.aircraft_airborne, "explicit carrier still enforces speed limit")
	_check(mission.land_aircraft("friendly_airfield"), "explicit valid alternate site can recover safely")
	mission.restart_scenario()
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	shell.get_node("StartButton").emit_signal("pressed")
	for step in range(7):
		var prep: Control = shell.get_node("GameCRTSlot/Preparation")
		if prep.stage == "tutorial": prep.tutorial.skip()
		prep.advance()
	var harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	harbor.navigation.cast_off()
	harbor.navigation.set_command(0, 10)
	harbor.advance_navigation(100)
	var main: Control = shell.get_node("GameCRTSlot").get_child(0)
	_launch(mission, clock)
	_check(main.radar.flight_navigation and main.radar.own_position_km == mission.aircraft_position_km and not main.radar.sweep_enabled, "cockpit map centers on actual aircraft and separates navigation from ship radar sweep")
	game.set_paused(true)
	await process_frame
	await process_frame
	var local_point: Vector2 = main.radar.size * 0.5 + Vector2(55, -35)
	var requested: Vector2 = main.radar.point_to_world(local_point)
	await _right_click(main, local_point)
	_check(mission.aircraft_destination == "waypoint" and mission.aircraft_waypoint_km.distance_to(requested) < 0.01 and main.radar.navigation_target_visible, "right mouse input traverses real CRT viewport into guarded waypoint controller")
	main.radar.grab_focus()
	await _key(main, KEY_RIGHT)
	await _key(main, KEY_ENTER)
	_check(mission.aircraft_waypoint_km.distance_to(mission.aircraft_position_km + Vector2(main.radar.display_range_km / 20.0, 0)) < 0.01, "keyboard radar cursor can issue waypoint without mouse")
	_check(main.flight_details.text.contains("抵达估算"), "flight panel shows navigation fuel estimate")
	game.set_paused(false)
	mission.set_aircraft_destination("airfield")
	mission.begin_return()
	_check(main._button("PhaseActions/Land").disabled, "landing disabled outside selected airport window")
	mission.aircraft_position_km = mission.airfield_position_km
	mission.state_changed.emit()
	_check(not main._button("PhaseActions/Land").disabled and main.radar.own_position_km == mission.aircraft_position_km, "map and landing control track actual recovery window")
	await process_frame
	var button_rect: Rect2 = main._button("PhaseActions/Land").get_global_rect()
	var scroll_rect: Rect2 = main.details.get_parent().get_global_rect()
	_check(button_rect.position.y >= scroll_rect.position.y and button_rect.end.y <= scroll_rect.end.y, "landing action is visible without scrolling")
	main._button("PhaseActions/Land").emit_signal("pressed")
	_check(game.recovery_site == "friendly_airfield" and not main.radar.flight_navigation, "landing releases navigation control and restores ship map")
	main.menu_requested.emit()
	await process_frame
	if failures.is_empty():
		print("Flight navigation smoke test passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func _launch(mission: Node, clock: Node) -> void:
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)

func _events(kind: String) -> int:
	var count := 0
	for event in root.get_node("EventBus").history:
		if event.kind == kind: count += 1
	return count

func _right_click(main: Control, local_point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	if DisplayServer.get_name() == "headless":
		click.position = local_point
		main.radar._gui_input(click)
		return
	await RenderingServer.frame_post_draw
	var logical: Vector2 = main.get_node("ScreenContainer").global_position + main.radar.global_position + local_point
	click.position = logical * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	click.global_position = click.position
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame

func _key(main: Control, code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	if DisplayServer.get_name() == "headless":
		main.radar._gui_input(key)
	else:
		Input.parse_input_event(key)
		await process_frame
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame

func _check(condition: bool, description: String) -> void:
	if not condition: failures.append(description)
