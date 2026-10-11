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
	clock.advance(2)
	mission.scan()
	mission.assign_fire_control_target(mission.CONTACT_ID)
	mission.set_fire_control_aim_mode("lead")

func run() -> void:
	mission = root.get_node("MissionController")
	clock = root.get_node("WorldClock")
	world = root.get_node("WorldState")
	independent_salvo()
	group_lifecycle()
	await ui_archive()
	if failures.is_empty():
		print("P2.6 groups smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func independent_salvo() -> void:
	fixture()
	var order: String = mission.fire_control_order_id
	check(mission.gun_groups().size() == 2 and mission.total_ship_ammo() == 12, "two groups have individual six-round magazines")
	check(mission.fire_ship_gun(), "fore launches through normal gate")
	var deadline: float = mission.next_ship_fire_seconds
	var fore: Dictionary = mission.projectiles[0].duplicate(true)
	check(fore.mount_id == "fore" and fore.origin_km != world.ship_position_km, "launch snapshot originates at actual fore mount")
	check(mission.select_gun_group("aft") and mission.ship_ammo == 6 and mission.next_ship_fire_seconds == 0, "aft retains independent ammo and reload")
	check(mission.ship_gun_block_reason().contains("射界") and not mission.fire_ship_gun(), "aft cannot fire forward despite fore readiness")
	check(mission.ship_ammo == 6, "rejected aft shot spends nothing")
	world.set_ship_command(222, 0)
	mission.set_ammunition("ammo.he")
	check(mission.fire_ship_gun(), "rotated hull brings aft target into arc, aft fires while fore reloads")
	check(mission.projectiles.size() == 2 and mission.total_ship_ammo() == 10, "both independent shots remain in flight")
	check(mission.select_gun_group("fore") and mission.ship_ammo == 5 and mission.next_ship_fire_seconds == deadline and mission.selected_ammunition_id == "ammo.sap", "switch restores fore resources and next-round SAP")
	check(not mission.fire_ship_gun() and mission.total_ship_ammo() == 10, "switch cannot bypass fore reload")
	var arrival := 0.0
	for shot in mission.projectiles: arrival = maxf(arrival, shot.flight_seconds)
	clock.advance(arrival + 0.01)
	check(is_equal_approx(mission.enemy_health, 39.5) and mission.projectiles.is_empty(), "SAP and HE shots settle independently against destroyer armor")
	var mounts: PackedStringArray = []
	for event in root.get_node("EventBus").history:
		if event.kind == "gun_projectile_impact":
			mounts.append(event.details.mount_id)
			check(event.details.order_id == order, "both impacts retain common assigned order")
	check("fore" in mounts and "aft" in mounts, "archive impact identifies each mount")

func group_lifecycle() -> void:
	fixture()
	mission.set_fire_control_lock(true)
	paused = true
	var origin: Vector2 = world.ship_position_km
	check(mission.select_gun_group("aft") and not mission.fire_control_locked, "paused group switch releases fore lock without advancing time")
	check(not clock.advance(4) and world.ship_position_km == origin and mission.total_ship_ammo() == 12, "paused switch does not move or spend resources")
	paused = false
	check(not mission.select_gun_group("invalid") and mission.selected_mount_id == "aft", "invalid group does not mutate selection")
	mission.ship_ammo = 0
	check(mission.select_gun_group("fore") and mission.ship_ammo == 6, "empty aft magazine does not drain fore")
	root.get_node("GameManager").change_mode("configuration")
	check(not mission.select_gun_group("aft"), "handoff prevents new group commands")
	mission.restart_scenario()
	check(mission.selected_mount_id == "fore" and mission.total_ship_ammo() == 12 and mission.selected_ammunition_id == "ammo.sap", "restart resets both magazines and selection")
	var data = root.get_node("DataManager")
	var ship = data.get_definition(mission.SHIP_ID)
	var original: String = ship.weapon_mounts[1].mount_id
	ship.weapon_mounts[1].mount_id = "fore"
	check(not data.validate_catalog(), "duplicate mount identities rejected")
	ship.weapon_mounts[1].mount_id = original
	check(data.reload(), "catalog restored after bad mount fixture")

func ui_archive() -> void:
	fixture()
	var main = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var scroll = main.details.get_parent()
	for control in [main.gun_group_selector, main.ammunition_selector, main.lock_button, main.correction_controls]:
		check(control.get_global_rect().position.y >= scroll.get_global_rect().position.y and control.get_global_rect().end.y <= scroll.get_global_rect().end.y and control.get_global_rect().end.x <= scroll.get_global_rect().end.x, "combat controls remain within first CRT viewport: " + control.name)
	check(not main.gun_group_selector.get_global_rect().intersects(main.aim_mode_button.get_global_rect()) and not main.lock_button.get_global_rect().intersects(main.aim_mode_button.get_global_rect()), "group, aim and lock controls do not overlap")
	main.gun_group_selector.item_selected.emit(1)
	check(mission.selected_mount_id == "aft" and main.gun_status.text.contains("后炮") and main.guidance.fire_control_hint.begins_with("后炮"), "CRT group switch and guidance show current gun")
	var input := InputEventKey.new()
	input.pressed = true
	input.keycode = KEY_1
	main._input(input)
	check(mission.selected_mount_id == "fore", "numeric hotkey switches back")
	main.toggle_archive()
	var archive_text: String = main._archive_fire_control("ready")
	check(archive_text.contains("前炮 / 余弹 6") and archive_text.contains("后炮 / 余弹 6") and archive_text.contains("切换炮组"), "archive includes both gun states and linked switch command")
	input.keycode = KEY_2
	main._input(input)
	check(mission.selected_mount_id == "fore", "archive modal consumes combat shortcuts")
	main.close_archive()
	main.queue_free()
	await process_frame
