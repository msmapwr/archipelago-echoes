extends Control

signal contact_selected(contact_id: String)
signal contact_deselected
signal waypoint_requested(position_km: Vector2)
signal ship_waypoint_append_requested(position_km: Vector2)

const MAX_RANGE_KM := 25.0
const DARK := Color("#031008")
const GRID := Color("#214c34")
const COAST := Color("#5a9d6d")
const PHOSPHOR := Color("#7cff9b")
const HOT := Color("#d6ffe0")
const AMBER := Color("#e7b66c")
const OWN_SHIP := Color("#83bad1")
const ECHO_LIFETIME_SECONDS := 95.0
const Decay = preload("res://scripts/ui/phosphor_decay.gd")

var contact_id: String = ""
var contact_visible: bool = false
var contact_selected_state: bool = false
var bearing_degrees: float = 0.0
var range_km: float = 0.0
var land_areas: Array[Dictionary] = []
var chart_facilities: Array[Dictionary] = []
var depth_contours: Array[Dictionary] = []
var _coast_key: Array = []
var _coast_polygons: Array[PackedVector2Array] = []
var _depth_key: Array = []
var _depth_lines: Array[PackedVector2Array] = []
var _drawn_depth_labels: Array[Dictionary] = []
var _marker_key: Array = []
var _markers: Array[Dictionary] = []
const ChartGeometry = preload("res://scripts/world/chart_geometry.gd")

func set_chart_features(facilities: Array[Dictionary], contours: Array[Dictionary]) -> void:
	# Immutable chart geometry is shared; no copies or regeneration each frame.
	if depth_contours != contours: _depth_key.clear()
	if chart_facilities != facilities: _marker_key.clear()
	chart_facilities = facilities
	depth_contours = contours
	queue_redraw()

func visible_chart_facilities() -> Array[Dictionary]:
	var facilities_in_range: Array[Dictionary] = []
	for facility in chart_facilities:
		if facility.get("chart_known", true) and facility.position_km.distance_to(own_position_km) <= display_range_km:
			facilities_in_range.append(facility)
	return facilities_in_range
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
var fire_control_assigned: bool = false
var gun_range_km: float = 10.0
var flight_navigation: bool = false
var ship_waypoint_input := false
var ship_route: Dictionary = {}
var carrier_position_km: Vector2 = Vector2.ZERO
var carrier_afloat: bool = true
var airfield_position_km: Vector2 = Vector2.ZERO
var navigation_target_km: Vector2 = Vector2.ZERO
var navigation_target_visible: bool = false
var _keyboard_offset_km: Vector2 = Vector2.ZERO
var _fire_control_prediction: Dictionary = {}
var _gun_projectiles: Array = []
var _gun_impact: Dictionary = {}

func set_gun_ballistics(shots: Array, impact: Dictionary) -> void:
	_gun_projectiles = shots.duplicate(true)
	_gun_impact = impact.duplicate(true)
	queue_redraw()

func set_fire_control_prediction(solution: Dictionary) -> void:
	_fire_control_prediction = solution.duplicate(true)
	queue_redraw()

func set_flight_navigation(enabled: bool, carrier: Vector2, afloat: bool, airfield: Vector2, solution: Dictionary) -> void:
	if flight_navigation != enabled:
		_keyboard_offset_km = Vector2.ZERO
	flight_navigation = enabled
	carrier_position_km = carrier
	carrier_afloat = afloat
	airfield_position_km = airfield
	navigation_target_visible = enabled and solution.get("available", false)
	navigation_target_km = solution.get("position_km", own_position_km)
	focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	tooltip_text = "右键设置航点；聚焦雷达后用方向键定位、Enter 确认" if enabled else "点击回波选择接触"
	queue_redraw()

func set_ship_navigation(enabled: bool, solution: Dictionary) -> void:
	if ship_waypoint_input != enabled: _keyboard_offset_km = Vector2.ZERO
	ship_waypoint_input = enabled
	ship_route = solution
	if enabled:
		focus_mode = Control.FOCUS_ALL
		tooltip_text = "母舰航线：右键替换，Shift+右键追加；方向键 / Enter，Shift+Enter 追加；每段需 2 m 余深"
	queue_redraw()

func point_to_world(local_point: Vector2) -> Vector2:
	var radius := minf(size.x, size.y) * 0.435
	return own_position_km + (local_point - size * 0.5) * display_range_km / radius

