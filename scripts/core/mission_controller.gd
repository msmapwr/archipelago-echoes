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
var last_contact_heading_degrees: float = 0.0
var fire_control_aim_mode: String = "observed"
var selected_mount_id := "fore"
var _gun_states: Dictionary = {"fore": {"ammo": 6, "reload": 0.0, "ammunition": "ammo.sap", "heading": 0.0}}
var _gun_mounts: Array[WeaponMountDefinition] = []
var selected_ammunition_id: String:
	get: return _gun_states[selected_mount_id].ammunition
	set(value): _gun_states[selected_mount_id].ammunition = value
const LOCK_MEMORY_SECONDS := 8.0
const TURRET_RATE_DEGREES := 20.0
var fire_control_locked := false
var turret_heading_degrees: float:
	get: return wrapf(WorldState.ship_heading_degrees + float(_gun_states[selected_mount_id].heading), 0, 360)
	set(value): _gun_states[selected_mount_id].heading = wrapf(value - WorldState.ship_heading_degrees, -180, 180)
var lock_status := "未锁定"
var _motion = preload("res://scripts/core/fire_control_solution.gd").new()
var fire_control_correction_km := Vector2.ZERO
var projectiles: Array[Dictionary] = []
var last_gun_impact: Dictionary = {}
var _shot_sequence := 0
var _last_tick_ship_position := Vector2.ZERO
const GUN_HIT_RADIUS_KM := 0.05
const GUN_NEAR_MISS_RADIUS_KM := 0.3

var ship_health: float = 100.0
# Compatibility properties project the selected group; default remains the fore gun.
var ship_ammo: int:
	get: return _gun_states[selected_mount_id].ammo
	set(value): _gun_states[selected_mount_id].ammo = value
var next_ship_fire_seconds: float:
	get: return _gun_states[selected_mount_id].reload
	set(value): _gun_states[selected_mount_id].reload = value
var fire_control_target_id: String = ""
var fire_control_order_id: String = ""
var _fire_control_sequence: int = 0
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
var aircraft_waypoint_km: Vector2 = Vector2.ZERO
var _navigation_arrived: bool = false
var _fuel_warning_level: int = 0
var airfield_position_km: Vector2 = Vector2.ZERO

var last_message: String = "系统待命"
var _last_clock_seconds: float = 0.0

func _ready() -> void:
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	EventBus.mode_changed.connect(_on_fire_control_mode_changed)
	EventBus.event_recorded.connect(_on_fire_control_event)
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
	var ship := DataManager.get_definition(SHIP_ID) as ShipDefinition
	_gun_mounts = ship.weapon_mounts.duplicate()
	if _gun_mounts.is_empty(): _gun_mounts.append(WeaponMountDefinition.new())
	_gun_states.clear()
	for mount in _gun_mounts:
		_gun_states[mount.mount_id] = {"ammo": mount.capacity, "reload": 0.0, "ammunition": "ammo.sap", "heading": mount.relative_heading_degrees}
	selected_mount_id = _gun_mounts[0].mount_id
	radar_emitting = true
	contact_visible = false
	contact_scan_count = 0
	last_contact_position_km = Vector2.ZERO
	last_contact_bearing_degrees = 0.0
	last_contact_range_km = 0.0
	last_contact_seconds = 0.0
	last_contact_heading_degrees = 0.0
	fire_control_aim_mode = "observed"
	selected_ammunition_id = "ammo.sap"
	fire_control_locked = false
	turret_heading_degrees = WorldState.ship_heading_degrees
	lock_status = "未锁定"
	_motion.reset()
	fire_control_correction_km = Vector2.ZERO
	projectiles.clear()
	last_gun_impact = {}
	_shot_sequence = 0
	_last_tick_ship_position = WorldState.ship_position_km
	ship_health = 100.0
	fire_control_target_id = ""
	fire_control_order_id = ""
	_fire_control_sequence = 0
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
	aircraft_waypoint_km = Vector2.ZERO
	_navigation_arrived = false
	_fuel_warning_level = 0
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
		_release_fire_control_lock("接触失联")
		_motion.reset()
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
	last_contact_heading_degrees = enemy_heading_degrees
	_motion.observe(last_contact_position_km, last_contact_seconds)
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
	if not is_enabled:
		_release_fire_control_lock("雷达静默")
		_motion.reset()
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

