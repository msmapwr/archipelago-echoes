extends Control

signal menu_requested

const Guidance = preload("res://scripts/core/mission_guidance.gd")
var unit_library: PanelContainer
var _library_paused_world := false
var contact_icon: Control
var library_shade: ColorRect
var fire_control_actions: HBoxContainer
var assign_target_button: Button
var clear_target_button: Button

@onready var terminal: Control = $ScreenContainer/ScreenViewport/Terminal
@onready var radar: Control = terminal.get_node("Content/RadarFrame/Radar")
@onready var details: VBoxContainer = terminal.get_node("Content/DetailsFrame/DetailsScroll/Details")
@onready var mode_status: Label = terminal.get_node("Header/ModeStatus")
@onready var mission_status: Label = details.get_node("MissionStatus")
@onready var contact_status: Label = details.get_node("ContactStatus")
@onready var contact_details: Label = details.get_node("ContactDetails")
@onready var selection_details: Label = details.get_node("SelectionDetails")
@onready var gun_status: Label = details.get_node("GunStatus")
@onready var ship_controls: VBoxContainer = details.get_node("ShipControls")
@onready var ship_details: Label = ship_controls.get_node("ShipDetails")
@onready var navigation_status: Label = ship_controls.get_node("NavigationStatus")
@onready var flight_controls: VBoxContainer = details.get_node("FlightControls")
@onready var flight_details: Label = flight_controls.get_node("FlightDetails")
@onready var debrief: VBoxContainer = details.get_node("Debrief")
@onready var debrief_details: Label = debrief.get_node("DebriefDetails")
@onready var action_status: Label = details.get_node("ActionStatus")
@onready var event_details: Label = details.get_node("EventDetails")
@onready var pause_status: Button = terminal.get_node("Footer/PauseStatus")
@onready var time_scale_button: Button = terminal.get_node("Footer/TimeScale")
@onready var time_status: Label = terminal.get_node("Footer/TimeStatus")
@onready var radar_range_button: Button = terminal.get_node("Footer/RadarRange")

var selected_contact_id: String = ""
var aim_mode_button: Button
var lock_button: Button
var aim_controls: HBoxContainer
var correction_controls: HBoxContainer
var _next_auto_scan_seconds: float = 30.0
var _displayed_second: int = -1
var objective_title: Label
var objective_hint: Label
var archive: Control
var _archive_paused_world: bool = false
var guidance: Dictionary = {}
var sortie_configuration: VBoxContainer
var sortie_details: Label
var standby_checkbox: CheckBox
var standby_button: Button
var cancel_return_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_build_guidance_ui()
	_build_sortie_ui()
	_build_unit_library()
	_build_fire_control_ui()
	_connect_buttons()
	radar.contact_selected.connect(_on_contact_selected)
	radar.contact_deselected.connect(_on_contact_deselected)
	radar.waypoint_requested.connect(func(position_km: Vector2) -> void: MissionController.set_aircraft_waypoint(position_km))
	MissionController.state_changed.connect(_refresh_ui)
	MissionController.feedback_changed.connect(_on_feedback_changed)
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	WorldState.ship_command_changed.connect(_on_ship_command_changed)
	WorldState.navigation_blocked.connect(_on_navigation_blocked)
	EventBus.event_recorded.connect(_on_event_recorded)
	EventBus.mode_changed.connect(func(_previous: String, _current: String) -> void: _refresh_ui())
	if not DataManager.errors.is_empty() or WorldState.map == null:
		contact_status.text = "系统故障 / DATA ERROR"
		action_status.text = "请检查 Godot 输出中的数据加载错误"
		return
	_next_auto_scan_seconds = WorldClock.elapsed_seconds + 30.0
	MissionController.scan()
	_refresh_ui()
	_on_world_time_advanced(WorldClock.elapsed_seconds)
	_on_event_recorded({})

func _build_fire_control_ui() -> void:
	fire_control_actions = HBoxContainer.new()
	fire_control_actions.name = "FireControlActions"
	fire_control_actions.add_theme_constant_override("separation", 6)
	details.add_child(fire_control_actions)
	details.move_child(fire_control_actions, details.get_node("RadarActions").get_index() + 1)
	assign_target_button = Button.new()
	assign_target_button.text = "指派目标 → 甲板炮"
	assign_target_button.custom_minimum_size.y = 38
	assign_target_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assign_target_button.pressed.connect(func() -> void: MissionController.assign_fire_control_target(selected_contact_id))
	fire_control_actions.add_child(assign_target_button)
	clear_target_button = Button.new()
	clear_target_button.text = "撤销指派"
	clear_target_button.custom_minimum_size.y = 38
	clear_target_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_target_button.pressed.connect(func() -> void: MissionController.clear_fire_control_target())
	fire_control_actions.add_child(clear_target_button)
	aim_mode_button = Button.new()
	aim_mode_button.name = "AimMode"
	aim_mode_button.custom_minimum_size.y = 38
	aim_mode_button.pressed.connect(func() -> void: MissionController.set_fire_control_aim_mode("lead" if MissionController.fire_control_aim_mode == "observed" else "observed"))
	aim_controls = HBoxContainer.new()
	aim_controls.name = "AimControls"
	details.add_child(aim_controls)
	details.move_child(aim_controls, fire_control_actions.get_index() + 1)
	aim_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_controls.add_child(aim_mode_button)
	lock_button = Button.new()
	lock_button.name = "Lock"
	lock_button.custom_minimum_size.y = 38
	lock_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock_button.pressed.connect(func() -> void: MissionController.set_fire_control_lock(not MissionController.fire_control_locked))
	aim_controls.add_child(lock_button)
	correction_controls = HBoxContainer.new()
	correction_controls.name = "CorrectionControls"
	details.add_child(correction_controls)
	details.move_child(correction_controls, aim_controls.get_index() + 1)
	for direction in ["left", "right", "short", "long", "reset"]:
		var button := Button.new()
		button.name = direction
		button.text = {"left":"左 50m", "right":"右 50m", "short":"近 50m", "long":"远 50m", "reset":"归零"}[direction]
		button.custom_minimum_size.y = 32
		button.tooltip_text = "校射：按当前己舰至最后观测目标的方向调整下一发；不改变已发射炮弹或装填。"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(MissionController.adjust_fire_control_correction.bind(direction))
		correction_controls.add_child(button)
	# Keep combat commands visible before the optional full structural preview.
	details.move_child(contact_icon, correction_controls.get_index() + 1)

