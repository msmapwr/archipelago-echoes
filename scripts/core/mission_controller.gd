extends Node

signal state_changed
signal feedback_changed(message: String)

const CONTACT_ID := "contact.alpha"
const SHIP_ID := "ship.haven"
const SCAN_RANGE_KM := 25.0
const RECON_RANGE_KM := 3.0
const GUN_DAMAGE := 50.0
const ENEMY_DAMAGE := 20.0
const KNOT_TO_KM_PER_SECOND := 1.852 / 3600.0

var contact_visible: bool = false
var contact_scan_count: int = 0
var last_contact_position_km: Vector2 = Vector2.ZERO
var last_contact_bearing_degrees: float = 0.0
var last_contact_range_km: float = 0.0
var last_contact_seconds: float = 0.0

var ship_health: float = 100.0
var ship_ammo: int = 6
var next_ship_fire_seconds: float = 0.0
var enemy_health: float = 100.0
var enemy_alive: bool = true
var enemy_heading_degrees: float = 90.0
var enemy_speed_knots: float = 6.0
var next_enemy_fire_seconds: float = 35.0
var _enemy_origin_km: Vector2 = Vector2.ZERO

var switch_seconds_remaining: float = 0.0
var aircraft_position_km: Vector2 = Vector2.ZERO
var aircraft_heading_degrees: float = 42.0
var aircraft_speed_knots: float = 135.0
var aircraft_fuel_seconds: float = 0.0
var aircraft_airborne: bool = false
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
	GameManager.reset_for_new_scenario()
	WorldClock.reset()
	WorldClock.set_time_scale(1.0)
	WorldState.load_first_scenario()
	_initialize_scenario()
	scan()

func _initialize_scenario() -> void:
	contact_visible = false
	contact_scan_count = 0
	last_contact_position_km = Vector2.ZERO
	last_contact_bearing_degrees = 0.0
	last_contact_range_km = 0.0
	last_contact_seconds = 0.0
	ship_health = 100.0
	ship_ammo = 6
	next_ship_fire_seconds = 0.0
	enemy_health = 100.0
	enemy_alive = true
	enemy_heading_degrees = 90.0
	next_enemy_fire_seconds = WorldClock.elapsed_seconds + 35.0
	_enemy_origin_km = WorldState.contact_position_km
	switch_seconds_remaining = 0.0
	aircraft_position_km = WorldState.ship_position_km
	aircraft_heading_degrees = 42.0
	var aircraft: AircraftDefinition = DataManager.get_definition("aircraft.kestrel") as AircraftDefinition
	if aircraft != null:
		aircraft_speed_knots = aircraft.cruise_speed_knots
		aircraft_fuel_seconds = aircraft.fuel_minutes * 60.0
	aircraft_airborne = false
	aircraft_bombs = 1
	aircraft_destination = "manual"
	if WorldState.map != null:
		airfield_position_km = WorldState.map.islands[1]["center"]
	_last_clock_seconds = WorldClock.elapsed_seconds
	last_message = "搜索海峡接触，确认目标后安全返航"
	state_changed.emit()

func scan() -> bool:
	if GameManager.mode == "settlement" or GameManager.mode == "campaign_failed":
		return _reject("任务已结束，无法扫描")
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

func identify_contact() -> bool:
	if GameManager.mode != "bridge":
		return _reject("识别命令需在舰桥下达")
	if not contact_visible or contact_scan_count < 2:
		return _reject("情报不足：需要两次有效扫描")
	if GameManager.target_identified:
		return _reject("A1 已确认")
	GameManager.identify_target(CONTACT_ID)
	state_changed.emit()
	return _accept("A1 已确认，首关目标情报完成")

