extends SceneTree

const Motion = preload("res://scripts/core/fire_control_solution.gd")
var failures: PackedStringArray = []
var mission: Node
var clock: Node
var world: Node
var events: Node

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	mission = root.get_node("MissionController")
	clock = root.get_node("WorldClock")
	world = root.get_node("WorldState")
	events = root.get_node("EventBus")
	solver_boundaries()
	controller_lifecycle()
	await ui_archive_guidance()
	if failures.is_empty():
		print("P2.2 lead solution smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func solver_boundaries() -> void:
	var model = Motion.new()
	model.observe(Vector2(0, -8), 0)
	model.observe(Vector2(0, -8), 0)
	check(not model.solve(Vector2.ZERO, 0, 0.8).valid, "same-instant scans do not establish motion")
	model.observe(Vector2(0.002, -8), 0.5)
	check(not model.solve(Vector2.ZERO, 0.5, 0.8).valid, "subsecond scans do not establish motion")
	model.observe(Vector2(0.01, -8), 1)
	var s: Dictionary = model.solve(Vector2.ZERO, 1, 0.8)
	check(s.valid and is_equal_approx(s.speed_knots, 0.01 * 3600 / 1.852), "one-second boundary estimates world-space motion")
	check(s.aim_position_km.is_equal_approx(Vector2(0.01, -8) + Vector2(0.01, 0) * s.flight_seconds), "intercept uses measured velocity")
	check(is_equal_approx(s.aim_position_km.length(), s.flight_seconds * 0.8), "intercept travel time matches projectile distance")
	var moved: Dictionary = model.solve(Vector2(3, 2), 1, 0.8)
	check(is_equal_approx(moved.speed_knots, s.speed_knots) and moved.aim_position_km != s.aim_position_km, "ownship relocation affects interception, not target velocity")
	check(model.solve(Vector2.ZERO, 16, 0.8).confidence == "新鲜" and model.solve(Vector2.ZERO, 16.01, 0.8).confidence == "老化", "confidence age boundary is explicit")
	check(model.solve(Vector2.ZERO, 46, 0.8).valid and not model.solve(Vector2.ZERO, 46.01, 0.8).valid, "motion expires after exactly 45 seconds")
	check(not model.solve(Vector2.ZERO, 0, 0.8).valid, "clock rollback cannot extrapolate backwards")
	check(not model.solve(Vector2.ZERO, 1, 0).valid and not model.solve(Vector2.ZERO, 1, INF).valid and not model.solve(Vector2(NAN, 0), 1, 0.8).valid, "invalid solution parameters rejected")
	model.observe(Vector2(0.02, -8), 47)
	check(not model.solve(Vector2.ZERO, 47, 0.8).valid, "reacquisition after gap requires a new pair")
	model.observe(Vector2(0.02, -8), 48)
	s = model.solve(Vector2.ZERO, 48, 0.8)
	check(s.valid and s.speed_knots == 0 and s.aim_position_km == Vector2(0.02, -8), "stationary target gives stationary aim")
	model.observe(Vector2(4, -8), 49)
	check(not model.solve(Vector2.ZERO, 49, 0.8).valid, "impossible displacement invalidates velocity")
	model.observe(Vector2(NAN, 0), 50)
	check(not model.solve(Vector2.ZERO, 50, 0.8).valid, "nonfinite observation resets chain")
	model.observe(Vector2(0, -8), 0)
	model.observe(Vector2(0, -8.2), 10)
	check(not model.solve(Vector2.ZERO, 10, 0.01).valid, "slower projectile cannot intercept receding target")
	model.reset()
	check(not model.solve(Vector2.ZERO, 10, 0.8).valid, "explicit reset clears solution")

func in_range() -> void:
	mission.restart_scenario()
	mission.scan()
	check(mission.identify_contact(), "real scans identify fixture")
	world.set_ship_command(42, 22)
	clock.advance(1000)
	world.set_ship_command(42, 0)
	check(mission.scan() and mission.assign_fire_control_target(mission.CONTACT_ID), "real navigation supplies assigned in-range target")

func controller_lifecycle() -> void:
	in_range()
	var ammo: int = mission.ship_ammo
	var order: String = mission.fire_control_order_id
	check(mission.set_fire_control_aim_mode("lead") and not mission.fire_control_solution().valid, "lead mode can be selected before motion is ready")
	check(not mission.fire_ship_gun() and mission.ship_ammo == ammo, "insufficient motion blocks lead shot without spending ammo")
	paused = true
	check(mission.set_fire_control_aim_mode("observed") and not mission.fire_ship_gun() and mission.ship_ammo == ammo, "paused mode change allowed while shot remains forbidden")
	paused = false
	check(not mission.set_fire_control_aim_mode("invalid") and mission.fire_control_aim_mode == "observed", "invalid mode preserves chosen aim")
	check(mission.ship_gun_block_reason().is_empty(), "observed mode remains playable without motion")
	clock.advance(30)
	check(mission.scan() and mission.fire_control_solution().valid, "time-separated real observations unlock solution")
	var s: Dictionary = mission.fire_control_solution()
	check(is_equal_approx(s.speed_knots, 6), "measured patrol speed comes from samples")
	var live: Vector2 = world.contact_position_km
	world.contact_position_km = Vector2(99, 99)
	check(mission.fire_control_solution().aim_position_km == s.aim_position_km, "hidden enemy position cannot move prediction")
	world.contact_position_km = live
	check(mission.set_fire_control_aim_mode("lead"), "ready lead mode selected")
	var weapon: Resource = root.get_node("DataManager").get_definition("weapon.deck_gun")
	var original_range: float = weapon.range_km
	var observed_range: float = world.ship_position_km.distance_to(mission.last_contact_position_km)
	var lead_range: float = world.ship_position_km.distance_to(s.aim_position_km)
	weapon.range_km = (observed_range + lead_range) * 0.5
	var lead_blocked: bool = not mission.ship_gun_block_reason().is_empty()
	mission.set_fire_control_aim_mode("observed")
	var observed_blocked: bool = not mission.ship_gun_block_reason().is_empty()
	check(lead_range != observed_range and lead_blocked == (lead_range > weapon.range_km) and observed_blocked == (observed_range > weapon.range_km) and lead_blocked != observed_blocked, "range gate follows each mode's distinct aim coordinate")
	mission.set_fire_control_aim_mode("lead")
	weapon.range_km = original_range
	check(mission.fire_ship_gun() and mission.ship_ammo == ammo - 1 and mission.enemy_health == 100, "lead shot launches one round with deferred damage")
	var shot: Dictionary = {}
	for event in events.history:
		if event.kind == "weapon_fired": shot = event.details
	check(shot.get("aim_mode", "") == "lead" and shot.get("order_id", "") == order and shot.get("aim_position_km", Vector2.ZERO) == s.aim_position_km and shot.get("solution", {}).get("valid", false), "shot archives exact lead snapshot and order")
	clock.advance(10)
	check(mission.enemy_health == 50, "measured lead intercept hits at arrival")
	var reload: float = mission.next_ship_fire_seconds
	mission.set_fire_control_aim_mode("observed")
	mission.set_fire_control_aim_mode("lead")
	check(mission.next_ship_fire_seconds == reload and mission.ship_ammo == ammo - 1 and mission.fire_control_order_id == order, "mode switches preserve reload ammo and assignment")
	mission.set_radar_emitting(false)
	check(not mission.fire_control_solution().valid, "silence clears motion readiness")
	mission.set_radar_emitting(true)
	check(not mission.fire_control_solution().valid and mission.fire_control_order_id == order, "first reacquisition preserves order but needs another sample")
	clock.advance(1)
	mission.scan()
	check(mission.fire_control_solution().valid, "second timed reacquisition restores lead")
	world.contact_position_km = world.ship_position_km + Vector2(26, 0)
	check(not mission.scan() and not mission.fire_control_solution().valid, "lost contact invalidates motion")
	world.contact_position_km = live
	mission.scan()
	check(not mission.fire_control_solution().valid, "lost-contact recovery needs a fresh pair")
	mission.restart_scenario()
	check(mission.fire_control_aim_mode == "observed" and not mission.fire_control_solution().valid, "restart restores observed mode and clears estimator")

func ui_archive_guidance() -> void:
	in_range()
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.aim_mode_button.emit_signal("pressed")
	check(mission.fire_control_aim_mode == "lead" and main.guidance.fire_control_hint.contains("切回最后观测"), "UI toggle supplies recovery advice without changing mission stage")
	check(main.guidance.stage == "sortie", "lead mode does not become a mission objective")
	clock.advance(30)
	mission.scan()
	main._refresh_ui()
	await process_frame
	await process_frame
	var scroll: Control = main.details.get_parent()
	check(main.aim_mode_button.get_global_rect().end.y <= scroll.get_global_rect().end.y and main.aim_mode_button.get_global_rect().position.y >= scroll.get_global_rect().position.y, "aim toggle stays in first visible CRT scroll viewport")
	check(main.radar._fire_control_prediction.get("valid", false) and main.gun_status.text.contains("运动 6.0 kn"), "CRT displays observed speed and independent prediction")
	var archive: String = main._archive_fire_control(mission.ship_gun_block_reason())
	check(archive.contains("运动提前量") and archive.contains(mission.fire_control_order_id) and archive.contains("运动 6.0 kn"), "fire control archive includes mode command and solution diagnostics")
	main.toggle_archive()
	check(paused and not mission.fire_ship_gun(), "reading archive cannot shoot")
	main.close_archive()
	check(not paused and mission.fire_control_aim_mode == "lead", "closing archive preserves aim mode and pause ownership")
	main.queue_free()
	await process_frame

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
