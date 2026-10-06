extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data_manager: Node = root.get_node("DataManager")
	var game_manager: Node = root.get_node("GameManager")
	var event_bus: Node = root.get_node("EventBus")
	_check(data_manager.errors.is_empty(), "sample definitions load without errors")
	_check(data_manager.definitions.size() == 10, "original definitions and five new warship prototypes are indexed")
	_check(data_manager.get_definition("task.first_recon") != null, "task id resolves")

	var bad_definition: Resource = load("res://scripts/data/weapon_definition.gd").new()
	_check(not data_manager.register_definition(bad_definition, "test_missing_id"), "missing id is rejected")
	_check(data_manager.errors.size() == 1 and "test_missing_id" in data_manager.errors[0], "validation identifies source")
	_check(data_manager.reload(), "data manager recovers after invalid data")

	_check(not game_manager.change_mode("cockpit"), "forbidden direct bridge-to-cockpit transition is rejected")
	_check(game_manager.change_mode("configuration"), "bridge-to-configuration transition works")
	_check(game_manager.change_mode("switching"), "configuration-to-switching transition works")
	_check(game_manager.change_mode("cockpit"), "switching-to-cockpit transition works")
	_check(not game_manager.change_mode("settlement"), "direct airborne settlement is rejected")
	game_manager.report_ship_sunk()
	_check(game_manager.mode == "cockpit" and game_manager.player_alive, "sinking ship does not end airborne campaign")
	_check(game_manager.change_mode("returning"), "airborne player can begin return")
	_check(not game_manager.change_mode("bridge"), "player cannot return to sunken ship")
	_check(not game_manager.settle("success"), "ship sinking cannot settle mission while player is airborne")
	_check(game_manager.recover_player("friendly_airfield"), "friendly airfield can recover airborne player")
	_check(not game_manager.settle("success"), "mission cannot settle before target identification")
	_check(game_manager.identify_target("contact.alpha"), "first task target can be identified")
	_check(not game_manager.change_mode("settlement"), "settlement cannot bypass result event")
	_check(game_manager.settle("success"), "identified task settles after safe recovery")
	_check(game_manager.task_settled, "task settlement is recorded once")
	game_manager.report_player_death("test")
	_check(game_manager.mode == "campaign_failed", "player death ends campaign")
	game_manager.mode = "configuration"
	game_manager.player_alive = true
	game_manager.report_ship_sunk()
	_check(game_manager.mode == "campaign_failed", "ship sinking during configuration ends campaign")
	game_manager.mode = "returning"
	game_manager.player_alive = true
	game_manager.ship_afloat = true
	game_manager.player_recovered = false
	game_manager.recovery_site = ""
	_check(not game_manager.change_mode("bridge"), "return to bridge cannot bypass recovery")
	_check(game_manager.recover_player("ship"), "ship recovery returns control to bridge")

	var main: Control = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	var radar: Control = main.get_node("Content/RadarFrame/Radar")
	_check(radar.contact_visible, "contact appears on initial radar")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = radar._contact_position()
	click.global_position = click.position
	radar._gui_input(click)
	_check(radar.contact_selected_state, "mouse click selects contact")
	game_manager.set_paused(true)
	main._on_next_sweep_pressed()
	main._on_sweep_timer_timeout()
	_check(main.sweep_phase == 0, "pause stops manual and timed scanning")
	game_manager.set_paused(false)
	main.advance_sweep()
	_check("已更新" in main.get_node("Content/Details/ContactStatus").text, "updated contact has separate feedback")
	main.advance_sweep()
	_check(not radar.contact_visible and not radar.contact_selected_state, "lost contact is hidden and selection clears")
	_check("失联" in main.get_node("Content/Details/ContactStatus").text, "lost contact has separate feedback")
	_check(event_bus.history.size() > 0, "events are recorded")
	main.queue_free()
	if failures.is_empty():
		print("P0 smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
