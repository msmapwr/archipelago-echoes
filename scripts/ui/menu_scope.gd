extends Control

const DARK := Color("#031008")
const GRID := Color("#244936")
const GRID_BRIGHT := Color("#407353")
const PHOSPHOR := Color("#7cff9b")
const HOT := Color("#d6ffe0")
const COAST := Color("#4f9366")
const Decay = preload("res://scripts/ui/phosphor_decay.gd")
const TARGET_BEARING := 39.29
const ECHO_LIFETIME_SECONDS := 16.0

var _sweep_degrees: float = 16.0
var _echo_age: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_echo_age += delta
	var crossed := fposmod(TARGET_BEARING - _sweep_degrees, 360.0) <= delta * 23.0
	_sweep_degrees = fposmod(_sweep_degrees + delta * 23.0, 360.0)
	if crossed:
		_echo_age = fposmod(_sweep_degrees - TARGET_BEARING, 360.0) / 23.0
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.455
	draw_circle(center, radius + 19.0, Color("#172321"))
	draw_arc(center, radius + 18.0, 0.0, TAU, 160, Color("#7c8a7b"), 2.0, true)
	draw_circle(center, radius + 7.0, Color("#091511"))
	draw_circle(center, radius, DARK)
	draw_arc(center, radius - 2.0, 0.0, TAU, 160, Color("#38644a"), 1.0, true)
	for ring in range(1, 5):
		draw_arc(center, radius * float(ring) / 4.0, 0.0, TAU, 128, GRID, 1.0, true)
	for degree in range(0, 360, 15):
		var direction := Vector2(sin(deg_to_rad(float(degree))), -cos(deg_to_rad(float(degree))))
		var length := 14.0 if degree % 45 == 0 else 7.0
		draw_line(center + direction * (radius - length), center + direction * (radius - 1.0), GRID_BRIGHT, 1.0)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), GRID, 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), GRID, 1.0)
	_island(center + Vector2(-104, 68), 48.0, 0.72)
	_island(center + Vector2(105, 114), 30.0, 0.63)
	_island(center + Vector2(135, -78), 21.0, 0.56)
	_draw_sweep(center, radius)
	var echo := center + Vector2(0.63, -0.77) * radius * 0.57
	var pulse := Decay.energy(_echo_age, ECHO_LIFETIME_SECONDS)
	draw_circle(echo, 21.0, Color(0.48, 1.0, 0.6, 0.045 * pulse))
	draw_circle(echo, 13.0, Color(0.48, 1.0, 0.6, 0.1 * pulse))
	draw_circle(echo, 6.0, Color(0.48, 1.0, 0.6, 0.3 * pulse))
	draw_circle(echo, 2.8, Color(HOT, pulse))
	draw_circle(center, 4.0, Color("#88bace"))
	draw_arc(center, 12.0, 0.0, TAU, 48, Color("#478d8d"), 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-7, -radius - 11), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PHOSPHOR)
	draw_string(font, center + Vector2(-radius - 15, radius + 28), "PPI  /  SEARCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#80b38b"))
	draw_string(font, center + Vector2(radius - 90, radius + 28), "25 KM", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#80b38b"))

func _draw_sweep(center: Vector2, radius: float) -> void:
	for segment in range(10):
		var angle := deg_to_rad(_sweep_degrees - float(segment) * 2.3)
		var next_angle := deg_to_rad(_sweep_degrees - float(segment + 1) * 2.3)
		var direction := Vector2(sin(angle), -cos(angle))
		var next_direction := Vector2(sin(next_angle), -cos(next_angle))
		draw_colored_polygon(PackedVector2Array([center, center + direction * radius, center + next_direction * radius]), Color(0.37, 0.85, 0.48, 0.018 * (10.0 - float(segment))))
	var beam := Vector2(sin(deg_to_rad(_sweep_degrees)), -cos(deg_to_rad(_sweep_degrees)))
	draw_line(center, center + beam * radius, Color(0.49, 0.94, 0.6, 0.48), 1.6, true)

func _island(center: Vector2, radius: float, flatten: float) -> void:
	for contour in range(3):
		var points := PackedVector2Array()
		var contour_scale := 1.0 - float(contour) * 0.25
		for index in range(65):
			var angle := TAU * float(index) / 64.0
			var edge := 1.0 + 0.13 * sin(angle * 4.0 + 0.7) + 0.07 * cos(angle * 7.0)
			points.append(center + Vector2(cos(angle) * radius * contour_scale * edge, sin(angle) * radius * contour_scale * flatten * edge))
		if contour == 0:
			draw_colored_polygon(points, Color(0.14, 0.37, 0.22, 0.35))
		draw_polyline(points, Color(COAST, 0.42 - float(contour) * 0.1), 1.0, true)
