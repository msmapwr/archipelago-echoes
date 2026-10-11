extends SceneTree

const Guidance = preload("res://scripts/core/mission_guidance.gd")
var failures: PackedStringArray = []
var mission: Node
var game: Node
var world: Node
var clock: Node
var events: Node

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	mission = root.get_node("MissionController")
	game = root.get_node("GameManager")
	world = root.get_node("WorldState")
	clock = root.get_node("WorldClock")
	events = root.get_node("EventBus")
	assignment_lifecycle()
	observation_and_resource_gates()
	await ui_archive_guidance()
	if failures.is_empty():
		print("P2.1 fire control smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func known_target() -> void:
	mission.restart_scenario()
	mission.scan()
	check(mission.identify_contact(), "fixture confirms target through real scans")

func in_range() -> void:
	known_target()
	# Real navigation and observation; no teleport or synthetic readiness flags.
	world.set_ship_command(42, 22)
	clock.advance(1000)
	world.set_ship_command(42, 0)
	check(mission.scan(), "fixture obtains fresh in-range observation")

func assignment_lifecycle() -> void:
	mission.restart_scenario()
	check(not mission.assign_fire_control_target(mission.CONTACT_ID) and mission.ship_ammo == 6 and mission.fire_control_target_id.is_empty(), "unknown target cannot be assigned")
	known_target()
	check(not mission.fire_ship_gun(mission.CONTACT_ID) and mission.last_message.contains("指派") and mission.ship_ammo == 6, "explicit target ID does not bypass assignment")
	check(not mission.assign_fire_control_target("bogus") and mission.fire_control_target_id.is_empty(), "invalid ID cannot create an order")
	mission.set_radar_emitting(false)
	check(not mission.assign_fire_control_target(mission.CONTACT_ID) and mission.fire_control_target_id.is_empty() and mission.ship_ammo == 6, "absent observation cannot create an order")
	mission.set_radar_emitting(true)
	game.set_paused(true)
	var time: float = clock.elapsed_seconds
	check(mission.assign_fire_control_target(mission.CONTACT_ID) and mission.fire_control_target_id == mission.CONTACT_ID, "pause queues assignment")
	var order: String = mission.fire_control_order_id
	check(events.history.back().kind == "fire_control_assigned" and events.history.back().details.queued, "queued order has command metadata")
	var count: int = events.history.size()
	check(mission.assign_fire_control_target(mission.CONTACT_ID) and events.history.size() == count and mission.fire_control_order_id == order, "duplicate assignment is idempotent")
	check(not mission.fire_ship_gun() and mission.last_message.contains("暂停"), "pause blocks firing")
	clock.advance(30)
	check(clock.elapsed_seconds == time and mission.ship_ammo == 6 and mission.enemy_health == 100, "queued order does not advance combat")
	check(mission.clear_fire_control_target() and mission.fire_control_target_id.is_empty() and mission.ship_ammo == 6, "paused cancellation preserves resources")
	check(not mission.clear_fire_control_target() and events.history.back().kind == "fire_control_rejected", "empty cancellation is archived without mutating resources")
	game.set_paused(false)
	check(mission.assign_fire_control_target(mission.CONTACT_ID) and mission.fire_control_order_id != order, "new assignment receives a new order ID")
	order = mission.fire_control_order_id
	check(mission.prepare_sortie() and mission.fire_control_order_id == order, "sortie retains but suspends order")
	check(not mission.assign_fire_control_target(mission.CONTACT_ID) and not mission.clear_fire_control_target() and not mission.fire_ship_gun(), "non-bridge commands cannot mutate or fire order")
	check(mission.launch_sortie(), "sortie can launch with retained order")
	clock.advance(5)
	check(mission.fire_control_order_id == order and mission.ship_ammo == 6, "AI handover never auto-fires")
	check(mission.begin_return() and mission.land_aircraft(), "immediate valid recovery returns bridge control")
	check(game.mode == "bridge" and mission.fire_control_order_id == order, "recovery retains original order")
	check(mission.complete_mission() and mission.fire_control_target_id.is_empty(), "settlement clears order without requiring combat")
	known_target()
	mission.assign_fire_control_target(mission.CONTACT_ID)
	game.report_player_death("test_failure")
	check(mission.fire_control_target_id.is_empty() and not mission.assign_fire_control_target(mission.CONTACT_ID), "failure clears order and rejects new commands")
	known_target()
	mission.assign_fire_control_target(mission.CONTACT_ID)
	game.report_ship_sunk()
	check(mission.fire_control_target_id.is_empty(), "platform loss clears order")
	known_target()
	mission.assign_fire_control_target(mission.CONTACT_ID)
	mission.restart_scenario()
	check(mission.fire_control_target_id.is_empty() and mission.fire_control_order_id.is_empty() and mission.ship_ammo == 6, "restart resets order and resources")

func observation_and_resource_gates() -> void:
	in_range()
	check(mission.assign_fire_control_target(mission.CONTACT_ID), "in-range assignment accepted")
	var order: String = mission.fire_control_order_id
	check(not mission.fire_ship_gun("bogus") and mission.ship_ammo == 6 and mission.fire_control_order_id == order, "mismatched request preserves order and ammunition")
	world.set_ship_command(222, 0)
	check(not mission.fire_ship_gun() and mission.last_message.contains("射界") and mission.ship_ammo == 6, "assigned target outside arc cannot fire")
	world.set_ship_command(42, 0)
	var observed: Vector2 = mission.last_contact_position_km
	var live: Vector2 = world.contact_position_km
	world.contact_position_km = Vector2(49, 49)
	check(mission.ship_gun_block_reason().is_empty() and mission.last_contact_position_km == observed, "readiness uses last observation rather than hidden live position")
	world.contact_position_km = live
	check(mission.fire_ship_gun() and mission.ship_ammo == 5 and mission.enemy_health == 100 and mission.fire_control_order_id == order, "one command fires one round against assigned target")
	var shot: Dictionary = {}
	for event in events.history:
		if event.kind == "weapon_fired": shot = event
	check(shot.details.get("target_id") == mission.CONTACT_ID and shot.details.get("order_id") == order and shot.details.get("aim_position_km") == observed, "shot records target order and observation")
	var reload_at: float = mission.next_ship_fire_seconds
	check(not mission.fire_ship_gun() and mission.ship_ammo == 5 and mission.next_ship_fire_seconds == reload_at, "reload rejection preserves ammunition and deadline")
	check(mission.clear_fire_control_target() and mission.ship_ammo == 5 and mission.next_ship_fire_seconds == reload_at, "cancellation cannot reset reload")
	check(mission.assign_fire_control_target(mission.CONTACT_ID), "reassignment during reload allowed")
	clock.advance(30)
	check(mission.enemy_health == 50, "arriving shell deals exactly one hit")
	mission.set_radar_emitting(false)
	check(not mission.fire_ship_gun() and mission.last_message.contains("静默") and not mission.fire_control_target_id.is_empty(), "silence suspends rather than clears assignment")
	mission.set_radar_emitting(true)
	clock.advance(45)
	check(mission.ship_gun_block_reason().is_empty(), "observation remains valid at exact 45 second boundary")
	clock.advance(0.01)
	check(not mission.fire_ship_gun() and mission.last_message.contains("过期") and mission.ship_ammo == 5, "expired observation blocks fire without resource cost")
	order = mission.fire_control_order_id
	check(not mission.assign_fire_control_target(mission.CONTACT_ID) and mission.fire_control_order_id == order and events.history.back().details.get("order_id") == order, "reassignment cannot refresh expired observation or replace existing order and rejection retains its ID")
	mission.scan()
	world.contact_position_km = world.ship_position_km + Vector2(mission.SCAN_RANGE_KM + 1, 0)
	mission.scan()
	check(not mission.contact_visible and not mission.fire_control_target_id.is_empty() and not mission.fire_ship_gun() and mission.ship_ammo == 5, "lost contact preserves order but blocks fire")
	world.contact_position_km = live
	mission.scan()
	check(mission.fire_ship_gun() and mission.enemy_alive and mission.ship_ammo == 4, "reacquisition permits second shell launch")
	clock.advance(10)
	check(not mission.enemy_alive and mission.fire_control_target_id.is_empty(), "second arriving hit destroys target and clears order")
	check(not mission.assign_fire_control_target(mission.CONTACT_ID) and not mission.fire_ship_gun(), "destroyed target cannot be reassigned or fired upon")

func ui_archive_guidance() -> void:
	in_range()
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_contact_selected(mission.CONTACT_ID)
	check(mission.fire_control_target_id.is_empty() and not main.assign_target_button.disabled, "selection exposes assignment without assigning automatically")
	main.assign_target_button.emit_signal("pressed")
	var order: String = mission.fire_control_order_id
	main._on_contact_deselected()
	main.radar.set_display_range(12.5)
	check(main.selected_contact_id.is_empty() and mission.fire_control_order_id == order and main.radar.fire_control_assigned, "deselection and scale changes leave gun assignment intact")
	check(main.guidance.stage == "sortie" and main.guidance.fire_control_hint.contains("手动射击"), "guidance adds fire-control advice without changing mission objective")
	main.toggle_archive()
	check(paused and main.archive.tabs.size() == 4, "archive pauses with additional fire-control tab")
	main.archive.select_tab(3)
	check(main.archive.content.text.contains(order) and main.archive.content.text.contains("甲板炮指派") and main.archive.content.text.contains("T+") and main.archive.content.text.contains("打开档案前 / 可手动射击"), "archive presents current assignment, pre-pause readiness and timestamped command")
	main.close_archive()
	check(not paused and mission.fire_control_order_id == order, "closing archive restores simulation and preserves order")
	main._button("RadarActions/Fire").emit_signal("pressed")
	check(mission.ship_ammo == 5 and main.gun_status.text.contains("装填"), "UI fires assigned gun without selected contact")
	main.clear_target_button.emit_signal("pressed")
	main.toggle_archive()
	main.archive.select_tab(3)
	check(main.archive.content.text.contains("射击 A1") and main.archive.content.text.contains("玩家撤销") and main.archive.content.text.contains(order), "archive links assignment shot and cancellation")
	main.archive.select_tab(2)
	check(main.archive.content.text.contains("甲板炮指派") and main.archive.content.text.contains("玩家撤销"), "existing action history also includes fire-control commands")
	main.close_archive()
	main.queue_free()
	await process_frame
	var guide := Guidance.project({"mode":"bridge", "identified":true,"fire_control_enabled":true,"fire_control_assigned":true,"fire_control_reason":"接触情报已过期", "tracking":true})
	check(guide.stage == "sortie" and guide.fire_control_hint.contains("过期") and guide.warning.contains("追踪"), "projection keeps fire-control blocker separate from safety warning")
	guide = Guidance.project({"mode":"settlement","fire_control_enabled":true,"fire_control_assigned":true})
	check(guide.stage == "complete" and guide.fire_control_hint.is_empty(), "ended guidance does not invite combat")

func check(ok: bool, description: String) -> void:
	if not ok: failures.append(description)
