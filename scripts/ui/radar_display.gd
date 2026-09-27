extends Control

signal contact_selected(contact_id: String)
signal contact_deselected

const MAX_RANGE_KM := 25.0
const GRID_COLOR := Color("28565b")
const RADAR_COLOR := Color("55dbbd")
const SELECTED_COLOR := Color("ffe4a3")
const LAND_COLOR := Color("245357")
const SHORE_COLOR := Color("60968c")

var contact_id: String = ""
var contact_visible: bool = false
var contact_selected_state: bool = false
var bearing_degrees: float = 0.0
var range_km: float = 0.0
var land_areas: Array[Dictionary] = []
var own_position_km: Vector2 = Vector2.ZERO

func set_land_areas(areas: Array[Dictionary], position_km: Vector2) -> void:
	land_areas = areas.duplicate(true)
	own_position_km = position_km
	queue_redraw()

func set_contact(id: String, bearing: float, distance: float, visible: bool) -> void:
	contact_id = id
	bearing_degrees = bearing
	range_km = distance
	contact_visible = visible
	if not visible and contact_selected_state:
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
		if contact_visible and event.position.distance_to(_contact_position()) <= 22.0:
			contact_selected_state = true
			contact_selected.emit(contact_id)
			queue_redraw()
			accept_event()
		else:
			clear_selection()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	draw_circle(center, radius, Color("08252a"))
	for island in land_areas:
		var offset_km: Vector2 = island["center"] - own_position_km
		var island_radius_km: float = island["radius_km"]
		if offset_km.length() + island_radius_km > MAX_RANGE_KM:
			continue
		var point := center + offset_km * radius / MAX_RANGE_KM
		var island_radius := island_radius_km * radius / MAX_RANGE_KM
		draw_circle(point, island_radius, LAND_COLOR)
		draw_arc(point, island_radius, 0.0, TAU, 48, SHORE_COLOR, 1.0, true)
	for ring in range(1, 5):
		draw_arc(center, radius * float(ring) / 4.0, 0.0, TAU, 96, GRID_COLOR, 1.0, true)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), GRID_COLOR, 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), GRID_COLOR, 1.0)
	draw_circle(center, 5.0, RADAR_COLOR)
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-10, -radius - 12), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RADAR_COLOR)
	draw_string(font, center + Vector2(radius - 43, radius + 23), "25 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GRID_COLOR)
	if contact_visible:
		var point := _contact_position()
		var marker_color := SELECTED_COLOR if contact_selected_state else RADAR_COLOR
		draw_circle(point, 8.0, marker_color)
		draw_arc(point, 15.0, 0.0, TAU, 32, marker_color, 2.0, true)
		draw_string(font, point + Vector2(20, -10), "A1", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, marker_color)

func _contact_position() -> Vector2:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	var distance := clampf(range_km / MAX_RANGE_KM, 0.0, 1.0) * radius
	var radians := deg_to_rad(bearing_degrees)
	return center + Vector2(sin(radians), -cos(radians)) * distance
