extends Node

signal state_changed
signal feedback_changed(message: String)

const CONTACT_ID := "contact.alpha"
const SHIP_ID := "ship.haven"
const SCAN_RANGE_KM := 25.0
const RECON_RANGE_KM := 3.0
const GUN_DAMAGE := 50.0
const GUN_HALF_ARC_DEGREES := 70.0
const REPAIR_SECONDS := 30.0
const REPAIR_AMOUNT := 20.0
const ENEMY_DAMAGE := 20.0
const RADAR_INTERCEPT_RANGE_KM := 14.0
const ENEMY_GUN_RANGE_KM := 10.0
const VISUAL_SPOTTING_RANGE_KM := 6.0
const TRACK_MEMORY_SECONDS := 90.0
const KNOT_TO_KM_PER_SECOND := 1.852 / 3600.0

var radar_emitting: bool = true
var contact_visible: bool = false
var contact_scan_count: int = 0
var last_contact_position_km: Vector2 = Vector2.ZERO
var last_contact_bearing_degrees: float = 0.0
var last_contact_range_km: float = 0.0
var last_contact_seconds: float = 0.0

var ship_health: float = 100.0
var ship_ammo: int = 6
var next_ship_fire_seconds: float = 0.0
var repair_teams: int = 2
var repair_seconds_remaining: float = 0.0
var enemy_health: float = 100.0
var enemy_alive: bool = true
var enemy_heading_degrees: float = 90.0
var enemy_speed_knots: float = 6.0
var next_enemy_fire_seconds: float = 35.0
var enemy_tracking_ship: bool = false
var enemy_alert_until_seconds: float = 0.0
var _enemy_origin_km: Vector2 = Vector2.ZERO

var switch_seconds_remaining: float = 0.0
var aircraft_position_km: Vector2 = Vector2.ZERO
var aircraft_heading_degrees: float = 42.0
var aircraft_speed_knots: float = 135.0
var aircraft_fuel_seconds: float = 0.0
var aircraft_airborne: bool = false
var sorties_launched: int = 0
var sortie_ship_standby: bool = false
var aircraft_bombs: int = 1
var aircraft_destination: String = "manual"
var airfield_position_km: Vector2 = Vector2.ZERO

var last_message: String = "系统待命"
var _last_clock_seconds: float = 0.0

func _ready() -> void:
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	_initialize_scenario()

func restart_scenario() -> void:
	EventBus.history.clear()
	WorldClock.reset()
	GameManager.reset_for_new_scenario()
	WorldClock.set_time_scale(1.0)
	WorldState.load_first_scenario(WorldState.scenario_seed)
	_initialize_scenario()
	scan()

func _initialize_scenario() -> void:
	radar_emitting = true
	contact_visible = false
	contact_scan_count = 0
	last_contact_position_km = Vector2.ZERO
	last_contact_bearing_degrees = 0.0
	last_contact_range_km = 0.0
	last_contact_seconds = 0.0
	ship_health = 100.0
	ship_ammo = 6
	next_ship_fire_seconds = 0.0
	repair_teams = 2
	repair_seconds_remaining = 0.0
	enemy_health = 100.0
	enemy_alive = true
	enemy_heading_degrees = 90.0
	next_enemy_fire_seconds = WorldClock.elapsed_seconds + 35.0
	enemy_tracking_ship = false
	enemy_alert_until_seconds = 0.0
	_enemy_origin_km = WorldState.contact_position_km
	switch_seconds_remaining = 0.0
	aircraft_position_km = WorldState.ship_position_km
	aircraft_heading_degrees = 42.0
	var aircraft: AircraftDefinition = DataManager.get_definition("aircraft.kestrel") as AircraftDefinition
	if aircraft != null:
		aircraft_speed_knots = aircraft.cruise_speed_knots
		aircraft_fuel_seconds = aircraft.fuel_minutes * 60.0
	aircraft_airborne = false
	sorties_launched = 0
	sortie_ship_standby = false
	aircraft_bombs = 1
	aircraft_destination = "manual"
	if WorldState.map != null:
		airfield_position_km = WorldState.map.islands[1]["center"]
	_last_clock_seconds = WorldClock.elapsed_seconds
	last_message = "搜索海峡接触，确认目标后安全返航"
	state_changed.emit()

