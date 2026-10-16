extends RefCounted

const Navigation = preload("res://scripts/world/harbor_navigation.gd")
const Geometry = preload("res://scripts/world/chart_geometry.gd")
var contours: Array[Dictionary] = []
var buildings: Array[Dictionary] = []

func _init(chart_seed: int = 270928) -> void:
	for index in range(3):
		buildings.append({"id": "harbor.warehouse.%02d" % (index + 1), "label": "WH%d" % (index + 1), "family": "building.port", "component": "warehouse", "position_km": Vector2(-0.83, -0.35 + index * 0.22), "size_class": "small", "variant": index + 1, "chart_known": true})
	buildings.append({"id": "harbor.control", "label": "HQ", "family": "building.headquarters", "position_km": Vector2(-0.49, 0.21), "size_class": "small", "variant": 1})
	buildings.append({"id": "harbor.quay", "label": "P1", "family": "building.port", "position_km": Vector2(-0.49, -0.37), "size_class": "medium", "variant": 1})
	buildings.append({"id": "harbor.drydock", "label": "DK", "family": "building.drydock", "position_km": Vector2(-0.49, 0.02), "size_class": "small", "variant": 1})
	var navigation := Navigation.new()
	navigation.map_seed = chart_seed
	contours = Geometry.grid_contours(Navigation.WATER_BOUNDS, navigation.sample_depth, navigation._clear_segment, [2.0, 5.0, 10.0], 80, 64)

static func depth_at(point: Vector2) -> float:
	return Navigation.depth_at(point)