func fire_ship_gun(contact_id: String) -> bool:
	if GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return _reject("甲板炮仅可在舰桥指挥")
	if contact_id != CONTACT_ID or not contact_visible or not enemy_alive:
		return _reject("没有可射击的已选接触")
	if not GameManager.target_identified:
		return _reject("目标尚未确认，禁止开火")
	if ship_ammo <= 0:
		return _reject("甲板炮弹药耗尽")
	if WorldClock.elapsed_seconds < next_ship_fire_seconds:
		return _reject("甲板炮装填中：还需 %.0f 秒" % (next_ship_fire_seconds - WorldClock.elapsed_seconds))
	var weapon: WeaponDefinition = DataManager.get_definition("weapon.deck_gun") as WeaponDefinition
	if weapon == null or WorldState.contact_range_km() > weapon.range_km:
		return _reject("目标超出甲板炮射程")
	if WorldClock.elapsed_seconds - last_contact_seconds > 45.0:
		return _reject("接触情报已过期，请重新扫描")
	if not WorldState.map.can_navigate_segment(WorldState.ship_position_km, WorldState.contact_position_km):
		return _reject("岛屿遮挡射线")
	ship_ammo -= 1
	next_ship_fire_seconds = WorldClock.elapsed_seconds + 30.0
	EventBus.weapon_fired.emit("weapon.deck_gun")
	EventBus.record("weapon_fired", {"weapon_id": "weapon.deck_gun", "ammo_remaining": ship_ammo})
	_damage_enemy(GUN_DAMAGE, "deck_gun")
	state_changed.emit()
	return _accept("甲板炮命中 A1，目标损伤 %.0f%%" % (100.0 - enemy_health))

func prepare_sortie() -> bool:
	if GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return _reject("当前无法配置出击")
	if not GameManager.change_mode("configuration"):
		return false
	state_changed.emit()
	return _accept("隼影侦察机已进入出击配置")

func cancel_sortie() -> bool:
	if GameManager.mode != "configuration" and GameManager.mode != "switching":
		return _reject("当前没有可取消的出击")
	if not GameManager.change_mode("bridge" if GameManager.mode == "configuration" else "configuration"):
		return false
	switch_seconds_remaining = 0.0
	state_changed.emit()
	return _accept("出击流程已取消")

func launch_sortie() -> bool:
	if GameManager.mode != "configuration" or not GameManager.aircraft_operational:
		return _reject("飞机未就绪")
	if not GameManager.change_mode("switching"):
		return false
	switch_seconds_remaining = 5.0
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
	if GameManager.mode != "cockpit" or not aircraft_airborne:
		return _reject("当前无法进入返航流程")
	if not GameManager.change_mode("returning"):
		return false
	aircraft_destination = "ship" if GameManager.ship_afloat else "airfield"
	state_changed.emit()
	return _accept("返航中；到达回收点后执行降落")

func land_aircraft() -> bool:
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
	if not GameManager.recover_player(site):
		return _reject("回收条件不满足")
	aircraft_airborne = false
	aircraft_destination = "manual"
	EventBus.record("aircraft_landed", {"site": site})
	state_changed.emit()
	return _accept("飞机已安全回收：%s" % ("母舰" if site == "ship" else "友方机场"))

func complete_mission() -> bool:
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
	if not enemy_alive or not GameManager.ship_afloat or total_seconds < next_enemy_fire_seconds:
		return
	if WorldState.contact_range_km() > 10.0 or not WorldState.map.can_navigate_segment(WorldState.ship_position_km, WorldState.contact_position_km):
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

func _start_flight() -> void:
	if GameManager.mode != "switching" or not GameManager.change_mode("cockpit"):
		return
	aircraft_position_km = WorldState.ship_position_km
	aircraft_airborne = true
	aircraft_destination = "contact"
	EventBus.record("aircraft_launched", {"position_km": aircraft_position_km})
	_feedback("隼影侦察机升空；舰艇由最后航行命令托管")

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
		contact_visible = false
		EventBus.record("enemy_destroyed", {"id": CONTACT_ID})

func _accept(message: String) -> bool:
	_feedback(message)
	return true

func _reject(message: String) -> bool:
	_feedback(message)
	return false

func _feedback(message: String) -> void:
	last_message = message
	feedback_changed.emit(message)
