extends Control

var active: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var width := size.x
	var height := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("#091014"))
	for row in range(0, 80, 3):
		var shade := float(row) / 80.0
		draw_rect(Rect2(4, 4 + row, width - 8, 3), Color("#365166").lerp(Color("#b6afa0"), shade))
	draw_circle(Vector2(width * 0.75, 48), 20.0, Color(1.0, 0.82, 0.55, 0.18))
	draw_circle(Vector2(width * 0.75, 48), 10.0, Color("#ddd0a4"))
	draw_rect(Rect2(4, 83, width - 8, height - 87), Color("#1a5760"))
	for row in range(86, roundi(height) - 4, 8):
		draw_line(Vector2(5, row), Vector2(width - 6, row), Color(0.6, 0.85, 0.82, 0.06), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(4, 82), Vector2(23, 68), Vector2(48, 60), Vector2(73, 64), Vector2(89, 77), Vector2(121, 86), Vector2(4, 95)]), Color("#263b3d"))
	draw_colored_polygon(PackedVector2Array([Vector2(73, 85), Vector2(111, 65), Vector2(132, 62), Vector2(164, 77), Vector2(width - 4, 82), Vector2(width - 4, 100)]), Color("#304948"))
	draw_polyline(PackedVector2Array([Vector2(4, 82), Vector2(23, 68), Vector2(48, 60), Vector2(73, 64), Vector2(89, 77)]), Color("#9caaa0"), 1.0)
	for x in range(5, roundi(width) - 4, 3):
		draw_line(Vector2(x, 5), Vector2(x, height - 4), Color(0.03, 0.08, 0.08, 0.028), 1.0)
	draw_rect(Rect2(3, 3, width - 6, height - 6), Color("#6d8580"), false, 1.0)
	draw_rect(Rect2(9, 111, 116, 29), Color(0.03, 0.09, 0.1, 0.81))
	draw_string(ThemeDB.fallback_font, Vector2(15, 128), "ARCHIVE  /  01", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e8e7d1"))
	draw_circle(Vector2(width - 18, 17), 4.0, Color("#7de7ab") if active else Color("#e4ab65"))
	draw_line(Vector2(5, height - 3), Vector2(width - 5, height - 3), Color("#1f3030"), 3.0)
