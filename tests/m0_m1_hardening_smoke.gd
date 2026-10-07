extends SceneTree

var failures: PackedStringArray = []
var transition_snapshots: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data: Node = root.get_node("DataManager")
	for field in ["cruise_speed_knots", "fuel_minutes"]:
		for invalid in [0.0, -1.0, NAN, INF]:
			var plane: Resource = load("res://scripts/data/aircraft_definition.gd").new()
			plane.id = "qa.invalid_plane"
			plane.display_name = "QA"
			plane.set(field, invalid)
			_check(not data.register_definition(plane, "qa_" + field) and not data.definitions.has(plane.id) and data.errors[-1].contains(field), "bad aircraft %s is rejected without indexing" % field)
			data.reload()
	var bad_contact: Resource = load("res://scripts/data/contact_definition.gd").new()
	bad_contact.id = "qa.contact"
	bad_contact.display_name = "QA"
	bad_contact.bearing_degrees = 360.0
	_check(not data.register_definition(bad_contact, "qa_bearing"), "invalid bearing is rejected")
	data.reload()
	var bad_task: Resource = load("res://scripts/data/task_definition.gd").new()
	bad_task.id = "qa.task"
	bad_task.display_name = "QA"
	_check(not data.register_definition(bad_task, "qa_empty_task") and data.errors[-1].contains("ship_id"), "missing task fields name their source")
	data.reload()
	bad_task.ship_id = "ship.destroyer"
	bad_task.aircraft_id = "aircraft.kestrel"
	bad_task.target_contact_id = "contact.alpha"
	bad_task.objective = "QA"
	_check(data.register_definition(bad_task, "qa_incompatible"), "complete task can be staged for reference validation")
	_check(not data.validate_catalog() and "not supported" in "\n".join(data.errors), "task cannot assign unsupported aircraft to ship")
	_check(data.reload(), "valid catalog restores after rejected data")
	var mission: Node = root.get_node("MissionController")
	var game: Node = root.get_node("GameManager")
	var world: Node = root.get_node("WorldState")
	var clock: Node = root.get_node("WorldClock")
	root.get_node("EventBus").mode_changed.connect(_observe_transition)
	mission.restart_scenario()
	paused = true
	_check(not mission.prepare_sortie() and game.mode == "bridge", "pause cannot begin sortie")
	_check(not mission.identify_contact() and not game.target_identified, "pause cannot confirm combat information")
	_check(mission.command_ship(20, 10), "paused bridge can queue navigation orders")
	var start_position: Vector2 = world.ship_position_km
	_check(not clock.advance(30) and world.ship_position_km == start_position, "queued orders do not advance paused world")
	paused = false
	mission.prepare_sortie()
	_check(mission.set_sortie_ship_standby(true), "configuration accepts standby choice")
	mission.launch_sortie()
	_check(transition_snapshots[-1].switch_seconds == 5.0, "transfer observers see initialized countdown")
	mission.cancel_sortie()
	_check(game.mode == "configuration" and transition_snapshots[-1].switch_seconds == 0.0 and not mission.aircraft_airborne, "cancelled transfer commits cleared countdown without launching")
	mission.launch_sortie()
	var before_transfer: Vector2 = world.ship_position_km
	clock.advance(4)
	_check(world.ship_position_km != before_transfer and world.ship_speed_knots == 10, "world and last ship command continue during transfer")
	clock.advance(1)
	_check(game.mode == "cockpit" and world.ship_speed_knots == 0 and mission.aircraft_airborne, "selected standby applies only when aircraft takes off")
	_check(transition_snapshots[-1].airborne and transition_snapshots[-1].sorties == 1, "cockpit observers see actual airborne ownership")
	var flight_fuel: float = mission.aircraft_fuel_seconds
	var flight_position: Vector2 = mission.aircraft_position_km
	_check(not mission.command_ship(180, 22) and world.ship_speed_knots == 0, "hidden bridge actions cannot control ship from cockpit")
	paused = true
	_check(not mission.perform_recon() and not mission.aircraft_attack() and not mission.begin_return(), "paused air actions cannot consume or complete anything")
	_check(mission.aircraft_fuel_seconds == flight_fuel and mission.aircraft_position_km == flight_position, "rejected actions preserve flight resources")
	paused = false
	mission.begin_return()
	var return_fuel: float = mission.aircraft_fuel_seconds
	_check(mission.cancel_return() and game.mode == "cockpit" and mission.aircraft_destination == "manual" and mission.aircraft_fuel_seconds == return_fuel, "cancel return restores flying without refill or teleport")
	_check(not mission.cancel_return(), "cannot cancel return twice")
	mission.set_aircraft_destination("contact")
	clock.advance(240)
	_check(mission.perform_recon(), "cancelled return can lead to real recon")
	mission.begin_return()
	clock.advance(250)
	paused = true
	_check(not mission.land_aircraft() and mission.aircraft_airborne, "paused landing cannot transfer ownership")
	paused = false
	_check(mission.land_aircraft(), "recon flight can safely return to waiting carrier")
	_check(transition_snapshots[-1].recovered and not transition_snapshots[-1].airborne, "bridge recovery emits coherent grounded state")
	_check(mission.command_ship(0, 5), "ship control returns after landing")
	paused = true
	_check(not mission.complete_mission(), "paused report cannot settle")
	paused = false
	_check(mission.complete_mission() and transition_snapshots[-1].settled, "settlement signal includes committed result")
	_check(not mission.command_ship(90, 10) and not mission.perform_recon(), "ended action cannot resume control or mutate objectives")
	mission.restart_scenario()
	mission.command_ship(0, 22)
	mission.prepare_sortie()
	mission.launch_sortie()
	clock.advance(5)
	_check(world.ship_speed_knots == 22, "default sortie retains last ship order")
	_check(mission.request_ship_standby() and world.ship_speed_knots == 0, "airborne radio request stops carrier for recovery")
	_check(not mission.request_ship_standby(), "repeated standby provides feedback without another order")
	mission.begin_return()
	mission.set_aircraft_destination("airfield")
	mission.aircraft_position_km = mission.airfield_position_km
	mission.land_aircraft()
	_check(transition_snapshots[-1].recovered and transition_snapshots[-1].site == "friendly_airfield" and not transition_snapshots[-1].airborne, "airfield recovery observer sees consistent result")
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	shell.get_node("StartButton").emit_signal("pressed")
	for step in range(7):
		var prep: Control = shell.get_node("GameCRTSlot/Preparation")
		if prep.stage == "tutorial":
			prep.tutorial.skip()
		prep.advance()
	var harbor: Control = shell.get_node("GameCRTSlot/Harbor")
	harbor.navigation.cast_off()
	harbor.navigation.set_command(0, 10)
	harbor.advance_navigation(100)
	var main: Control = shell.get_node("GameCRTSlot").get_child(0)
	main._button("PhaseActions/Prepare").emit_signal("pressed")
	_check(main.sortie_configuration.visible and main.sortie_details.text.contains("余油"), "UI shows real sortie data")
	main.standby_checkbox.button_pressed = true
	await process_frame
	var launch_rect: Rect2 = main._button("PhaseActions/Launch").get_global_rect()
	var scroll_rect: Rect2 = main.details.get_parent().get_global_rect()
	_check(launch_rect.position.y >= scroll_rect.position.y and launch_rect.end.y <= scroll_rect.end.y, "launch button remains visible with configuration without scrolling")
	main._button("PhaseActions/Launch").emit_signal("pressed")
	clock.advance(5)
	main._button("PhaseActions/Return").emit_signal("pressed")
	main.cancel_return_button.emit_signal("pressed")
	_check(game.mode == "cockpit" and not main.cancel_return_button.visible and world.ship_speed_knots == 0, "UI config and return cancellation use guarded controller")
	main._toggle_pause()
	_check(main._button("FlightControls/FlightActions/Recon").disabled and main._button("PhaseActions/Return").disabled, "pause disables resource-changing buttons")
	main.menu_requested.emit()
	await process_frame
	if failures.is_empty():
		print("M0/M1 hardening smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _observe_transition(_previous: String, current: String) -> void:
	var game: Node = root.get_node("GameManager")
	var mission: Node = root.get_node("MissionController")
	transition_snapshots.append({"mode": current, "recovered": game.player_recovered, "site": game.recovery_site, "settled": game.task_settled, "airborne": mission.aircraft_airborne, "sorties": mission.sorties_launched, "switch_seconds": mission.switch_seconds_remaining})

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