func fire_control_assignment_reason(contact_id: String) -> String:
	if not GameManager.player_alive or GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return "火控指派需要未结束行动中的舰桥指挥权"
	if contact_id != CONTACT_ID:
		return "请先选择 A1，再指派甲板炮目标"
	if not GameManager.target_identified:
		return "目标尚未确认，禁止指派"
	if not enemy_alive:
		return "目标已失能，无法指派"
	if not radar_emitting or not contact_visible or contact_scan_count == 0:
		return "没有有效观测；开启雷达并重新扫描后指派"
	if WorldClock.elapsed_seconds - last_contact_seconds > 45.0:
		return "接触情报已过期，请重新扫描后指派"
	return ""

func assign_fire_control_target(contact_id: String) -> bool:
	var reason := fire_control_assignment_reason(contact_id)
	if not reason.is_empty():
		EventBus.record("fire_control_rejected", {"action": "assign", "target_id": contact_id, "order_id": fire_control_order_id, "reason": reason})
		return _reject(reason)
	if fire_control_target_id == contact_id:
		return _accept("甲板炮已指派 A1；重复指派不生成新命令")
	_fire_control_sequence += 1
	fire_control_target_id = contact_id
	fire_control_order_id = "fire_control.%03d" % _fire_control_sequence
	fire_control_correction_km = Vector2.ZERO
	EventBus.record("fire_control_assigned", {"weapon_id": active_gun_mount().weapon_id, "target_id": contact_id, "order_id": fire_control_order_id, "observation_seconds": last_contact_seconds, "queued": get_tree().paused})
	EventBus.command_issued.emit(fire_control_order_id)
	state_changed.emit()
	return _accept("甲板炮目标已指派 A1；继续模拟后可手动射击" if get_tree().paused else "甲板炮目标已指派 A1；查看火控条件后手动射击")

func clear_fire_control_target() -> bool:
	if not GameManager.player_alive or GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return _reject_fire_control_clear("撤销火控指派需要舰桥指挥权")
	if fire_control_target_id.is_empty():
		return _reject_fire_control_clear("甲板炮当前没有指派目标")
	_clear_fire_control("player_cancelled")
	state_changed.emit()
	return _accept("甲板炮目标指派已撤销；不会自动射击，装填与弹药保持不变")

func _reject_fire_control_clear(reason: String) -> bool:
	EventBus.record("fire_control_rejected", {"action": "clear", "target_id": fire_control_target_id, "order_id": fire_control_order_id, "reason": reason})
	return _reject(reason)

func _on_fire_control_event(event: Dictionary) -> void:
	if event.get("kind", "") == "ship_sunk":
		_cancel_gun_projectiles("母舰沉没")
		_clear_fire_control("ship_sunk")
		state_changed.emit()

func _clear_fire_control(reason: String, simulation_seconds: float = -1.0) -> void:
	_release_fire_control_lock(reason, simulation_seconds)
	if fire_control_target_id.is_empty():
		return
	var target := fire_control_target_id
	var order := fire_control_order_id
	fire_control_target_id = ""
	fire_control_order_id = ""
	fire_control_correction_km = Vector2.ZERO
	EventBus.record("fire_control_cleared", {"weapon_id": active_gun_mount().weapon_id, "target_id": target, "order_id": order, "reason": reason}, simulation_seconds)
	EventBus.command_issued.emit(order + ".clear")

func _on_fire_control_mode_changed(_previous: String, current: String) -> void:
	if current != "bridge":
		_release_fire_control_lock("离开舰桥")
	if current in ["settlement", "campaign_failed"] or not GameManager.ship_afloat:
		_cancel_gun_projectiles("行动结束")
		_clear_fire_control("action_ended" if GameManager.ship_afloat else "ship_sunk")
		state_changed.emit()

func _cancel_gun_projectiles(reason: String) -> void:
	for projectile in projectiles:
		EventBus.record("gun_projectile_cancelled", {"shot_id": projectile.shot_id, "order_id": projectile.order_id, "mount_id": projectile.mount_id, "reason": reason})
	projectiles.clear()

