extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var mission: Node = root.get_node("MissionController")
	var game: Node = root.get_node("GameManager")
	var clock: Node = root.get_node("WorldClock")
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	shell.get_node("StartButton").emit_signal("pressed")
	var main: Control = shell.get_node("GameCRTSlot").get_child(0)
	var terminal: Control = main.get_node("ScreenContainer/ScreenViewport/Terminal")
	var details: VBoxContainer = terminal.get_node("Content/DetailsFrame/DetailsScroll/Details")
	var radar: Control = terminal.get_node("Content/RadarFrame/Radar")
	await process_frame
	_check(radar.contact_visible, "CRT starts with a live radar report")
	_check("群岛回波" in terminal.get_node("Header/Brand").text, "CRT displays game title")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var logical_position: Vector2 = main.get_node("ScreenContainer").get_global_rect().position + radar.get_global_rect().position + radar._contact_position()
	var window_scale: Vector2 = Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	click.position = logical_position * window_scale
	click.global_position = click.position
	if DisplayServer.get_name() == "headless":
		click.position = radar._contact_position()
		click.global_position = click.position
		radar._gui_input(click)
	else:
		Input.parse_input_event(click)
	await process_frame
	_check(main.selected_contact_id == "contact.alpha", "radar selection reaches CRT controller")
	details.get_node("RadarActions/Fire").emit_signal("pressed")
	_check("尚未确认" in details.get_node("ActionStatus").text, "failed fire explains missing identification")
	var scans_before_silence: int = mission.contact_scan_count
	details.get_node("RadarActions/ToggleEmission").emit_signal("pressed")
	_check(not mission.radar_emitting and not radar.contact_visible and not radar.sweep_enabled, "silent command blanks live echo and freezes sweep")
	clock.advance(31.0)
	_check(mission.contact_scan_count == scans_before_silence, "silent radar does not auto-scan")
	details.get_node("RadarActions/ToggleEmission").emit_signal("pressed")
	_check(mission.radar_emitting and radar.contact_visible and radar.sweep_enabled, "CRT can restore active radar and contact")
	terminal.get_node("Footer/PauseStatus").emit_signal("pressed")
	_check(paused and details.get_node("RadarActions/NextSweep").disabled, "pause freezes scan action")
	terminal.get_node("Footer/PauseStatus").emit_signal("pressed")
	_check(not paused, "pause control resumes world")
	terminal.get_node("Footer/TimeScale").emit_signal("pressed")
	_check(clock.time_scale == 10.0 and "×10" in terminal.get_node("Footer/TimeScale").text, "time compression is visible")
	clock.set_time_scale(1.0)
	details.get_node("PhaseActions/Prepare").emit_signal("pressed")
	_check(game.mode == "configuration" and details.get_node("PhaseActions/Launch").visible, "sortie configuration exposes launch action")
	details.get_node("PhaseActions/Launch").emit_signal("pressed")
	clock.advance(5.0)
	_check(game.mode == "cockpit" and details.get_node("FlightControls").visible, "cockpit displays flight controls")
	clock.advance(240.0)
	details.get_node("FlightControls/FlightActions/Recon").emit_signal("pressed")
	_check(game.target_identified and "确认" in details.get_node("ActionStatus").text, "recon button confirms nearby contact")
	details.get_node("PhaseActions/Return").emit_signal("pressed")
	clock.advance(250.0)
	details.get_node("PhaseActions/Land").emit_signal("pressed")
	_check(game.mode == "bridge" and game.player_recovered, "landing returns to bridge")
	details.get_node("PhaseActions/Settle").emit_signal("pressed")
	_check(game.mode == "settlement" and details.get_node("PhaseActions/Restart").visible, "successful mission offers restart")
	details.get_node("PhaseActions/Restart").emit_signal("pressed")
	_check(game.mode == "bridge" and not game.target_identified, "restart begins a fresh mission")
	terminal.get_node("Footer/RadarRange").emit_signal("pressed")
	_check(radar.display_range_km == 12.5 and not radar.contact_visible and mission.contact_visible, "near display clips distant echo without losing sensor report")
	terminal.get_node("Footer/RadarRange").emit_signal("pressed")
	_check(radar.display_range_km == 25.0 and radar.contact_visible, "search display restores distant contact")
	_check("没有可射击" in details.get_node("GunStatus").text and radar.gun_arc_visible, "fire control states missing selection and displays gun arc")
	var world: Node = root.get_node("WorldState")
	world.set_ship_command(42.0, 22.0)
	clock.advance(1000.0)
	world.set_ship_command(world.ship_heading_degrees, 0.0)
	mission.scan()
	details.get_node("RadarActions/Identify").emit_signal("pressed")
	click.position = radar._contact_position()
	radar._gui_input(click)
	_check(radar.gun_ready and "可开火" in details.get_node("GunStatus").text, "in-range forward contact produces a ready firing solution")
	details.get_node("RadarActions/Fire").emit_signal("pressed")
	await process_frame
	_check(mission.enemy_health == 50.0 and not radar.gun_ready and "装填" in details.get_node("GunStatus").text, "successful shot updates damage and reload display")
	await process_frame
	var details_bottom: float = terminal.get_node("Content/DetailsFrame").get_rect().end.y
	var footer_top: float = terminal.get_node("Footer").get_rect().position.y
	_check(details_bottom <= footer_top, "CRT details do not overlap footer")
	shell.queue_free()
	mission.restart_scenario()
	_finish()

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("M1 CRT UI smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
