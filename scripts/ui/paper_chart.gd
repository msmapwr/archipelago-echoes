extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#d1ccb6"))
	draw_rect(Rect2(6, 6, size.x - 12, size.y - 12), Color("#e1ddc8"))
	for x in range(14, roundi(size.x), 22):
		draw_line(Vector2(x, 8), Vector2(x, size.y - 8), Color(0.26, 0.37, 0.39, 0.13), 1.0)
	for y in range(12, roundi(size.y), 22):
		draw_line(Vector2(8, y), Vector2(size.x - 8, y), Color(0.26, 0.37, 0.39, 0.13), 1.0)
	for index in range(4):
		_contour(Vector2(69, 93), 21.0 + float(index) * 12.0, Color("#687d79"))
	for index in range(3):
		_contour(Vector2(148, 62), 12.0 + float(index) * 9.0, Color("#6f8580"))
	draw_line(Vector2(26, 127), Vector2(96, 64), Color("#b4564e"), 2.0, true)
	draw_circle(Vector2(26, 127), 4.0, Color("#a44f46"))
	draw_circle(Vector2(96, 64), 4.0, Color("#a44f46"))
	draw_string(ThemeDB.fallback_font, Vector2(14, 22), "NAV CHART  /  07", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#344947"))
	draw_string(ThemeDB.fallback_font, Vector2(122, 144), "E 020  S 050", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#566762"))
	draw_rect(Rect2(5, 5, size.x - 10, size.y - 10), Color("#839085"), false, 1.0)

func _contour(center: Vector2, radius: float, tint: Color) -> void:
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		var irregular := 1.0 + 0.12 * sin(angle * 3.0) + 0.08 * cos(angle * 5.0 + 1.0)
		points.append(center + Vector2(cos(angle) * radius * irregular, sin(angle) * radius * 0.72 * irregular))
	draw_polyline(points, tint, 1.2, true)
