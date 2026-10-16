extends SceneTree

const Hazards = preload("res://scripts/world/navigation_hazards.gd")
const Map = preload("res://scripts/world/archipelago_map.gd")
const Harbor = preload("res://scripts/world/harbor_navigation.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	root.get_node("WorldClock").set_physics_process(false)
	geometry()
	await sea_lifecycle()
	await harbor_transfer()
	clock_scales()
	if failures.is_empty():
		print("Navigation hazards smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func geometry() -> void:
	var map = Map.new(270928, 42, 18)
	var repeat = Map.new(270928, 42, 18)
	var other = Map.new(270929, 42, 18)
	check(map.depth_contours == repeat.depth_contours and map.depth_contours != other.depth_contours, "seed owns reproducible noncircular shelves")
	var island: Dictionary = map.islands[0]
	var depths: Array[float] = []
	for angle in [0.0, 0.6, 1.5, 2.3]:
		depths.append(map.depth_at(island.center + Vector2.from_angle(angle) * (island.radius_km + 1)))
	check(depths.max() - depths.min() > 5, "equal coast distances have irregular bathymetry")
	var near_a: Vector2 = island.center + Vector2.from_angle(0.00001) * (island.radius_km + 1)
	var near_b: Vector2 = island.center + Vector2.from_angle(TAU - 0.00001) * (island.radius_km + 1)
	check(absf(map.depth_at(near_a) - map.depth_at(near_b)) < 0.02, "shelf transition is continuous across angular seam")
	for angle in [0.2, 1.0, 2.4]:
		var shallow: Vector2 = island.center + Vector2.from_angle(angle) * (island.radius_km + 0.3)
		var deep: Vector2 = island.center + Vector2.from_angle(angle) * (island.radius_km + 0.8)
		check(map.depth_at(deep) > map.depth_at(shallow), "shelf deepens away from coast")
	var depth := func(point: Vector2) -> float: return maxf(0, point.x * 10)
	var bounds := Rect2(-4, -4, 8, 8)
	var shoal := Hazards.trace(Vector2(2, 0), Vector2(-2, 0), 4, depth, bounds)
	check(shoal.kind == "grounding" and shoal.position.x >= 0.4 and shoal.position.x < 0.43, "large step stops before shallow water")
	check(Hazards.trace(Vector2(1, 0), Vector2(2, 0), 4, depth, bounds).is_empty(), "deep route stays available")
	check(Hazards.trace(Vector2(0.2, 0), Vector2(1, 0), 4, depth, bounds, true).is_empty(), "escape may cross shallow water while deepening")
	check(not Hazards.trace(Vector2(0.2, 0), Vector2(0.1, 0), 4, depth, bounds, true).is_empty(), "escape cannot enter shallower water")
	var cliff := func(point: Vector2) -> float: return 100.0 if point.x > 0 else 0.0
	check(Hazards.trace(Vector2(1, 0), Vector2(-1, 0), 4, cliff, bounds).kind == "collision", "steep coast produces physical collision")
	check(Hazards.trace(Vector2(2, 0), Vector2(5, 0), 4, depth, bounds).kind == "boundary" and Hazards.impact_damage(22, "boundary") == 0, "map limit is not damaging land")
	check(Hazards.impact_damage(8, "grounding") < Hazards.impact_damage(16, "grounding") and Hazards.impact_damage(22, "grounding") == 100, "impact energy increases with speed and high speed can wreck hull")

func place_near_coast(world: Node) -> void:
	var island: Dictionary = world.map.islands[0]
	world.ship_position_km = island.center - Vector2(island.radius_km + 0.35, 0)

func clock_scales() -> void:
	var world: Node = root.get_node("WorldState")
	var mission: Node = root.get_node("MissionController")
	var clock: Node = root.get_node("WorldClock")
	var states: Array[Dictionary] = []
	for scale in [1.0, 10.0]:
		mission.restart_scenario()
		mission.enemy_alive = false
		place_near_coast(world)
		world.set_ship_command(90, 8)
		clock.set_time_scale(scale)
		for step in range(int(300 / scale)): clock._physics_process(1.0)
		states.append({"health":mission.ship_health, "position":world.ship_position_km, "grounded":world.ship_grounded})
	check(states[0].grounded and states[1].grounded and states[0].health == states[1].health and states[0].position.distance_to(states[1].position) <= Hazards.SAMPLE_KM, "1x and 10x clock scales preserve impact outcome within sampling tolerance")
	mission.restart_scenario()

func sea_lifecycle() -> void:
	var world: Node = root.get_node("WorldState")
	var mission: Node = root.get_node("MissionController")
	var game: Node = root.get_node("GameManager")
	var clock: Node = root.get_node("WorldClock")
	mission.restart_scenario()
	mission.enemy_alive = false
	place_near_coast(world)
	world.set_ship_command(90, 8)
	check(not world.navigation_risk().warning.is_empty(), "one-minute shallow forecast warns before impact")
	clock.advance(200)
	check(world.ship_grounded and world.ship_speed_knots == 0 and mission.ship_health > 0 and mission.ship_health < 100, "low-speed grounding damages and stops ship")
	var health: float = mission.ship_health
	var point: Vector2 = world.ship_position_km
	clock.advance(100)
	check(mission.ship_health == health and world.ship_position_km == point, "stationary grounding does not repeatedly damage hull")
	paused = true
	check(not clock.advance(50) and mission.ship_health == health, "pause freezes hazard damage")
	paused = false
	check(not world.set_ship_command(270, 10) and world.set_ship_command(270, 0), "refloat has explicit speed limit")
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.ship_controls.get_index() < main.details.get_node("RadarActions").get_index(), "recovery helm controls outrank combat while grounded")
	main._button("ShipControls/SpeedControls/SpeedUp").emit_signal("pressed")
	check(world.ship_speed_knots == 2, "actual helm acceleration button can start low-speed escape")
	main._button("ShipControls/SpeedControls/SpeedUp").emit_signal("pressed")
	main._button("ShipControls/SpeedControls/SpeedUp").emit_signal("pressed")
	check(world.ship_speed_knots == 4, "helm buttons stay within refloat speed limit")
	check("搁浅" in main.guidance.warning and "搁浅" in main._archive_history(), "grounding enters guidance and command archive")
	check("吃水" in main.under_keel.text, "bridge shows depth and hull draft")
	check(main.objective_hint.get_global_rect().end.y <= main.terminal.get_node("Content").get_global_rect().position.y, "critical guidance stays above map and controls")
	main.queue_free()
	await process_frame
	clock.advance(180)
	check(not world.ship_grounded and mission.ship_health == health, "low-speed departure into deep water refloats without free repair")
	mission.restart_scenario()
	mission.enemy_alive = false
	place_near_coast(world)
	world.set_ship_command(90, 22)
	clock.advance(200)
	check(mission.ship_health == 0 and not game.ship_afloat and game.mode == "campaign_failed" and mission.ship_loss_cause == "触礁撞毁", "high-speed wreck ends action with player aboard")
	check(not world.set_ship_command(270, 4), "wreck cannot move again")
	mission.restart_scenario()
	check(not world.ship_grounded and world.last_navigation_impact.is_empty() and mission.ship_health == 100 and mission.ship_loss_cause.is_empty(), "retry resets hazard state and hull")
	mission.enemy_alive = false
	clock.advance(181.0 / 60.0)
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)
	check(mission.aircraft_airborne and game.mode == "cockpit", "five-second transfer completes at fractional clock origin without floating residue")
	check(mission.set_aircraft_destination("ship"), "airborne recovery navigator follows carrier before its loss")
	place_near_coast(world)
	world.set_ship_command(90, 22)
	clock.advance(200)
	check(not game.ship_afloat and game.player_alive and mission.aircraft_airborne and mission.aircraft_destination == "airfield", "airborne pilot survives wreck and diverts to airport")
	mission.restart_scenario()

