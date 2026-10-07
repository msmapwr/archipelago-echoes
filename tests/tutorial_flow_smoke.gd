extends SceneTree

const Simulation = preload("res://scripts/core/tutorial_simulation.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settings: Node = root.get_node("UserSettings")
	var original_progress_path: String = settings.tutorial_progress_path
	var original_completed: bool = settings.tutorial_completed
	var original_error: String = settings.tutorial_progress_error
	var progress_path := "user://qa_tutorial_%d.cfg" % Time.get_ticks_usec()
	settings.tutorial_progress_path = progress_path
	settings.load_tutorial_progress()
	_check(not settings.tutorial_completed, "missing tutorial record defaults to first run")
	var model = Simulation.new()
	_check(not model.act("fire") and not model.fired and model.step == 0, "cannot fire before observing and identifying")
	model.act("scan")
	model.act("select")
	_check(not model.act("identify") and not model.identified, "one observation does not identify target")
	model.act("scan")
	model.advance_time(16)
	_check(not model.act("identify"), "stale observations require new scan")
	model.act("scan")
	model.act("identify")
	model.advance_time(16)
	_check(not model.act("fire") and not model.fired, "stale fire control cannot fire")
	model.act("scan")
	model.act("fire")
	model.act("throttle")
	_check(model.step == 4, "speed alone does not complete helm lesson")
	model.act("turn")
	model.act("pause")
	var age: float = model.echo_age
	model.advance_time(100)
	_check(model.paused and model.echo_age == age and not model.act("scan"), "pause freezes phosphor and blocks active scan")
	model.act("pause")
	_check(not model.act("land") and model.flight == "deck", "cannot land before taking off and returning")
	model.act("launch")
	_check(not model.act("land") and not model.ready_to_continue(), "cannot land before return")
	model.act("return")
	model.act("land")
	_check(model.ready_to_continue() and model.flight == "recovered" and not model.skipped, "all seven lessons complete through valid operations")
	var shell: Control = load("res://scenes/main/console_shell.tscn").instantiate()
	root.add_child(shell)
	shell.get_node("StartButton").emit_signal("pressed")
	var prep: Control = shell.get_node("GameCRTSlot/Preparation")
	var mission: Node = root.get_node("MissionController")
	var clock: Node = root.get_node("WorldClock")
	var world: Node = root.get_node("WorldState")
	var game: Node = root.get_node("GameManager")
	var events: Node = root.get_node("EventBus")
	var health: float = mission.ship_health
	var ammo: int = mission.ship_ammo
	var fuel: float = mission.aircraft_fuel_seconds
	var seconds: float = clock.elapsed_seconds
	var position: Vector2 = world.ship_position_km
	var event_count: int = events.history.size()
	prep.advance()
	prep.advance()
	_check("原型叙事" in prep.body.text and prep.accepted_task_id.is_empty(), "background comes from task without prematurely accepting command")
	prep.advance()
	var trainer: Control = prep.tutorial
	prep.advance()
	_check(prep.stage == "tutorial" and prep.advance_button.disabled, "programmatic advance also respects tutorial gate")
	trainer.perform("scan")
	await process_frame
	await process_frame
	# Graphical runs dispatch a window click; headless runs use the same hit-test handler.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	if DisplayServer.get_name() == "headless":
		click.position = trainer.scope.echo_position()
		trainer.scope._gui_input(click)
	else:
		var logical: Vector2 = trainer.scope.global_position + trainer.scope.echo_position()
		click.position = logical * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
		click.global_position = click.position
		Input.parse_input_event(click)
		await process_frame
		var release: InputEventMouseButton = click.duplicate()
		release.pressed = false
		Input.parse_input_event(release)
		await process_frame
	_check(trainer.simulation.selected and trainer.simulation.step == 2, "radar echo selection advances lesson")
	for action in ["scan", "identify", "fire", "turn", "throttle", "pause", "pause", "launch", "return", "land"]:
		trainer.action_buttons[action].emit_signal("pressed")
	_check(not prep.advance_button.disabled, "completed tutorial enables continuation")
	_check(settings.tutorial_completed and FileAccess.file_exists(progress_path), "actual tutorial completion persists independently of display settings")
	settings.tutorial_completed = false
	_check(settings.load_tutorial_progress() and settings.tutorial_completed, "tutorial completion survives reload")
	_check(paused and clock.elapsed_seconds == seconds and mission.ship_health == health and mission.ship_ammo == ammo and mission.aircraft_fuel_seconds == fuel and world.ship_position_km == position and events.history.size() == event_count and not game.target_identified, "rehearsal preserves live clock, combat resources, world, events and mission flags")
	_check(trainer.replay_button.get_global_rect().end.y < prep.get_global_rect().position.y + 678, "tutorial controls stay inside CRT glass")
	trainer.replay_button.emit_signal("pressed")
	_check(prep.advance_button.disabled and trainer.simulation.step == 0 and not trainer.simulation.selected and trainer.simulation.scans == 0, "replay clears training and closes completion gate")
	trainer.skip_button.emit_signal("pressed")
	_check(trainer.simulation.skipped and not prep.advance_button.disabled, "explicit skip opens completion gate")
	prep.advance()
	_check(prep.stage == "orders" and "任务目标" in prep.body.text and "舰船 /" in prep.body.text and prep.accepted_task_id.is_empty(), "briefing binds task and actual units before acceptance")
	var data: Node = root.get_node("DataManager")
	data.errors.append("qa_invalid_orders")
	prep.advance()
	_check(prep.stage == "orders" and prep.accepted_task_id.is_empty(), "invalid task blocks command acceptance")
	data.errors.erase("qa_invalid_orders")
	prep.advance()
	_check(prep.accepted_task_id == game.current_task_id and prep.stage == "generation" and prep.generation_ready, "valid command unlocks generation")
	prep.advance()
	prep.accepted_task_id = ""
	prep.advance()
	_check(shell.session_stage == "harbor" and not shell.started, "harbor rejects missing command acceptance")
	prep.menu_requested.emit()
	await process_frame
	shell.get_node("StartButton").emit_signal("pressed")
	var fresh: Control = shell.get_node("GameCRTSlot/Preparation")
	_check(fresh.accepted_task_id.is_empty() and not fresh.tutorial.simulation.ready_to_continue(), "new session does not inherit command or skipped training")
	fresh.advance()
	fresh.advance()
	_check(fresh.stage == "background" and fresh.replay_tutorial_button.visible, "returning player has explicit replay entry")
	fresh.advance()
	_check(fresh.stage == "orders", "completed tutorial is automatically omitted on later starts")
	fresh.replay_tutorial_button.emit_signal("pressed")
	_check(fresh.stage == "tutorial" and fresh.advance_button.disabled and settings.tutorial_completed, "manual replay requires actions without erasing past completion")
	fresh.tutorial.skip_button.emit_signal("pressed")
	fresh.advance()
	_check(fresh.stage == "orders", "manual replay returns to command briefing")
	settings.tutorial_progress_path = progress_path + ".first_skip"
	settings.load_tutorial_progress()
	fresh.replay_tutorial()
	fresh.tutorial.skip()
	_check(not settings.tutorial_completed and not FileAccess.file_exists(settings.tutorial_progress_path), "skipping does not falsely record tutorial completion")
	settings.tutorial_progress_path = "user://qa_missing_tutorial_%d/progress.cfg" % Time.get_ticks_usec()
	_check(not settings.mark_tutorial_completed() and not settings.tutorial_completed and not settings.tutorial_progress_error.is_empty(), "failed persistence leaves explicit error and no false saved completion")
	DirAccess.remove_absolute(progress_path)
	settings.tutorial_progress_path = original_progress_path
	settings.tutorial_completed = original_completed
	settings.tutorial_progress_error = original_error
	fresh.menu_requested.emit()
	if failures.is_empty():
		print("Tutorial and briefing smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