func _build_unit_library() -> void:
	library_shade = ColorRect.new()
	library_shade.color = Color(0, 0.015, 0.008, 0.88)
	library_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	library_shade.hide()
	terminal.add_child(library_shade)
	unit_library = preload("res://scenes/unit_showcase.tscn").instantiate()
	unit_library.hide()
	terminal.add_child(unit_library)
	unit_library.close_requested.connect(close_unit_library)
	var button := Button.new()
	button.text = "图鉴 / F2"
	button.pressed.connect(toggle_unit_library)
	terminal.get_node("Footer").add_child(button)
	contact_icon = preload("res://scripts/ui/unit_icon.gd").new()
	contact_icon.custom_minimum_size = Vector2(150, 150)
	contact_icon.pixels = 140
	contact_icon.hide()
	details.add_child(contact_icon)
	details.move_child(contact_icon, contact_details.get_index() + 1)

func toggle_unit_library() -> void:
	if archive.visible:
		return
	if unit_library.visible:
		close_unit_library()
		return
	_library_paused_world = not get_tree().paused
	if _library_paused_world:
		GameManager.set_paused(true)
	unit_library.show()
	library_shade.show()
	library_shade.move_to_front()
	unit_library.move_to_front()
	terminal.get_node("GlassOverlay").move_to_front()
	unit_library.family_picker.grab_focus()
	_refresh_ui()

func close_unit_library() -> void:
	unit_library.hide()
	library_shade.hide()
	if _library_paused_world and GameManager.mode not in ["settlement", "campaign_failed"]:
		GameManager.set_paused(false)
	_library_paused_world = false
	_refresh_ui()

func _build_guidance_ui() -> void:
	var strip := VBoxContainer.new()
	strip.name = "ObjectiveStrip"
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_left = 18
	strip.offset_top = 55
	strip.offset_right = -18
	strip.offset_bottom = 116
	strip.add_theme_constant_override("separation", 3)
	terminal.add_child(strip)
	objective_title = Label.new()
	objective_title.add_theme_font_size_override("font_size", 18)
	objective_title.add_theme_color_override("font_color", Color("#d1e7cc"))
	strip.add_child(objective_title)
	objective_hint = Label.new()
	objective_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_hint.add_theme_font_size_override("font_size", 15)
	objective_hint.add_theme_color_override("font_color", Color("#a2c0a9"))
	strip.add_child(objective_hint)
	archive = Control.new()
	archive.name = "CommandArchive"
	archive.set_script(preload("res://scripts/ui/command_archive.gd"))
	terminal.add_child(archive)
	archive.close_requested.connect(close_archive)
	terminal.get_node("Footer/CommandArchive").pressed.connect(toggle_archive)

func _build_sortie_ui() -> void:
	sortie_configuration = VBoxContainer.new()
	sortie_configuration.name = "SortieConfiguration"
	details.add_child(sortie_configuration)
	details.move_child(sortie_configuration, details.get_node("PhaseActions").get_index())
	sortie_details = Label.new()
	sortie_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sortie_details.add_theme_color_override("font_color", Color("#b9d7bc"))
	sortie_configuration.add_child(sortie_details)
	standby_checkbox = CheckBox.new()
	standby_checkbox.text = "飞机升空后母舰停车待命"
	standby_checkbox.toggled.connect(func(enabled: bool) -> void: MissionController.set_sortie_ship_standby(enabled))
	sortie_configuration.add_child(standby_checkbox)
	var flight_requests := HBoxContainer.new()
	flight_requests.add_theme_constant_override("separation", 6)
	flight_controls.add_child(flight_requests)
	standby_button = Button.new()
	standby_button.text = "请求母舰停车"
	standby_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	standby_button.pressed.connect(func() -> void: MissionController.request_ship_standby())
	flight_requests.add_child(standby_button)
	cancel_return_button = Button.new()
	cancel_return_button.text = "取消返航"
	cancel_return_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_return_button.pressed.connect(func() -> void: MissionController.cancel_return())
	flight_requests.add_child(cancel_return_button)

func guidance_state() -> Dictionary:
	var state := {"mode": GameManager.mode, "identified": GameManager.target_identified, "recovered": GameManager.player_recovered, "settled": GameManager.task_settled, "scans": MissionController.contact_scan_count, "contact_visible": MissionController.contact_visible, "launched": MissionController.sorties_launched > 0, "airborne": MissionController.aircraft_airborne, "switch_seconds": MissionController.switch_seconds_remaining, "ship_afloat": GameManager.ship_afloat, "ship_speed": WorldState.ship_speed_knots, "ship_health": MissionController.ship_health, "tracking": MissionController.enemy_tracking_ship, "contact_distance": MissionController.aircraft_position_km.distance_to(WorldState.contact_position_km), "ship_distance": MissionController.aircraft_position_km.distance_to(WorldState.ship_position_km), "airfield_distance": MissionController.aircraft_position_km.distance_to(MissionController.airfield_position_km), "flight_speed": MissionController.aircraft_speed_knots, "fuel_seconds": MissionController.aircraft_fuel_seconds, "destination": MissionController.aircraft_destination, "death_reason": GameManager.last_death_reason}

	state.fire_control_enabled = true
	state.fire_control_assigned = not MissionController.fire_control_target_id.is_empty()
	state.fire_control_reason = MissionController.ship_gun_block_reason()
	state.fire_control_lead = MissionController.fire_control_aim_mode == "lead"
	state.fire_control_motion_ready = MissionController.fire_control_solution().valid
	state.fire_control_locked = MissionController.fire_control_locked
	state.fire_control_lock_status = MissionController.lock_status
	state.fire_control_impact = MissionController.last_gun_impact if MissionController.last_gun_impact.get("order_id", "") == MissionController.fire_control_order_id else {}
	state.enemy_alive = MissionController.enemy_alive
	return state

func _refresh_guidance() -> void:
	guidance = Guidance.project(guidance_state())
	objective_title.text = "当前目标 / " + guidance.title
	objective_hint.text = guidance.next
	if not guidance.warning.is_empty():
		objective_hint.text = guidance.warning + "  " + guidance.next
	if not guidance.fire_control_hint.is_empty():
		objective_hint.text += "\n" + guidance.fire_control_hint
	objective_hint.add_theme_color_override("font_color", Color("#e8b968") if not guidance.warning.is_empty() else Color("#a2c0a9"))