func scan() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode == "settlement" or GameManager.mode == "campaign_failed":
		return _reject("任务已结束，无法扫描")
	if not radar_emitting:
		return _reject("雷达静默中；开机后才能扫描")
	var was_visible := contact_visible
	var range_km := WorldState.contact_range_km()
	contact_visible = enemy_alive and range_km <= SCAN_RANGE_KM and WorldState.map.can_navigate_segment(WorldState.ship_position_km, WorldState.contact_position_km)
	if not contact_visible:
		if was_visible:
			EventBus.contact_lost.emit(CONTACT_ID)
			EventBus.record("contact_lost", {"id": CONTACT_ID})
		state_changed.emit()
		return _reject("扫描无回波，保留最后观测")
	contact_scan_count += 1
	last_contact_position_km = WorldState.contact_position_km
	last_contact_bearing_degrees = WorldState.contact_bearing_degrees()
	last_contact_range_km = range_km
	last_contact_seconds = WorldClock.elapsed_seconds
	var kind := "contact_updated" if was_visible else "contact_discovered"
	if was_visible:
		EventBus.contact_updated.emit(CONTACT_ID)
	else:
		EventBus.contact_discovered.emit(CONTACT_ID)
	EventBus.record(kind, {"id": CONTACT_ID, "bearing_degrees": last_contact_bearing_degrees, "range_km": range_km})
	state_changed.emit()
	return _accept("A1 回波已复测" if was_visible else "A1 未知水面回波")

func set_radar_emitting(is_enabled: bool) -> bool:
	if GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return _reject("只能在舰桥切换舰载雷达")
	if get_tree().paused:
		return _reject("模拟暂停，无法切换雷达")
	if radar_emitting == is_enabled:
		return _reject("雷达状态未改变")
	radar_emitting = is_enabled
	EventBus.record("radar_emission_changed", {"emitting": radar_emitting})
	if radar_emitting:
		var found := scan()
		_update_enemy_tracking(WorldClock.elapsed_seconds)
		state_changed.emit()
		if enemy_tracking_ship:
			return _accept("敌方已截获雷达辐射；注意交战距离")
		return _accept("主动雷达开启；A1 回波已获得，敌舰可能测向" if found else "主动雷达开启；暂无回波，敌舰可能测向")
	if contact_visible:
		contact_visible = false
		EventBus.contact_lost.emit(CONTACT_ID)
		EventBus.record("contact_lost", {"id": CONTACT_ID, "reason": "radar_silent"})
	_update_enemy_tracking(WorldClock.elapsed_seconds)
	state_changed.emit()
	return _accept("雷达静默；保留最后观测，敌方追踪不会立即消失" if enemy_tracking_ship else "雷达静默；保留最后观测")

func identify_contact() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "bridge":
		return _reject("识别命令需在舰桥下达")
	if not radar_emitting:
		return _reject("雷达静默中，无法复测确认")
	if not contact_visible or contact_scan_count < 2:
		return _reject("情报不足：需要两次有效扫描")
	if GameManager.target_identified:
		return _reject("A1 已确认")
	GameManager.identify_target(CONTACT_ID)
	state_changed.emit()
	return _accept("A1 已确认，首关目标情报完成")

