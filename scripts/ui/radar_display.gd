extends Control

signal contact_selected(contact_id: String)
signal contact_deselected

const MAX_RANGE_KM := 25.0
const DARK := Color("#031008")
const GRID := Color("#214c34")
const COAST := Color("#5a9d6d")
const PHOSPHOR := Color("#7cff9b")
const HOT := Color("#d6ffe0")
const AMBER := Color("#e7b66c")
const OWN_SHIP := Color("#83bad1")
const ECHO_LIFETIME_SECONDS := 95.0

var contact_id: String = ""
var contact_visible: bool = false
var contact_selected_state: bool = false
var bearing_degrees: float = 0.0
var range_km: float = 0.0
var land_areas: Array[Dictionary] = []
var own_position_km: Vector2 = Vector2.ZERO
var own_heading_degrees: float = 0.0
var aircraft_position_km: Vector2 = Vector2.ZERO
var aircraft_visible: bool = false
var contact_confirmed: bool = false
var sweep_angle_degrees: float = 0.0
var sweep_enabled: bool = true
var hull_integrity: float = 100.0
var _echoes: Array[Dictionary] = []
var display_range_km: float = MAX_RANGE_KM
var gun_arc_visible: bool = false
var gun_ready: bool = false
var gun_range_km: float = 10.0

func set_display_range(value: float) -> void:
	display_range_km = value
	queue_redraw()

func set_gun_solution(show_arc: bool, solution_ready: bool, weapon_range_km: float) -> void:
	gun_arc_visible = show_arc
	gun_ready = solution_ready
	gun_range_km = weapon_range_km
	queue_redraw()

func _ready() -> void:
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	EventBus.contact_discovered.connect(_capture_echo)
	EventBus.contact_updated.connect(_capture_echo)
	EventBus.event_recorded.connect(_on_event_recorded)
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_event_recorded(event: Dictionary) -> void:
	if event.get("kind", "") == "scenario_started":
		_echoes.clear()
		queue_redraw()

func _capture_echo(id: String) -> void:
	if id != MissionController.CONTACT_ID:
		return
	_echoes.append({
		"position_km": MissionController.last_contact_position_km,
		"time": WorldClock.elapsed_seconds,
		"strength": clampf(float(MissionController.contact_scan_count) / 3.0, 0.36, 1.0),
	})
	while _echoes.size() > 16:
		_echoes.pop_front()
	queue_redraw()

func _on_world_time_advanced(total_seconds: float) -> void:
	if sweep_enabled:
		sweep_angle_degrees = fposmod(total_seconds * 12.0, 360.0)
	while not _echoes.is_empty() and total_seconds - float(_echoes[0]["time"]) > ECHO_LIFETIME_SECONDS:
		_echoes.pop_front()
	queue_redraw()

func set_sweep_enabled(is_enabled: bool) -> void:
	if sweep_enabled != is_enabled:
		sweep_enabled = is_enabled
		queue_redraw()

func set_integrity(value: float) -> void:
	hull_integrity = value
	queue_redraw()

func set_land_areas(areas: Array[Dictionary], position_km: Vector2) -> void:
	land_areas = areas.duplicate(true)
	own_position_km = position_km
	queue_redraw()

func set_ship_heading(heading_degrees: float) -> void:
	own_heading_degrees = heading_degrees
	queue_redraw()

func set_aircraft(position_km: Vector2, display_visible: bool) -> void:
	aircraft_position_km = position_km
	aircraft_visible = display_visible
	queue_redraw()

func set_contact(id: String, bearing: float, distance: float, display_visible: bool, confirmed: bool = false) -> void:
	contact_id = id
	bearing_degrees = bearing
	range_km = distance
	contact_confirmed = confirmed
	contact_visible = display_visible and distance <= display_range_km
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if contact_visible else Control.CURSOR_ARROW
	if not contact_visible and contact_selected_state:
		clear_selection()
	queue_redraw()

