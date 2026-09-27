extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world: Node = root.get_node("WorldState")
	var clock: Node = root.get_node("WorldClock")
	clock.reset()
	_check(world.load_first_scenario(), "scenario resets navigation state")
	var main: Control = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	var radar: Control = main.get_node("Content/RadarFrame/Radar")
	main.get_node("Content/Details/HeadingControls/TurnStarboard").emit_signal("pressed")
	main.get_node("Content/Details/SpeedControls/SpeedUp").emit_signal("pressed")
	_check(is_equal_approx(world.ship_heading_degrees, 15.0) and is_equal_approx(world.ship_speed_knots, 5.0), "visible controls issue navigation commands")
	var initial_bearing: float = main.last_observed_bearing_degrees
	var initial_marker: Vector2 = radar._contact_position()
	_check(is_equal_approx(initial_bearing, 42.0), "initial observation comes from world coordinates")
	_check(not world.set_ship_command(90.0, world.ship_max_speed_knots + 1.0), "speed above ship limit is rejected")
	_check(not world.set_ship_command(INF, 5.0), "non-finite heading is rejected")
	_check(world.set_ship_command(90.0, 10.0), "ship accepts course and speed")
	var start: Vector2 = world.ship_position_km
	_check(clock.advance(600.0), "clock accepts simulation interval")
	var expected_distance := 10.0 * 1.852 * 600.0 / 3600.0
	_check(world.ship_position_km.distance_to(start + Vector2(expected_distance, 0.0)) < 0.001, "ship moves at commanded knots")
	_check(is_equal_approx(main.last_observed_bearing_degrees, initial_bearing), "reported bearing stays at last scan")
	_check(radar._contact_position().distance_to(initial_marker) > 1.0, "radar plots last observation relative to moving ship")
	_check("航速" in main.get_node("Content/Details/ShipDetails").text, "ship panel reports live navigation")
	main.advance_sweep()
	_check(absf(main.last_observed_bearing_degrees - world.contact_bearing_degrees()) < 0.01, "new scan samples world-relative bearing")
	_check("观测" in main.get_node("Content/Details/ContactDetails").text, "contact panel shows observation time")
	paused = true
	var paused_position: Vector2 = world.ship_position_km
	_check(not clock.advance(600.0) and world.ship_position_km == paused_position, "pause freezes ship movement")
	paused = false

	var first_island: Dictionary = world.map.islands[0]
	var blocked_start: Vector2 = first_island["center"] - Vector2(first_island["radius_km"] + 0.2, 0.0)
	_check(world.map.is_water(blocked_start), "collision test begins in water")
	world.ship_position_km = blocked_start
	_check(world.set_ship_command(90.0, 10.0), "ship accepts course toward island")
	clock.advance(600.0)
	_check(world.ship_position_km == blocked_start and is_zero_approx(world.ship_speed_knots), "island blocks movement and stops ship")
	_check("航路受阻" in main.get_node("Content/Details/NavigationStatus").text, "blocked route gives visible feedback")
	var boundary_start := Vector2(99.0, 50.0)
	_check(world.map.is_water(boundary_start), "boundary test begins in water")
	world.ship_position_km = boundary_start
	world.set_ship_command(90.0, 10.0)
	clock.advance(600.0)
	_check(world.ship_position_km == boundary_start and is_zero_approx(world.ship_speed_knots), "map boundary also stops ship")
	main.advance_sweep()
	_check(not radar.contact_visible, "lost contact marker is hidden")
	_check("最后观测" in main.get_node("Content/Details/ContactDetails").text, "lost contact retains last observation")
	await process_frame
	var log_bottom: float = main.get_node("Content/Details/EventDetails").get_global_rect().end.y
	var footer_top: float = main.get_node("Footer").get_global_rect().position.y
	_check(log_bottom <= footer_top, "navigation panel stays clear of footer at target viewport")

	main.queue_free()
	clock.reset()
	world.load_first_scenario()
	_finish()

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("P1 navigation smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
