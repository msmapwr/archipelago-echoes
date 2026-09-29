extends Control

const GRID := Color("305846")
const PHOSPHOR := Color("83dda0")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	for index in range(1, 5):
		draw_arc(center, radius * float(index) / 4.0, 0.0, TAU, 96, GRID, 1.5, true)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), GRID, 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), GRID, 1.0)
	var bearing := Vector2(0.67, -0.74)
	draw_line(center, center + bearing * radius, Color(0.55, 0.9, 0.65, 0.35), 2.0, true)
	draw_circle(center, 5.0, Color("65b5e8"))
	var echo := center + bearing * radius * 0.68
	draw_arc(echo, 12.0, 0.0, TAU, 40, PHOSPHOR, 2.0, true)
	draw_circle(echo, 4.0, PHOSPHOR)
	draw_string(ThemeDB.fallback_font, center + Vector2(-8, -radius - 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PHOSPHOR)
