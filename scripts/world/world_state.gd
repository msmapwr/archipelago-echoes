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
var ship_draft_m := 4.0
var ship_grounded := false
var last_navigation_impact: Dictionary = {}
var _risk_key: Array = []
var _risk_cache: Dictionary = {}
var _navigation_warning := ""

func _ready() -> void:
	WorldClock.time_advanced.connect(_on_world_time_advanced)
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
	ship_heading_degrees = fposmod(heading_degrees, 360.0)
	ship_speed_knots = speed_knots
	ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	EventBus.command_issued.emit("ship_navigation")
	EventBus.record("ship_navigation_command", {"heading_degrees": ship_heading_degrees, "speed_knots": ship_speed_knots})
	_record_navigation_warning()
	return true

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
	var direction := Vector2(sin(deg_to_rad(ship_heading_degrees)), -cos(deg_to_rad(ship_heading_degrees)))
	var destination := ship_position_km + direction * ship_speed_knots * KNOT_TO_KM_PER_SECOND * delta
	var impact := Hazards.trace(ship_position_km, destination, ship_draft_m, map.depth_at, Rect2(Vector2.ZERO, map.MAP_SIZE_KM), ship_grounded)
	if not impact.is_empty():
		var speed := ship_speed_knots
		impact.origin_position_km = ship_position_km
		impact.requested_position_km = destination
		impact.step_seconds = delta
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
		return
	ship_position_km = destination
	if ship_grounded and map.depth_at(destination) >= ship_draft_m + 1.0:
		ship_grounded = false
		EventBus.record("ship_refloated", {"position_km":destination})
	_record_navigation_warning()
	ship_position_changed.emit(ship_position_km)

func _record_navigation_warning() -> void:
	var warning: String = navigation_risk().warning
	if warning != _navigation_warning:
		_navigation_warning = warning
		EventBus.record("navigation_warning_changed", {"warning":warning, "position_km":ship_position_km})

func navigation_risk() -> Dictionary:
	var key := [ship_position_km, ship_heading_degrees, ship_speed_knots, ship_draft_m, ship_grounded, scenario_seed]
	if key == _risk_key: return _risk_cache
	_risk_key = key
	_risk_cache = _compute_navigation_risk()
	return _risk_cache

func _compute_navigation_risk() -> Dictionary:
	if map == null: return {"warning":"", "depth_m":0.0}
	var depth: float = map.depth_at(ship_position_km)
	if ship_grounded: return {"warning":"搁浅 / 已停车：转向深水，以不超过 4 kn 脱浅；损管不会自动脱浅。", "depth_m":depth}
	if ship_speed_knots > 0:
		var ahead := ship_position_km + Vector2.UP.rotated(deg_to_rad(ship_heading_degrees)) * ship_speed_knots * KNOT_TO_KM_PER_SECOND * 60
		var risk := Hazards.trace(ship_position_km, ahead, ship_draft_m + 2, map.depth_at, Rect2(Vector2.ZERO, map.MAP_SIZE_KM))
		if not risk.is_empty(): return {"warning":"航行警报：前方浅水 / 岸线，请减速转向。" if risk.kind != "boundary" else "前方为海图边界，请转向。", "depth_m":depth}
	return {"warning":"", "depth_m":depth}
