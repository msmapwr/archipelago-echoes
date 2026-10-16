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
var facilities: Array[Dictionary] = []
var depth_contours: Array[Dictionary] = []

func _init(map_seed: int, contact_bearing_degrees: float, contact_range_km: float) -> void:
	seed = map_seed
	var bearing := deg_to_rad(contact_bearing_degrees)
	contact_position_km = ship_start_km + Vector2(sin(bearing), -cos(bearing)) * contact_range_km
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for anchor in ISLAND_ANCHORS:
		var center: Vector2 = anchor + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		islands.append({"center": center, "radius_km": rng.randf_range(4.0, 6.0)})
	# Keep the existing land geometry and navigation corridors; only the shelf varies.
	for island in islands: island.depth_phase = rng.randf_range(0, TAU)
	var families := ["headquarters", "airfield", "radar_station", "factory", "city"]
	for index in range(islands.size()):
		facilities.append({"id": "facility.%s.01" % families[index], "label": ["HQ1", "AF1", "RD1", "FX1", "CT1"][index], "family": "building." + families[index], "position_km": islands[index].center, "size_class": "medium", "variant": index + 1, "chart_known": true, "role": "recovery_airfield" if index == 1 else "chart_reference"})
	# Coastal port marker belongs to the chart, not a detected hostile contact.
	facilities.append({"id": "facility.port.01", "label": "P1", "family": "building.port", "position_km": islands[0].center + Vector2(-0.66, 0.48) * islands[0].radius_km, "size_class": "medium", "variant": 1, "chart_known": true, "role": "chart_reference"})
	_build_depth_contours()

func depth_at(point_km: Vector2) -> float:
	if not is_water(point_km): return 0.0
	var coast_distance := INF
	for island in islands:
		var offset: Vector2 = point_km - island.center
		coast_distance = minf(coast_distance, (offset.length() - float(island.radius_km)) / shelf_factor(island, offset.angle()))
	return minf(300.0, coast_distance * 50.0)

static func shelf_factor(island: Dictionary, angle: float) -> float:
	var phase: float = island.get("depth_phase", 0.0)
	return 1.0 + 0.34 * sin(angle * 3 + phase) + 0.18 * sin(angle * 5 - phase * 1.3) + 0.10 * cos(angle * 8 + phase * 0.7)

func _build_depth_contours() -> void:
	depth_contours.clear()
	for depth in [20.0, 50.0, 100.0, 200.0]:
		var segments: Array[PackedVector2Array] = []
		for island in islands:
			for index in range(192):
				var angle := TAU * index / 192.0
				var next_angle := TAU * (index + 1) / 192.0
				var from: Vector2 = island.center + Vector2.from_angle(angle) * (island.radius_km + depth / 50.0 * shelf_factor(island, angle))
				var to: Vector2 = island.center + Vector2.from_angle(next_angle) * (island.radius_km + depth / 50.0 * shelf_factor(island, next_angle))
				if can_navigate_segment(from, to) and absf(depth_at(from) - depth) < 0.1 and absf(depth_at(to) - depth) < 0.1 and absf(depth_at((from + to) * 0.5) - depth) < 1.0:
					segments.append(PackedVector2Array([from, to]))
		depth_contours.append({"depth_m": depth, "segments": segments})

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
