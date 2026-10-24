extends Node

signal ship_position_changed(position_km: Vector2)
signal ship_command_changed(heading_degrees: float, speed_knots: float)
signal navigation_blocked(position_km: Vector2)
signal navigation_impact(impact: Dictionary)

const ArchipelagoMap = preload("res://scripts/world/archipelago_map.gd")
const FIRST_SCENARIO_SEED := 270928
const KNOT_TO_KM_PER_SECOND := 1.852 / 3600.0
const Hazards = preload("res://scripts/world/navigation_hazards.gd")

var map: RefCounted
var ship_position_km: Vector2 = Vector2.ZERO
var contact_position_km: Vector2 = Vector2.ZERO
var ship_heading_degrees: float = 0.0
var ship_speed_knots: float = 0.0
var ship_max_speed_knots: float = 0.0
var _last_clock_seconds: float = 0.0
var scenario_seed: int = FIRST_SCENARIO_SEED
var generation_error: String = ""
const MAX_SHIP_ROUTE_POINTS := 8
var ship_route_points: Array[Vector2] = []
var ship_route_reached := 0
var ship_route_revision := 0
var ship_waypoint_active := false
var ship_waypoint_km := Vector2.ZERO
var ship_waypoint_status := "manual"
var ship_waypoint_order_id := ""
var _waypoint_sequence := 0
var ship_draft_m := 4.0
var ship_grounded := false
var last_navigation_impact: Dictionary = {}
var _risk_key: Array = []
var _risk_cache: Dictionary = {}
var _navigation_warning := ""

func _ready() -> void:
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	EventBus.mode_changed.connect(_on_mode_changed)
	load_first_scenario()

func load_first_scenario(map_seed: int = FIRST_SCENARIO_SEED) -> bool:
	generation_error = ""
	if map_seed < 0 or map_seed > 2147483647:
		generation_error = "海域种子必须在 0–2147483647 之间。"
		DebugLog.write("warning", "generation_rejected", {"seed": map_seed, "reason": generation_error}, true)
		return false
	var contact: ContactDefinition = DataManager.get_definition("contact.alpha") as ContactDefinition
	var ship: ShipDefinition = DataManager.get_definition("ship.haven") as ShipDefinition
	if contact == null or ship == null:
		generation_error = "首关舰艇或接触数据缺失。"
		DebugLog.write("error", "generation_rejected", {"seed": map_seed, "reason": generation_error})
		push_error("[WorldState] first scenario ship or contact is missing")
		return false
	var candidate = ArchipelagoMap.new(map_seed, contact.bearing_degrees, contact.range_km)
	if not candidate.is_water(candidate.ship_start_km) or not candidate.is_water(candidate.contact_position_km) or not candidate.can_navigate_segment(candidate.ship_start_km, candidate.ship_start_km + Vector2(0, preload("res://scripts/world/harbor_navigation.gd").EXIT_Y_KM)):
		generation_error = "海域未通过出生点与离港航道校验，请更换种子重试。"
		DebugLog.write("warning", "generation_rejected", {"seed": map_seed, "reason": generation_error}, true)
		return false
	map = candidate
	scenario_seed = map_seed
	ship_position_km = map.ship_start_km
	contact_position_km = map.contact_position_km
	ship_heading_degrees = 0.0
	ship_speed_knots = 0.0
	ship_max_speed_knots = ship.max_speed_knots
	ship_draft_m = ship.draft_m
	ship_grounded = false
	ship_waypoint_active = false
	ship_route_points.clear()
	ship_route_reached = 0
	ship_route_revision = 0
	ship_waypoint_km = Vector2.ZERO
	ship_waypoint_status = "manual"
	ship_waypoint_order_id = ""
	_waypoint_sequence = 0
	last_navigation_impact = {}
	_risk_key.clear()
	_navigation_warning = ""
	_last_clock_seconds = WorldClock.elapsed_seconds
	ship_position_changed.emit(ship_position_km)
	ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	DebugLog.write("info", "world_generated", {"seed": scenario_seed}, true)
	return true

