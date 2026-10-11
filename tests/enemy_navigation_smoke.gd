extends SceneTree

const Policy = preload("res://scripts/core/enemy_navigation.gd")
const Map = preload("res://scripts/world/archipelago_map.gd")
var failures: PackedStringArray = []
var mission: Node
var clock: Node
var world: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	mission = root.get_node("MissionController")
	clock = root.get_node("WorldClock")
	world = root.get_node("WorldState")
	policy_boundaries()
	profile_validation()
	await combat_observation_lifecycle()
	if failures.is_empty():
		print("Enemy navigation smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func policy_boundaries() -> void:
	var policy = Policy.new()
	check(not policy.react_to_damage(40.01, 40), "above threshold keeps patrol")
	check(policy.react_to_damage(40, 40), "exact threshold enters withdrawal once")
	check(not policy.react_to_damage(39, 40), "repeated damage does not restart withdrawal")
	policy.observe_threat(Vector2(50, 55))
	var map = Map.new(27, 42, 18)
	var first: Dictionary = policy.advance(Vector2(50, 50), 90, 18, 1, 5, map)
	check(is_equal_approx(first.heading, 85), "finite turn rate limits rotation to five degrees per second")
	check(first.position.y < 50 and first.position.x > 50, "actual motion follows turned heading")
	var one: Dictionary = policy.advance(Vector2(50, 50), 90, 18, 30, 5, map)
	var many := {"position": Vector2(50, 50), "heading": 90.0}
	for step in range(30): many = policy.advance(many.position, many.heading, 18, 1, 5, map)
	check(one.position.distance_to(many.position) < 0.00001 and is_equal_approx(one.heading, many.heading), "large tick matches one-second steps")
	policy.observe_threat(Vector2(110, 50))
	var blocked: Dictionary = policy.advance(Vector2(0.001, 50), 270, 18, 1, 5, map)
	check(blocked.blocked and blocked.position == Vector2(0.001, 50) and map.is_water(blocked.position), "map boundary holds position and reports obstruction")
	map.islands.clear()
	map.islands.append({"center": Vector2(50, 50), "radius_km": 1.0})
	policy.observe_threat(Vector2(55, 50))
	blocked = policy.advance(Vector2(51.001, 50), 270, 18, 1, 5, map)
	check(blocked.blocked and blocked.position == Vector2(51.001, 50), "island collision never moves through land")
	policy.reset()
	check(not policy.withdrawing and not policy.threat_known and policy.threat_position_km == Vector2.ZERO, "reset clears tactical memory")
	check(not policy.react_to_damage(0, 40), "destroyed targets do not start withdrawal")
	policy.react_to_damage(20, 40)
	var straight: Dictionary = policy.advance(Vector2(10, 10), 90, 18, 2, 5, map)
	check(is_equal_approx(straight.heading, 90), "no threat knowledge holds current escape heading")
	policy.observe_threat(Vector2(NAN, 1))
	check(not policy.threat_known, "invalid observation cannot corrupt threat memory")

func profile_validation() -> void:
	var manager = root.get_node("DataManager")
	var original: PackedStringArray = manager.errors.duplicate()
	for field in ["withdrawal_health", "withdrawal_speed_knots", "withdrawal_turn_degrees"]:
		var profile := ContactDefinition.new()
		profile.set(field, NAN)
		check(not manager._validate_fields(profile, "AI fixture"), "nonfinite withdrawal field rejected: " + field)
		profile.set(field, 0)
		check(not manager._validate_fields(profile, "AI fixture"), "zero withdrawal field rejected: " + field)
		profile.set(field, -1)
		check(not manager._validate_fields(profile, "AI fixture"), "negative withdrawal field rejected: " + field)
	var profile := ContactDefinition.new()
	check(manager._validate_fields(profile, "AI fixture"), "default profile valid")
	profile.withdrawal_health = 100
	check(not manager._validate_fields(profile, "AI fixture"), "full health is not valid retreat threshold")
	profile.withdrawal_health = 0
	check(not manager._validate_fields(profile, "AI fixture"), "zero threshold rejected")
	profile.withdrawal_health = 40
	profile.withdrawal_turn_degrees = 181
	check(not manager._validate_fields(profile, "AI fixture"), "excessive turn profile rejected")
	manager.errors = original

func combat_observation_lifecycle() -> void:
	mission.restart_scenario()
	mission.scan()
	mission.identify_contact()
	world.set_ship_command(42, 22)
	clock.advance(1000)
	world.set_ship_command(42, 0)
	mission.scan()
	clock.advance(2)
	mission.scan()
	mission.assign_fire_control_target(mission.CONTACT_ID)
	mission.set_fire_control_aim_mode("lead")
	mission.set_ammunition("ammo.ap")
	for shot in range(2):
		if shot == 1:
			clock.advance(30)
			mission.scan()
		check(mission.fire_ship_gun(), "real AP shell accepted")
		if mission.projectiles.is_empty(): return
		clock.advance(mission.projectiles[0].flight_seconds + 0.01)
	check(mission.enemy_alive and is_equal_approx(mission.enemy_health, 30), "two AP hits leave damaged target alive")
	check(mission._enemy_navigation.withdrawing and mission.enemy_speed_knots == 18, "actual damage triggers retreat speed")
	var old_observation: Vector2 = mission.last_contact_position_km
	var old_status: String = mission.contact_maneuver_status()
	clock.advance(12)
	check(mission.last_contact_position_km == old_observation and mission.contact_maneuver_status() == old_status, "hidden navigation does not update player observations")
	mission.scan()
	check(mission.contact_maneuver_status().contains("转向"), "successful scan observes turn")
	mission.scan()
	check(mission.contact_maneuver_status().contains("转向"), "same-time duplicate scan cannot erase observed turn")
	check(mission.fire_control_order_id == "fire_control.001", "retreat does not revoke player assignment")
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.contact_details.text.contains("转向"), "real CRT shows sampled maneuver")
	check(main.guidance.fire_control_hint.contains("目标机动"), "guidance recommends rescan rather than hidden intent")
	check(main._archive_history().contains("A1 复测 / 转向机动"), "observed maneuver enters command archive")
	for event in root.get_node("EventBus").history:
		check(event.kind != "enemy_withdrawal_started", "actual AI intent remains developer-only")
	paused = true
	var position: Vector2 = world.contact_position_km
	var heading: float = mission.enemy_heading_degrees
	check(not clock.advance(20) and world.contact_position_km == position and mission.enemy_heading_degrees == heading, "pause freezes withdrawal")
	paused = false
	mission.set_radar_emitting(false)
	var memory: Vector2 = mission._enemy_navigation.threat_position_km
	world.ship_position_km = Vector2(1, 90)
	mission._update_enemy_tracking(clock.elapsed_seconds)
	check(mission._enemy_navigation.threat_position_km == memory, "lost sensor contact cannot read hidden ship position")
	check(mission.contact_maneuver_status().contains("旧观测"), "silent radar marks last maneuver stale")
	mission._damage_enemy(100, "test")
	position = world.contact_position_km
	clock.advance(5)
	check(not mission.enemy_alive and world.contact_position_km == position, "destroyed withdrawing target stops moving")
	main.queue_free()
	await process_frame
	mission.restart_scenario()
	check(not mission._enemy_navigation.withdrawing and mission.enemy_speed_knots == 6 and mission.contact_maneuver_status().is_empty(), "restart restores patrol and clears sampled maneuver")
	mission._damage_enemy(60, "end fixture")
	position = world.contact_position_km
	root.get_node("GameManager").report_player_death("test")
	clock.advance(20)
	check(world.contact_position_km == position, "ended scenario freezes withdrawing target")
	mission.restart_scenario()
