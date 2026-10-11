extends SceneTree

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
	flight_and_correction()
	lifecycle_and_observation()
	coarse_step_and_handoff()
	await ui_and_archive()
	if failures.is_empty():
		print("P2.3 ballistics smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func fixture() -> void:
	mission.restart_scenario()
	mission.scan()
	check(mission.identify_contact(), "fixture identified")
	world.set_ship_command(42, 22)
	clock.advance(1000)
	world.set_ship_command(42, 0)
	mission.scan()
	clock.advance(2)
	mission.scan()
	check(mission.assign_fire_control_target(mission.CONTACT_ID) and mission.set_fire_control_aim_mode("lead"), "fixture uses real assigned motion solution")

func flight_and_correction() -> void:
	fixture()
	for step in range(3): check(mission.adjust_fire_control_correction("long"), "manual correction accepted")
	var order: String = mission.fire_control_order_id
	check(mission.fire_ship_gun() and mission.enemy_health == 100 and mission.ship_ammo == 5, "launch spends one round without damage")
	var shot: Dictionary = mission.projectiles[0].duplicate(true)
	var deadline: float = mission.next_ship_fire_seconds
	paused = true
	check(not clock.advance(100) and mission.projectiles.size() == 1 and mission.enemy_health == 100, "pause freezes projectile flight")
	check(mission.adjust_fire_control_correction("reset") and mission.projectiles[0].aim_position_km == shot.aim_position_km, "paused correction changes next aim only")
	paused = false
	clock.advance(shot.flight_seconds - 0.01)
	check(mission.enemy_health == 100 and mission.projectiles.size() == 1, "damage does not occur before arrival")
	clock.advance(0.02)
	check(mission.projectiles.is_empty() and mission.enemy_health == 100 and mission.last_gun_impact.result == "near_miss", "offset shot makes observed near miss without damage")
	check(mission.last_gun_impact.error_meters > 100 and mission.last_gun_impact.order_id == order, "near miss reports measured error and order")
	check(mission.next_ship_fire_seconds == deadline and not mission.fire_ship_gun(), "correction cannot bypass reload")
	clock.advance(maxf(0, deadline - clock.elapsed_seconds))
	mission.scan()
	check(mission.fire_ship_gun(), "corrected follow-up launches after reload")
	var flight: float = mission.projectiles[0].flight_seconds
	clock.advance(flight + 0.01)
	check(mission.enemy_health == 50 and mission.last_gun_impact.result == "hit" and mission.ship_ammo == 4, "removing correction produces deterministic lead hit")
	clock.advance(1)
	check(mission.enemy_health == 50, "resolved shell cannot damage twice")
	var impact_time: float = -1
	for event in events.history:
		if event.kind == "gun_projectile_impact": impact_time = event.simulation_seconds
	check(is_equal_approx(impact_time, mission.last_gun_impact.impact_seconds), "archive records exact impact time within a clock step")

func lifecycle_and_observation() -> void:
	fixture()
	check(not mission.adjust_fire_control_correction("invalid") and mission.fire_control_correction_km == Vector2.ZERO, "invalid calibration preserves correction")
	for step in range(20): mission.adjust_fire_control_correction("long")
	var correction: Vector2 = mission.fire_control_correction_km
	check(not mission.adjust_fire_control_correction("long") and mission.fire_control_correction_km == correction, "correction capped at one kilometer")
	mission.adjust_fire_control_correction("reset")
	mission.fire_ship_gun()
	var flight: float = mission.projectiles[0].flight_seconds
	mission.clear_fire_control_target()
	check(mission.projectiles.size() == 1 and mission.fire_control_correction_km == Vector2.ZERO, "cancelling order cannot recall a shell")
	mission.set_radar_emitting(false)
	clock.advance(flight + 0.01)
	check(mission.enemy_health == 50 and mission.last_gun_impact.result == "unobserved" and not mission.last_gun_impact.has("error_km") and not mission.last_gun_impact.has("error_meters"), "unobserved impact still simulates hit without leaking position error")
	fixture()
	mission.fire_ship_gun()
	root.get_node("GameManager").report_player_death("qa_ballistics_end")
	check(mission.projectiles.is_empty() and mission.ship_ammo == 5 and mission.enemy_health == 100, "ending action clears flight without refund or late damage")
	mission.restart_scenario()
	check(mission.projectiles.is_empty() and mission.last_gun_impact.is_empty() and mission.fire_control_correction_km == Vector2.ZERO, "restart clears projectile result and calibration")

func coarse_step_and_handoff() -> void:
	fixture()
	mission.fire_ship_gun()
	var expected_time: float = mission.projectiles[0].impact_seconds
	clock.advance(100)
	check(mission.enemy_health == 50 and mission.last_gun_impact.observed and is_equal_approx(mission.last_gun_impact.impact_seconds, expected_time), "large step observes and resolves at arrival, not end-of-step stale time")
	var coarse_error: float = mission.last_gun_impact.error_meters
	fixture()
	mission.fire_ship_gun()
	var flight: float = mission.projectiles[0].flight_seconds
	clock.advance(flight * 0.25)
	clock.advance(flight * 0.75 + 0.01)
	check(mission.enemy_health == 50 and absf(mission.last_gun_impact.error_meters - coarse_error) < 0.1, "split and large time steps agree on impact")
	fixture()
	mission.fire_ship_gun()
	flight = mission.projectiles[0].flight_seconds
	check(mission.prepare_sortie() and mission.launch_sortie(), "real handoff starts with projectile in flight")
	clock.advance(flight + 0.01)
	check(mission.projectiles.is_empty() and mission.enemy_health == 50 and root.get_node("GameManager").mode == "cockpit", "projectile continues through real bridge-to-cockpit handoff")
	fixture()
	mission.fire_ship_gun()
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)
	check(root.get_node("GameManager").mode == "cockpit" and mission.projectiles.size() == 1, "commander can be airborne while shell is in flight")
	root.get_node("GameManager").report_ship_sunk()
	check(mission.projectiles.is_empty() and root.get_node("GameManager").player_alive and mission.ship_ammo == 5, "mother ship sinking clears shells even if cockpit mode continues")
	clock.advance(10)
	check(mission.enemy_health == 100, "sunk ship's cleared shell cannot cause late damage")

func ui_and_archive() -> void:
	fixture()
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.correction_controls.get_node("long").emit_signal("pressed")
	main.correction_controls.get_node("long").emit_signal("pressed")
	main.correction_controls.get_node("long").emit_signal("pressed")
	main._button("RadarActions/Fire").emit_signal("pressed")
	check(main.gun_status.text.contains("炮弹飞行中") and main.radar._gun_projectiles.size() == 1, "CRT exposes projectile flight and correction controls")
	clock.advance(mission.projectiles[0].flight_seconds + 0.01)
	check(main.gun_status.text.contains("近失弹") and main.guidance.fire_control_hint.contains("校射"), "observable near miss supplies actionable guidance")
	var history: String = main._archive_fire_control(mission.ship_gun_block_reason())
	check(history.contains("校射修正") and history.contains("弹着") and history.contains(mission.fire_control_order_id), "archive links correction launch and impact to order")
	main.toggle_archive()
	check(paused, "archive freezes flight clock")
	main.close_archive()
	check(not paused, "archive restores pause ownership")
	main.queue_free()
	await process_frame

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