func set_display_range(value: float) -> void:
	display_range_km = value
	queue_redraw()

func set_gun_solution(show_arc: bool, solution_ready: bool, weapon_range_km: float) -> void:
	gun_arc_visible = show_arc
	gun_ready = solution_ready
	gun_range_km = weapon_range_km
	queue_redraw()

func _ready() -> void:
	var phosphor := ShaderMaterial.new()
	phosphor.shader = preload("res://shaders/ppi_phosphor.gdshader")
	material = phosphor
	resized.connect(func() -> void: phosphor.set_shader_parameter("screen_size", size))
	phosphor.set_shader_parameter("screen_size", size)
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
	if (flight_navigation or ship_waypoint_input) and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if event.position.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.435:
			_request_waypoint(point_to_world(event.position), event.shift_pressed)
			accept_event()
		return
	if (flight_navigation or ship_waypoint_input) and event is InputEventKey and event.pressed:
		if event.is_echo() and event.keycode in [KEY_ENTER, KEY_KP_ENTER]: return
		var step := display_range_km / 20.0
		match event.keycode:
			KEY_LEFT: _keyboard_offset_km.x -= step
			KEY_RIGHT: _keyboard_offset_km.x += step
			KEY_UP: _keyboard_offset_km.y -= step
			KEY_DOWN: _keyboard_offset_km.y += step
			KEY_ENTER, KEY_KP_ENTER: _request_waypoint(own_position_km + _keyboard_offset_km, event.shift_pressed)
			_: return
		_keyboard_offset_km = _keyboard_offset_km.limit_length(display_range_km)
		accept_event()
		queue_redraw()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if contact_visible and event.position.distance_to(_contact_position()) <= 23.0:
			contact_selected_state = true
			contact_selected.emit(contact_id)
			queue_redraw()
			accept_event()
		else:
			clear_selection()

func _request_waypoint(position_km: Vector2, append: bool) -> void:
	if ship_waypoint_input and not flight_navigation and append:
		ship_waypoint_append_requested.emit(position_km)
	else:
		waypoint_requested.emit(position_km)

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.435
	draw_circle(center, radius + 20.0, Color("#20302a"))
	draw_arc(center, radius + 19.0, 0.0, TAU, 160, Color("#829285"), 2.0, true)
	draw_circle(center, radius + 8.0, Color("#07130e"))
	draw_arc(center, radius + 7.0, 0.0, TAU, 160, Color("#40674b"), 2.0, true)
	draw_circle(center, radius, DARK)
	_draw_grid(center, radius)
	_draw_depth_chart(center, radius)
	if gun_arc_visible:
		_draw_gun_arc(center, radius)
	_draw_land(center, radius)
	_draw_facilities(center, radius)
	_draw_echoes(center, radius)
	if sweep_enabled:
		_draw_sweep(center, radius)
	_draw_ownship(center, radius)
	if flight_navigation:
		_draw_navigation(center, radius)
	else:
		_draw_ship_route(center, radius)
	_draw_contact(center, radius)
	_draw_prediction(center, radius)
	_draw_ballistics(center, radius)
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
	var key := [own_position_km, display_range_km, radius, land_areas.hash()]
	if key != _coast_key:
		_coast_key = key
		_coast_polygons.clear()
		for island in land_areas:
			var offset: Vector2 = (island.center - own_position_km) * radius / display_range_km
			var reach: float = island.radius_km * radius / display_range_km
			if offset.length() - reach >= radius: continue
			var points := PackedVector2Array()
			for index in range(96): points.append(offset + Vector2.from_angle(TAU * index / 96.0) * reach)
			var clipped := ChartGeometry.clip_polygon_circle(points, radius - 1)
			if clipped.size() >= 3: _coast_polygons.append(clipped)
	for polygon in _coast_polygons:
		var points := PackedVector2Array()
		for point in polygon: points.append(center + point)
		draw_colored_polygon(points, Color(0.12, 0.32, 0.18, 0.46))
		points.append(points[0])
		draw_polyline(points, Color(COAST, 0.55), 1.0, true)

