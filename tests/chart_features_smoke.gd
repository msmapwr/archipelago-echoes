extends SceneTree

const Map = preload("res://scripts/world/archipelago_map.gd")
const Geometry = preload("res://scripts/world/chart_geometry.gd")
const HarborLayout = preload("res://scripts/world/harbor_layout.gd")
const Navigation = preload("res://scripts/world/harbor_navigation.gd")
const Glyph = preload("res://scripts/data/unit_glyph.gd")
const Catalog = preload("res://scripts/data/unit_visual_catalog.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	map_data()
	port_structure()
	harbor_data()
	clip_boundaries()
	await projections()
	if failures.is_empty():
		print("Chart features smoke passed")
		quit(0)
	else:
		for failure in failures: printerr("FAIL: " + failure)
		quit(1)

func map_data() -> void:
	var map = Map.new(270928, 42, 18)
	var same = Map.new(270928, 42, 18)
	var other = Map.new(270929, 42, 18)
	check(map.depth_contours == same.depth_contours and map.facilities == same.facilities, "seed reproduces facilities and depths")
	check(map.depth_contours != other.depth_contours, "different seed changes actual chart geometry")
	check(map.depth_at(map.islands[0].center) == 0, "land has zero sea depth")
	var coast: Vector2 = map.islands[0].center + Vector2(map.islands[0].radius_km + 1, 0)
	check(map.depth_at(coast) > 25 and map.depth_at(coast) < 150, "one-kilometer coastal shelf stays within seeded depth bounds")
	check(map.depth_at(Vector2(-1, 2)) == 0, "outside map cannot be navigable water")
	var ids := {}
	for facility in map.facilities:
		check(not ids.has(facility.id) and not facility.label.is_empty(), "unique facility identity")
		ids[facility.id] = true
		check(not Catalog.variant_slots(facility.family, facility.size_class).is_empty() and not Glyph.source(facility.family, facility.size_class, facility.variant).is_empty(), "every facility has a real structural icon")
		check(not map.is_water(facility.position_km), "shore facility located on its island")
	check(map.facilities[1].position_km == map.islands[1].center, "airport registry matches existing recovery site")
	check(map.depth_contours.size() == 4, "four labeled depths")
	for contour in map.depth_contours:
		check(not contour.segments.is_empty(), "each depth has real segments")
		for segment in contour.segments:
			check(map.can_navigate_segment(segment[0], segment[1]), "depth contours remain on water")
			check(absf(map.depth_at(segment[0]) - contour.depth_m) < 0.1, "line corresponds to labeled depth")

func port_structure() -> void:
	for grade in Catalog.SIZE_CLASSES:
		for variant in range(1, 11):
			var roofs: Array[Rect2] = []
			var piers: Array[Rect2] = []
			for cell in Glyph.source("building.port", grade, variant, false):
				var footprint := Rect2(cell[0], cell[1], cell[2], cell[3])
				if is_equal_approx(cell[4], 0.22) and footprint.size.x >= 8 and footprint.size.y >= 5: roofs.append(footprint)
				if footprint.size.x >= 20 and footprint.size.y <= 3 and footprint.position.x < 0 and footprint.end.x > 0: piers.append(footprint)
			check(roofs.size() >= 3 and piers.size() >= 2, "every port has several roofs and horizontal water piers")
			for roof in roofs: check(roof.end.x <= -7, "roof footprints remain on land side of quay")
			for pier in piers:
				var served := false
				for roof in roofs:
					if absf(roof.get_center().y - pier.get_center().y) < 6 and roof.end.x <= pier.position.x: served = true
				check(served, "each pier serves a separate ashore building")
	check(Catalog.BUILDING_KINDS.size() == 8 and Catalog.variant_slots("building.warehouse", "small").is_empty(), "port components preserve stable catalog contract")
	var warehouses := {}
	for variant in range(1, 11):
		var cells := Glyph.port_component_source("warehouse", variant, true)
		check(not cells.is_empty() and not warehouses.has(str(cells)), "ten distinct warehouse substructures")
		warehouses[str(cells)] = true
		for cell in cells:
			check(cell[0] >= -32 and cell[1] >= -32 and cell[0] + cell[2] <= 32 and cell[1] + cell[3] <= 32, "warehouse substructure remains inside icon")

func harbor_data() -> void:
	var layout = HarborLayout.new()
	var navigation := Navigation.new()
	check(layout.buildings.size() == 6, "quay has three warehouses, control, port and repair icons")
	for building in layout.buildings:
		check(Navigation.OBSTACLES[0].has_point(building.position_km), "harbor buildings stay within existing solid quay")
		check(not Glyph.source(building.family, building.size_class, building.variant).is_empty(), "every harbor building has an icon")
	check(HarborLayout.depth_at(Vector2(-0.8, 0)) == 0 and HarborLayout.depth_at(Vector2.ZERO) > 5, "solid quay and deep central channel distinguished")
	for contour in layout.contours:
		check(not contour.segments.is_empty(), "harbor depth level has lines")
		for segment in contour.segments:
			check(navigation._clear_segment(segment[0], segment[1]), "harbor depth lines do not cross collision structures")

func clip_boundaries() -> void:
	var crossing := Geometry.clip_circle(Vector2(-20, 0), Vector2(20, 0), 10)
	check(crossing.size() == 2 and crossing[0] == Vector2(-10, 0) and crossing[1] == Vector2(10, 0), "contour crossing scope clipped at both boundaries")
	check(Geometry.clip_circle(Vector2(20, 20), Vector2(30, 30), 10).is_empty(), "off-scope segments excluded")
	check(Geometry.clip_circle(Vector2.ZERO, Vector2.ZERO, 10).is_empty(), "degenerate segment ignored")
	var inside := Geometry.clip_circle(Vector2(-1, 0), Vector2(1, 0), 10)
	check(inside.size() == 2 and inside[0] == Vector2(-1, 0) and inside[1] == Vector2(1, 0), "inside segment retains geography")
	var square := PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	var polygon := Geometry.clip_polygon_circle(square, 10)
	check(polygon.size() >= 3, "land containing scope produces valid clipped fill")
	for point in polygon: check(point.length() <= 10.001, "land fill stays within circular glass")
	check(Geometry.clip_polygon_circle(PackedVector2Array([Vector2(20, 20), Vector2(30, 20), Vector2(20, 30)]), 10).is_empty(), "off-scope land fill excluded")

func projections() -> void:
	var mission = root.get_node("MissionController")
	var world = root.get_node("WorldState")
	mission.restart_scenario()
	var main: Control = load("res://scenes/main/crt_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.radar.chart_facilities == world.map.facilities and main.radar.depth_contours == world.map.depth_contours, "live bridge uses authoritative facility and depth data")
	var labels: Array = main.radar.depth_chart_labels(200)
	check(not labels.is_empty(), "visible water chart has depth captions")
	for index in range(labels.size()):
		for previous in range(index): check(not labels[index].rect.intersects(labels[previous].rect), "depth captions never overlap each other")
	main.radar.set_display_range(100)
	check(main.radar.visible_chart_facilities().size() == world.map.facilities.size(), "all known buildings have reachable map markers")
	var markers: Array = main.radar.chart_facility_markers(200)
	check(markers.size() == world.map.facilities.size(), "wide chart renders every known facility")
	for index in range(markers.size()):
		check(markers[index].pixels >= 32 and markers[index].pixels <= 48, "facility keeps readable symbol size")
		check(not markers[index].icon_rect.intersects(Rect2(-36, -36, 72, 72)), "facility symbols avoid ownship")
		for other in range(markers.size()):
			if index != other: check(not markers[index].icon_rect.intersects(markers[other].icon_rect), "facility symbols do not overlap")
			if markers[index].caption_visible: check(not markers[index].caption_rect.intersects(markers[other].icon_rect), "facility captions avoid every symbol")
	var hidden: Dictionary = world.map.facilities[0].duplicate()
	hidden.chart_known = false
	var hidden_facilities: Array[Dictionary] = [hidden]
	main.radar.set_chart_features(hidden_facilities, world.map.depth_contours)
	check(main.radar.visible_chart_facilities().is_empty(), "unmapped facility is never revealed by static chart")
	main.radar.set_chart_features(world.map.facilities, world.map.depth_contours)
	var snapshot: Array = main.radar.chart_facilities.duplicate(true)
	main.radar.set_display_range(12.5)
	check(main.radar.chart_facilities == snapshot, "range changes preserve chart data")
	check(main.radar.visible_chart_facilities().size() < snapshot.size(), "out-of-range buildings excluded by geography")
	main.queue_free()
	var harbor: Control = load("res://scripts/ui/harbor_screen.gd").new()
	root.add_child(harbor)
	await process_frame
	check(harbor.chart.layout.buildings.size() == 6 and harbor.chart.layout.contours.size() == 3, "real harbor view includes building and depth layers")
	harbor.queue_free()
	await process_frame