func set_ship_command(heading_degrees: float, speed_knots: float) -> bool:
	if speed_knots > 0 and (not GameManager.ship_afloat or GameManager.mode in ["settlement", "campaign_failed"]): return false
	if ship_grounded and speed_knots > Hazards.REFLOAT_SPEED_KNOTS:
		EventBus.record("ship_navigation_rejected", {"reason":"搁浅脱险限速 4 kn；转向深水后低速驶离。"})
		return false
	if map == null or not is_finite(heading_degrees) or not is_finite(speed_knots):
		DebugLog.write("warning", "navigation_rejected", {"reason": "invalid map or nonfinite command"})
		return false
	if speed_knots < 0.0 or speed_knots > ship_max_speed_knots:
		DebugLog.write("warning", "navigation_rejected", {"reason": "speed outside ship limits", "speed_knots": speed_knots})
		return false
	cancel_ship_waypoint("manual_override", false)
	ship_waypoint_status = "manual"
	ship_heading_degrees = fposmod(heading_degrees, 360.0)
	ship_speed_knots = speed_knots
	ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	EventBus.command_issued.emit("ship_navigation")
	EventBus.record("ship_navigation_command", {"heading_degrees": ship_heading_degrees, "speed_knots": ship_speed_knots})
	_record_navigation_warning()
	return true

func ship_waypoint_reason(target: Vector2, append: bool = false) -> String:
	if map == null or not is_finite(target.x) or not is_finite(target.y): return "航点坐标无效"
	if not Rect2(Vector2.ZERO, map.MAP_SIZE_KM).has_point(target): return "航点超出海图边界"
	if ship_grounded: return "搁浅时请先手动低速脱浅"
	if append and ship_waypoint_active and ship_route_points.size() >= MAX_SHIP_ROUTE_POINTS: return "航线最多保留 8 个待执行航点"
	var origin := ship_route_points[-1] if append and ship_waypoint_active else ship_position_km
	if target.distance_to(origin) < 0.05: return "相邻航点距离至少 50 m"
	if not Hazards.trace(origin, target, ship_draft_m + 2.0, map.depth_at, Rect2(Vector2.ZERO, map.MAP_SIZE_KM)).is_empty():
		return "直线航路穿过浅水或岸线；请另选航点（要求 2 m 余深）"
	return ""

func set_ship_waypoint(target: Vector2, append: bool = false) -> bool:
	var reason := ship_waypoint_reason(target, append)
	if not GameManager.ship_afloat or not GameManager.player_alive or GameManager.mode not in ["bridge", "configuration", "switching"]:
		reason = "航点指派需要舰桥航行控制权"
	if not reason.is_empty():
		EventBus.record("ship_waypoint_rejected", {"reason":reason, "order_id":ship_waypoint_order_id, "append":append})
		return false
	if append and ship_waypoint_active:
		ship_route_points.append(target)
		ship_route_revision += 1
		EventBus.record("ship_route_appended", {"order_id":ship_waypoint_order_id, "revision":ship_route_revision, "position_km":target, "remaining":ship_route_points.size(), "queued":get_tree().paused})
		ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
		return true
	cancel_ship_waypoint("replaced", false)
	_waypoint_sequence += 1
	ship_waypoint_order_id = "ship_route.%03d" % _waypoint_sequence
	ship_route_points.assign([target])
	ship_route_reached = 0
	ship_route_revision = 1
	ship_waypoint_active = true
	ship_waypoint_status = "enroute"
	_point_ship_at_next_waypoint()
	if ship_speed_knots <= 0: ship_speed_knots = minf(10.0, ship_max_speed_knots)
	EventBus.record("ship_waypoint_ordered", {"order_id":ship_waypoint_order_id, "position_km":target, "speed_knots":ship_speed_knots, "queued":get_tree().paused})
	EventBus.command_issued.emit(ship_waypoint_order_id)
	ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	_record_navigation_warning()
	return true