func clear_selection() -> void:
	if not contact_selected_state:
		return
	contact_selected_state = false
	contact_deselected.emit()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if contact_visible and event.position.distance_to(_contact_position()) <= 23.0:
			contact_selected_state = true
			contact_selected.emit(contact_id)
			queue_redraw()
			accept_event()
		else:
			clear_selection()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.435
	draw_circle(center, radius + 20.0, Color("#20302a"))
	draw_arc(center, radius + 19.0, 0.0, TAU, 160, Color("#829285"), 2.0, true)
	draw_circle(center, radius + 8.0, Color("#07130e"))
	draw_arc(center, radius + 7.0, 0.0, TAU, 160, Color("#40674b"), 2.0, true)
	draw_circle(center, radius, DARK)
	_draw_grid(center, radius)
	if gun_arc_visible:
		_draw_gun_arc(center, radius)
	_draw_land(center, radius)
	_draw_echoes(center, radius)
	if sweep_enabled:
		_draw_sweep(center, radius)
	_draw_ownship(center, radius)
	_draw_contact(center, radius)
	_draw_readout(center, radius)
	if hull_integrity < 50.0:
		draw_arc(center, radius - 4.0, deg_to_rad(113.0), deg_to_rad(183.0), 32, Color("#8d5e3b"), 3.0, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-90, radius + 28), "SIGNAL DEGRADED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AMBER)

func _draw_grid(center: Vector2, radius: float) -> void:
	for ring in range(1, 5):
		draw_arc(center, radius * float(ring) / 4.0, 0.0, TAU, 128, GRID, 1.0, true)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), GRID, 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), GRID, 1.0)
	for degree in range(0, 360, 10):
		var direction := Vector2(sin(deg_to_rad(float(degree))), -cos(deg_to_rad(float(degree))))
		var tick_length := 15.0 if degree % 30 == 0 else 7.0
		draw_line(center + direction * (radius - tick_length), center + direction * radius, Color("#427954") if degree % 30 == 0 else GRID, 1.0, true)
	draw_arc(center, radius, 0.0, TAU, 160, Color("#447551"), 1.0, true)

func _draw_land(center: Vector2, radius: float) -> void:
	for island in land_areas:
		var offset_km: Vector2 = island["center"] - own_position_km
		var island_radius_km: float = island["radius_km"]
		if offset_km.length() + island_radius_km > display_range_km:
			continue
		var point := center + offset_km * radius / display_range_km
		var island_radius := island_radius_km * radius / display_range_km
		for contour in range(3):
			var points := PackedVector2Array()
			var contour_scale := 1.0 - float(contour) * 0.24
			for index in range(49):
				var angle := TAU * float(index) / 48.0
				var edge := 1.0 + 0.10 * sin(angle * 4.0 + point.x * 0.03) + 0.07 * cos(angle * 7.0 + point.y * 0.02)
				points.append(point + Vector2(cos(angle), sin(angle)) * island_radius * contour_scale * edge)
			if contour == 0:
				draw_colored_polygon(points, Color(0.12, 0.32, 0.18, 0.46))
			draw_polyline(points, Color(COAST, 0.42 - float(contour) * 0.1), 1.0, true)

func _draw_echoes(center: Vector2, radius: float) -> void:
	for echo in _echoes:
		var offset: Vector2 = echo["position_km"] - own_position_km
		if offset.length() > display_range_km:
			continue
		var age: float = maxf(0.0, WorldClock.elapsed_seconds - float(echo["time"]))
		var energy: float = pow(1.0 - age / ECHO_LIFETIME_SECONDS, 1.7) * float(echo["strength"])
		if energy <= 0.0:
			continue
		var point := center + offset * radius / display_range_km
		draw_circle(point, 15.0, Color(0.49, 1.0, 0.61, energy * 0.045))
		draw_circle(point, 8.0, Color(0.49, 1.0, 0.61, energy * 0.09))
		draw_circle(point, 3.0, Color(0.71, 1.0, 0.76, energy * 0.48))

