extends Control

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
var _next_auto_scan_seconds: float = 30.0
var _displayed_second: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_connect_buttons()
	radar.contact_selected.connect(_on_contact_selected)
	radar.contact_deselected.connect(_on_contact_deselected)
	MissionController.state_changed.connect(_refresh_ui)
	MissionController.feedback_changed.connect(_on_feedback_changed)
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	WorldState.ship_command_changed.connect(_on_ship_command_changed)
	WorldState.navigation_blocked.connect(_on_navigation_blocked)
	EventBus.event_recorded.connect(_on_event_recorded)
	if not DataManager.errors.is_empty() or WorldState.map == null:
		contact_status.text = "系统故障 / DATA ERROR"
		action_status.text = "请检查 Godot 输出中的数据加载错误"
		return
	_next_auto_scan_seconds = WorldClock.elapsed_seconds + 30.0
	MissionController.scan()
	_refresh_ui()
	_on_world_time_advanced(WorldClock.elapsed_seconds)

func _connect_buttons() -> void:
	_button("RadarActions/NextSweep").pressed.connect(_on_scan_pressed)
	_button("RadarActions/ToggleEmission").pressed.connect(func() -> void: MissionController.set_radar_emitting(not MissionController.radar_emitting))
	_button("RadarActions/Identify").pressed.connect(func() -> void: MissionController.identify_contact())
	_button("RadarActions/Fire").pressed.connect(func() -> void: MissionController.fire_ship_gun(selected_contact_id))
	_button("ShipControls/HeadingControls/TurnPort").pressed.connect(func() -> void: WorldState.set_ship_command(WorldState.ship_heading_degrees - 15.0, WorldState.ship_speed_knots))
	_button("ShipControls/HeadingControls/TurnStarboard").pressed.connect(func() -> void: WorldState.set_ship_command(WorldState.ship_heading_degrees + 15.0, WorldState.ship_speed_knots))
	_button("ShipControls/SpeedControls/SlowDown").pressed.connect(func() -> void: WorldState.set_ship_command(WorldState.ship_heading_degrees, maxf(0.0, WorldState.ship_speed_knots - 5.0)))
	_button("ShipControls/SpeedControls/SpeedUp").pressed.connect(func() -> void: WorldState.set_ship_command(WorldState.ship_heading_degrees, minf(WorldState.ship_max_speed_knots, WorldState.ship_speed_knots + 5.0)))
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
	if event.is_action_pressed("ui_cancel"):
		radar.clear_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_simulation"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	GameManager.set_paused(not get_tree().paused)
	_refresh_ui()

func _toggle_time_scale() -> void:
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
	ship_controls.visible = mode == "bridge" or mode == "configuration" or mode == "switching"
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
	_button("PhaseActions/Restart").visible = mode == "settlement" or mode == "campaign_failed"
	_button("RadarActions/NextSweep").disabled = get_tree().paused
	_button("RadarActions/ToggleEmission").disabled = get_tree().paused
	_button("RadarActions/ToggleEmission").text = "雷达静默" if MissionController.radar_emitting else "开启雷达"
	_button("RadarActions/Identify").disabled = get_tree().paused
	_button("RadarActions/Fire").disabled = get_tree().paused
	pause_status.text = "已暂停 · 点击继续" if get_tree().paused else "运行中 · 空格暂停"
	time_scale_button.text = "时间 ×%.0f" % WorldClock.time_scale
	radar_range_button.text = "量程 %.1f km" % radar.display_range_km
	action_status.text = MissionController.last_message

func _refresh_gun_status() -> void:
	var reason := MissionController.ship_gun_block_reason(selected_contact_id)
	var weapon: WeaponDefinition = DataManager.get_definition("weapon.deck_gun") as WeaponDefinition
	var weapon_range := weapon.range_km if weapon != null else 0.0
	gun_status.text = "火控 / %s" % ("可开火 · %.0f km / 前向 ±%.0f°" % [weapon_range, MissionController.GUN_HALF_ARC_DEGREES] if reason.is_empty() else reason)
	gun_status.add_theme_color_override("font_color", Color("#83e8aa") if reason.is_empty() else Color("#e8b968"))
	_button("RadarActions/Fire").tooltip_text = "甲板炮 %.0f km / 舰艏两侧各 %.0f°\n%s" % [weapon_range, MissionController.GUN_HALF_ARC_DEGREES, "可开火" if reason.is_empty() else reason]
	radar.set_gun_solution(GameManager.mode == "bridge", reason.is_empty(), weapon_range)