func fire_ship_gun(contact_id: String) -> bool:
	var reason := ship_gun_block_reason(contact_id)
	if not reason.is_empty():
		return _reject(reason)
	ship_ammo -= 1
	next_ship_fire_seconds = WorldClock.elapsed_seconds + 30.0
	enemy_alert_until_seconds = maxf(enemy_alert_until_seconds, WorldClock.elapsed_seconds + TRACK_MEMORY_SECONDS)
	EventBus.weapon_fired.emit("weapon.deck_gun")
	EventBus.record("weapon_fired", {"weapon_id": "weapon.deck_gun", "ammo_remaining": ship_ammo})
	_damage_enemy(GUN_DAMAGE, "deck_gun")
	state_changed.emit()
	return _accept("甲板炮命中 A1，目标损伤 %.0f%%" % (100.0 - enemy_health))

func ship_gun_block_reason(contact_id: String) -> String:
	if GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return "甲板炮仅可在舰桥指挥"
	if get_tree().paused:
		return "模拟暂停，无法开火"
	if not radar_emitting:
		return "雷达静默中，火控无法跟踪接触"
	if contact_id != CONTACT_ID or not contact_visible or not enemy_alive:
		return "没有可射击的已选接触"
	if not GameManager.target_identified:
		return "目标尚未确认，禁止开火"
	if repair_seconds_remaining > 0.0:
		return "损管作业中，甲板炮暂时停用"
	if ship_ammo <= 0:
		return "甲板炮弹药耗尽"
	if WorldClock.elapsed_seconds < next_ship_fire_seconds:
		return "甲板炮装填中：还需 %.0f 秒" % ceilf(next_ship_fire_seconds - WorldClock.elapsed_seconds)
	var weapon: WeaponDefinition = DataManager.get_definition("weapon.deck_gun") as WeaponDefinition
	if weapon == null or WorldState.contact_range_km() > weapon.range_km:
		return "目标超出甲板炮射程"
	if WorldClock.elapsed_seconds - last_contact_seconds > 45.0:
		return "接触情报已过期，请重新扫描"
	var relative := last_contact_position_km - WorldState.ship_position_km
	var bearing := rad_to_deg(atan2(relative.x, -relative.y))
	var bearing_error := absf(wrapf(bearing - WorldState.ship_heading_degrees, -180.0, 180.0))
	if bearing_error > GUN_HALF_ARC_DEGREES:
		return "目标在甲板炮射界外：调整舰艏朝向 A1"
	if not WorldState.map.can_navigate_segment(WorldState.ship_position_km, WorldState.contact_position_km):
		return "岛屿遮挡射线"
	return ""

func start_damage_control() -> bool:
	if GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return _reject("损管命令仅可在未沉没母舰的舰桥下达")
	if get_tree().paused:
		return _reject("模拟暂停，无法投入损管队")
	if repair_seconds_remaining > 0.0:
		return _reject("损管作业已经进行中")
	if ship_health >= 100.0:
		return _reject("舰体完好，无需损管")
	if repair_teams <= 0:
		return _reject("本关损管队已耗尽")
	if WorldState.ship_speed_knots > 12.0:
		return _reject("请减速至不超过 12 kn 再投入损管队")
	repair_teams -= 1
	repair_seconds_remaining = REPAIR_SECONDS
	EventBus.record("damage_control_started", {"teams_remaining": repair_teams, "duration": REPAIR_SECONDS})
	state_changed.emit()
	return _accept("损管队已投入：30 秒内甲板炮停用，母舰仍可能遭受攻击")

func _advance_damage_control(delta: float) -> void:
	if repair_seconds_remaining <= 0.0:
		return
	if not GameManager.ship_afloat:
		repair_seconds_remaining = 0.0
		EventBus.record("damage_control_aborted", {"reason": "ship_sunk"})
		return
	repair_seconds_remaining = maxf(0.0, repair_seconds_remaining - delta)
	if repair_seconds_remaining == 0.0:
		ship_health = minf(100.0, ship_health + REPAIR_AMOUNT)
		EventBus.record("damage_control_completed", {"health": ship_health})
		_feedback("损管完成：舰体 %.0f%%，甲板炮恢复可用" % ship_health)