func toggle_archive() -> void:
	if unit_library != null and unit_library.visible:
		return
	if archive.visible:
		close_archive()
		return
	var paused_before := get_tree().paused
	var fire_control_reason_before := MissionController.ship_gun_block_reason()
	_archive_paused_world = not paused_before
	if _archive_paused_world:
		GameManager.set_paused(true)
	_refresh_guidance()
	archive.present(_archive_briefing(), _archive_progress(), _archive_history(), paused_before, GameManager.mode in ["settlement", "campaign_failed"], _archive_fire_control(fire_control_reason_before))
	_refresh_ui()

func close_archive(resume_owned_pause: bool = true) -> void:
	archive.hide()
	if resume_owned_pause and _archive_paused_world and GameManager.mode not in ["settlement", "campaign_failed"]:
		GameManager.set_paused(false)
	_archive_paused_world = false
	terminal.get_node("Footer/CommandArchive").grab_focus()
	_refresh_ui()

func _archive_briefing() -> String:
	var task: TaskDefinition = DataManager.definitions.get(GameManager.current_task_id) as TaskDefinition
	if task == null:
		return "命令数据不可用。关闭档案后可返回主菜单重新开始。"
	var ship: GameDefinition = DataManager.definitions.get(task.ship_id)
	var aircraft: GameDefinition = DataManager.definitions.get(task.aircraft_id)
	return "%s\n%s\n\n%s\n\n目标 / %s\n舰船 / %s\n飞机 / %s\n\n%s" % [task.command_source, task.display_name, task.briefing, task.objective, ship.display_name if ship != null else "资料缺失", aircraft.display_name if aircraft != null else "资料缺失", task.operational_notes]

func _archive_progress() -> String:
	var lines: PackedStringArray = ["当前阶段 / " + guidance.title, guidance.next, ""]
	var names := ["取得雷达观测", "确认指定接触", "飞机实际升空", "指挥官安全回收", "提交任务报告"]
	for index in range(names.size()):
		lines.append("%s  %s" % ["[已完成]" if guidance.milestones[index] else "[待完成]", names[index]])
	lines.append("\n舰体 %.0f%% · 甲板炮余弹 %d · 出击 %d 次\n回收地点 / %s\n模拟耗时 / %s · 海域种子 / %d" % [MissionController.ship_health, MissionController.ship_ammo, MissionController.sorties_launched, {"ship": "母舰", "friendly_airfield": "友方机场", "rescue": "救援"}.get(GameManager.recovery_site, "尚未回收"), WorldClock.formatted_time(), WorldState.scenario_seed])
	if not guidance.warning.is_empty():
		lines.append("\n" + guidance.warning)
	if MissionController.aircraft_airborne:
		lines.append("直线回收估算 %.1f 分，燃油剩余 %.1f 分；估算不包含移动回收点与后续操纵。" % [guidance.return_seconds / 60.0, MissionController.aircraft_fuel_seconds / 60.0])
	return "\n".join(lines)

func _archive_history() -> String:
	var lines: PackedStringArray = []
	for event in EventBus.history:
		if event.get("kind", "") == "contact_updated":
			continue
		var seconds := int(event.get("simulation_seconds", 0.0))
		lines.append("T+%02d:%02d  %s" % [floori(float(seconds) / 60.0), seconds % 60, _event_line(event)])
		if lines.size() > 40:
			lines.remove_at(0)
	return "行动记录 / 最近 40 条（重复复测省略）\n\n" + ("尚无记录。" if lines.is_empty() else "\n".join(lines))