func fire_ship_gun(contact_id: String = "") -> bool:
	# Explicit caller IDs must match the existing order; selection never assigns a gun.
	var target := fire_control_target_id if contact_id.is_empty() else contact_id
	var reason := ship_gun_block_reason(target)
	if not reason.is_empty():
		EventBus.record("ship_gun_rejected", {"weapon_id": active_gun_mount().weapon_id, "target_id": target, "order_id": fire_control_order_id, "mount_id": selected_mount_id, "reason": reason})
		return _reject(reason)
	var solution := fire_control_solution()
	var aim: Vector2 = solution.aim_position_km if fire_control_aim_mode == "lead" else last_contact_position_km
	aim += fire_control_correction_km
	var weapon: WeaponDefinition = DataManager.get_definition(active_gun_mount().weapon_id) as WeaponDefinition
	var flight_seconds := maxf(0.1, gun_origin_km().distance_to(aim) / weapon.projectile_speed_km_per_second)
	var ammunition := DataManager.get_definition(selected_ammunition_id) as AmmunitionDefinition
	_shot_sequence += 1
	var shot := {"shot_id": "deck_gun.%03d" % _shot_sequence, "order_id": fire_control_order_id, "target_id": target,
		"origin_km": gun_origin_km(), "mount_id": selected_mount_id, "aim_position_km": aim, "aim_mode": fire_control_aim_mode,
		"correction_km": fire_control_correction_km, "locked": fire_control_locked, "turret_heading_degrees": turret_heading_degrees, "fired_seconds": WorldClock.elapsed_seconds,
		"impact_seconds": WorldClock.elapsed_seconds + flight_seconds, "flight_seconds": flight_seconds, "ammunition": ammunition.snapshot()}
	projectiles.append(shot.duplicate(true))
	projectiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.impact_seconds < b.impact_seconds)
	ship_ammo -= 1
	next_ship_fire_seconds = WorldClock.elapsed_seconds + active_gun_mount().reload_seconds
	enemy_alert_until_seconds = maxf(enemy_alert_until_seconds, WorldClock.elapsed_seconds + TRACK_MEMORY_SECONDS)
	EventBus.weapon_fired.emit(active_gun_mount().weapon_id)
	shot.merge({"weapon_id": active_gun_mount().weapon_id, "observation_seconds": last_contact_seconds, "solution": solution.duplicate(true), "ammo_remaining": ship_ammo})
	EventBus.record("weapon_fired", shot)
	state_changed.emit()
	return _accept("甲板炮已发射 / %s · 预计 %.1f 秒后弹着" % [shot.shot_id, flight_seconds])

func active_gun_mount() -> WeaponMountDefinition:
	for mount in _gun_mounts:
		if mount.mount_id == selected_mount_id: return mount
	return null

func gun_origin_km() -> Vector2:
	return WorldState.ship_position_km + active_gun_mount().local_position_km.rotated(deg_to_rad(WorldState.ship_heading_degrees))

func gun_center_heading_degrees() -> float:
	return wrapf(WorldState.ship_heading_degrees + active_gun_mount().relative_heading_degrees, 0, 360)

func gun_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for mount in _gun_mounts:
		groups.append({"mount_id": mount.mount_id, "label": mount.display_name, "origin_km": WorldState.ship_position_km + mount.local_position_km.rotated(deg_to_rad(WorldState.ship_heading_degrees)), "heading": wrapf(WorldState.ship_heading_degrees + mount.relative_heading_degrees, 0, 360), "half_arc": mount.half_arc_degrees, "range_km": (DataManager.get_definition(mount.weapon_id) as WeaponDefinition).range_km, "ammo": _gun_states[mount.mount_id].ammo, "reload_remaining": maxf(0, _gun_states[mount.mount_id].reload - WorldClock.elapsed_seconds), "ammunition_id": _gun_states[mount.mount_id].ammunition})
	return groups

func total_ship_ammo() -> int:
	var total := 0
	for group in _gun_states.values(): total += int(group.ammo)
	return total

func select_gun_group(mount_id: String) -> bool:
	if not _gun_states.has(mount_id) or GameManager.mode != "bridge" or not GameManager.ship_afloat or not GameManager.player_alive:
		EventBus.record("fire_control_rejected", {"action": "group", "order_id": fire_control_order_id, "reason": "炮组无效或无舰桥指挥权"})
		return _reject("炮组无效或无舰桥指挥权")
	if selected_mount_id == mount_id: return true
	_release_fire_control_lock("切换炮组")
	selected_mount_id = mount_id
	lock_status = "未锁定"
	EventBus.record("fire_control_group_selected", {"mount_id": mount_id, "order_id": fire_control_order_id, "queued": get_tree().paused})
	EventBus.command_issued.emit("deck_gun.group." + mount_id)
	state_changed.emit()
	return _accept("%s已选中；独立弹药与装填，保持 A1 指派，需重新照射" % active_gun_mount().display_name)

