extends Control

const GRID := Color(0.27, 0.54, 0.39, 0.09)
const MUTED := Color(0.48, 0.7, 0.55, 0.17)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color("#071512"))
	for x in range(0, roundi(size.x), 48):
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 1.0)
	for y in range(0, roundi(size.y), 48):
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0)
	draw_rect(Rect2(22, 70, 590, size.y - 108), Color("#08130f"))
	draw_line(Vector2(625, 86), Vector2(625, size.y - 36), Color("#476653"), 1.0)
	draw_line(Vector2(650, 135), Vector2(size.x - 44, 135), Color("#3a684b"), 2.0)
	draw_rect(Rect2(650, 136, 126, 3), Color("#d4a663"))
	draw_line(Vector2(650, 398), Vector2(size.x - 44, 398), Color("#355b46"), 1.0)
	for index in range(4):
		_draw_contour(Vector2(1033, 523), 43.0 + float(index) * 25.0, Color(0.44, 0.72, 0.5, 0.06 + float(index) * 0.025))
	for index in range(5):
		draw_rect(Rect2(657 + float(index) * 104.0, size.y - 28.0, 56, 2), MUTED)
	draw_rect(bounds.grow(-2), Color("#214132"), false, 1.0)

func _draw_contour(center: Vector2, radius: float, tint: Color) -> void:
	var points := PackedVector2Array()
	for index in range(65):
		var angle := TAU * float(index) / 64.0
		var wobble := 1.0 + 0.12 * sin(angle * 3.0 + 1.2) + 0.07 * cos(angle * 7.0)
		points.append(center + Vector2(cos(angle) * radius * wobble, sin(angle) * radius * 0.58 * wobble))
	draw_polyline(points, tint, 1.0, true)
