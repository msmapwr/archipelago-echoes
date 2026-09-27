extends RefCounted

const MAP_SIZE_KM := Vector2(100.0, 100.0)
const SHIP_START_KM := Vector2(20.0, 50.0)
const ISLAND_ANCHORS := [
	Vector2(22.0, 35.0),
	Vector2(35.0, 73.0),
	Vector2(49.0, 25.0),
	Vector2(61.0, 76.0),
	Vector2(78.0, 31.0),
]

var seed: int
var ship_start_km: Vector2 = SHIP_START_KM
var contact_position_km: Vector2
var islands: Array[Dictionary] = []

func _init(map_seed: int, contact_bearing_degrees: float, contact_range_km: float) -> void:
	seed = map_seed
	var bearing := deg_to_rad(contact_bearing_degrees)
	contact_position_km = ship_start_km + Vector2(sin(bearing), -cos(bearing)) * contact_range_km
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for anchor in ISLAND_ANCHORS:
		var center: Vector2 = anchor + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		islands.append({"center": center, "radius_km": rng.randf_range(4.0, 6.0)})

func is_water(point_km: Vector2) -> bool:
	if point_km.x < 0.0 or point_km.y < 0.0 or point_km.x > MAP_SIZE_KM.x or point_km.y > MAP_SIZE_KM.y:
		return false
	for island in islands:
		if point_km.distance_to(island["center"]) <= island["radius_km"]:
			return false
	return true

func can_navigate_segment(from_km: Vector2, to_km: Vector2) -> bool:
	if not is_water(from_km) or not is_water(to_km):
		return false
	var segment := to_km - from_km
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return true
	for island in islands:
		var center: Vector2 = island["center"]
		var closest_fraction := clampf((center - from_km).dot(segment) / length_squared, 0.0, 1.0)
		var closest_point := from_km + segment * closest_fraction
		if closest_point.distance_to(center) <= island["radius_km"]:
			return false
	return true
