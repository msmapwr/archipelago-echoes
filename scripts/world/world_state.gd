extends Node

signal ship_position_changed(position_km: Vector2)
signal ship_command_changed(heading_degrees: float, speed_knots: float)
signal navigation_blocked(position_km: Vector2)

const ArchipelagoMap = preload("res://scripts/world/archipelago_map.gd")
const FIRST_SCENARIO_SEED := 270928
const KNOT_TO_KM_PER_SECOND := 1.852 / 3600.0

var map: RefCounted
var ship_position_km: Vector2 = Vector2.ZERO
var contact_position_km: Vector2 = Vector2.ZERO
var ship_heading_degrees: float = 0.0
var ship_speed_knots: float = 0.0
var ship_max_speed_knots: float = 0.0
var _last_clock_seconds: float = 0.0
var scenario_seed: int = FIRST_SCENARIO_SEED
var generation_error: String = ""

func _ready() -> void:
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	load_first_scenario()

func load_first_scenario(map_seed: int = FIRST_SCENARIO_SEED) -> bool:
	generation_error = ""
	if map_seed < 0 or map_seed > 2147483647:
		generation_error = "海域种子必须在 0–2147483647 之间。"
		return false
	var contact: ContactDefinition = DataManager.get_definition("contact.alpha") as ContactDefinition
	var ship: ShipDefinition = DataManager.get_definition("ship.haven") as ShipDefinition
	if contact == null or ship == null:
		generation_error = "首关舰艇或接触数据缺失。"
		push_error("[WorldState] first scenario ship or contact is missing")
		return false
	var candidate = ArchipelagoMap.new(map_seed, contact.bearing_degrees, contact.range_km)
	if not candidate.is_water(candidate.ship_start_km) or not candidate.is_water(candidate.contact_position_km) or not candidate.can_navigate_segment(candidate.ship_start_km, candidate.ship_start_km + Vector2(0, preload("res://scripts/world/harbor_navigation.gd").EXIT_Y_KM)):
		generation_error = "海域未通过出生点与离港航道校验，请更换种子重试。"
		return false
	map = candidate
	scenario_seed = map_seed
	ship_position_km = map.ship_start_km
	contact_position_km = map.contact_position_km
	ship_heading_degrees = 0.0
	ship_speed_knots = 0.0
	ship_max_speed_knots = ship.max_speed_knots
	_last_clock_seconds = WorldClock.elapsed_seconds
	ship_position_changed.emit(ship_position_km)
	ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	return true

func set_ship_command(heading_degrees: float, speed_knots: float) -> bool:
	if map == null or not is_finite(heading_degrees) or not is_finite(speed_knots):
		return false
	if speed_knots < 0.0 or speed_knots > ship_max_speed_knots:
		return false
	ship_heading_degrees = fposmod(heading_degrees, 360.0)
	ship_speed_knots = speed_knots
	ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
	EventBus.command_issued.emit("ship_navigation")
	EventBus.record("ship_navigation_command", {"heading_degrees": ship_heading_degrees, "speed_knots": ship_speed_knots})
	return true

func contact_bearing_degrees() -> float:
	var relative := contact_position_km - ship_position_km
	return fposmod(rad_to_deg(atan2(relative.x, -relative.y)), 360.0)

func contact_range_km() -> float:
	return ship_position_km.distance_to(contact_position_km)

func _on_world_time_advanced(total_seconds: float) -> void:
	var delta := total_seconds - _last_clock_seconds
	_last_clock_seconds = total_seconds
	if delta <= 0.0 or ship_speed_knots <= 0.0 or map == null:
		return
	var direction := Vector2(sin(deg_to_rad(ship_heading_degrees)), -cos(deg_to_rad(ship_heading_degrees)))
	var destination := ship_position_km + direction * ship_speed_knots * KNOT_TO_KM_PER_SECOND * delta
	if not map.can_navigate_segment(ship_position_km, destination):
		ship_speed_knots = 0.0
		ship_command_changed.emit(ship_heading_degrees, ship_speed_knots)
		navigation_blocked.emit(ship_position_km)
		EventBus.record("ship_navigation_blocked", {"position_km": ship_position_km})
		return
	ship_position_km = destination
	ship_position_changed.emit(ship_position_km)