func ship_gun_block_reason(contact_id: String = "") -> String:
	if not GameManager.player_alive or GameManager.mode != "bridge" or not GameManager.ship_afloat:
		return "甲板炮仅可在舰桥指挥"
	if get_tree().paused:
		return "模拟暂停，无法开火"
	if not radar_emitting:
		return "雷达静默中，火控无法跟踪接触"
	if not GameManager.target_identified:
		return "目标尚未确认，禁止开火"
	if fire_control_target_id.is_empty():
		return "甲板炮尚未指派目标：选择 A1 后点击指派目标"
	if not contact_id.is_empty() and contact_id != fire_control_target_id:
		return "射击目标与甲板炮指派不符，请重新指派"
	if not contact_visible or not enemy_alive:
		return "已指派接触当前失联或失能，请重新扫描"
	if repair_seconds_remaining > 0.0:
		return "损管作业中，甲板炮暂时停用"
	if ship_ammo <= 0:
		return "甲板炮弹药耗尽"
	if WorldClock.elapsed_seconds < next_ship_fire_seconds:
		return "甲板炮装填中：还需 %.0f 秒" % ceilf(next_ship_fire_seconds - WorldClock.elapsed_seconds)
	var weapon: WeaponDefinition = DataManager.get_definition(active_gun_mount().weapon_id) as WeaponDefinition
	if WorldClock.elapsed_seconds - last_contact_seconds > 45.0:
		return "接触情报已过期，请重新扫描"
	var aim := last_contact_position_km
	if fire_control_aim_mode == "lead":
		var solution := fire_control_solution()
		if not solution.valid:
			return solution.reason
		aim = solution.aim_position_km
	aim += fire_control_correction_km
	if weapon == null or not is_finite(weapon.projectile_speed_km_per_second) or weapon.projectile_speed_km_per_second <= 0:
		return "甲板炮弹道参数无效"
	if weapon == null or gun_origin_km().distance_to(aim) > weapon.range_km:
		return "提前量瞄准点超出甲板炮射程" if fire_control_aim_mode == "lead" else "最后观测目标超出甲板炮射程"
	var relative := aim - gun_origin_km()
	var bearing := rad_to_deg(atan2(relative.x, -relative.y))
	var bearing_error := absf(wrapf(bearing - gun_center_heading_degrees(), -180.0, 180.0))
	if bearing_error > active_gun_mount().half_arc_degrees:
		return "目标在%s射界外：转向使该炮位朝向 A1" % active_gun_mount().display_name
	if fire_control_locked:
		var lock_reason := fire_control_lock_reason()
		if not lock_reason.is_empty(): return lock_reason
		if absf(wrapf(bearing - turret_heading_degrees, -180.0, 180.0)) > 2.0:
			return "炮塔跟踪中：等待炮口对准"
	if not WorldState.map.can_navigate_segment(gun_origin_km(), aim):
		return "岛屿遮挡射线"
	return ""

func fire_control_lock_reason() -> String:
	if GameManager.mode != "bridge" or not GameManager.ship_afloat or not GameManager.player_alive:
		return "照射需要舰桥指挥权"
	if fire_control_target_id.is_empty() or not enemy_alive or not GameManager.target_identified:
		return "照射需要已识别的指派目标"
	if not radar_emitting or not contact_visible:
		return "照射中断：重新开机并扫描"
	if WorldClock.elapsed_seconds - last_contact_seconds > LOCK_MEMORY_SECONDS:
		return "照射过期：8 秒内复测，再重新锁定"
	return ""

func set_fire_control_lock(enabled: bool) -> bool:
	var reason := fire_control_lock_reason() if enabled else ("照射需要舰桥指挥权" if GameManager.mode != "bridge" or not GameManager.player_alive or not GameManager.ship_afloat else "")
	if not reason.is_empty():
		EventBus.record("fire_control_rejected", {"action": "lock", "order_id": fire_control_order_id, "reason": reason})
		return _reject(reason)
	if enabled == fire_control_locked: return true
	if enabled:
		fire_control_locked = true
		lock_status = "持续照射"
		EventBus.record("fire_control_locked", {"order_id": fire_control_order_id, "mount_id": selected_mount_id, "target_id": fire_control_target_id, "queued": get_tree().paused})
	else:
		_release_fire_control_lock("手动解除")
	EventBus.command_issued.emit(fire_control_order_id + ".lock")
	state_changed.emit()
	return _accept("持续照射：每 8 秒内复测；炮塔跟踪，不自动开火" if enabled else "恢复手动射界")

