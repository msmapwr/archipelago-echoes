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
	armor_partitions()
	shot_snapshot_and_gates()
	await ui_archive()
	if failures.is_empty():
		print("P2.5 ammunition smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func armor_partitions() -> void:
	var data = root.get_node("DataManager")
	var ap: Dictionary = data.get_definition("ammo.ap").snapshot()
	var sap: Dictionary = data.get_definition("ammo.sap").snapshot()
	var he: Dictionary = data.get_definition("ammo.he").snapshot()
	check(AmmunitionDefinition.resolve(he, 0).damage == 70 and AmmunitionDefinition.resolve(ap, 0).damage == 17.5, "HE wins against unarmored hull, AP overpenetrates")
	check(AmmunitionDefinition.resolve(sap, 70).damage == 50 and AmmunitionDefinition.resolve(he, 70).damage == 10.5, "SAP penetrates identified destroyer, HE does not")
	check(AmmunitionDefinition.resolve(ap, 160).damage == 35 and AmmunitionDefinition.resolve(sap, 160).damage == 7.5, "AP wins against heavy armor")
	check(AmmunitionDefinition.resolve(ap, 160.01).outcome.begins_with("未穿透"), "penetration exact boundary and adjacent armor differ")
	check(AmmunitionDefinition.resolve(ap, 24).damage == 35 and AmmunitionDefinition.resolve(ap, 23.99).damage == 17.5, "overpenetration exact boundary and adjacent armor differ")
	var invalid = AmmunitionDefinition.new()
	invalid.id = "ammo.invalid"
	invalid.display_name = "invalid"
	invalid.penetration_mm = -1
	check(not data.register_definition(invalid, "invalid_ammo"), "invalid data rejected before combat")
	check(data.reload(), "catalog restores after rejected fixture")

func shot_snapshot_and_gates() -> void:
	fixture()
	check(not mission.set_ammunition("ammo.invalid") and mission.selected_ammunition_id == "ammo.sap", "invalid selection preserves current ammo")
	paused = true
	check(mission.set_ammunition("ammo.he") and mission.ship_ammo == 6, "paused ammo selection spends nothing")
	paused = false
	check(mission.fire_ship_gun(), "HE can launch through normal fire gate")
	var flight: float = mission.projectiles[0].flight_seconds
	var deadline: float = mission.next_ship_fire_seconds
	mission.set_ammunition("ammo.ap")
	check(not mission.fire_ship_gun() and mission.ship_ammo == 5 and mission.next_ship_fire_seconds == deadline, "switch cannot bypass reload")
	check(mission.projectiles[0].ammunition.id == "ammo.he", "inflight projectile preserves HE snapshot")
	clock.advance(flight + 0.01)
	check(is_equal_approx(mission.enemy_health, 89.5) and mission.last_gun_impact.armor_outcome.begins_with("未穿透"), "arrival uses HE armor result despite AP selection")
	fixture()
	mission.set_ammunition("ammo.ap")
	mission.fire_ship_gun()
	mission.set_radar_emitting(false)
	clock.advance(mission.projectiles[0].flight_seconds + 0.01)
	check(mission.enemy_health == 65 and not mission.last_gun_impact.has("damage") and not mission.last_gun_impact.has("armor_outcome"), "blind hit simulates damage without revealing armor result")
	fixture()
	root.get_node("GameManager").change_mode("configuration")
	check(not mission.set_ammunition("ammo.he"), "no bridge command rejects ammo switch")
	mission.restart_scenario()
	check(mission.selected_ammunition_id == "ammo.sap", "restart restores compatible SAP default")

func ui_archive() -> void:
	fixture()
	var main = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.ammunition_selector.item_selected.emit(2)
	check(mission.selected_ammunition_id == "ammo.he" and main.gun_status.text.contains("HE"), "CRT selector changes next shot")
	mission.fire_ship_gun()
	clock.advance(mission.projectiles[0].flight_seconds + 0.01)
	check(main.guidance.fire_control_hint.contains("未穿透"), "guidance recommends recoverable ammo choice")
	main.toggle_archive()
	var archive_text: String = main._archive_fire_control("ready")
	check(archive_text.contains("下一发换弹") and archive_text.contains("HE 高爆弹") and archive_text.contains("未穿透"), "archive preserves ammo command, shot snapshot and impact")
	main.close_archive()
	main.queue_free()
	await process_frame