func _draw_depth_chart(center: Vector2, radius: float) -> void:
	var key := [own_position_km, display_range_km, radius]
	if key != _depth_key:
		_depth_key = key
		_depth_lines.clear()
		for contour in depth_contours:
			for segment in contour.segments:
				var clipped := ChartGeometry.clip_circle((segment[0] - own_position_km) * radius / display_range_km, (segment[1] - own_position_km) * radius / display_range_km, radius - 2)
				if clipped.size() == 2: _depth_lines.append(clipped)
	for line in _depth_lines:
		draw_line(center + line[0], center + line[1], Color(0.30, 0.58, 0.66, 0.28), 1.0, true)
	_drawn_depth_labels = depth_chart_labels(radius)
	for label in _drawn_depth_labels:
		draw_string(ThemeDB.fallback_font, center + label.point, "%dm" % label.depth_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#668f96"))

func depth_chart_labels(radius: float) -> Array[Dictionary]:
	var labels: Array[Dictionary] = []
	var occupied := _chart_tactical_rects(radius)
	for marker in chart_facility_markers(radius):
		occupied.append(marker.icon_rect.grow(3))
		if marker.caption_visible: occupied.append(marker.caption_rect.grow(3))
	if contact_visible:
		var contact_point := Vector2(sin(deg_to_rad(bearing_degrees)), -cos(deg_to_rad(bearing_degrees))) * range_km * radius / display_range_km
		occupied.append(Rect2(contact_point - Vector2(22, 22), Vector2(70, 44)))
	for contour in depth_contours:
		for index in range(contour.segments.size()):
			var segment: PackedVector2Array = contour.segments[(index + labels.size() * 32) % contour.segments.size()]
			var point: Vector2 = (segment[0] - own_position_km) * radius / display_range_km
			if point.length() > radius - 36 or point.length() < 25: continue
			var rect := Rect2(point + Vector2(-2, -12), Vector2(36, 16))
			var free := true
			for previous in occupied:
				if previous.intersects(rect):
					free = false
					break
			if not free: continue
			labels.append({"depth_m": contour.depth_m, "point": point, "rect": rect})
			occupied.append(rect.grow(4))
			break
	return labels

func _chart_tactical_rects(radius: float) -> Array[Rect2]:
	var occupied: Array[Rect2] = [Rect2(-36, -36, 72, 72)]
	if contact_visible:
		var point := Vector2.UP.rotated(deg_to_rad(bearing_degrees)) * range_km * radius / display_range_km
		occupied.append(Rect2(point - Vector2(30, 30), Vector2(130, 70)))
	if flight_navigation:
		for location in [carrier_position_km, airfield_position_km]:
			var point: Vector2 = ((location - own_position_km) * radius / display_range_km).limit_length(radius - 24)
			occupied.append(Rect2(point - Vector2(38, 35), Vector2(100, 65)))
		if navigation_target_visible:
			var point := ((navigation_target_km - own_position_km) * radius / display_range_km).limit_length(radius - 18)
			occupied.append(Rect2(point - Vector2(15, 15), Vector2(30, 30)))
	return occupied

func chart_facility_markers(radius: float) -> Array[Dictionary]:
	var key := [own_position_km, display_range_km, radius, chart_facilities.hash(), contact_visible, bearing_degrees, range_km, flight_navigation, carrier_position_km, airfield_position_km, navigation_target_visible, navigation_target_km]
	if key == _marker_key: return _markers
	_marker_key = key
	var result: Array[Dictionary] = []
	var occupied := _chart_tactical_rects(radius)
	var pixels := clampf(34.0 * MAX_RANGE_KM / display_range_km, 32, 48)
	for facility in visible_chart_facilities():
		# Flight recovery marker owns AF1, including its off-screen bearing.
		if flight_navigation and facility.id == "facility.airfield.01": continue
		var anchor: Vector2 = (facility.position_km - own_position_km) * radius / display_range_km
		var point := anchor.limit_length(maxf(0, radius - pixels * 0.72))
		var candidates: Array[Vector2] = [Vector2.ZERO]
		for distance in [44, 88, 132]:
			for direction in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1)]: candidates.append(direction * distance)
		for delta in candidates:
			var candidate: Vector2 = point + delta
			if candidate.length() > radius - pixels * 0.72: continue
			var candidate_rect := Rect2(candidate - Vector2.ONE * pixels * 0.5, Vector2.ONE * pixels)
			var free := true
			for rect in occupied:
				if candidate_rect.intersects(rect):
					free = false
					break
			if free:
				point = candidate
				break
		var icon_rect := Rect2(point - Vector2.ONE * pixels * 0.5, Vector2.ONE * pixels)
		occupied.append(icon_rect.grow(3))
		result.append({"facility": facility, "anchor": anchor, "point": point, "pixels": pixels, "icon_rect": icon_rect, "caption_visible": false, "caption_rect": Rect2()})
	# Place all symbols first, so captions cannot cover a later facility.
	for marker in result:
		var text_width := ThemeDB.fallback_font.get_string_size(marker.facility.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		for delta in [Vector2(marker.pixels * 0.5 + 4, -4), Vector2(-text_width * 0.5, marker.pixels * 0.5 + 14), Vector2(-text_width - marker.pixels * 0.5 - 4, -4), Vector2(-text_width * 0.5, -marker.pixels * 0.5 - 5)]:
			var point: Vector2 = marker.point + delta
			var rect := Rect2(point - Vector2(0, 11), Vector2(text_width, 14))
			if rect.position.length() > radius - 4 or rect.end.length() > radius - 4: continue
			var free := true
			for previous in occupied:
				if previous.intersects(rect):
					free = false
					break
			if not free: continue
			marker.caption_visible = true
			marker.caption_point = point
			marker.caption_rect = rect
			occupied.append(rect.grow(2))
			break
	_markers = result
	return _markers

func _draw_facilities(center: Vector2, radius: float) -> void:
	for marker in chart_facility_markers(radius):
		if marker.point.distance_to(marker.anchor) > 2:
			draw_line(center + marker.anchor, center + marker.point, Color(COAST, 0.5), 1, true)
			draw_circle(center + marker.anchor, 1.5, COAST)
		var facility: Dictionary = marker.facility
		preload("res://scripts/data/unit_glyph.gd").draw(self, center + marker.point, marker.pixels, facility.family, Color("#8ab9a3"), facility.size_class, facility.variant, false, facility.get("component", ""))
		if marker.caption_visible:
			draw_string(ThemeDB.fallback_font, center + marker.caption_point, facility.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#92bba5"))

func _draw_echoes(center: Vector2, radius: float) -> void:
	for echo in _echoes:
		var offset: Vector2 = echo["position_km"] - own_position_km
		if offset.length() > display_range_km:
			continue
		var age: float = maxf(0.0, WorldClock.elapsed_seconds - float(echo["time"]))
		var energy: float = Decay.energy(age, ECHO_LIFETIME_SECONDS) * float(echo["strength"])
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
	if not GameManager.ship_afloat and not flight_navigation:
		draw_line(center + Vector2(-10, -10), center + Vector2(10, 10), AMBER, 2, true)
		draw_line(center + Vector2(-10, 10), center + Vector2(10, -10), AMBER, 2, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(16, 4), "WRECK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AMBER)
		return
	var direction := Vector2(sin(deg_to_rad(own_heading_degrees)), -cos(deg_to_rad(own_heading_degrees)))
	draw_line(center, center + direction * 28.0, OWN_SHIP, 2.0, true)
	draw_circle(center, 4.0, Color("#b7dbe0"))
	var task: TaskDefinition = DataManager.get_definition(GameManager.current_task_id) as TaskDefinition
	var ship: ShipDefinition = DataManager.get_definition(task.ship_id) as ShipDefinition if task != null else null
	if flight_navigation:
		_draw_plane(center, own_heading_degrees)
	elif ship != null:
		_draw_unit_symbol(center, ship.visual_family_id, OWN_SHIP, own_heading_degrees, ship.symbol_texture, ship.size_class, ship.shape_variant)
	draw_arc(center, 12.0, 0.0, TAU, 32, Color("#3c7977"), 1.0)
	if aircraft_visible and not flight_navigation:
		var offset := aircraft_position_km - own_position_km
		if offset.length() <= display_range_km:
			var point := center + offset * radius / display_range_km
			_draw_plane(point, MissionController.aircraft_heading_degrees)

func _draw_plane(point: Vector2, heading: float) -> void:
	var outline := PackedVector2Array([Vector2(0, -10), Vector2(-8, 6), Vector2(0, 2), Vector2(8, 6), Vector2(0, -10)])
	for index in range(outline.size()):
		outline[index] = point + outline[index].rotated(deg_to_rad(heading))
	draw_polyline(outline, OWN_SHIP, 1.8, true)

func _draw_navigation(center: Vector2, radius: float) -> void:
	if carrier_afloat:
		var task: TaskDefinition = DataManager.definitions.get(GameManager.current_task_id) as TaskDefinition
		var ship: ShipDefinition = DataManager.definitions.get(task.ship_id) as ShipDefinition if task != null else null
		if ship != null:
			_draw_recovery_marker(center, radius, carrier_position_km, "CV", 2.0, OWN_SHIP, ship.visual_family_id, WorldState.ship_heading_degrees, ship.symbol_texture)
	_draw_recovery_marker(center, radius, airfield_position_km, "AF", 3.0, COAST, "building.airfield")
	if navigation_target_visible:
		var offset := (navigation_target_km - own_position_km) * radius / display_range_km
		var point := center + offset.limit_length(radius - 18.0)
		draw_line(center, point, Color(AMBER, 0.48), 1.0, true)
		draw_arc(point, 7.0, 0.0, TAU, 24, AMBER, 1.4, true)
		draw_line(point + Vector2(-10, 0), point + Vector2(10, 0), AMBER, 1.0)
		draw_line(point + Vector2(0, -10), point + Vector2(0, 10), AMBER, 1.0)
	if has_focus():
		var cursor := center + _keyboard_offset_km * radius / display_range_km
		draw_arc(cursor, 11.0, 0.0, TAU, 24, HOT, 1.0, true)

func _draw_ship_route(center: Vector2, radius: float) -> void:
	var points: Array = ship_route.get("points", [])
	var previous := own_position_km
	var occupied := _chart_tactical_rects(radius)
	for marker in chart_facility_markers(radius):
		occupied.append(marker.icon_rect.grow(3))
		if marker.caption_visible: occupied.append(marker.caption_rect.grow(3))
	for depth_label in _drawn_depth_labels: occupied.append(depth_label.rect.grow(2))
	for index in range(points.size()):
		var offset: Vector2 = (points[index] - own_position_km) * radius / display_range_km
		var from: Vector2 = (previous - own_position_km) * radius / display_range_km
		var clipped := ChartGeometry.clip_circle(from, offset, radius - 2)
		if clipped.size() == 2: draw_line(center + clipped[0], center + clipped[1], Color(OWN_SHIP, 0.55 if index == 0 else 0.32), 1.0, true)
		previous = points[index]
		if offset.length() > radius and index > 0: continue
		var point := center + offset.limit_length(radius - 18)
		var tint := OWN_SHIP if index == 0 else Color("#65858c")
		draw_rect(Rect2(point - Vector2.ONE * 5, Vector2.ONE * 10), tint, false, 1.5)
		var number: int = ship_route.get("reached", 0) + index + 1
		var label := "WP%d" % number
		if offset.length() > radius: label += " %.1f km" % points[index].distance_to(own_position_km)
		var label_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		for label_offset in [Vector2(10, 19), Vector2(-label_size.x - 10, 19), Vector2(10, -12), Vector2(-label_size.x - 10, -12)]:
			var baseline: Vector2 = point - center + label_offset
			var rect := Rect2(baseline - Vector2(0, label_size.y), label_size).grow(2)
			var free := true
			for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
				if corner.length() > radius - 2: free = false
			for blocked in occupied:
				if blocked.intersects(rect): free = false
			if not free: continue
			draw_string(ThemeDB.fallback_font, center + baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)
			occupied.append(rect)
			break
	if ship_route.get("status", "") == "arrived":
		draw_rect(Rect2(center - Vector2.ONE * 6, Vector2.ONE * 12), OWN_SHIP, false, 1.5)
		draw_string(ThemeDB.fallback_font, center + Vector2(12, 21), "WP / STOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, OWN_SHIP)
	if ship_waypoint_input and has_focus():
		var cursor := center + _keyboard_offset_km * radius / display_range_km
		draw_arc(cursor, 11.0, 0.0, TAU, 24, HOT, 1.0, true)

func _draw_recovery_marker(center: Vector2, radius: float, world_point: Vector2, label: String, window_km: float, tint: Color, family: String, heading: float = 0.0, texture: Texture2D = null) -> void:
	var offset := world_point - own_position_km
	var point := center + (offset * radius / display_range_km).limit_length(radius - 24.0)
	if offset.length() + window_km <= display_range_km:
		draw_arc(point, window_km * radius / display_range_km, 0.0, TAU, 48, Color(tint, 0.3), 1.0, true)
	_draw_unit_symbol(point, family, tint, heading, texture)
	var caption := "%s %.1f km" % [label, offset.length()] if offset.length() > display_range_km else label
	var text_offset := Vector2(14, -14) if point.x > center.x else Vector2(-24, -14)
	if offset.length() > display_range_km:
		text_offset = Vector2(-82, -14) if point.x > center.x else Vector2(14, -14)
	draw_string(ThemeDB.fallback_font, point + text_offset, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)

func contact_energy() -> float:
	return Decay.energy(WorldClock.elapsed_seconds - MissionController.last_contact_seconds, ECHO_LIFETIME_SECONDS)

func _draw_unit_symbol(point: Vector2, family: String, tint: Color, heading: float = NAN, texture: Texture2D = null, size_class: String = "medium", variant: int = 1) -> void:
	var pixels := clampf(34.0 * MAX_RANGE_KM / display_range_km, 32, 48)
	var rotates := family.begins_with("ship.") and is_finite(heading)
	if rotates:
		draw_set_transform(point, deg_to_rad(heading))
	var origin := Vector2.ZERO if rotates else point
	if texture != null:
		draw_texture_rect(texture, Rect2(origin - Vector2.ONE * pixels * 0.5, Vector2.ONE * pixels), false, tint)
	else:
		preload("res://scripts/data/unit_glyph.gd").draw(self, origin, pixels, family, tint, size_class, variant)
	if rotates:
		draw_set_transform(Vector2.ZERO)
	if family.begins_with("ship.") and is_finite(heading):
		var direction := Vector2.UP.rotated(deg_to_rad(heading))
		var tip := point + direction * (pixels * 0.5 + 11)
		draw_line(tip - direction * 7, tip, tint)
		draw_line(tip, tip - direction.rotated(0.6) * 5, tint)
		draw_line(tip, tip - direction.rotated(-0.6) * 5, tint)

func _draw_contact(_center: Vector2, _radius: float) -> void:
	if not contact_visible:
		return
	var point := _contact_position()
	var strength := contact_energy()
	var tint := AMBER if contact_selected_state else PHOSPHOR
	draw_circle(point, 22.0, Color(tint, 0.045 * strength))
	draw_circle(point, 12.0, Color(tint, 0.10 * strength))
	draw_circle(point, 6.0, Color(tint, 0.3 * strength))
	if not contact_confirmed:
		if MissionController.contact_scan_count < 2:
			preload("res://scripts/data/unit_glyph.gd").unknown(self, point, Color(tint, strength))
		else:
			var definition: ContactDefinition = DataManager.get_definition(contact_id) as ContactDefinition
			var category: ShipDefinition = DataManager.get_definition(definition.identified_ship_id) as ShipDefinition if definition != null else null
			if category != null:
				# Category stage uses canonical geometry; model/size/variant remain concealed.
				_draw_unit_symbol(point, category.visual_family_id, Color(tint, strength))
	if contact_confirmed:
		var contact: ContactDefinition = DataManager.get_definition(contact_id) as ContactDefinition
		if contact != null and not contact.identified_ship_id.is_empty():
			var ship: ShipDefinition = DataManager.get_definition(contact.identified_ship_id) as ShipDefinition
			if ship != null:
				_draw_unit_symbol(point, ship.visual_family_id, Color(tint, strength), MissionController.last_contact_heading_degrees, ship.symbol_texture, ship.size_class, ship.shape_variant)
	if contact_selected_state:
		draw_arc(point, 17.0, 0.0, TAU, 40, AMBER, 1.5, true)
	if fire_control_assigned and not flight_navigation:
		draw_rect(Rect2(point - Vector2(27, 27), Vector2(54, 54)), Color(AMBER, strength), false, 1)
		draw_string(ThemeDB.fallback_font, point + Vector2(30, 20), "GUN / A1", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(AMBER, strength))
	# Neutral contact bracket; identity is not assumed before confirmation.
	draw_line(point + Vector2(-19, -19), point + Vector2(-11, -19), Color(tint, strength))
	draw_line(point + Vector2(-19, -19), point + Vector2(-19, -11), Color(tint, strength))
	if contact_confirmed or contact_selected_state:
		draw_string(ThemeDB.fallback_font, point + Vector2(21, -8), "A1 / TRACK" if contact_confirmed else "A1 / SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)

func _draw_prediction(center: Vector2, radius: float) -> void:
	if flight_navigation or not fire_control_assigned or not contact_visible or not contact_confirmed or not _fire_control_prediction.get("valid", false):
		return
	var aim: Vector2 = _fire_control_prediction.aim_position_km
	var offset := aim - own_position_km
	if offset.length() > display_range_km:
		return
	var point := center + offset * radius / display_range_km
	var tint := Color(AMBER, contact_energy())
	draw_dashed_line(_contact_position(), point, tint, 1, 3)
	draw_line(point + Vector2(-6, -6), point + Vector2(6, 6), tint)
	draw_line(point + Vector2(-6, 6), point + Vector2(6, -6), tint)
	var label_offset := Vector2(-96 if point.x > center.x else 14, 42)
	draw_string(ThemeDB.fallback_font, point + label_offset, "LEAD +%.1fs" % _fire_control_prediction.flight_seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)

func _draw_ballistics(center: Vector2, radius: float) -> void:
	if flight_navigation: return
	for shot in _gun_projectiles:
		var origin: Vector2 = shot.origin_km
		var aim: Vector2 = shot.aim_position_km
		var fraction := clampf((WorldClock.elapsed_seconds - shot.fired_seconds) / shot.flight_seconds, 0, 1)
		var flight_offset := origin.lerp(aim, fraction) - own_position_km
		if flight_offset.length() <= display_range_km:
			draw_circle(center + flight_offset * radius / display_range_km, 2.5, HOT)
	if not _gun_impact.get("observed", false): return
	var age: float = WorldClock.elapsed_seconds - _gun_impact.impact_seconds
	if age < 0 or age > 15: return
	var offset: Vector2 = _gun_impact.aim_position_km - own_position_km
	if offset.length() > display_range_km: return
	var point := center + offset * radius / display_range_km
	var tint := Color(HOT if _gun_impact.result == "hit" else AMBER, 1 - age / 15)
	draw_arc(point, 8 + age * 0.3, 0, TAU, 24, tint, 1)
	if _gun_impact.result != "hit":
		var error: Vector2 = _gun_impact.error_km
		var text := "SPLASH %.0fm E%.0f N%.0f" % [error.length() * 1000, error.x * 1000, -error.y * 1000]
		draw_string(ThemeDB.fallback_font, point + Vector2(-75, -32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)

func _draw_readout(center: Vector2, radius: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-7, -radius - 11), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PHOSPHOR)
	draw_string(font, center + Vector2(radius + 7, 5), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRID)
	draw_string(font, center + Vector2(-7, radius + 18), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRID)
	draw_string(font, center + Vector2(-radius - 16, 5), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRID)
	draw_string(font, center + Vector2(-radius + 2, radius + 28), "NAV / AIRCRAFT" if flight_navigation else "PPI / SEARCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#73a984"))
	draw_string(font, center + Vector2(radius - 80, radius + 28), "%.1f KM" % display_range_km, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#73a984"))

func _draw_gun_arc(center: Vector2, radius: float) -> void:
	for group in MissionController.gun_groups():
		var selected: bool = group.mount_id == MissionController.selected_mount_id
		var origin: Vector2 = center + (group.origin_km - own_position_km) * radius / display_range_km
		var reach := radius * minf(float(group.range_km) / display_range_km, 1.0)
		var start := deg_to_rad(float(group.heading) - float(group.half_arc) - 90)
		var end := deg_to_rad(float(group.heading) + float(group.half_arc) - 90)
		var tint := PHOSPHOR if selected and gun_ready else AMBER if selected else GRID
		var alpha := 0.45 if selected else 0.18
		draw_arc(origin, reach, start, end, 64, Color(tint, alpha), 1.2 if selected else 0.8, true)
		for angle in [start, end]:
			draw_line(origin, origin + Vector2(cos(angle), sin(angle)) * reach, Color(tint, alpha * 0.6), 1.0, true)
		if selected and MissionController.fire_control_locked:
			var barrel_angle := deg_to_rad(MissionController.turret_heading_degrees - 90)
			draw_line(origin, origin + Vector2(cos(barrel_angle), sin(barrel_angle)) * reach, Color(PHOSPHOR, 0.7), 1.5, true)

func _contact_position() -> Vector2:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.435
	var distance := clampf(range_km / display_range_km, 0.0, 1.0) * radius
	var radians := deg_to_rad(bearing_degrees)
	return center + Vector2(sin(radians), -cos(radians)) * distance