func _release_fire_control_lock(reason: String, simulation_seconds: float = -1.0) -> void:
	if not fire_control_locked: return
	fire_control_locked = false
	lock_status = "失锁 / " + reason
	EventBus.record("fire_control_lock_lost", {"order_id": fire_control_order_id, "mount_id": selected_mount_id, "target_id": fire_control_target_id, "reason": reason}, simulation_seconds)

func _advance_fire_control_lock(delta: float) -> void:
	if not fire_control_locked: return
	var reason := fire_control_lock_reason()
	if not reason.is_empty():
		_release_fire_control_lock(reason)
		return
	var aim := last_contact_position_km
	if fire_control_aim_mode == "lead":
		var solution := fire_control_solution()
		if not solution.valid:
			lock_status = "照射 / 等待运动解"
			return
		aim = solution.aim_position_km
	aim += fire_control_correction_km
	var relative := aim - gun_origin_km()
	var bearing := rad_to_deg(atan2(relative.x, -relative.y))
	bearing = gun_center_heading_degrees() + clampf(wrapf(bearing - gun_center_heading_degrees(), -180, 180), -active_gun_mount().half_arc_degrees, active_gun_mount().half_arc_degrees)
	var error := wrapf(bearing - turret_heading_degrees, -180.0, 180.0)
	turret_heading_degrees = wrapf(turret_heading_degrees + clampf(error, -TURRET_RATE_DEGREES * delta, TURRET_RATE_DEGREES * delta), 0, 360)
	turret_heading_degrees = wrapf(gun_center_heading_degrees() + clampf(wrapf(turret_heading_degrees - gun_center_heading_degrees(), -180, 180), -active_gun_mount().half_arc_degrees, active_gun_mount().half_arc_degrees), 0, 360)
	lock_status = "照射 / 已对准" if absf(wrapf(bearing - turret_heading_degrees, -180, 180)) <= 2 else "照射 / 炮塔跟踪"

func set_fire_control_aim_mode(value: String) -> bool:
	if value not in ["observed", "lead"] or GameManager.mode != "bridge" or not GameManager.player_alive or not GameManager.ship_afloat:
		EventBus.record("fire_control_rejected", {"action": "aim_mode", "reason": "瞄准模式无效或无舰桥指挥权", "order_id": fire_control_order_id})
		return _reject("瞄准模式无效或无舰桥指挥权")
	if value == fire_control_aim_mode:
		return true
	fire_control_aim_mode = value
	EventBus.record("fire_control_aim_mode_changed", {"aim_mode": value, "weapon_id": active_gun_mount().weapon_id, "target_id": fire_control_target_id, "order_id": fire_control_order_id, "queued": get_tree().paused})
	EventBus.command_issued.emit("deck_gun.aim." + value)
	state_changed.emit()
	return _accept(("提前量瞄准：运动解算已就绪" if fire_control_solution().valid else "提前量瞄准：等待有效运动解算") if value == "lead" else "最后观测瞄准：不补偿目标运动")

func set_ammunition(ammunition_id: String) -> bool:
	if GameManager.mode != "bridge" or not GameManager.player_alive or not GameManager.ship_afloat or ammunition_id not in ["ammo.ap", "ammo.sap", "ammo.he"]:
		EventBus.record("fire_control_rejected", {"action": "ammunition", "order_id": fire_control_order_id, "reason": "弹种无效或无舰桥指挥权"})
		return _reject("弹种无效或无舰桥指挥权")
	if ammunition_id == selected_ammunition_id: return true
	selected_ammunition_id = ammunition_id
	EventBus.record("fire_control_ammunition_changed", {"ammunition_id": ammunition_id, "mount_id": selected_mount_id, "order_id": fire_control_order_id, "queued": get_tree().paused})
	EventBus.command_issued.emit("deck_gun.ammunition." + ammunition_id)
	state_changed.emit()
	return _accept("下一发使用 %s；换弹不刷新装填，不改变已发射炮弹" % (DataManager.get_definition(ammunition_id).display_name))

func enemy_armor_mm() -> float:
	var contact := DataManager.get_definition(CONTACT_ID) as ContactDefinition
	var ship := DataManager.get_definition(contact.identified_ship_id) as ShipDefinition
	return ship.armor_mm