func prepare_sortie() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return _reject("当前无法配置出击")
	if GameManager.player_recovered:
		return _reject("已安全回收，请完成目标并提交任务报告")
	var readiness := _sortie_readiness_error()
	if not readiness.is_empty():
		return _reject(readiness)
	if not GameManager.change_mode("configuration"):
		return false
	state_changed.emit()
	return _accept("隼影侦察机已进入出击配置")

func command_ship(heading_degrees: float, speed_knots: float) -> bool:
	if GameManager.mode not in ["bridge", "configuration", "switching"] or not GameManager.ship_afloat or not GameManager.player_alive:
		return _reject("当前没有舰桥航行控制权")
	if not WorldState.set_ship_command(heading_degrees, speed_knots):
		return _reject("航行命令无效，请检查航向和航速范围")
	return _accept("航行命令已接收；暂停时将在继续后执行" if get_tree().paused else "舰桥航行命令已生效")

func set_sortie_ship_standby(enabled: bool) -> bool:
	if GameManager.mode != "configuration":
		return _reject("母舰托管方式只能在出击配置中选择")
	sortie_ship_standby = enabled
	EventBus.record("sortie_configured", {"ship_standby": enabled})
	state_changed.emit()
	return _accept("离舰后母舰将停车待命" if enabled else "离舰后母舰将保持最后航行命令")

func request_ship_standby() -> bool:
	if GameManager.mode not in ["cockpit", "returning"] or not aircraft_airborne or not GameManager.ship_afloat:
		return _reject("母舰待命请求需要飞机在空中且母舰仍在航")
	if WorldState.ship_speed_knots == 0:
		return _reject("母舰已经停车待命")
	WorldState.set_ship_command(WorldState.ship_heading_degrees, 0.0)
	EventBus.record("ship_standby_requested", {})
	state_changed.emit()
	return _accept("母舰收到待命请求，已停车；敌方行动仍会继续")

func cancel_sortie() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "configuration" and GameManager.mode != "switching":
		return _reject("当前没有可取消的出击")
	var previous_wait := switch_seconds_remaining
	switch_seconds_remaining = 0.0
	if not GameManager.change_mode("bridge" if GameManager.mode == "configuration" else "configuration"):
		switch_seconds_remaining = previous_wait
		return false
	state_changed.emit()
	return _accept("出击流程已取消")

func launch_sortie() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "configuration" or not GameManager.aircraft_operational:
		return _reject("飞机未就绪")
	var readiness := _sortie_readiness_error()
	if not readiness.is_empty():
		return _reject(readiness)
	switch_seconds_remaining = 5.0
	if not GameManager.change_mode("switching"):
		switch_seconds_remaining = 0.0
		return false
	state_changed.emit()
	return _accept("指挥权移交中，母舰继续执行最后航行命令")

func set_aircraft_heading(heading_degrees: float) -> bool:
	if not aircraft_airborne or (GameManager.mode != "cockpit" and GameManager.mode != "returning"):
		return _reject("当前无法操纵飞机")
	if not is_finite(heading_degrees):
		return false
	aircraft_heading_degrees = fposmod(heading_degrees, 360.0)
	aircraft_destination = "manual"
	state_changed.emit()
	return _accept("飞机转向 %03d°" % roundi(aircraft_heading_degrees))

func set_aircraft_destination(destination: String) -> bool:
	if not aircraft_airborne or (GameManager.mode != "cockpit" and GameManager.mode != "returning"):
		return _reject("飞机尚未升空")
	if destination != "contact" and destination != "ship" and destination != "airfield":
		return false
	if destination == "ship" and not GameManager.ship_afloat:
		return _reject("母舰已沉没，请转往友方机场")
	aircraft_destination = destination
	state_changed.emit()
	var target_names := {"contact": "A1", "ship": "母舰", "airfield": "友方机场"}
	return _accept("飞机导航目标：%s" % target_names[destination])

