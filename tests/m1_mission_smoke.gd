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
	_check(not mission.identify_contact(), "one scan cannot identify target")
	_check(mission.scan() and mission.scan() and mission.identify_contact(), "two valid scans allow confirmation")
	_check(not mission.fire_ship_gun("contact.alpha") and "射程" in mission.last_message, "out of range shot explains failure")
	_check(world.set_ship_command(42.0, 22.0), "ship can close with target")
	clock.advance(1000.0)
	_check(mission.enemy_tracking_ship and mission.ship_health == 100.0, "enemy tracking warning precedes first counterfire")
	clock.advance(10.0)
	_check(mission.ship_health < 100.0, "enemy counters when ship closes")
	_check(not mission.fire_ship_gun("contact.alpha") and "过期" in mission.last_message, "stale contact cannot guide fire")
	world.set_ship_command(world.ship_heading_degrees, 0.0)
	mission.scan()
	_check(mission.fire_ship_gun("contact.alpha") and mission.enemy_health == 50.0, "confirmed in-range shot damages target")
	_check(not mission.fire_ship_gun("contact.alpha") and "装填" in mission.last_message, "reload interval prevents instant repeat")
	clock.advance(30.0)
	mission.scan()
	_check(mission.fire_ship_gun("contact.alpha") and not mission.enemy_alive and not mission.enemy_tracking_ship, "second hit disables enemy and ends its tracking")
	_check(mission.ship_ammo == 4, "gun consumes exactly two rounds")

	mission.restart_scenario()
	world.set_ship_command(42.0, 22.0)
	clock.advance(600.0)
	_check(mission.enemy_tracking_ship and mission.ship_health == 100.0 and world.contact_range_km() > 10.0, "active radar warns of interception before enemy gun range")
	mission.set_radar_emitting(false)
	clock.advance(91.0)
	_check(not mission.enemy_tracking_ship and mission.ship_health == 100.0, "silent ship can break distant tracking after warning")

	mission.restart_scenario()
	_check(mission.set_radar_emitting(false) and not mission.contact_visible, "radio silence hides live contact")
	_check(not mission.scan() and "静默" in mission.last_message, "silent radar cannot provide new scans")
	_check(not mission.fire_ship_gun("contact.alpha") and "静默" in mission.last_message, "silent radar cannot guide deck gun")
	world.set_ship_command(42.0, 22.0)
	clock.advance(970.0)
	world.set_ship_command(world.ship_heading_degrees, 0.0)
	_check(mission.ship_health == 100.0 and not mission.enemy_tracking_ship and world.contact_range_km() < 10.0, "silent approach avoids distant passive interception")
	_check(mission.set_radar_emitting(true) and mission.contact_visible and mission.enemy_tracking_ship, "active radar reacquires target and exposes carrier")
	clock.advance(9.0)
	_check(mission.ship_health == 100.0, "interception gives a short reaction window")
	clock.advance(1.0)
	_check(mission.ship_health == 80.0, "enemy can counterfire after radar interception")
	mission.set_radar_emitting(false)
	clock.advance(46.0)
	_check(mission.ship_health == 60.0 and mission.enemy_tracking_ship, "going silent does not instantly erase enemy tracking")
	clock.advance(91.0)
	_check(not mission.enemy_tracking_ship and mission.ship_health == 60.0, "enemy loses track after silent withdrawal")

	mission.restart_scenario()
	mission.set_radar_emitting(false)
	world.set_ship_command(42.0, 22.0)
	clock.advance(1100.0)
	_check(mission.enemy_tracking_ship and mission.ship_health == 100.0 and world.contact_range_km() < 6.0, "enemy lookouts can find a silent ship at visual range")
	clock.advance(10.0)
	_check(mission.ship_health == 80.0, "silence cannot prevent close-range counterfire")

	mission.restart_scenario()
	world.set_ship_command(42.0, 22.0)
	clock.advance(1000.0)
	world.set_ship_command(world.ship_heading_degrees, 0.0)
	clock.advance(10.0)
	for volley in range(4):
		clock.advance(45.0)
	_check(not game.ship_afloat and game.mode == "campaign_failed", "enemy counterfire can sink an occupied carrier")

	mission.restart_scenario()
	_check(mission.prepare_sortie() and mission.launch_sortie(), "player can configure and start transfer")
	_check(game.mode == "switching", "transfer has a distinct waiting state")
	clock.advance(4.0)
	_check(game.mode == "switching" and mission.switch_seconds_remaining > 0.0, "transfer waits on world time")
	clock.advance(1.0)
	_check(game.mode == "cockpit" and mission.aircraft_airborne, "aircraft receives control after transfer")
	_check(mission.set_aircraft_destination("contact"), "aircraft can navigate to contact")
	clock.advance(240.0)
	_check(mission.perform_recon() and game.target_identified, "aircraft identifies target inside recon range")
	_check(mission.aircraft_attack() and not mission.enemy_alive and mission.aircraft_bombs == 0, "identified target can be disabled in one bomb run")
	_check(not mission.aircraft_attack(), "aircraft cannot attack again without ammunition")
	_check(mission.begin_return(), "aircraft enters return state")
	clock.advance(250.0)
	_check(mission.land_aircraft() and game.player_recovered and game.mode == "bridge", "aircraft can land on stopped carrier")
	_check(mission.complete_mission() and game.mode == "settlement", "identified target and safe return settle mission")

	mission.restart_scenario()
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5.0)
	clock.advance(4501.0)
	_check(game.mode == "campaign_failed" and not game.player_alive, "fuel exhaustion ends one-life scenario")

	mission.restart_scenario()
	mission.scan()
	mission.scan()
	mission.identify_contact()
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5.0)
	game.report_ship_sunk()
	_check(game.mode == "cockpit" and game.player_alive, "airborne pilot survives carrier sinking")
	mission.begin_return()
	_check(mission.aircraft_destination == "airfield", "sunk carrier redirects return to airfield")
	clock.advance(450.0)
	_check(mission.land_aircraft() and game.recovery_site == "friendly_airfield", "airfield can recover pilot after carrier loss")
	_check(mission.complete_mission(), "safe airfield recovery permits task settlement")

	_finish()

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("M1 mission smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