func fire_control_solution() -> Dictionary:
	if not radar_emitting or not contact_visible or not enemy_alive or not GameManager.ship_afloat or not GameManager.player_alive or GameManager.mode in ["settlement", "campaign_failed"] or not GameManager.target_identified:
		return {"valid": false, "reason": "运动解算不可用：需要已识别的有效雷达接触"}
	var weapon: WeaponDefinition = DataManager.get_definition(active_gun_mount().weapon_id) as WeaponDefinition
	return _motion.solve(gun_origin_km(), WorldClock.elapsed_seconds, weapon.projectile_speed_km_per_second if weapon != null else 0.0)

func adjust_fire_control_correction(direction: String) -> bool:
	if GameManager.mode != "bridge" or not GameManager.player_alive or not GameManager.ship_afloat or fire_control_target_id.is_empty() or direction not in ["left", "right", "short", "long", "reset"]:
		EventBus.record("fire_control_rejected", {"action": "correction", "order_id": fire_control_order_id, "reason": "校射需要舰桥指派及有效方向"})
		return _reject("校射需要舰桥指派及有效方向")
	var forward := (last_contact_position_km - WorldState.ship_position_km).normalized()
	var side := Vector2(-forward.y, forward.x)
	var offsets := {"left": -side, "right": side, "short": -forward, "long": forward}
	var candidate: Vector2 = Vector2.ZERO if direction == "reset" else fire_control_correction_km + offsets[direction] * 0.05
	if candidate.length() > 1.000001:
		EventBus.record("fire_control_rejected", {"action": "correction", "order_id": fire_control_order_id, "reason": "校射修正不能超过 1000 米"})
		return _reject("校射修正不能超过 1000 米")
	fire_control_correction_km = candidate
	EventBus.record("fire_control_correction", {"order_id": fire_control_order_id, "target_id": fire_control_target_id, "direction": direction, "correction_km": candidate, "queued": get_tree().paused})
	EventBus.command_issued.emit(fire_control_order_id + ".correction")
	state_changed.emit()
	return _accept("校射修正 %.0f 米；下一发采用，已发射炮弹保持原落点" % (candidate.length() * 1000))

func _advance_gun_projectiles(delta: float, total_seconds: float, observer_origin: Vector2) -> void:
	var cursor := total_seconds - delta
	while not projectiles.is_empty() and float(projectiles[0].impact_seconds) <= total_seconds:
		var shot: Dictionary = projectiles.pop_front()
		_advance_enemy(maxf(0, float(shot.impact_seconds) - cursor))
		cursor = float(shot.impact_seconds)
		var observer := observer_origin.lerp(WorldState.ship_position_km, clampf((cursor - (total_seconds - delta)) / delta, 0, 1))
		var age := cursor - last_contact_seconds
		var observed: bool = radar_emitting and contact_visible and age >= 0 and age <= 45 and observer.distance_to(WorldState.contact_position_km) <= SCAN_RANGE_KM and WorldState.map.can_navigate_segment(observer, WorldState.contact_position_km)
		var impact_position: Vector2 = shot.aim_position_km
		var error := impact_position - WorldState.contact_position_km
		var hit := enemy_alive and error.length() <= GUN_HIT_RADIUS_KM
		var result := "hit" if hit else "near_miss" if enemy_alive and error.length() <= GUN_NEAR_MISS_RADIUS_KM else "miss"
		last_gun_impact = {"shot_id": shot.shot_id, "order_id": shot.order_id, "mount_id": shot.mount_id, "aim_position_km": shot.aim_position_km, "impact_seconds": cursor, "observed": observed, "result": result if observed else "unobserved"}
		if observed:
			last_gun_impact.error_km = error
			last_gun_impact.error_meters = error.length() * 1000
		var damage_result := AmmunitionDefinition.resolve(shot.ammunition, enemy_armor_mm()) if hit else {"damage": 0.0, "outcome": "未命中"}
		last_gun_impact.ammunition_id = shot.ammunition.id
		if observed and hit:
			last_gun_impact.damage = damage_result.damage
			last_gun_impact.armor_outcome = damage_result.outcome
		EventBus.record("gun_projectile_impact", last_gun_impact, cursor)
		if hit:
			_damage_enemy(damage_result.damage, "deck_gun" if observed else "deck_gun_unobserved", cursor)
		_feedback("甲板炮命中 A1" if observed and hit else "近失弹：偏差 %.0f 米，可修正下一发" % (error.length() * 1000) if observed and result == "near_miss" else "炮弹未命中：偏差 %.0f 米" % (error.length() * 1000) if observed else "炮弹已到达，结果未观测；重新扫描")
	_advance_enemy(maxf(0, total_seconds - cursor))

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
	_navigation_arrived = false
	EventBus.record("aircraft_navigation_command", {"destination": "manual", "heading_degrees": aircraft_heading_degrees})
	state_changed.emit()
	return _accept("飞机转向 %03d°" % roundi(aircraft_heading_degrees))