func perform_recon() -> bool:
	if not _action_allowed():
		return false
	if not aircraft_airborne or GameManager.mode != "cockpit":
		return _reject("侦察须在座舱执行")
	if not enemy_alive:
		return _reject("目标已失去活动迹象")
	if aircraft_position_km.distance_to(WorldState.contact_position_km) > RECON_RANGE_KM:
		return _reject("距离目标超过 3 km，无法目视确认")
	if GameManager.target_identified:
		return _reject("A1 已确认")
	GameManager.identify_target(CONTACT_ID)
	EventBus.record("aircraft_recon", {"id": CONTACT_ID})
	state_changed.emit()
	return _accept("空中侦察确认 A1，情报已回传")

func aircraft_attack() -> bool:
	if not _action_allowed():
		return false
	if not aircraft_airborne or GameManager.mode != "cockpit":
		return _reject("当前无法对海攻击")
	if not GameManager.target_identified or not enemy_alive:
		return _reject("没有可攻击的已确认目标")
	if aircraft_bombs <= 0:
		return _reject("对海弹药已用尽")
	if aircraft_position_km.distance_to(WorldState.contact_position_km) > 2.0:
		return _reject("未进入 2 km 投放窗口")
	aircraft_bombs -= 1
	EventBus.weapon_fired.emit("aircraft.bomb")
	EventBus.record("aircraft_attack", {"id": CONTACT_ID})
	_damage_enemy(100.0, "aircraft_bomb")
	state_changed.emit()
	return _accept("对海攻击命中，A1 已失去战斗力")

func begin_return() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "cockpit" or not aircraft_airborne:
		return _reject("当前无法进入返航流程")
	var previous_destination := aircraft_destination
	aircraft_destination = "ship" if GameManager.ship_afloat else "airfield"
	if not GameManager.change_mode("returning"):
		aircraft_destination = previous_destination
		return false
	state_changed.emit()
	return _accept("返航中；到达回收点后执行降落")

func cancel_return() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "returning" or not aircraft_airborne:
		return _reject("当前没有可取消的返航")
	var previous_destination := aircraft_destination
	aircraft_destination = "manual"
	if not GameManager.change_mode("cockpit"):
		aircraft_destination = previous_destination
		return false
	EventBus.record("return_cancelled", {})
	state_changed.emit()
	return _accept("返航已取消；保持当前航向，燃油不会恢复。可重新导航 A1 继续侦察")

func land_aircraft() -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "returning" or not aircraft_airborne:
		return _reject("飞机尚未进入返航状态")
	var ship_distance := aircraft_position_km.distance_to(WorldState.ship_position_km)
	var airfield_distance := aircraft_position_km.distance_to(airfield_position_km)
	var site := ""
	if GameManager.ship_afloat and ship_distance <= 2.0:
		if WorldState.ship_speed_knots > 12.0:
			return _reject("母舰航速超过 12 kn，无法回收")
		site = "ship"
	elif airfield_distance <= 3.0:
		site = "friendly_airfield"
	else:
		return _reject("尚未到达回收点：母舰 %.1f km / 机场 %.1f km" % [ship_distance, airfield_distance])
	var previous_destination := aircraft_destination
	aircraft_airborne = false
	aircraft_destination = "manual"
	if not GameManager.recover_player(site):
		aircraft_airborne = true
		aircraft_destination = previous_destination
		return _reject("回收条件不满足")
	EventBus.record("aircraft_landed", {"site": site})
	state_changed.emit()
	return _accept("飞机已安全回收：%s" % ("母舰" if site == "ship" else "友方机场"))

func complete_mission() -> bool:
	if not _action_allowed():
		return false
	if not GameManager.target_identified:
		return _reject("指定接触尚未确认")
	if not GameManager.player_recovered:
		return _reject("指挥官尚未安全回收")
	if not GameManager.settle("success"):
		return _reject("当前状态无法结算")
	state_changed.emit()
	return _accept("任务完成：目标已确认，指挥官安全返回")