func _archive_fire_control(reason_before_open: String) -> String:
	var solution := MissionController.fire_control_solution()
	var lines: PackedStringArray = ["甲板炮 / " + ("未指派" if MissionController.fire_control_target_id.is_empty() else "A1 · " + MissionController.fire_control_order_id), "打开档案前 / " + ("可手动射击" if reason_before_open.is_empty() else reason_before_open), "阅读期间不能射击；关闭后重新验证条件。交战不是本关胜利条件。", ""]
	lines.insert(2, "瞄准 / " + ("运动提前量" if MissionController.fire_control_aim_mode == "lead" else "最后观测"))
	lines.insert(3, _motion_description(solution))
	lines.insert(4, "照射 / " + MissionController.lock_status)
	var entries: PackedStringArray = []
	for event in EventBus.history:
		var kind: String = event.get("kind", "")
		if kind.begins_with("fire_control_") or kind.begins_with("gun_projectile_") or kind == "ship_gun_rejected" or (kind == "weapon_fired" and event.details.get("weapon_id", "") == "weapon.deck_gun"):
			var seconds := floori(float(event.get("simulation_seconds", 0)))
			entries.append("T+%02d:%02d · %s" % [floori(float(seconds) / 60.0), seconds % 60, _event_line(event)])
			if kind == "weapon_fired" and event.details.get("aim_mode", "") == "lead":
				var aim: Vector2 = event.details.get("aim_position_km", Vector2.ZERO)
				entries[entries.size() - 1] += "\n  解算快照 / %s · 瞄准 (%.3f, %.3f) km" % [_motion_description(event.details.get("solution", {})), aim.x, aim.y]
	for index in range(maxi(0, entries.size() - 40), entries.size()): lines.append(entries[index])
	return "\n".join(lines)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		toggle_unit_library()
		get_viewport().set_input_as_handled()
		return
	if unit_library != null and unit_library.visible:
		if event.is_action_pressed("ui_cancel"):
			close_unit_library()
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_simulation"):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		toggle_archive()
		get_viewport().set_input_as_handled()
	elif archive != null and archive.visible and (event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		archive.cycle_focus(event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"))
		get_viewport().set_input_as_handled()
	elif archive != null and archive.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_simulation")):
		if event.is_action_pressed("ui_cancel"):
			close_archive()
		get_viewport().set_input_as_handled()

func _connect_buttons() -> void:
	_button("RadarActions/NextSweep").pressed.connect(_on_scan_pressed)
	_button("RadarActions/ToggleEmission").pressed.connect(func() -> void: MissionController.set_radar_emitting(not MissionController.radar_emitting))
	_button("RadarActions/Identify").pressed.connect(func() -> void: MissionController.identify_contact())
	_button("RadarActions/Fire").pressed.connect(func() -> void: MissionController.fire_ship_gun())
	_button("ShipControls/HeadingControls/TurnPort").pressed.connect(func() -> void: MissionController.command_ship(WorldState.ship_heading_degrees - 15.0, WorldState.ship_speed_knots))
	_button("ShipControls/HeadingControls/TurnStarboard").pressed.connect(func() -> void: MissionController.command_ship(WorldState.ship_heading_degrees + 15.0, WorldState.ship_speed_knots))
	_button("ShipControls/SpeedControls/SlowDown").pressed.connect(func() -> void: MissionController.command_ship(WorldState.ship_heading_degrees, maxf(0.0, WorldState.ship_speed_knots - 5.0)))
	_button("ShipControls/SpeedControls/SpeedUp").pressed.connect(func() -> void: MissionController.command_ship(WorldState.ship_heading_degrees, minf(WorldState.ship_max_speed_knots, WorldState.ship_speed_knots + 5.0)))
	_button("ShipControls/DamageControl/Repair").pressed.connect(func() -> void: MissionController.start_damage_control())
	_button("FlightControls/FlightHeadingControls/FlightPort").pressed.connect(func() -> void: MissionController.set_aircraft_heading(MissionController.aircraft_heading_degrees - 15.0))
	_button("FlightControls/FlightHeadingControls/FlightStarboard").pressed.connect(func() -> void: MissionController.set_aircraft_heading(MissionController.aircraft_heading_degrees + 15.0))
	_button("FlightControls/FlightNavControls/NavContact").pressed.connect(func() -> void: MissionController.set_aircraft_destination("contact"))
	_button("FlightControls/FlightNavControls/NavShip").pressed.connect(func() -> void: MissionController.set_aircraft_destination("ship"))
	_button("FlightControls/FlightNavControls/NavAirfield").pressed.connect(func() -> void: MissionController.set_aircraft_destination("airfield"))
	_button("FlightControls/FlightActions/Recon").pressed.connect(func() -> void: MissionController.perform_recon())
	_button("FlightControls/FlightActions/Attack").pressed.connect(func() -> void: MissionController.aircraft_attack())
	_button("PhaseActions/Prepare").pressed.connect(func() -> void: MissionController.prepare_sortie())
	_button("PhaseActions/Launch").pressed.connect(func() -> void: MissionController.launch_sortie())
	_button("PhaseActions/Cancel").pressed.connect(func() -> void: MissionController.cancel_sortie())
	_button("PhaseActions/Return").pressed.connect(func() -> void: MissionController.begin_return())
	_button("PhaseActions/Land").pressed.connect(func() -> void: MissionController.land_aircraft())
	_button("PhaseActions/Settle").pressed.connect(func() -> void: MissionController.complete_mission())
	_button("PhaseActions/Restart").pressed.connect(_on_restart_pressed)
	_button("PhaseActions/MainMenu").pressed.connect(func() -> void: menu_requested.emit())
	pause_status.pressed.connect(_toggle_pause)
	time_scale_button.pressed.connect(_toggle_time_scale)
	radar_range_button.pressed.connect(_toggle_radar_range)

func _toggle_radar_range() -> void:
	radar.set_display_range(12.5 if radar.display_range_km == 25.0 else 25.0)
	_refresh_ui()

func _button(path: String) -> Button:
	return details.get_node(path) as Button

func _apply_theme() -> void:
	var ui_theme := Theme.new()
	var terminal_font := SystemFont.new()
	terminal_font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Microsoft YaHei"])
	ui_theme.default_font = terminal_font
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Button", Color("#c3d9c3"))
	ui_theme.set_color("font_hover_color", "Button", Color("#eff9e8"))
	ui_theme.set_color("font_pressed_color", "Button", Color("#07140e"))
	ui_theme.set_color("font_disabled_color", "Button", Color("#6f8474"))
	ui_theme.set_font_size("font_size", "Button", 17)
	ui_theme.set_stylebox("normal", "Button", _button_style(Color("#152720"), Color("#4a6e58")))
	ui_theme.set_stylebox("hover", "Button", _button_style(Color("#28513a"), Color("#a5efb2")))
	ui_theme.set_stylebox("pressed", "Button", _button_style(Color("#8be6a3"), Color("#8be6a3")))
	ui_theme.set_stylebox("disabled", "Button", _button_style(Color("#142119"), Color("#354c3b")))
	ui_theme.set_stylebox("scroll", "VScrollBar", _scroll_style(Color("#15231b")))
	ui_theme.set_stylebox("grabber", "VScrollBar", _scroll_style(Color("#526d58")))
	ui_theme.set_stylebox("grabber_highlight", "VScrollBar", _scroll_style(Color("#8ad59c")))
	ui_theme.set_stylebox("grabber_pressed", "VScrollBar", _scroll_style(Color("#a5efb2")))
	var focus := _button_style(Color.TRANSPARENT, Color("#edc37e"))
	focus.draw_center = false
	ui_theme.set_stylebox("focus", "Button", focus)
	terminal.theme = ui_theme
	for path in ["RadarActions/Fire", "FlightControls/FlightActions/Attack", "PhaseActions/Launch"]:
		var action := _button(path)
		action.add_theme_stylebox_override("normal", _button_style(Color("#382723"), Color("#a66b57")))
		action.add_theme_stylebox_override("hover", _button_style(Color("#694036"), Color("#edb081")))
		action.add_theme_color_override("font_color", Color("#f2d0ac"))
	for path in ["PhaseActions/Prepare", "PhaseActions/Return", "PhaseActions/Settle"]:
		var action := _button(path)
		action.add_theme_stylebox_override("normal", _button_style(Color("#3b3423"), Color("#9b8658")))
		action.add_theme_color_override("font_color", Color("#e5d6ac"))

func _scroll_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(2)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	return style

func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style

func _unhandled_input(event: InputEvent) -> void:
	if unit_library.visible:
		return
	if archive != null and archive.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		radar.clear_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_simulation"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if archive.visible or unit_library.visible or GameManager.mode in ["settlement", "campaign_failed"]:
		return
	GameManager.set_paused(not get_tree().paused)
	_refresh_ui()

func _toggle_time_scale() -> void:
	if archive.visible or unit_library.visible or GameManager.mode in ["settlement", "campaign_failed"]:
		return
	WorldClock.set_time_scale(10.0 if WorldClock.time_scale == 1.0 else 1.0)
	_refresh_ui()

func _on_world_time_advanced(total_seconds: float) -> void:
	var second := floori(total_seconds)
	if second != _displayed_second:
		_displayed_second = second
		time_status.text = WorldClock.formatted_time()
	if total_seconds >= _next_auto_scan_seconds:
		_next_auto_scan_seconds = total_seconds + 30.0
		if MissionController.radar_emitting and GameManager.mode != "settlement" and GameManager.mode != "campaign_failed":
			MissionController.scan()

func _on_scan_pressed() -> void:
	if not get_tree().paused:
		MissionController.scan()
		_next_auto_scan_seconds = WorldClock.elapsed_seconds + 30.0

func _on_restart_pressed() -> void:
	if archive.visible:
		close_archive(false)
	selected_contact_id = ""
	radar.clear_selection()
	MissionController.restart_scenario()
	_next_auto_scan_seconds = 30.0
	_on_event_recorded({})
	_refresh_ui()

func _on_contact_selected(id: String) -> void:
	selected_contact_id = id
	_refresh_ui()

func _on_contact_deselected() -> void:
	selected_contact_id = ""
	_refresh_ui()

func _on_ship_command_changed(_heading: float, _speed: float) -> void:
	navigation_status.text = "暂停中 · 航行命令将在继续后执行" if get_tree().paused else "航行命令已生效"
	_refresh_ui()

func _on_navigation_blocked(_position: Vector2) -> void:
	navigation_status.text = "航路受阻，舰艇已停车 · 请调整航向"
	_refresh_ui()

func _on_feedback_changed(message: String) -> void:
	action_status.text = message

func _refresh_ui() -> void:
	if not is_node_ready():
		return
	var mode: String = GameManager.mode
	var mode_labels := {
		"bridge": "CIC / 舰桥",
		"configuration": "FLIGHT DECK / 出击配置",
		"switching": "TRANSFER / 指挥权移交",
		"cockpit": "COCKPIT / 座舱",
		"returning": "RETURN / 返航",
		"recovered": "RECOVERED / 安全回收",
		"settlement": "AFTER ACTION / 任务结算",
		"campaign_failed": "SIGNAL LOST / 战役失败",
	}
	mode_status.text = mode_labels.get(mode, mode)
	_refresh_guidance()
	mission_status.text = "任务 01  /  确认 A1 · 指挥官安全返航"
	if mode == "settlement":
		mission_status.text = "任务完成  /  情报确认 · 指挥官安全回收"
	elif mode == "campaign_failed":
		mission_status.text = "战役结束  /  指挥官失联"
	elif mode == "switching":
		mission_status.text = "指挥权移交 / 剩余 %.1f 秒" % MissionController.switch_seconds_remaining
	_refresh_contact()
	_refresh_ship()
	_refresh_flight()
	_refresh_debrief()
	_refresh_radar()
	_refresh_gun_status()
	_refresh_sortie_configuration()
	ship_controls.visible = mode == "bridge" or mode == "configuration" or mode == "switching"
	contact_status.visible = mode == "bridge"
	contact_details.visible = contact_status.visible
	flight_controls.visible = mode == "cockpit" or mode == "returning"
	debrief.visible = mode == "settlement" or mode == "campaign_failed"
	details.get_node("RadarActions").visible = mode == "bridge"
	selection_details.visible = mode == "bridge"
	gun_status.visible = mode == "bridge"
	_button("PhaseActions/Prepare").visible = mode == "bridge" and not GameManager.player_recovered
	_button("PhaseActions/Launch").visible = mode == "configuration"
	_button("PhaseActions/Cancel").visible = mode == "configuration" or mode == "switching"
	_button("PhaseActions/Return").visible = mode == "cockpit"
	_button("PhaseActions/Land").visible = mode == "returning"
	_button("PhaseActions/Settle").visible = (mode == "bridge" or mode == "recovered") and GameManager.player_recovered
	var incomplete_recovery := mode == "recovered" and not GameManager.target_identified
	_button("PhaseActions/Restart").visible = mode == "settlement" or mode == "campaign_failed" or incomplete_recovery
	_button("PhaseActions/MainMenu").visible = mode == "settlement" or mode == "campaign_failed" or incomplete_recovery
	_button("RadarActions/NextSweep").disabled = get_tree().paused
	_button("RadarActions/ToggleEmission").disabled = get_tree().paused
	_button("RadarActions/ToggleEmission").text = "雷达静默" if MissionController.radar_emitting else "开启雷达"
	_button("RadarActions/Identify").disabled = get_tree().paused
	_button("RadarActions/Fire").disabled = get_tree().paused
	for path in ["PhaseActions/Prepare", "PhaseActions/Launch", "PhaseActions/Cancel", "PhaseActions/Return", "PhaseActions/Land", "FlightControls/FlightActions/Recon", "FlightControls/FlightActions/Attack"]:
		_button(path).disabled = get_tree().paused
	_button("PhaseActions/Settle").disabled = get_tree().paused or not GameManager.target_identified
	_button("PhaseActions/Land").disabled = get_tree().paused or not guidance.can_land
	cancel_return_button.disabled = get_tree().paused
	cancel_return_button.visible = mode == "returning"
	standby_button.disabled = not GameManager.ship_afloat or WorldState.ship_speed_knots == 0.0
	pause_status.text = "已暂停 · 点击继续" if get_tree().paused else "运行中 · 空格暂停"
	time_scale_button.text = "时间 ×%.0f" % WorldClock.time_scale
	radar_range_button.text = "量程 %.1f km" % radar.display_range_km
	action_status.text = MissionController.last_message

func _refresh_sortie_configuration() -> void:
	sortie_configuration.visible = GameManager.mode == "configuration" or GameManager.mode == "switching"
	standby_checkbox.disabled = GameManager.mode != "configuration"
	standby_checkbox.set_pressed_no_signal(MissionController.sortie_ship_standby)
	var task: TaskDefinition = DataManager.definitions.get(GameManager.current_task_id) as TaskDefinition
	var aircraft: AircraftDefinition = DataManager.definitions.get(task.aircraft_id) as AircraftDefinition if task != null else null
	if aircraft == null:
		sortie_details.text = "出击数据不可用；取消配置后检查任务数据。"
		return
	sortie_details.text = "出击配置 / %s\n巡航 %.0f kn · 余油 %.1f 分 · 对海弹 %d\n母舰托管 / %s\n移交期间世界继续运行，停车不免疫敌方攻击。" % [aircraft.display_name, MissionController.aircraft_speed_knots, MissionController.aircraft_fuel_seconds / 60.0, MissionController.aircraft_bombs, "实际升空后停车待命" if MissionController.sortie_ship_standby else "保持当前 %03.0f° / %.0f kn" % [WorldState.ship_heading_degrees, WorldState.ship_speed_knots]]

func _refresh_gun_status() -> void:
	var reason := MissionController.ship_gun_block_reason()
	fire_control_actions.visible = GameManager.mode == "bridge"
	aim_mode_button.visible = fire_control_actions.visible
	aim_controls.visible = fire_control_actions.visible
	lock_button.text = "解除照射" if MissionController.fire_control_locked else "锁定照射"
	lock_button.disabled = not MissionController.fire_control_lock_reason().is_empty() and not MissionController.fire_control_locked
	lock_button.tooltip_text = MissionController.lock_status + "\n每 8 秒内复测；炮塔 20°/秒跟踪，不自动射击。"
	correction_controls.visible = fire_control_actions.visible
	for button in correction_controls.get_children():
		button.disabled = MissionController.fire_control_target_id.is_empty() or not GameManager.ship_afloat or not GameManager.player_alive
	aim_mode_button.disabled = not GameManager.ship_afloat or not GameManager.player_alive
	aim_mode_button.text = "瞄准：运动提前量 ↔" if MissionController.fire_control_aim_mode == "lead" else "瞄准：最后观测 ↔"
	var solution := MissionController.fire_control_solution()
	aim_mode_button.tooltip_text = _motion_description(solution) + "\n切换不射击、不重置装填；提前量不足时可切回最后观测。"
	var assignment_reason := MissionController.fire_control_assignment_reason(selected_contact_id)
	assign_target_button.disabled = not assignment_reason.is_empty() or not MissionController.fire_control_target_id.is_empty()
	assign_target_button.tooltip_text = assignment_reason if not assignment_reason.is_empty() else "仅建立目标指派；暂停时可排队，不会自动射击"
	clear_target_button.disabled = MissionController.fire_control_target_id.is_empty() or GameManager.mode != "bridge"
	var weapon: WeaponDefinition = DataManager.get_definition("weapon.deck_gun") as WeaponDefinition
	var weapon_range := weapon.range_km if weapon != null else 0.0
	gun_status.text = "火控 / %s" % ("可开火 · %.0f km / 前向 ±%.0f°" % [weapon_range, MissionController.GUN_HALF_ARC_DEGREES] if reason.is_empty() else reason)
	gun_status.text = ("甲板炮 → A1 / " + MissionController.fire_control_order_id if not MissionController.fire_control_target_id.is_empty() else "甲板炮 / 未指派") + "\n" + gun_status.text
	gun_status.text += "\n" + (MissionController.lock_status + " · " if MissionController.fire_control_locked or MissionController.lock_status.begins_with("失锁") else "") + _motion_description(solution)
	gun_status.text += "\n修正 %.0f m · %s" % [MissionController.fire_control_correction_km.length() * 1000, "炮弹飞行中 / %.1f 秒" % maxf(0, MissionController.projectiles[0].impact_seconds - WorldClock.elapsed_seconds) if not MissionController.projectiles.is_empty() else _impact_description(MissionController.last_gun_impact)]
	gun_status.add_theme_color_override("font_color", Color("#83e8aa") if reason.is_empty() else Color("#e8b968"))
	_button("RadarActions/Fire").tooltip_text = "甲板炮 %.0f km / 舰艏两侧各 %.0f°\n%s" % [weapon_range, MissionController.GUN_HALF_ARC_DEGREES, "可开火" if reason.is_empty() else reason]
	radar.set_gun_solution(GameManager.mode == "bridge", reason.is_empty(), weapon_range)
	radar.fire_control_assigned = not MissionController.fire_control_target_id.is_empty()
	var prediction := solution.duplicate(true)
	if prediction.valid: prediction.aim_position_km += MissionController.fire_control_correction_km
	radar.set_fire_control_prediction(prediction if radar.fire_control_assigned and GameManager.mode == "bridge" else {})
	radar.set_gun_ballistics(MissionController.projectiles if GameManager.mode == "bridge" else [], MissionController.last_gun_impact if GameManager.mode == "bridge" else {})

func _impact_description(impact: Dictionary) -> String:
	if impact.is_empty(): return "尚无弹着"
	if not impact.get("observed", false): return "弹着结果未观测"
	var error: Vector2 = impact.get("error_km", Vector2.ZERO)
	return "%s / %.0f m · E %.0f / N %.0f" % [{"hit":"命中", "near_miss":"近失弹", "miss":"未命中"}.get(impact.get("result", ""), "弹着"), impact.get("error_meters", 0), error.x * 1000, -error.y * 1000]

func _motion_description(solution: Dictionary) -> String:
	if not solution.get("valid", false):
		return str(solution.get("reason", "运动解算不可用"))
	return "运动 %.1f kn · %s / %.0f 秒 · 提前 %.1f 秒" % [solution.speed_knots, solution.confidence, solution.age_seconds, solution.flight_seconds]

func _refresh_contact() -> void:
	contact_icon.visible = GameManager.target_identified and selected_contact_id == MissionController.CONTACT_ID
	if contact_icon.visible:
		var contact: ContactDefinition = DataManager.get_definition(MissionController.CONTACT_ID) as ContactDefinition
		var ship: ShipDefinition = DataManager.get_definition(contact.identified_ship_id) as ShipDefinition if contact != null else null
		if ship != null:
			contact_icon.family = ship.visual_family_id
			contact_icon.size_class = ship.size_class
			contact_icon.variant = ship.shape_variant
			contact_icon.queue_redraw()
	if not MissionController.enemy_alive:
		contact_status.text = "A1 / 目标失能"
	elif not MissionController.radar_emitting:
		contact_status.text = "A1 / 静默 · 敌方追踪中" if MissionController.enemy_tracking_ship else "A1 / 雷达静默"
	elif MissionController.contact_visible:
		contact_status.text = "A1 / 已确认" if GameManager.target_identified else "A1 / 未知回波"
	else:
		contact_status.text = "A1 / 信号丢失"
	if MissionController.radar_emitting and MissionController.enemy_tracking_ship:
		contact_status.text += " · 已暴露"
	if MissionController.contact_scan_count == 0:
		contact_details.text = "等待首轮扫描"
	else:
		var seen := floori(MissionController.last_contact_seconds)
		if GameManager.mode == "cockpit" or GameManager.mode == "returning":
			contact_details.text = "方位 %03d°   距离 %.1f km   /   %s" % [roundi(MissionController.last_contact_bearing_degrees), MissionController.last_contact_range_km, "已确认" if GameManager.target_identified else "待确认"]
		else:
			contact_details.text = "方位 %03d°   距离 %.1f km\n观测 T+%02d:%02d   /   %s" % [roundi(MissionController.last_contact_bearing_degrees), MissionController.last_contact_range_km, floori(float(seen) / 60.0), seen % 60, "稳定" if MissionController.contact_visible else "中断"]
	selection_details.text = "雷达静默 · 开机后可复测接触" if not MissionController.radar_emitting else ("已选择 A1 · 确认身份后可指派甲板炮目标" if selected_contact_id == MissionController.CONTACT_ID else "未选择接触 · 点击雷达回波")

func _refresh_ship() -> void:
	ship_details.text = "航向 %03d°   航速 %.0f / %.0f kn   舰体 %.0f%%\n位置 E %05.1f / S %05.1f km   弹药 %d" % [roundi(WorldState.ship_heading_degrees), WorldState.ship_speed_knots, WorldState.ship_max_speed_knots, MissionController.ship_health, WorldState.ship_position_km.x, WorldState.ship_position_km.y, MissionController.ship_ammo]
	radar.set_ship_heading(WorldState.ship_heading_degrees)
	var repairing := MissionController.repair_seconds_remaining > 0.0
	ship_controls.get_node("DamageControl").visible = MissionController.ship_health < 100.0 or repairing
	ship_controls.get_node("DamageControl/Status").text = "损管 / %.0f 秒 · 余 %d 组" % [ceilf(MissionController.repair_seconds_remaining), MissionController.repair_teams] if repairing else "损管 / 余 %d 组待命" % MissionController.repair_teams
	if not repairing and MissionController.repair_teams == 0:
		ship_controls.get_node("DamageControl/Status").text = "损管 / 本关资源已耗尽"
	_button("ShipControls/DamageControl/Repair").disabled = repairing or MissionController.repair_teams == 0 or get_tree().paused or GameManager.mode != "bridge"

func _refresh_flight() -> void:
	var contact_distance := MissionController.aircraft_position_km.distance_to(WorldState.contact_position_km)
	var ship_distance := MissionController.aircraft_position_km.distance_to(WorldState.ship_position_km)
	var airfield_distance := MissionController.aircraft_position_km.distance_to(MissionController.airfield_position_km)
	var destination_names := {"manual": "手动", "contact": "A1", "ship": "母舰", "airfield": "机场", "waypoint": "航点"}
	flight_details.text = "位置 E %05.1f / S %05.1f km   航向 %03d°\n燃油 %.0f 分   对海弹 %d   导航 %s\nA1 %.1f km  母舰 %.1f km  机场 %.1f km" % [MissionController.aircraft_position_km.x, MissionController.aircraft_position_km.y, roundi(MissionController.aircraft_heading_degrees), MissionController.aircraft_fuel_seconds / 60.0, MissionController.aircraft_bombs, destination_names.get(MissionController.aircraft_destination, "未知"), contact_distance, ship_distance, airfield_distance]
	_button("FlightControls/FlightNavControls/NavShip").disabled = not GameManager.ship_afloat
	_button("FlightControls/FlightNavControls/NavContact").disabled = not MissionController.enemy_alive
	var solution := MissionController.navigation_solution()
	if solution.available:
		flight_details.text += "\n%s %.1f 分 · 余油 %+.1f 分" % ["入窗估算" if MissionController.aircraft_destination in ["ship", "airfield"] else "抵达估算", float(solution.eta_seconds) / 60.0, float(solution.fuel_margin_seconds) / 60.0]
		flight_details.add_theme_color_override("font_color", Color("#e8b968") if not solution.reachable else Color("#a2c0a9"))
	else:
		flight_details.add_theme_color_override("font_color", Color("#a2c0a9"))
	flight_details.text += "\n母舰 %.0f%% · 损管 %s" % [MissionController.ship_health, "剩余 %.0f 秒" % ceilf(MissionController.repair_seconds_remaining) if MissionController.repair_seconds_remaining > 0.0 else "待命 %d 组" % MissionController.repair_teams]
	flight_details.text += "\n右键设航点；雷达聚焦后方向键 / Enter"

func _refresh_debrief() -> void:
	var outcome := "任务完成" if GameManager.mode == "settlement" else "战役失败"
	var recovery := "母舰" if GameManager.recovery_site == "ship" else ("友方机场" if GameManager.recovery_site == "friendly_airfield" else "未回收")
	debrief_details.text = "结果 ........ %s\n任务目标 .... %s\n指挥官 ...... %s\n母舰舰体 .... %.0f%%\n敌舰舰体 .... %.0f%%\n甲板炮余弹 .. %d\n模拟耗时 .... %s" % [outcome, "已确认" if GameManager.target_identified else "未确认", recovery, MissionController.ship_health, MissionController.enemy_health, MissionController.ship_ammo, WorldClock.formatted_time()]

func _refresh_radar() -> void:
	if WorldState.map == null:
		return
	var flying: bool = MissionController.aircraft_airborne and GameManager.mode in ["cockpit", "returning"]
	var origin: Vector2 = MissionController.aircraft_position_km if flying else WorldState.ship_position_km
	radar.set_land_areas(WorldState.map.islands, origin)
	radar.set_ship_heading(MissionController.aircraft_heading_degrees if flying else WorldState.ship_heading_degrees)
	radar.set_sweep_enabled(MissionController.radar_emitting and not flying)
	radar.set_integrity(MissionController.ship_health)
	radar.set_aircraft(MissionController.aircraft_position_km, MissionController.aircraft_airborne)
	radar.set_flight_navigation(flying, WorldState.ship_position_km, GameManager.ship_afloat, MissionController.airfield_position_km, MissionController.navigation_solution())
	var relative := MissionController.last_contact_position_km - origin
	var bearing := fposmod(rad_to_deg(atan2(relative.x, -relative.y)), 360.0)
	radar.set_contact(MissionController.CONTACT_ID, bearing, relative.length(), MissionController.contact_visible and MissionController.enemy_alive, GameManager.target_identified)

func _on_event_recorded(_event: Dictionary) -> void:
	var lines: PackedStringArray = []
	for index in range(maxi(0, EventBus.history.size() - 3), EventBus.history.size()):
		lines.append("• " + _event_line(EventBus.history[index]))
	event_details.text = "通信日志 / RADIO LOG\n" + "\n".join(lines)

func _event_line(event: Dictionary) -> String:
	var details_data: Dictionary = event.get("details", {})
	match event.get("kind", ""):
		"fire_control_locked": return "锁定照射 / " + str(details_data.get("order_id", ""))
		"fire_control_lock_lost": return "照射终止 / %s · %s" % [details_data.get("order_id", ""), details_data.get("reason", "")]
		"gun_projectile_impact": return "甲板炮弹着 / %s · %s · %s" % [details_data.get("shot_id", ""), details_data.get("order_id", ""), _impact_description(details_data)]
		"gun_projectile_cancelled": return "炮弹清理 / %s · %s" % [details_data.get("shot_id", ""), details_data.get("reason", "行动结束")]
		"fire_control_correction": return "校射修正 / %s · %.0f m" % [details_data.get("order_id", ""), (details_data.get("correction_km", Vector2.ZERO) as Vector2).length() * 1000]
		"fire_control_aim_mode_changed": return "甲板炮瞄准 / %s · %s" % ["运动提前量" if details_data.get("aim_mode", "observed") == "lead" else "最后观测", details_data.get("order_id", "未指派")]
		"fire_control_assigned": return "甲板炮指派 A1 / %s%s" % [details_data.get("order_id", ""), " · 暂停排队" if details_data.get("queued", false) else ""]
		"fire_control_cleared": return "甲板炮撤销 A1 / %s · %s" % [details_data.get("order_id", ""), {"player_cancelled":"玩家撤销", "target_destroyed":"目标失能", "ship_sunk":"母舰沉没", "action_ended":"行动结束"}.get(details_data.get("reason", ""), "指派终止")]
		"fire_control_rejected": return {"clear":"火控撤销拒绝 / ", "aim_mode":"瞄准切换拒绝 / ", "correction":"校射修正拒绝 / "}.get(details_data.get("action", ""), "火控指派拒绝 / ") + str(details_data.get("order_id", "")) + " · " + str(details_data.get("reason", ""))
		"ship_gun_rejected": return "甲板炮射击拒绝 / %s · %s" % [details_data.get("order_id", "未指派"), details_data.get("reason", "")]
		"contact_discovered": return "A1 回波发现"
		"contact_updated": return "A1 方位复测"
		"contact_lost": return "A1 信号丢失"
		"radar_emission_changed": return "舰载雷达开启" if details_data.get("emitting", false) else "舰载雷达静默"
		"enemy_tracking": return "敌方截获舰载雷达" if details_data.get("source", "") == "radar" else "敌舰发现母舰"
		"enemy_tracking_lost": return "敌舰失去追踪"
		"target_identified", "aircraft_recon": return "A1 情报确认"
		"ship_navigation_command": return "航行命令 %03d° / %.0f kn" % [roundi(details_data.get("heading_degrees", 0.0)), details_data.get("speed_knots", 0.0)]
		"ship_navigation_blocked": return "航路受阻，舰艇停车"
		"weapon_fired": return "飞机对海投弹" if details_data.get("weapon_id", "") == "aircraft.bomb" else "甲板炮射击 A1 / %s · %s · 余弹 %d" % [details_data.get("order_id", ""), "运动提前量" if details_data.get("aim_mode", "observed") == "lead" else "最后观测", details_data.get("ammo_remaining", 0)]
		"aircraft_attack": return "飞机对海攻击 A1"
		"enemy_damaged": return "战斗结果尚未观测" if details_data.get("source", "") == "deck_gun_unobserved" else "A1 受损 %.0f%%" % (100.0 - details_data.get("health", 100.0))
		"ship_damaged": return "母舰受损 · 舰体 %.0f%%" % details_data.get("health", 0.0)
		"damage_control_started": return "损管队投入 · 甲板炮停用 30 秒"
		"damage_control_completed": return "损管完成 · 舰体 %.0f%%" % details_data.get("health", 0.0)
		"damage_control_aborted": return "母舰沉没，损管终止"
		"aircraft_launched": return "隼影侦察机升空"
		"sortie_configured": return "出击托管：停车待命" if details_data.get("ship_standby", false) else "出击托管：保持航行"
		"ship_standby_requested": return "母舰收到空中待命请求"
		"return_cancelled": return "返航取消，恢复飞行控制"
		"aircraft_navigation_command": return "飞机导航 / " + {"manual": "手动航向", "contact": "A1", "ship": "母舰", "airfield": "机场", "waypoint": "指定航点"}.get(details_data.get("destination", ""), "未知")
		"aircraft_navigation_arrived": return "飞机已抵达导航点，仍消耗燃油"
		"aircraft_navigation_diverted": return "母舰沉没，导航改向机场"
		"aircraft_fuel_warning": return "飞机燃油预警 / 余 %.0f 秒" % details_data.get("seconds_remaining", 0.0)
		"aircraft_landed": return "飞机安全回收"
		"enemy_destroyed": return "A1 失去战斗力"
		"player_death": return "指挥官失联"
		"command_accepted": return "指令部命令已接收"
		"scenario_generated": return "海域生成 · 种子 %d" % details_data.get("seed", 0)
		"harbor_departure": return "驶过港口离港线，行动开始"
		"task_settled": return "任务结算完成"
		"mode_changed": return "指挥模式切换"
		"simulation_pause_changed": return "模拟暂停" if details_data.get("paused", false) else "模拟继续"
		"scenario_started": return "首关任务开始"
		_ : return str(event.get("kind", ""))