func set_aircraft_destination(destination: String) -> bool:
	if not aircraft_airborne or (GameManager.mode != "cockpit" and GameManager.mode != "returning"):
		return _reject("飞机尚未升空")
	if destination != "contact" and destination != "ship" and destination != "airfield":
		return false
	if destination == "ship" and not GameManager.ship_afloat:
		return _reject("母舰已沉没，请转往友方机场")
	if destination == "contact" and not enemy_alive:
		return _reject("A1 已失去活动迹象，请选择回收点或航点")
	aircraft_destination = destination
	_navigation_arrived = false
	EventBus.record("aircraft_navigation_command", {"destination": destination})
	state_changed.emit()
	var target_names := {"contact": "A1", "ship": "母舰", "airfield": "友方机场"}
	return _accept("飞机导航目标：%s" % target_names[destination])

func set_aircraft_waypoint(position_km: Vector2) -> bool:
	if not aircraft_airborne or GameManager.mode not in ["cockpit", "returning"]:
		return _reject("航点只能在空中下达")
	if not position_km.is_finite() or WorldState.map == null or not Rect2(Vector2.ZERO, WorldState.map.MAP_SIZE_KM).has_point(position_km):
		return _reject("航点不在有效海域内")
	aircraft_waypoint_km = position_km
	aircraft_destination = "waypoint"
	_navigation_arrived = false
	EventBus.record("aircraft_navigation_command", {"destination": "waypoint", "position_km": position_km})
	state_changed.emit()
	return _accept("航点已下达：E %.1f / S %.1f km" % [position_km.x, position_km.y])

func navigation_solution(destination: String = "") -> Dictionary:
	var chosen := aircraft_destination if destination.is_empty() else destination
	var target := aircraft_position_km
	var radius := 0.0
	var available := true
	match chosen:
		"contact":
			target = WorldState.contact_position_km
			available = enemy_alive
		"ship":
			target = WorldState.ship_position_km
			radius = 2.0
			available = GameManager.ship_afloat
		"airfield":
			target = airfield_position_km
			radius = 3.0
		"waypoint": target = aircraft_waypoint_km
		_: available = false
	var distance := aircraft_position_km.distance_to(target)
	var speed := aircraft_speed_knots * KNOT_TO_KM_PER_SECOND
	var eta := maxf(0.0, distance - radius) / speed if available and speed > 0.0 else INF
	return {"destination": chosen, "position_km": target, "available": available, "distance_km": distance, "eta_seconds": eta, "fuel_margin_seconds": aircraft_fuel_seconds - eta, "reachable": available and aircraft_fuel_seconds > eta, "in_window": available and distance <= radius, "ship_speed_ok": chosen != "ship" or WorldState.ship_speed_knots <= 12.0}

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

func begin_return(destination: String = "") -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "cockpit" or not aircraft_airborne:
		return _reject("当前无法进入返航流程")
	var previous_destination := aircraft_destination
	var chosen := destination
	if chosen.is_empty():
		chosen = aircraft_destination if aircraft_destination in ["ship", "airfield"] else "ship" if GameManager.ship_afloat else "airfield"
	if chosen not in ["ship", "airfield"] or (chosen == "ship" and not GameManager.ship_afloat):
		return _reject("回收地点不可用，请选择友方机场")
	aircraft_destination = chosen
	_navigation_arrived = false
	if not GameManager.change_mode("returning"):
		aircraft_destination = previous_destination
		return false
	EventBus.record("aircraft_navigation_command", {"destination": chosen})
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
	_navigation_arrived = false
	EventBus.record("return_cancelled", {})
	state_changed.emit()
	return _accept("返航已取消；保持当前航向，燃油不会恢复。可重新导航 A1 继续侦察")

