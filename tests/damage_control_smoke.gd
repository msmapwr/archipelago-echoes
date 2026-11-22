extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var mission: Node = root.get_node("MissionController")
	var clock: Node = root.get_node("WorldClock")
	var world: Node = root.get_node("WorldState")
	var game: Node = root.get_node("GameManager")
	mission.restart_scenario()
	_check(not mission.start_damage_control() and mission.repair_teams == 2, "healthy hull cannot consume a repair team")
	mission.ship_health = 60.0
	world.set_ship_command(0.0, 22.0)
	_check(not mission.start_damage_control() and mission.repair_teams == 2, "high speed prevents repair without cost")
	world.set_ship_command(0.0, 0.0)
	_check(mission.start_damage_control() and mission.repair_teams == 1)
	_check(not mission.start_damage_control() and mission.repair_teams == 1, "duplicate repair cannot consume resources")
	mission.scan()
	mission.identify_contact()
	_check(mission.assign_fire_control_target("contact.alpha"), "repair can retain a target order without firing")
	_check("损管" in mission.ship_gun_block_reason("contact.alpha"), "repair temporarily stops gun crew")
	game.set_paused(true)
	clock.advance(30.0)
	_check(mission.repair_seconds_remaining == 30.0 and mission.ship_health == 60.0, "pause freezes repair")
	game.set_paused(false)
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(29.0)
	_check(game.mode == "cockpit" and mission.ship_health == 60.0 and mission.repair_seconds_remaining == 1.0)
	clock.advance(1.0)
	_check(mission.ship_health == 80.0 and mission.repair_seconds_remaining == 0.0, "repair completes while commander is airborne")
	mission.restart_scenario()
	mission.ship_health = 90.0
	_check(mission.start_damage_control())
	clock.advance(30.0)
	_check(mission.ship_health == 100.0, "repair cannot exceed hull capacity")
	mission.ship_health = 70.0
	_check(mission.start_damage_control())
	clock.advance(30.0)
	_check(not mission.start_damage_control() and mission.repair_teams == 0, "supplies remain depleted")
	mission.restart_scenario()
	world.set_ship_command(42.0, 22.0)
	clock.advance(1000.0)
	world.set_ship_command(42.0, 0.0)
	mission.ship_health = 20.0
	_check(mission.start_damage_control())
	clock.advance(10.0)
	_check(not game.ship_afloat and mission.ship_health == 0.0 and mission.repair_seconds_remaining == 0.0, "lethal incoming fire cancels repair instead of resurrecting hull")
	mission.restart_scenario()
	mission.enemy_tracking_ship = true
	world.ship_position_km = world.contact_position_km + Vector2(0, 1)
	mission._enemy_attack(100)
	mission._enemy_attack(145)
	_check(mission.damaged_gun_mounts.size() == 1, "second incoming hit disables one mount")
	var damaged: String = mission.damaged_gun_mounts[0]
	mission.select_gun_group(damaged)
	_check("受损" in mission.ship_gun_block_reason(), "damaged mount rejects fire")
	var ammunition_before: int = mission.ship_ammo
	var reload_before: float = mission.next_ship_fire_seconds
	mission.select_gun_group("aft")
	_check("受损" not in mission.ship_gun_block_reason(), "other mount remains operational")
	mission.select_gun_group(damaged)
	world.set_ship_command(0, 0)
	_check(mission.start_damage_control() and mission.repair_mount_id == damaged, "repair prioritizes selected damaged mount")
	mission.enemy_alive = false
	clock.advance(30)
	_check(mission.damaged_gun_mounts.is_empty() and mission.ship_ammo == ammunition_before and mission.next_ship_fire_seconds == reload_before, "repair restores mount without replenishing ammunition or resetting reload")
	mission.restart_scenario()
	_check(mission.damaged_gun_mounts.is_empty() and mission.repair_mount_id.is_empty(), "restart clears subsystem damage")
	if failures.is_empty():
		print("Damage control smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, description: String = "damage control state transition") -> void:
	if not condition:
		failures.append(description)