func _point_ship_at_next_waypoint() -> void:
	ship_waypoint_km = ship_route_points[0]
	var offset := ship_waypoint_km - ship_position_km
	ship_heading_degrees = fposmod(rad_to_deg(atan2(offset.x, -offset.y)), 360.0)

func remove_last_ship_waypoint() -> bool:
	if not ship_waypoint_active: return false
	if ship_route_points.size() == 1: return cancel_ship_waypoint("last_point_removed")
	var removed: Vector2 = ship_route_points.pop_back()
	ship_route_revision += 1
	EventBus.record("ship_route_trimmed", {"order_id":ship_waypoint_order_id, "revision":ship_route_revision, "position_km":removed, "remaining":ship_route_points.size()})
	ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	return true

func cancel_ship_waypoint(reason: String = "player_cancelled", stop: bool = true) -> bool:
	if not ship_waypoint_active: return false
	ship_waypoint_active = false
	ship_route_points.clear()
	ship_waypoint_status = "interrupted" if reason in ["hazard", "ship_sunk"] else "cancelled"
	if stop: ship_speed_knots = 0
	EventBus.record("ship_waypoint_cancelled", {"order_id":ship_waypoint_order_id, "reason":reason, "position_km":ship_position_km})
	if stop: ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	return true

func ship_route_solution() -> Dictionary:
	var distance := 0.0
	var previous := ship_position_km
	for point in ship_route_points:
		distance += previous.distance_to(point)
		previous = point
	return {"active":ship_waypoint_active, "status":ship_waypoint_status, "position_km":ship_waypoint_km, "order_id":ship_waypoint_order_id, "distance_km":distance, "points":ship_route_points.duplicate(), "remaining":ship_route_points.size(), "reached":ship_route_reached, "revision":ship_route_revision, "eta_seconds":distance / (ship_speed_knots * KNOT_TO_KM_PER_SECOND) if ship_waypoint_active and ship_speed_knots > 0 else 0.0}

func _on_mode_changed(_previous: String, current: String) -> void:
	if current in ["settlement", "campaign_failed", "recovered"]:
		cancel_ship_waypoint("action_ended")

func contact_bearing_degrees() -> float:
	var relative := contact_position_km - ship_position_km
	return fposmod(rad_to_deg(atan2(relative.x, -relative.y)), 360.0)

func navigation_speed_step() -> float:
	return 2.0 if ship_grounded else 5.0

func navigation_speed_limit() -> float:
	return minf(ship_max_speed_knots, Hazards.REFLOAT_SPEED_KNOTS) if ship_grounded else ship_max_speed_knots

func contact_range_km() -> float:
	return ship_position_km.distance_to(contact_position_km)

func _on_world_time_advanced(total_seconds: float) -> void:
	var delta := total_seconds - _last_clock_seconds
	_last_clock_seconds = total_seconds
	if delta <= 0.0 or ship_speed_knots <= 0.0 or map == null or not GameManager.ship_afloat or GameManager.mode in ["settlement", "campaign_failed"]:
		return
	var remaining := delta
	# Every completed leg consumes one of at most eight pending points.
	while remaining > 0.000001 and ship_speed_knots > 0:
		var direction := Vector2(sin(deg_to_rad(ship_heading_degrees)), -cos(deg_to_rad(ship_heading_degrees)))
		var speed_km_s := ship_speed_knots * KNOT_TO_KM_PER_SECOND
		var leg_seconds := remaining
		var arriving := false
		if ship_waypoint_active:
			var seconds_to_point := ship_position_km.distance_to(ship_waypoint_km) / speed_km_s
			arriving = remaining >= seconds_to_point
			if arriving: leg_seconds = seconds_to_point
		var destination := ship_waypoint_km if arriving else ship_position_km + direction * speed_km_s * leg_seconds
		if not _move_ship_segment(destination, leg_seconds): return
		remaining = maxf(0, remaining - leg_seconds)
		if not arriving: break
		ship_route_points.pop_front()
		ship_route_reached += 1
		var arrival_seconds := total_seconds - remaining
		var details := {"order_id":ship_waypoint_order_id, "revision":ship_route_revision, "index":ship_route_reached, "position_km":ship_position_km, "remaining":ship_route_points.size()}
		if ship_route_points.is_empty():
			ship_waypoint_active = false
			ship_waypoint_status = "arrived"
			ship_speed_knots = 0
			EventBus.record("ship_waypoint_arrived", details, arrival_seconds)
		else:
			_point_ship_at_next_waypoint()
			EventBus.record("ship_waypoint_reached", details, arrival_seconds)
		ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	_record_navigation_warning()
	ship_position_changed.emit(ship_position_km)