func land_aircraft(site: String = "") -> bool:
	if not _action_allowed():
		return false
	if GameManager.mode != "returning" or not aircraft_airborne:
		return _reject("飞机尚未进入返航状态")
	var ship_distance := aircraft_position_km.distance_to(WorldState.ship_position_km)
	var airfield_distance := aircraft_position_km.distance_to(airfield_position_km)
	var chosen := site
	if chosen.is_empty():
		if aircraft_destination in ["ship", "airfield"]:
			chosen = "ship" if aircraft_destination == "ship" else "friendly_airfield"
		else:
			chosen = "ship" if GameManager.ship_afloat and ship_distance <= 2.0 else "friendly_airfield"
	if chosen == "ship" and GameManager.ship_afloat and ship_distance <= 2.0:
		if WorldState.ship_speed_knots > 12.0:
			return _reject("母舰航速超过 12 kn，无法回收")
	elif chosen == "friendly_airfield" and airfield_distance <= 3.0:
		pass
	else:
		return _reject("尚未到达回收点：母舰 %.1f km / 机场 %.1f km" % [ship_distance, airfield_distance])
	var previous_destination := aircraft_destination
	aircraft_airborne = false
	aircraft_destination = "manual"
	if not GameManager.recover_player(chosen):
		aircraft_airborne = true
		aircraft_destination = previous_destination
		return _reject("回收条件不满足")
	EventBus.record("aircraft_landed", {"site": chosen})
	state_changed.emit()
	return _accept("飞机已安全回收：%s" % ("母舰" if chosen == "ship" else "友方机场"))

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
	var observer_origin := _last_tick_ship_position
	_last_tick_ship_position = WorldState.ship_position_km
	_last_clock_seconds = total_seconds
	if delta <= 0.0 or GameManager.mode == "settlement" or GameManager.mode == "campaign_failed":
		return
	_advance_gun_projectiles(delta, total_seconds, observer_origin)
	_advance_fire_control_lock(delta)
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
		_clear_fire_control("ship_sunk")
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
	# Lost recovery platforms cannot leave the navigator following a sunk ship.
	if aircraft_destination == "ship" and not GameManager.ship_afloat:
		aircraft_destination = "airfield"
		_navigation_arrived = false
		EventBus.record("aircraft_navigation_diverted", {"reason": "ship_sunk", "destination": "airfield"})
		_feedback("母舰已沉没，导航已转向友方机场；请检查燃油")
	var solution := navigation_solution()
	if solution.available:
		var target: Vector2 = solution.position_km
		var relative := target - aircraft_position_km
		if relative.length() > 0.001:
			aircraft_heading_degrees = fposmod(rad_to_deg(atan2(relative.x, -relative.y)), 360.0)
	var direction := Vector2(sin(deg_to_rad(aircraft_heading_degrees)), -cos(deg_to_rad(aircraft_heading_degrees)))
	var distance := aircraft_speed_knots * KNOT_TO_KM_PER_SECOND * delta
	if solution.available:
		distance = minf(distance, float(solution.distance_km))
	aircraft_position_km += direction * distance
	if solution.available and aircraft_position_km.distance_to(solution.position_km) <= 0.01 and not _navigation_arrived:
		_navigation_arrived = true
		EventBus.record("aircraft_navigation_arrived", {"destination": aircraft_destination})
		_feedback("已到达导航点；自动保持点位仍消耗燃油，回收须点击降落")
	var warning_level := 2 if aircraft_fuel_seconds <= 30.0 else 1 if aircraft_fuel_seconds <= 120.0 else 0
	if warning_level > _fuel_warning_level:
		_fuel_warning_level = warning_level
		EventBus.record("aircraft_fuel_warning", {"seconds_remaining": aircraft_fuel_seconds, "level": warning_level})
		_feedback("燃油紧急：不足 30 秒，立即寻找回收窗口" if warning_level == 2 else "燃油预警：不足两分钟，请返航回收")

func _damage_enemy(amount: float, source: String, simulation_seconds: float = -1.0) -> void:
	enemy_health = maxf(0.0, enemy_health - amount)
	EventBus.damage_reported.emit(CONTACT_ID)
	EventBus.record("enemy_damaged", {"health": enemy_health, "source": source}, simulation_seconds)
	if enemy_health <= 0.0:
		enemy_alive = false
		enemy_tracking_ship = false
		enemy_alert_until_seconds = 0.0
		contact_visible = false
		_clear_fire_control("target_destroyed", simulation_seconds)
		EventBus.record("enemy_destroyed", {"id": CONTACT_ID}, simulation_seconds)

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
