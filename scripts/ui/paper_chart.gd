extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	WorldState.ship_position_changed.connect(func(_position: Vector2) -> void: queue_redraw())
	EventBus.event_recorded.connect(func(event: Dictionary) -> void:
		if event.get("kind", "") == "scenario_started": queue_redraw())

func _point(world_point: Vector2) -> Vector2:
	return Vector2(10, 26) + world_point * (size - Vector2(20, 44)) / Vector2(100, 100)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#d1ccb6"))
	draw_rect(Rect2(6, 6, size.x - 12, size.y - 12), Color("#e1ddc8"))
	for x in range(14, roundi(size.x), 22):
		draw_line(Vector2(x, 8), Vector2(x, size.y - 8), Color(0.26, 0.37, 0.39, 0.13), 1.0)
	for y in range(12, roundi(size.y), 22):
		draw_line(Vector2(8, y), Vector2(size.x - 8, y), Color(0.26, 0.37, 0.39, 0.13), 1.0)
	if WorldState.map != null:
		for contour in WorldState.map.depth_contours:
			for segment in contour.segments: draw_line(_point(segment[0]), _point(segment[1]), Color(0.25, 0.43, 0.51, 0.45), 0.8, true)
		for island in WorldState.map.islands:
			var points := PackedVector2Array()
			for index in range(64): points.append(_point(island.center + Vector2.from_angle(TAU * index / 64.0) * island.radius_km))
			draw_colored_polygon(points, Color("#afbda0"))
			points.append(points[0])
			draw_polyline(points, Color("#52685b"), 1, true)
		for facility in WorldState.map.facilities:
			if not facility.get("chart_known", true): continue
			var anchor := _point(facility.position_km)
			# Dense coastal pair uses a leader instead of overlapping tiny symbols.
			var icon := anchor + Vector2(-12, 9) if facility.family == "building.port" else anchor
			if icon != anchor: draw_line(anchor, icon, Color("#52685b"), 0.8)
			preload("res://scripts/data/unit_glyph.gd").draw(self, icon, 15, facility.family, Color("#344947"), facility.size_class, facility.variant, false)
		draw_circle(_point(WorldState.ship_position_km), 3, Color("#a44f46"))
	draw_string(ThemeDB.fallback_font, Vector2(14, 22), "NAV CHART  /  07", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#344947"))
	draw_string(ThemeDB.fallback_font, Vector2(10, size.y - 10), "DEPTH 20/50/100/200m", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#566762"))
	draw_rect(Rect2(5, 5, size.x - 10, size.y - 10), Color("#839085"), false, 1.0)