func _on_world_time_advanced(total_seconds: float) -> void:
	var delta := total_seconds - _last_clock_seconds
	_last_clock_seconds = total_seconds
	if delta <= 0.0 or GameManager.mode == "settlement" or GameManager.mode == "campaign_failed":
		return
	_advance_enemy(delta)
	var flight_delta := delta
	if GameManager.mode == "switching":
		var waiting := minf(delta, switch_seconds_remaining)
		switch_seconds_remaining -= waiting
		flight_delta -= waiting
		if switch_seconds_remaining <= 0.0:
			_start_flight()
	if aircraft_airborne and flight_delta > 0.0:
		_advance_aircraft(flight_delta)
	_enemy_attack(total_seconds)
	_advance_damage_control(delta)
	state_changed.emit()

func _advance_enemy(delta: float) -> void:
	if not enemy_alive:
		return
	var direction := 1.0 if enemy_heading_degrees == 90.0 else -1.0
	var destination := WorldState.contact_position_km + Vector2(direction * enemy_speed_knots * KNOT_TO_KM_PER_SECOND * delta, 0.0)
	if absf(destination.x - _enemy_origin_km.x) > 3.0 or not WorldState.map.can_navigate_segment(WorldState.contact_position_km, destination):
		enemy_heading_degrees = 270.0 if enemy_heading_degrees == 90.0 else 90.0
		return
	WorldState.contact_position_km = destination

func _enemy_attack(total_seconds: float) -> void:
	_update_enemy_tracking(total_seconds)
	if not enemy_alive or not GameManager.ship_afloat or not enemy_tracking_ship or total_seconds < next_enemy_fire_seconds:
		return
	if WorldState.contact_range_km() > ENEMY_GUN_RANGE_KM or not WorldState.map.can_navigate_segment(WorldState.ship_position_km, WorldState.contact_position_km):
		return
	next_enemy_fire_seconds = total_seconds + 45.0
	ship_health = maxf(0.0, ship_health - ENEMY_DAMAGE)
	EventBus.damage_reported.emit(SHIP_ID)
	EventBus.record("ship_damaged", {"health": ship_health, "source": CONTACT_ID})
	_feedback("母舰遭到还击，舰体 %.0f%%" % ship_health)
	if ship_health <= 0.0:
		WorldState.set_ship_command(WorldState.ship_heading_degrees, 0.0)
		GameManager.report_ship_sunk()
		_feedback("母舰沉没；空中指挥官可转往友方机场" if aircraft_airborne else "母舰沉没，战役结束")

func _update_enemy_tracking(total_seconds: float) -> void:
	if not enemy_alive or not GameManager.ship_afloat:
		enemy_tracking_ship = false
		return
	var range_km: float = WorldState.contact_range_km()
	var line_of_sight: bool = WorldState.map.can_navigate_segment(WorldState.ship_position_km, WorldState.contact_position_km)
	var radar_intercept: bool = radar_emitting and range_km <= RADAR_INTERCEPT_RANGE_KM and line_of_sight
	var visual_contact: bool = range_km <= VISUAL_SPOTTING_RANGE_KM and line_of_sight
	if radar_intercept or visual_contact:
		enemy_alert_until_seconds = maxf(enemy_alert_until_seconds, total_seconds + TRACK_MEMORY_SECONDS)
	var tracking: bool = radar_intercept or visual_contact or total_seconds < enemy_alert_until_seconds
	if tracking and not enemy_tracking_ship:
		enemy_tracking_ship = true
		next_enemy_fire_seconds = maxf(next_enemy_fire_seconds, total_seconds + 10.0)
		EventBus.record("enemy_tracking", {"source": "radar" if radar_intercept else "visual" if visual_contact else "recent_contact", "range_km": range_km})
		_feedback("敌方测向警报：主动雷达暴露母舰" if radar_intercept else "敌舰接近并发现母舰")
	elif not tracking and enemy_tracking_ship:
		enemy_tracking_ship = false
		EventBus.record("enemy_tracking_lost", {})

