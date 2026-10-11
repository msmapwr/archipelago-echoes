extends Control

signal departure_reached
signal menu_requested

const Navigation = preload("res://scripts/world/harbor_navigation.gd")
var navigation = Navigation.new()
var locally_paused: bool = false
var time_scale: float = 1.0
var status: Label
var feedback: Label
var chart: Control
var cast_off_button: Button
var pause_button: Button
var scale_button: Button
var menu_button: Button
var command_buttons: Array[Button] = []

class HarborChart extends Control:
	var navigation: RefCounted
	func _point(value: Vector2) -> Vector2:
		return Vector2(24, 24) + (value - Navigation.WATER_BOUNDS.position) * (size - Vector2(48, 48)) / Navigation.WATER_BOUNDS.size
	func _draw() -> void:
		if navigation == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color("#061b14"))
		for index in range(11):
			var x := 24.0 + float(index) * (size.x - 48.0) / 10.0
			draw_line(Vector2(x, 24), Vector2(x, size.y - 24), Color("#183b2a"))
		for index in range(9):
			var y := 24.0 + float(index) * (size.y - 48.0) / 8.0
			draw_line(Vector2(24, y), Vector2(size.x - 24, y), Color("#183b2a"))
		for obstacle in Navigation.OBSTACLES:
			var rect := Rect2(_point(obstacle.position), _point(obstacle.end) - _point(obstacle.position))
			draw_rect(rect, Color("#244536"))
			draw_rect(rect, Color("#88aa91"), false, 2.0)
		# Berth lines and warehouses stay inside the solid quay's collision bounds.
		for berth in range(3):
			var y := -0.36 + berth * 0.22
			draw_line(_point(Vector2(-0.55, y)), _point(Vector2(-0.32, y)), Color("#e8b968"), 3)
			draw_string(get_theme_default_font(), _point(Vector2(-0.85, y)), "B%02d" % (berth + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#bfd0bb"))
			draw_rect(Rect2(_point(Vector2(-0.95, y - 0.12)), _point(Vector2(-0.66, y - 0.03)) - _point(Vector2(-0.95, y - 0.12))), Color("#55715a"), false, 2)
		draw_string(get_theme_default_font(), _point(Vector2(-0.92, 0.24)), "码头 / 泊位", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#bfd0bb"))
		draw_string(get_theme_default_font(), _point(Vector2(0.44, -0.60)), "防波堤", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#bfd0bb"))
		var gate_left := _point(Vector2(-Navigation.EXIT_HALF_WIDTH_KM, Navigation.EXIT_Y_KM))
		var gate_right := _point(Vector2(Navigation.EXIT_HALF_WIDTH_KM, Navigation.EXIT_Y_KM))
		draw_line(gate_left, gate_right, Color("#e8b968"), 3.0)
		draw_string(get_theme_default_font(), gate_left + Vector2(-18, -12), "离港线 / N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#e8b968"))
		draw_dashed_line(_point(Vector2.ZERO), _point(Vector2(0, Navigation.EXIT_Y_KM)), Color("#5c9971"), 1.0, 8.0)
		var ship := _point(navigation.position_km)
		var direction := Vector2(sin(deg_to_rad(navigation.heading_degrees)), -cos(deg_to_rad(navigation.heading_degrees)))
		draw_set_transform(ship, deg_to_rad(navigation.heading_degrees))
		preload("res://scripts/data/unit_glyph.gd").draw(self, Vector2.ZERO, 60, "ship.escort_carrier", Color("#a5f1ba"))
		draw_set_transform(Vector2.ZERO)
		draw_line(ship + direction * 25, ship + direction * 36, Color("#a5f1ba"), 2)
		draw_line(ship + direction * 36, ship + direction * 36 - direction.rotated(0.6) * 7, Color("#a5f1ba"), 2)
		draw_line(ship + direction * 36, ship + direction * 36 - direction.rotated(-0.6) * 7, Color("#a5f1ba"), 2)
		draw_string(get_theme_default_font(), Vector2(35, size.y - 4), "港区 2 km · 码头 / 防波堤", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#a4c6af"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bezel := Control.new()
	bezel.set_script(preload("res://scripts/ui/crt_bezel.gd"))
	add_child(bezel)
	bezel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 42)
	panel.size = Vector2(1200, 636)
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color("#04110d")
	glass.set_corner_radius_all(22)
	glass.content_margin_left = 32
	glass.content_margin_right = 32
	glass.content_margin_top = 24
	glass.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", glass)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var title := Label.new()
	title.text = "港口出航 / HARBOR CONTROL     ·     指令部命令已接收"
	title.add_theme_color_override("font_color", Color("#a5f1ba"))
	column.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	chart = HarborChart.new()
	chart.navigation = navigation
	chart.custom_minimum_size = Vector2(620, 380)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(chart)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 360
	controls.add_theme_constant_override("separation", 8)
	row.add_child(controls)
	status = Label.new()
	status.add_theme_color_override("font_color", Color("#a4c6af"))
	controls.add_child(status)
	cast_off_button = _button(controls, "解缆", func() -> void: navigation.cast_off(); _refresh())
	var turn_row := HBoxContainer.new()
	controls.add_child(turn_row)
	command_buttons.append(_button(turn_row, "左转 15°", func() -> void: command(-15, 0)))
	command_buttons.append(_button(turn_row, "右转 15°", func() -> void: command(15, 0)))
	var speed_row := HBoxContainer.new()
	controls.add_child(speed_row)
	command_buttons.append(_button(speed_row, "加速 2 kn", func() -> void: command(0, 2)))
	command_buttons.append(_button(speed_row, "减速 2 kn", func() -> void: command(0, -2)))
	command_buttons.append(_button(controls, "停车", func() -> void: navigation.set_command(navigation.heading_degrees, 0); _refresh()))
	var time_row := HBoxContainer.new()
	controls.add_child(time_row)
	pause_button = _button(time_row, "暂停", toggle_pause)
	scale_button = _button(time_row, "时间 ×1", func() -> void: time_scale = 10.0 if time_scale == 1.0 else 1.0; _refresh())
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_color_override("font_color", Color("#e8b968"))
	column.add_child(feedback)
	menu_button = _button(column, "返回主菜单", func() -> void: menu_requested.emit())
	cast_off_button.grab_focus()
	_refresh()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func command(turn: float, acceleration: float) -> void:
	navigation.set_command(navigation.heading_degrees + turn, clampf(navigation.speed_knots + acceleration, 0, Navigation.MAX_SPEED_KNOTS))
	_refresh()

func toggle_pause() -> void:
	locally_paused = not locally_paused
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_simulation") and not event.is_echo():
		toggle_pause()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	advance_navigation(delta * time_scale)

func advance_navigation(delta: float) -> void:
	if locally_paused or navigation.departed:
		return
	var departed: bool = navigation.advance(delta)
	_refresh()
	if departed:
		departure_reached.emit()

func _refresh() -> void:
	status.text = "航向 %03d°    航速 %.0f / 10 kn\n距离港线 %.0f m\n港内时间 %.0f 秒\n%s" % [roundi(navigation.heading_degrees), navigation.speed_knots, maxf(0, navigation.position_km.y - Navigation.EXIT_Y_KM) * 1000, navigation.elapsed_seconds, "港内已暂停" if locally_paused else "已系泊" if navigation.moored else "正在出航"]
	feedback.text = navigation.message + "\n离港前海上任务保持冻结；通过离港线后自动开始。"
	cast_off_button.disabled = not navigation.moored or locally_paused
	for button in command_buttons:
		button.disabled = navigation.moored or locally_paused
	pause_button.text = "继续" if locally_paused else "暂停"
	scale_button.text = "时间 ×%.0f" % time_scale
	chart.queue_redraw()
