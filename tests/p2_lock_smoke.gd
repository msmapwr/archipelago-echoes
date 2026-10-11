extends SceneTree

var failures: PackedStringArray = []
var mission: Node
var clock: Node
var world: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func fixture() -> void:
	mission.restart_scenario()
	mission.scan()
	mission.identify_contact()
	world.set_ship_command(42, 22)
	clock.advance(1000)
	world.set_ship_command(42, 0)
	mission.scan()
	mission.assign_fire_control_target(mission.CONTACT_ID)

func run() -> void:
	mission = root.get_node("MissionController")
	clock = root.get_node("WorldClock")
	world = root.get_node("WorldState")
	lock_lifecycle()
	await ui_archive()
	if failures.is_empty():
		print("P2.4 lock smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func lock_lifecycle() -> void:
	mission.restart_scenario()
	check(not mission.set_fire_control_lock(true), "unknown contact cannot lock")
	fixture()
	mission.turret_heading_degrees = 110
	paused = true
	check(mission.set_fire_control_lock(true), "paused lock queues without resources")
	check(not clock.advance(2) and mission.turret_heading_degrees == 110 and mission.ship_ammo == 6, "pause freezes turret and does not shoot")
	paused = false
	check(mission.ship_gun_block_reason().contains("炮塔"), "slewing turret blocks shot")
	clock.advance(1)
	check(absf(mission.turret_heading_degrees - 90) < 0.01, "turret has finite 20 degree rate")
	var heading: float = mission.turret_heading_degrees
	var live: Vector2 = world.contact_position_km
	world.contact_position_km = Vector2(99, 99)
	clock.advance(1)
	check(absf(mission.turret_heading_degrees - (heading - 20)) < 0.01, "hidden live position cannot steer turret")
	world.contact_position_km = live
	clock.advance(2)
	check(mission.fire_control_locked and mission.ship_gun_block_reason().is_empty(), "tracking settles without firing")
	clock.advance(4)
	check(mission.fire_control_locked, "exact eight second observation valid")
	clock.advance(0.01)
	check(not mission.fire_control_locked and mission.lock_status.begins_with("失锁"), "observation beyond eight seconds loses lock")
	check(not mission.set_fire_control_lock(true), "expired lock cannot reacquire until scan")
	mission.scan()
	check(mission.set_fire_control_lock(true), "fresh scan allows explicit reacquisition")
	mission.set_radar_emitting(false)
	check(not mission.fire_control_locked and not mission.fire_control_order_id.is_empty(), "silence loses lock but preserves assignment")
	mission.set_radar_emitting(true)
	mission.set_fire_control_lock(true)
	root.get_node("GameManager").change_mode("configuration")
	check(not mission.fire_control_locked, "handoff loses illumination immediately")
	fixture()
	mission.set_fire_control_lock(true)
	mission.clear_fire_control_target()
	check(not mission.fire_control_locked, "cancel clears lock")
	mission.restart_scenario()
	check(not mission.fire_control_locked and mission.lock_status == "未锁定", "restart resets lock status")

func ui_archive() -> void:
	fixture()
	var main = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.lock_button.pressed.emit()
	check(mission.fire_control_locked and main.lock_button.text == "解除照射", "actual CRT button acquires lock")
	check(main.guidance.fire_control_hint.contains("8 秒"), "guidance explains sustained scan requirement")
	main.toggle_archive()
	check(main._archive_fire_control("ready").contains("锁定照射"), "archive includes correlated lock event")
	main.close_archive()
	main.queue_free()
	await process_frame
