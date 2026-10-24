extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func reset() -> void:
	paused = false
	root.get_node("MissionController").restart_scenario()
	root.get_node("MissionController").enemy_alive = false

func records(kind: String) -> Array:
	var matches: Array = []
	for event in root.get_node("EventBus").history:
		if event.kind == kind: matches.append(event)
	return matches

func run() -> void:
	root.get_node("WorldClock").set_physics_process(false)
	detour_and_budget()
	forecast_turns()
	editing()
	lifecycle()
	await ui()
	if failures.is_empty():
		print("Ship route queue smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func detour_and_budget() -> void:
	var world := root.get_node("WorldState")
	var mission := root.get_node("MissionController")
	var clock := root.get_node("WorldClock")
	reset()
	var island: Dictionary = world.map.islands[0]
	var margin: float = island.radius_km + 2
	var start: Vector2 = island.center - Vector2(margin, 0)
	var points: Array[Vector2] = [start + Vector2(0, -margin), island.center + Vector2(margin, -margin), island.center + Vector2(margin, 0)]
	world.ship_position_km = start
	check(not mission.set_ship_waypoint(points[2]), "direct route across island is rejected")
	paused = true
	check(mission.set_ship_waypoint(points[0]) and mission.set_ship_waypoint(points[1], true) and mission.set_ship_waypoint(points[2], true), "tail-based validation permits a safe multi-leg island detour")
	var solution: Dictionary = world.ship_route_solution()
	var eta: float = solution.eta_seconds
	check(solution.remaining == 3 and absf(solution.distance_km - margin * 4) < 0.001, "route distance and ETA include every leg rather than straight shortcut")
	solution.points.clear()
	check(world.ship_route_points.size() == 3 and not clock.advance(100), "solution snapshot cannot mutate queue and pause freezes route")
	paused = false
	clock.advance(eta + 100)
	check(world.ship_position_km.distance_to(points[2]) < 0.001 and mission.ship_health == 100 and not world.ship_waypoint_active and world.ship_speed_knots == 0, "single large tick follows all turns without touching island or overshooting final stop")
	var passed := records("ship_waypoint_reached")
	var arrived := records("ship_waypoint_arrived")
	check(passed.size() == 2 and arrived.size() == 1 and world.ship_route_reached == 3, "intermediate and final passage events are distinct and nonduplicated")
	if passed.size() == 2 and arrived.size() == 1:
		check(passed[0].simulation_seconds < passed[1].simulation_seconds and passed[1].simulation_seconds < arrived[0].simulation_seconds and absf(arrived[0].simulation_seconds - eta) < 0.1, "passage timestamps reflect actual travel within oversized clock step")
	clock.advance(100)
	check(records("ship_waypoint_arrived").size() == 1 and world.ship_position_km.distance_to(points[2]) < 0.001, "completed route stays stopped without repeated events")
	for scale in [1.0, 10.0]:
		reset()
		var origin: Vector2 = world.ship_position_km
		mission.set_ship_waypoint(origin + Vector2(0.1, 0))
		mission.set_ship_waypoint(origin + Vector2(0.1, -0.1), true)
		clock.set_time_scale(scale)
		for step in range(int(50 / scale)): clock._physics_process(1)
		check(world.ship_position_km.distance_to(origin + Vector2(0.1, -0.1)) < 0.001 and world.ship_route_reached == 2 and world.ship_speed_knots == 0, "1x and 10x preserve turning route completion")
	reset()
	var origin: Vector2 = world.ship_position_km
	mission.set_ship_waypoint(origin + Vector2(0.1, 0))
	mission.set_ship_waypoint(origin + Vector2(0.1, -1), true)
	clock.advance(0.15 / (10 * world.KNOT_TO_KM_PER_SECOND))
	check(world.ship_position_km.distance_to(origin + Vector2(0.1, -0.05)) < 0.001 and world.ship_route_points.size() == 1, "unused frame time continues along next leg rather than being discarded")

func forecast_turns() -> void:
	reset()
	var world := root.get_node("WorldState")
	var mission := root.get_node("MissionController")
	world.ship_position_km = Vector2(99.8, 50)
	mission.command_ship(90, 22)
	check(not world.navigation_risk().warning.is_empty(), "straight manual course warns about upcoming map boundary")
	mission.set_ship_waypoint(Vector2(99.9, 50))
	check(world.navigation_risk().warning.is_empty(), "forecast stops at final waypoint instead of projecting beyond arrival")
	mission.set_ship_waypoint(Vector2(99.9, 49), true)
	check(world.navigation_risk().warning.is_empty(), "forecast follows queued turn instead of straight continuation across boundary")
	reset()

func editing() -> void:
	reset()
	var world := root.get_node("WorldState")
	var mission := root.get_node("MissionController")
	var origin: Vector2 = world.ship_position_km
	for index in range(8): check(mission.set_ship_waypoint(origin + Vector2(index + 1, 0), index > 0), "pending route accepts points up to capacity")
	var order: String = world.ship_waypoint_order_id
	var revision: int = world.ship_route_revision
	var points: Array = world.ship_route_points.duplicate()
	check(not mission.set_ship_waypoint(origin + Vector2(9, 0), true) and world.ship_route_points == points and world.ship_route_revision == revision and world.ship_waypoint_order_id == order, "ninth append is rejected atomically")
	check(mission.remove_last_ship_waypoint() and world.ship_route_points.size() == 7 and world.ship_waypoint_km == points[0] and world.ship_speed_knots == 10, "tail removal preserves current leg, speed and order")
	points = world.ship_route_points.duplicate()
	check(not mission.set_ship_waypoint(world.map.islands[0].center, true) and world.ship_route_points == points, "unsafe appended leg leaves previous route intact below capacity")
	check(mission.set_ship_waypoint(origin + Vector2(8, -1), true) and world.ship_waypoint_order_id == order and world.ship_route_revision > revision, "append after undo edits existing route revision")
	check(mission.set_ship_waypoint(origin + Vector2(0, -1)) and world.ship_route_points.size() == 1 and world.ship_waypoint_order_id != order, "ordinary order replaces entire queue")
	check(mission.remove_last_ship_waypoint() and not world.ship_waypoint_active and world.ship_speed_knots == 0 and world.ship_route_points.is_empty(), "removing last pending point stops and clears route")
	check(not mission.remove_last_ship_waypoint(), "empty queue removal is rejected")

func lifecycle() -> void:
	reset()
	var world := root.get_node("WorldState")
	var mission := root.get_node("MissionController")
	var clock := root.get_node("WorldClock")
	var start: Vector2 = world.ship_position_km
	mission.set_ship_waypoint(start + Vector2(0.1, 0))
	mission.set_ship_waypoint(start + Vector2(0.1, -2), true)
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)
	clock.advance(30)
	check(mission.aircraft_airborne and world.ship_route_reached == 1 and world.ship_waypoint_active, "airborne custody proceeds through intermediate point")
	check(not mission.remove_last_ship_waypoint() and world.ship_route_points.size() == 1, "pilot cannot edit ship queue")
	check(mission.request_ship_standby() and world.ship_route_points.is_empty(), "airborne standby clears every pending leg")
	reset()
	mission.set_ship_waypoint(start + Vector2(1, 0))
	mission.set_ship_waypoint(start + Vector2(1, -1), true)
	world.ship_draft_m = 400
	clock.advance(1)
	check(world.ship_route_points.is_empty() and world.ship_waypoint_status == "interrupted", "runtime hazard clears future route rather than resuming after accident")
	reset()
	check(world.ship_route_reached == 0 and world.ship_route_revision == 0 and world.ship_route_points.is_empty(), "retry resets queue and revision")
	mission.set_ship_waypoint(start + Vector2(1, 0))
	mission.set_ship_waypoint(start + Vector2(1, -1), true)
	mission.apply_navigation_damage({"kind":"collision", "damage":100})
	check(world.ship_route_points.is_empty() and not world.ship_waypoint_active, "ship loss clears entire queued route")
	reset()