func _move_ship_segment(destination: Vector2, seconds: float) -> bool:
	var impact := Hazards.trace(ship_position_km, destination, ship_draft_m, map.depth_at, Rect2(Vector2.ZERO, map.MAP_SIZE_KM), ship_grounded)
	if not impact.is_empty():
		var speed := ship_speed_knots
		cancel_ship_waypoint("hazard", false)
		impact.origin_position_km = ship_position_km
		impact.requested_position_km = destination
		impact.step_seconds = seconds
		# Map boundary is an interface limit, not a physical coastline.
		if impact.kind != "boundary": ship_position_km = impact.position
		ship_speed_knots = 0.0
		ship_grounded = impact.kind != "boundary"
		impact.speed_knots = speed
		impact.damage = Hazards.impact_damage(speed, impact.kind)
		last_navigation_impact = impact.duplicate(true)
		_record_navigation_warning()
		ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
		ship_position_changed.emit(ship_position_km)
		navigation_blocked.emit(ship_position_km)
		EventBus.record("ship_navigation_blocked", {"position_km": ship_position_km})
		if impact.kind != "boundary":
			EventBus.record("ship_grounded" if impact.kind == "grounding" else "ship_collision", impact)
			navigation_impact.emit(impact)
		return false
	ship_position_km = destination
	if ship_grounded and map.depth_at(destination) >= ship_draft_m + 1.0:
		ship_grounded = false
		EventBus.record("ship_refloated", {"position_km":destination})
	return true

func _record_navigation_warning() -> void:
	var warning: String = navigation_risk().warning
	if warning != _navigation_warning:
		_navigation_warning = warning
		EventBus.record("navigation_warning_changed", {"warning":warning, "position_km":ship_position_km})

func navigation_risk() -> Dictionary:
	var key := [ship_position_km, ship_heading_degrees, ship_speed_knots, ship_draft_m, ship_grounded, scenario_seed, ship_route_revision, ship_waypoint_active]
	if key == _risk_key: return _risk_cache
	_risk_key = key
	_risk_cache = _compute_navigation_risk()
	return _risk_cache

func _compute_navigation_risk() -> Dictionary:
	if map == null: return {"warning":"", "depth_m":0.0}
	var depth: float = map.depth_at(ship_position_km)
	if ship_grounded: return {"warning":"搁浅 / 已停车：转向深水，以不超过 4 kn 脱浅；损管不会自动脱浅。", "depth_m":depth}
	if ship_speed_knots > 0:
		var distance_left := ship_speed_knots * KNOT_TO_KM_PER_SECOND * 60
		var ahead := ship_position_km + Vector2.UP.rotated(deg_to_rad(ship_heading_degrees)) * distance_left
		var targets: Array[Vector2] = []
		if ship_waypoint_active: targets.assign(ship_route_points)
		else: targets.append(ahead)
		var previous := ship_position_km
		for target in targets:
			var offset := target - previous
			var endpoint := previous + offset.limit_length(distance_left)
			var risk := Hazards.trace(previous, endpoint, ship_draft_m + 2, map.depth_at, Rect2(Vector2.ZERO, map.MAP_SIZE_KM))
			if not risk.is_empty(): return {"warning":"航行警报：前方浅水 / 岸线，请减速转向。" if risk.kind != "boundary" else "前方为海图边界，请转向。", "depth_m":depth}
			distance_left -= offset.length()
			if distance_left <= 0: break
			previous = target
	return {"warning":"", "depth_m":depth}