func _draw_sweep(center: Vector2, radius: float) -> void:
	for segment in range(8):
		var angle := deg_to_rad(sweep_angle_degrees - float(segment) * 2.4)
		var next_angle := deg_to_rad(sweep_angle_degrees - float(segment + 1) * 2.4)
		draw_colored_polygon(PackedVector2Array([
			center,
			center + Vector2(sin(angle), -cos(angle)) * radius,
			center + Vector2(sin(next_angle), -cos(next_angle)) * radius,
		]), Color(0.34, 0.8, 0.46, 0.016 * (8.0 - float(segment))))
	var direction := Vector2(sin(deg_to_rad(sweep_angle_degrees)), -cos(deg_to_rad(sweep_angle_degrees)))
	draw_line(center, center + direction * radius, Color(0.5, 0.96, 0.6, 0.42), 1.6, true)

func _draw_ownship(center: Vector2, radius: float) -> void:
	var direction := Vector2(sin(deg_to_rad(own_heading_degrees)), -cos(deg_to_rad(own_heading_degrees)))
	draw_line(center, center + direction * 28.0, OWN_SHIP, 2.0, true)
	draw_circle(center, 4.0, Color("#b7dbe0"))
	draw_arc(center, 12.0, 0.0, TAU, 32, Color("#3c7977"), 1.0)
	if aircraft_visible:
		var offset := aircraft_position_km - own_position_km
		if offset.length() <= display_range_km:
			var point := center + offset * radius / display_range_km
			draw_colored_polygon(PackedVector2Array([point + Vector2(0, -8), point + Vector2(-6, 6), point + Vector2(6, 6)]), OWN_SHIP)

func _draw_contact(_center: Vector2, _radius: float) -> void:
	if not contact_visible:
		return
	var point := _contact_position()
	var strength := clampf(float(MissionController.contact_scan_count) / 3.0, 0.38, 1.0)
	var tint := AMBER if contact_selected_state else PHOSPHOR
	draw_circle(point, 22.0, Color(tint, 0.045 * strength))
	draw_circle(point, 12.0, Color(tint, 0.10 * strength))
	draw_circle(point, 6.0, Color(tint, 0.3 * strength))
	draw_circle(point, 3.2, HOT if contact_confirmed else tint)
	if contact_selected_state:
		draw_arc(point, 17.0, 0.0, TAU, 40, AMBER, 1.5, true)
	if contact_confirmed or contact_selected_state:
		draw_string(ThemeDB.fallback_font, point + Vector2(21, -8), "A1 / TRACK" if contact_confirmed else "A1 / SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)

func _draw_readout(center: Vector2, radius: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-7, -radius - 11), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PHOSPHOR)
	draw_string(font, center + Vector2(radius + 7, 5), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRID)
	draw_string(font, center + Vector2(-7, radius + 18), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRID)
	draw_string(font, center + Vector2(-radius - 16, 5), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRID)
	draw_string(font, center + Vector2(-radius + 2, radius + 28), "PPI / SEARCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#73a984"))
	draw_string(font, center + Vector2(radius - 80, radius + 28), "%.1f KM" % display_range_km, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#73a984"))

func _draw_gun_arc(center: Vector2, radius: float) -> void:
	var reach := radius * minf(gun_range_km / display_range_km, 1.0)
	var start := deg_to_rad(own_heading_degrees - MissionController.GUN_HALF_ARC_DEGREES - 90.0)
	var end := deg_to_rad(own_heading_degrees + MissionController.GUN_HALF_ARC_DEGREES - 90.0)
	var tint := PHOSPHOR if gun_ready else AMBER
	draw_arc(center, reach, start, end, 64, Color(tint, 0.45), 1.2, true)
	for angle in [start, end]:
		draw_line(center, center + Vector2(cos(angle), sin(angle)) * reach, Color(tint, 0.24), 1.0, true)

func _contact_position() -> Vector2:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.435
	var distance := clampf(range_km / display_range_km, 0.0, 1.0) * radius
	var radians := deg_to_rad(bearing_degrees)
	return center + Vector2(sin(radians), -cos(radians)) * distance