func _start_flight() -> void:
	if GameManager.mode != "switching":
		return
	aircraft_position_km = WorldState.ship_position_km
	aircraft_airborne = true
	aircraft_destination = "contact"
	sorties_launched += 1
	if not GameManager.change_mode("cockpit"):
		aircraft_airborne = false
		aircraft_destination = "manual"
		sorties_launched -= 1
		return
	if sortie_ship_standby:
		WorldState.set_ship_command(WorldState.ship_heading_degrees, 0.0)
	EventBus.record("aircraft_launched", {"position_km": aircraft_position_km})
	_feedback("隼影侦察机升空；母舰停车待命" if sortie_ship_standby else "隼影侦察机升空；舰艇由最后航行命令托管")

func _advance_aircraft(delta: float) -> void:
	aircraft_fuel_seconds = maxf(0.0, aircraft_fuel_seconds - delta)
	if aircraft_fuel_seconds <= 0.0:
		aircraft_airborne = false
		GameManager.aircraft_operational = false
		GameManager.report_player_death("fuel_exhausted")
		_feedback("燃油耗尽，飞机失事；战役结束")
		return
	if aircraft_destination != "manual":
		var target := WorldState.contact_position_km
		if aircraft_destination == "ship":
			target = WorldState.ship_position_km
		elif aircraft_destination == "airfield":
			target = airfield_position_km
		var relative := target - aircraft_position_km
		if relative.length() > 0.001:
			aircraft_heading_degrees = fposmod(rad_to_deg(atan2(relative.x, -relative.y)), 360.0)
	var direction := Vector2(sin(deg_to_rad(aircraft_heading_degrees)), -cos(deg_to_rad(aircraft_heading_degrees)))
	var distance := aircraft_speed_knots * KNOT_TO_KM_PER_SECOND * delta
	if aircraft_destination != "manual":
		var target := WorldState.contact_position_km
		if aircraft_destination == "ship":
			target = WorldState.ship_position_km
		elif aircraft_destination == "airfield":
			target = airfield_position_km
		distance = minf(distance, aircraft_position_km.distance_to(target))
	aircraft_position_km += direction * distance

func _damage_enemy(amount: float, source: String) -> void:
	enemy_health = maxf(0.0, enemy_health - amount)
	EventBus.damage_reported.emit(CONTACT_ID)
	EventBus.record("enemy_damaged", {"health": enemy_health, "source": source})
	if enemy_health <= 0.0:
		enemy_alive = false
		enemy_tracking_ship = false
		enemy_alert_until_seconds = 0.0
		contact_visible = false
		EventBus.record("enemy_destroyed", {"id": CONTACT_ID})

func _accept(message: String) -> bool:
	_feedback(message)
	return true

func _action_allowed() -> bool:
	if not GameManager.player_alive or GameManager.mode in ["settlement", "campaign_failed"]:
		return _reject("行动已结束，无法下达该命令")
	if get_tree().paused:
		return _reject("模拟暂停，请继续后执行该操作")
	return true

func _sortie_readiness_error() -> String:
	var task: TaskDefinition = DataManager.definitions.get(GameManager.current_task_id) as TaskDefinition
	if task == null or not DataManager.errors.is_empty():
		return "任务数据无效，无法出击；请返回菜单检查数据"
	var ship: ShipDefinition = DataManager.definitions.get(task.ship_id) as ShipDefinition
	var aircraft: AircraftDefinition = DataManager.definitions.get(task.aircraft_id) as AircraftDefinition
	if ship == null or aircraft == null or not task.aircraft_id in ship.aircraft_ids:
		return "舰机不兼容，无法配置出击"
	if not GameManager.aircraft_operational or aircraft_fuel_seconds <= 0.0:
		return "飞机不可用或燃油已耗尽"
	return ""

func _reject(message: String) -> bool:
	_feedback(message)
	return false

func _feedback(message: String) -> void:
	last_message = message
	feedback_changed.emit(message)