func harbor_transfer() -> void:
	var navigation = Harbor.new()
	navigation.hull = 2
	navigation.cast_off()
	navigation.set_command(270, 10)
	navigation.advance(160)
	check(navigation.failed and navigation.hull == 0 and not navigation.set_command(0, 4), "port destruction is terminal with no departure")
	var clock: Node = root.get_node("WorldClock")
	var mission: Node = root.get_node("MissionController")
	var settings: Node = root.get_node("UserSettings")
	settings.skip_tutorial_by_default = false
	settings.tutorial_completed = false
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	shell.get_node("StartButton").emit_signal("pressed")
	for step in range(7):
		var preparation: Control = shell.get_node("GameCRTSlot/Preparation")
		if preparation.stage == "tutorial": preparation.tutorial.skip()
		preparation.advance()
	var harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	harbor.navigation.hull = 72
	harbor.navigation.impacts.append({"kind":"grounding", "hull":72, "harbor_seconds":3})
	harbor.navigation.cast_off()
	harbor.navigation.set_command(0, 10)
	harbor.advance_navigation(400)
	check(shell.started and mission.ship_health == 72, "port damage survives mission initialization")
	var main: Control = shell.get_node("GameCRTSlot").get_child(0)
	check("港内触浅" in main._archive_history(), "port collision history survives transfer")
	shell.queue_free()
	await process_frame
	paused = false
	clock.reset()
	mission.restart_scenario()