func ui() -> void:
	var world := root.get_node("WorldState")
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	paused = true
	main.ship_route_button.button_pressed = true
	await process_frame
	await process_frame
	var center: Vector2 = main.radar.size * 0.5
	await right_click(main, center + Vector2(30, 0), false)
	await right_click(main, center + Vector2(55, -35), true)
	check(world.ship_route_points.size() == 2 and main.radar.ship_route.points.size() == 2, "real Shift right-click appends a distinct displayed ship leg")
	main.ship_route_append.button_pressed = true
	await right_click(main, center + Vector2(80, -35), false)
	check(world.ship_route_points.size() == 3, "visible append control works without keyboard modifier")
	main.ship_route_append.button_pressed = false
	main.radar.grab_focus()
	await key(main, KEY_RIGHT, false)
	await key(main, KEY_RIGHT, false)
	await key(main, KEY_RIGHT, false)
	await key(main, KEY_ENTER, true)
	check(world.ship_route_points.size() == 4 and main.ship_route_status.tooltip_text.contains("WP4"), "Shift Enter appends and complete route is readable in status tooltip")
	var before: int = world.ship_route_revision
	main.toggle_archive()
	await key(main, KEY_ENTER, true)
	check(world.ship_route_revision == before and paused, "archive modal blocks hidden route append")
	main.toggle_archive()
	main.trim_ship_route_button.emit_signal("pressed")
	check(world.ship_route_points.size() == 3 and main._archive_history().contains("撤回末点"), "actual undo control edits queue and archives decision")
	main.cancel_ship_route_button.emit_signal("pressed")
	check(world.ship_route_points.is_empty() and world.ship_speed_knots == 0, "actual cancel clears full queue")
	main.queue_free()
	await process_frame
	reset()

func right_click(main: Control, local_point: Vector2, append: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.shift_pressed = append
	click.pressed = true
	if DisplayServer.get_name() == "headless":
		click.position = local_point
		main.radar._gui_input(click)
		return
	await RenderingServer.frame_post_draw
	var logical: Vector2 = main.get_node("ScreenContainer").global_position + main.radar.global_position + local_point
	click.position = logical * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	click.global_position = click.position
	var motion := InputEventMouseMotion.new()
	motion.position = click.position
	motion.global_position = click.position
	Input.parse_input_event(motion)
	await process_frame
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame

func key(main: Control, code: Key, append: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = append
	event.pressed = true
	if DisplayServer.get_name() == "headless":
		if not main.archive.visible: main.radar._gui_input(event)
	else:
		Input.parse_input_event(event)
		await process_frame
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