func _refresh_contact() -> void:
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
	selection_details.text = "雷达静默 · 开机后可复测接触" if not MissionController.radar_emitting else ("已选择 A1 · 可下达识别或开火命令" if selected_contact_id == MissionController.CONTACT_ID else "未选择接触 · 点击雷达回波")

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
	var destination_names := {"manual": "手动", "contact": "A1", "ship": "母舰", "airfield": "机场"}
	flight_details.text = "位置 E %05.1f / S %05.1f km   航向 %03d°\n燃油 %.0f 分   对海弹 %d   导航 %s\nA1 %.1f km  母舰 %.1f km  机场 %.1f km" % [MissionController.aircraft_position_km.x, MissionController.aircraft_position_km.y, roundi(MissionController.aircraft_heading_degrees), MissionController.aircraft_fuel_seconds / 60.0, MissionController.aircraft_bombs, destination_names.get(MissionController.aircraft_destination, "未知"), contact_distance, ship_distance, airfield_distance]
	_button("FlightControls/FlightNavControls/NavShip").disabled = not GameManager.ship_afloat
	flight_details.text += "\n母舰 %.0f%% · 损管 %s" % [MissionController.ship_health, "剩余 %.0f 秒" % ceilf(MissionController.repair_seconds_remaining) if MissionController.repair_seconds_remaining > 0.0 else "待命 %d 组" % MissionController.repair_teams]

func _refresh_debrief() -> void:
	var outcome := "任务完成" if GameManager.mode == "settlement" else "战役失败"
	var recovery := "母舰" if GameManager.recovery_site == "ship" else ("友方机场" if GameManager.recovery_site == "friendly_airfield" else "未回收")
	debrief_details.text = "结果 ........ %s\n任务目标 .... %s\n指挥官 ...... %s\n母舰舰体 .... %.0f%%\n敌舰舰体 .... %.0f%%\n甲板炮余弹 .. %d\n模拟耗时 .... %s" % [outcome, "已确认" if GameManager.target_identified else "未确认", recovery, MissionController.ship_health, MissionController.enemy_health, MissionController.ship_ammo, WorldClock.formatted_time()]

func _refresh_radar() -> void:
	if WorldState.map == null:
		return
	radar.set_land_areas(WorldState.map.islands, WorldState.ship_position_km)
	radar.set_sweep_enabled(MissionController.radar_emitting)
	radar.set_integrity(MissionController.ship_health)
	radar.set_aircraft(MissionController.aircraft_position_km, MissionController.aircraft_airborne)
	var relative := MissionController.last_contact_position_km - WorldState.ship_position_km
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
		"contact_discovered": return "A1 回波发现"
		"contact_updated": return "A1 方位复测"
		"contact_lost": return "A1 信号丢失"
		"radar_emission_changed": return "舰载雷达开启" if details_data.get("emitting", false) else "舰载雷达静默"
		"enemy_tracking": return "敌方截获舰载雷达" if details_data.get("source", "") == "radar" else "敌舰发现母舰"
		"enemy_tracking_lost": return "敌舰失去追踪"
		"target_identified", "aircraft_recon": return "A1 情报确认"
		"ship_navigation_command": return "航行命令 %03d° / %.0f kn" % [roundi(details_data.get("heading_degrees", 0.0)), details_data.get("speed_knots", 0.0)]
		"ship_navigation_blocked": return "航路受阻，舰艇停车"
		"weapon_fired": return "飞机对海投弹" if details_data.get("weapon_id", "") == "aircraft.bomb" else "甲板炮射击"
		"aircraft_attack": return "飞机对海攻击 A1"
		"enemy_damaged": return "A1 受损 %.0f%%" % (100.0 - details_data.get("health", 100.0))
		"ship_damaged": return "母舰受损 · 舰体 %.0f%%" % details_data.get("health", 0.0)
		"damage_control_started": return "损管队投入 · 甲板炮停用 30 秒"
		"damage_control_completed": return "损管完成 · 舰体 %.0f%%" % details_data.get("health", 0.0)
		"damage_control_aborted": return "母舰沉没，损管终止"
		"aircraft_launched": return "隼影侦察机升空"
		"aircraft_landed": return "飞机安全回收"
		"enemy_destroyed": return "A1 失去战斗力"
		"player_death": return "指挥官失联"
		"task_settled": return "任务结算完成"
		"mode_changed": return "指挥模式切换"
		"simulation_pause_changed": return "模拟暂停" if details_data.get("paused", false) else "模拟继续"
		"scenario_started": return "首关任务开始"
		_ : return str(event.get("kind", ""))
