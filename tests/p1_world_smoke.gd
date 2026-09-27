extends SceneTree

const ArchipelagoMap = preload("res://scripts/world/archipelago_map.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var contact: ContactDefinition = root.get_node("DataManager").get_definition("contact.alpha") as ContactDefinition
	_check(contact != null, "sample contact exists")
	if contact == null:
		_finish()
		return
	var first = ArchipelagoMap.new(270928, contact.bearing_degrees, contact.range_km)
	var repeated = ArchipelagoMap.new(270928, contact.bearing_degrees, contact.range_km)
	var alternate = ArchipelagoMap.new(270929, contact.bearing_degrees, contact.range_km)
	_check(first.islands == repeated.islands, "same seed reproduces islands")
	_check(first.islands != alternate.islands, "different seed changes islands")
	var world_state: Node = root.get_node("WorldState")
	_check(world_state.map != null and world_state.map.seed == 270928, "scenario state owns the fixed seed map")
	_check(world_state.ship_position_km == first.ship_start_km, "scenario state owns carrier position")
	_check(first.is_water(first.ship_start_km), "carrier starts in water")
	_check(first.is_water(first.contact_position_km), "target contact is at sea")
	_check(first.can_navigate_segment(first.ship_start_km, first.contact_position_km), "carrier-to-contact corridor is navigable")
	var first_island: Dictionary = first.islands[0]
	_check(not first.is_water(first_island["center"]), "island center blocks navigation")
	_check(first_island["center"].distance_to(first.ship_start_km) + first_island["radius_km"] < 25.0, "first island is fully visible in initial radar range")
	_check(not first.can_navigate_segment(first_island["center"] - Vector2(10.0, 0.0), first_island["center"] + Vector2(10.0, 0.0)), "route through island is blocked")

	var clock: Node = root.get_node("WorldClock")
	clock.reset()
	await physics_frame
	await physics_frame
	_check(clock.elapsed_seconds > 0.0, "clock advances from physics ticks")
	clock.reset()
	_check(clock.advance(2.5) and is_equal_approx(clock.elapsed_seconds, 2.5), "clock advances in simulation time")
	paused = true
	_check(not clock.advance(1.0) and is_equal_approx(clock.elapsed_seconds, 2.5), "clock stops while paused")
	await process_frame
	await process_frame
	_check(is_equal_approx(clock.elapsed_seconds, 2.5), "physics ticks do not advance a paused clock")
	paused = false
	clock.reset()
	_check(clock.advance(61.0) and clock.formatted_time() == "T+01:01", "clock formats minutes and seconds")
	clock.reset()

	var main: Control = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	var radar: Control = main.get_node("Content/RadarFrame/Radar")
	_check(radar.land_areas.size() == first.islands.size(), "radar receives generated islands")
	_check(main.get_node("Footer/TimeStatus").text == "T+00:00", "scene displays simulation time")
	main.queue_free()
	_finish()

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("P1 world smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
