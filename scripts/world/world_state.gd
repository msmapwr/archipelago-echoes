extends Node

const ArchipelagoMap = preload("res://scripts/world/archipelago_map.gd")
const FIRST_SCENARIO_SEED := 270928

var map: RefCounted
var ship_position_km: Vector2 = Vector2.ZERO
var contact_position_km: Vector2 = Vector2.ZERO

func _ready() -> void:
	load_first_scenario()

func load_first_scenario(map_seed: int = FIRST_SCENARIO_SEED) -> bool:
	var contact: ContactDefinition = DataManager.get_definition("contact.alpha") as ContactDefinition
	if contact == null:
		push_error("[WorldState] first scenario contact is missing")
		return false
	map = ArchipelagoMap.new(map_seed, contact.bearing_degrees, contact.range_km)
	ship_position_km = map.ship_start_km
	contact_position_km = map.contact_position_km
	return true
