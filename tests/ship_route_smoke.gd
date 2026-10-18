extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func events(kind: String) -> int:
	var count := 0
	for event in root.get_node("EventBus").history:
		if event.kind == kind: count += 1
	return count

func reset() -> void:
	paused = false
	root.get_node("MissionController").restart_scenario()
	root.get_node("MissionController").enemy_alive = false

func run() -> void:
	root.get_node("WorldClock").set_physics_process(false)
	var world := root.get_node("WorldState")
	var mission := root.get_node("MissionController")
	var clock := root.get_node("WorldClock")
	var game := root.get_node("GameManager")
	reset()
	var start: Vector2 = world.ship_position_km
	var target := start + Vector2(2, 0)
	paused = true
	check(mission.set_ship_waypoint(target), "paused route accepts safe target")
	var first_id: String = world.ship_waypoint_order_id
	var eta: float = world.ship_route_solution().eta_seconds
	check(is_equal_approx(world.ship_speed_knots, 10) and absf(eta - 2 / (10 * world.KNOT_TO_KM_PER_SECOND)) < 0.01, "stopped ship gets explicit 10 kn command and correct ETA")
	check(not clock.advance(100) and world.ship_position_km == start, "queued route does not move paused world")
	for invalid in [Vector2(NAN, 50), Vector2(-1, 50), Vector2(100, 50), start + Vector2(0.01, 0), world.map.islands[0].center]:
		check(not mission.set_ship_waypoint(invalid) and world.ship_waypoint_order_id == first_id and world.ship_waypoint_active, "rejected route preserves previous active order")
	var island: Dictionary = world.map.islands[0]
	var coast_start: Vector2 = island.center - Vector2(island.radius_km + 1, 0)
	var coast_end: Vector2 = island.center + Vector2(island.radius_km + 1, 0)
	world.ship_position_km = coast_start
	check(world.map.is_water(coast_end) and not mission.set_ship_waypoint(coast_end), "deep endpoints do not permit a route crossing island interior")
	var shallow: Vector2 = island.center - Vector2(island.radius_km + world.map.shelf_factor(island, PI) * 0.1, 0)
	check(world.map.depth_at(shallow) > world.ship_draft_m and world.map.depth_at(shallow) < world.ship_draft_m + 2 and not mission.set_ship_waypoint(shallow), "physically navigable shoal still fails route safety margin")
	world.ship_position_km = start
	world.ship_grounded = true
	check(not mission.set_ship_waypoint(target), "grounding requires manual escape")
	world.ship_grounded = false
	check(not world.set_ship_command(NAN, 8) and world.ship_waypoint_active, "invalid helm does not cancel valid route")
	paused = false
	clock.advance(eta * 0.5)
	check(world.ship_position_km.distance_to(start + Vector2(1, 0)) < 0.001 and world.ship_waypoint_active, "half ETA reaches half route")
	clock.advance(eta * 2)
	check(world.ship_position_km.distance_to(target) < 0.001 and not world.ship_waypoint_active and world.ship_speed_knots == 0 and world.ship_waypoint_status == "arrived", "large step clamps to waypoint and stops")
	clock.advance(50)
	check(events("ship_waypoint_arrived") == 1 and world.ship_position_km.distance_to(target) < 0.001, "arrival records once and remains stopped")
	check(mission.command_ship(90, 5) and world.ship_waypoint_status == "manual", "manual command clears completed waypoint marker and guidance")
	check(mission.set_ship_waypoint(target + Vector2(1, 0)) and world.ship_waypoint_order_id != first_id, "new route has distinct order")
	check(mission.command_ship(180, 5) and not world.ship_waypoint_active, "manual helm takes over route")
	clock.advance(10)
	check(world.ship_position_km.y > target.y, "manual course moves independently of old target")
	for scale in [1.0, 10.0]:
		reset()
		check(mission.set_ship_waypoint(start + Vector2(0.1, 0)), "short route accepted")
		clock.set_time_scale(scale)
		for step in range(int(40 / scale)): clock._physics_process(1)
		check(not world.ship_waypoint_active and world.ship_position_km.distance_to(start + Vector2(0.1, 0)) < 0.001, "both time scales reach same exact stopped destination")
	reset()
	mission.set_ship_waypoint(start + Vector2(3, 0))
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)
	check(mission.aircraft_airborne and world.ship_waypoint_active, "route survives transfer to airborne commander")
	var before: Vector2 = world.ship_position_km
	clock.advance(20)
	check(world.ship_position_km.x > before.x and not mission.set_ship_waypoint(start + Vector2(4, 0)), "ship continues custody while pilot cannot command new ship route")
	check(mission.request_ship_standby() and not world.ship_waypoint_active and world.ship_speed_knots == 0, "airborne standby cancels route and stops")
	reset()
	mission.set_ship_waypoint(start + Vector2(3, 0))
	mission.prepare_sortie()
	mission.set_sortie_ship_standby(true)
	mission.launch_sortie()
	clock.advance(5)
	check(not world.ship_waypoint_active and world.ship_speed_knots == 0, "configured launch standby cancels active route")
	reset()
	mission.set_ship_waypoint(start + Vector2(3, 0))
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)
	mission.apply_navigation_damage({"kind":"collision", "damage":100})
	check(game.player_alive and not game.ship_afloat and not world.ship_waypoint_active, "airborne commander survives loss while ship route terminates")
	reset()
	mission.set_ship_waypoint(target)
	world.ship_draft_m = 400
	clock.advance(1)
	check(not world.ship_waypoint_active and world.ship_waypoint_status == "interrupted" and world.ship_speed_knots == 0, "runtime hazard interrupts rather than silently continuing route")
	reset()
	check(world.ship_waypoint_status == "manual" and world.ship_waypoint_km == Vector2.ZERO, "retry clears route and old waypoint")
	mission.set_ship_waypoint(target)
	game.report_ship_sunk()
	check(not world.ship_waypoint_active and not mission.set_ship_waypoint(target), "death cancels navigation and prevents new route")
	reset()
	await ui()
	if failures.is_empty():
		print("Ship route smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func ui() -> void:
	var world := root.get_node("WorldState")
	var mission := root.get_node("MissionController")
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	paused = true
	main.ship_route_button.button_pressed = true
	await process_frame
	await process_frame
	check(main.radar.ship_waypoint_input, "ship waypoint mode enables guarded chart input")
	var local_point: Vector2 = main.radar.size * 0.5 + Vector2(45, 0)
	var requested: Vector2 = main.radar.point_to_world(local_point)
	await right_click(main, local_point)
	check(world.ship_waypoint_active and world.ship_waypoint_km.distance_to(requested) < 0.001, "real CRT pointer sets ship rather than aircraft waypoint")
	var order: String = world.ship_waypoint_order_id
	await right_click(main, Vector2.ZERO)
	check(world.ship_waypoint_order_id == order, "outside circular chart cannot issue waypoint")
	main.radar.grab_focus()
	await key(main, KEY_RIGHT)
	await key(main, KEY_ENTER)
	check(world.ship_waypoint_km.distance_to(world.ship_position_km + Vector2(main.radar.display_range_km / 20, 0)) < 0.001, "keyboard can order ship waypoint")
	check(main._archive_history().contains("母舰航点") and main.guidance.next.contains("航点"), "route reaches archive and task guidance")
	check(main.ship_controls.get_index() < main.details.get_node("RadarActions").get_index(), "active navigation controls precede combat")
	main.toggle_archive()
	order = world.ship_waypoint_order_id
	await key(main, KEY_ENTER)
	check(world.ship_waypoint_order_id == order and paused, "archive consumes keys without issuing hidden route")
	main.toggle_archive()
	main.cancel_ship_route_button.emit_signal("pressed")
	check(not world.ship_waypoint_active and world.ship_speed_knots == 0, "actual cancel control stops route")
	main.ship_route_button.button_pressed = false
	check(not main.radar.ship_waypoint_input, "waypoint mode can be disarmed")
	main.queue_free()
	await process_frame
	reset()

func right_click(main: Control, local_point: Vector2) -> void:
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

func key(main: Control, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	if DisplayServer.get_name() == "headless":
		# Modal keyboard paths live on the main CRT, not on a hidden radar.
		if not main.archive.visible: main.radar._gui_input(event)
	else:
		Input.parse_input_event(event)
		await process_frame
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
