extends Control

const CRT_SCENE: PackedScene = preload("res://scenes/main/crt_main.tscn")
const BACKGROUND := Color("080e0b")
const STEEL := Color("28352e")
const PANEL := Color("111e17")
const INSET := Color("07120c")
const EDGE := Color("506353")
const PHOSPHOR := Color("8be6a3")
const MUTED := Color("749780")
const AMBER := Color("e8af58")

@onready var menu_crt: Control = $MenuCRT
@onready var game_crt_slot: Control = $GameCRTSlot
@onready var start_button: Button = $StartButton
@onready var top_message: Label = $TopMessage
@onready var time_value: Label = $TimeValue
@onready var ammo_value: Label = $AmmoValue
@onready var mode_value: Label = $ModeValue
@onready var hull_value: Label = $HullValue

var started: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var console_theme := Theme.new()
	var terminal_font := SystemFont.new()
	terminal_font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Microsoft YaHei"])
	console_theme.default_font = terminal_font
	console_theme.default_font_size = 20
	theme = console_theme
	_style_start_button()
	get_tree().paused = true
	start_button.pressed.connect(_start_game)
	start_button.grab_focus()
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	MissionController.state_changed.connect(_refresh_status)
	_refresh_status()

func _style_start_button() -> void:
	start_button.add_theme_stylebox_override("normal", _button_style(Color("3a3020"), AMBER))
	start_button.add_theme_stylebox_override("hover", _button_style(Color("584125"), Color("ffd083")))
	start_button.add_theme_stylebox_override("pressed", _button_style(AMBER, AMBER))
	var focus := _button_style(Color.TRANSPARENT, Color("f6e6b9"))
	focus.draw_center = false
	start_button.add_theme_stylebox_override("focus", focus)
	start_button.add_theme_color_override("font_color", Color("ffe6ad"))
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	start_button.add_theme_color_override("font_pressed_color", Color("11180f"))
	start_button.add_theme_font_size_override("font_size", 26)

func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style

func _start_game() -> void:
	if started:
		return
	started = true
	menu_crt.hide()
	start_button.hide()
	MissionController.restart_scenario()
	game_crt_slot.add_child(CRT_SCENE.instantiate())
	game_crt_slot.show()
	_refresh_status()

func _on_world_time_advanced(_total_seconds: float) -> void:
	if started:
		_refresh_status()

func _refresh_status() -> void:
	if not is_node_ready():
		return
	if started:
		top_message.text = "SYSTEM ONLINE  /  作战情报中心已上线"
		time_value.text = WorldClock.formatted_time()
		ammo_value.text = "甲板炮余弹  %02d    /    对海弹  %01d" % [MissionController.ship_ammo, MissionController.aircraft_bombs]
		mode_value.text = "指挥模式  /  %s" % GameManager.mode.to_upper()
		hull_value.text = "舰体完整度  %03.0f%%" % MissionController.ship_health
	else:
		top_message.text = "SYSTEM STANDBY  /  指挥终端待命"
		time_value.text = "T+00:00"
		ammo_value.text = "甲板炮余弹  --    /    对海弹  --"
		mode_value.text = "指挥模式  /  待机"
		hull_value.text = "舰体完整度  ---"
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	_panel(Rect2(30, 25, 1860, 1030), STEEL, EDGE, 4.0)
	_panel(Rect2(47, 43, 1826, 994), Color("17231b"), Color("384a3d"), 2.0)
	_panel(Rect2(70, 130, 230, 765), PANEL, EDGE, 2.0)
	_panel(Rect2(320, 65, 1280, 90), INSET, EDGE, 2.0)
	_panel(Rect2(1620, 130, 230, 765), PANEL, EDGE, 2.0)
	_panel(Rect2(70, 915, 230, 100), INSET, EDGE, 2.0)
	_panel(Rect2(320, 915, 1530, 100), INSET, EDGE, 2.0)
	for screw in [Vector2(52, 50), Vector2(1868, 50), Vector2(52, 1030), Vector2(1868, 1030)]:
		draw_circle(screw, 7.0, Color("07100b"))
		draw_line(screw + Vector2(-3, 3), screw + Vector2(3, -3), EDGE, 2.0, true)
	_draw_gauge(Vector2(185, 282), "HEADING", 0.25 if not started else WorldState.ship_heading_degrees / 360.0)
	_draw_gauge(Vector2(185, 510), "SPEED", 0.0 if not started else WorldState.ship_speed_knots / maxf(1.0, WorldState.ship_max_speed_knots))
	_draw_gauge(Vector2(185, 738), "HULL", 1.0 if not started else MissionController.ship_health / 100.0)
	_draw_hardware_rails()

func _panel(rect: Rect2, fill: Color, border: Color, border_width: float) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, border_width)

func _draw_gauge(center: Vector2, label: String, fraction: float) -> void:
	draw_arc(center, 74.0, PI * 0.77, PI * 2.23, 56, EDGE, 3.0, true)
	draw_arc(center, 61.0, 0.0, TAU, 64, Color("263e30"), 1.0, true)
	for mark in range(9):
		var angle := PI * (0.77 + float(mark) * 1.46 / 8.0)
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * 57.0, center + direction * 70.0, MUTED, 2.0, true)
	var needle_angle := PI * (0.77 + clampf(fraction, 0.0, 1.0) * 1.46)
	draw_line(center, center + Vector2(cos(needle_angle), sin(needle_angle)) * 52.0, AMBER, 3.0, true)
	draw_circle(center, 6.0, AMBER)
	draw_string(ThemeDB.fallback_font, center + Vector2(-36, 104), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PHOSPHOR)

func _draw_hardware_rails() -> void:
	for index in range(4):
		var y := 250.0 + float(index) * 118.0
		draw_rect(Rect2(1660, y, 150, 46), INSET)
		draw_rect(Rect2(1660, y, 150, 46), Color("385041"), false, 2.0)
		draw_line(Vector2(1682, y + 23), Vector2(1788, y + 23), EDGE, 2.0)
		draw_circle(Vector2(1698 + index * 23, y + 23), 8.0, Color("708275"))
	draw_circle(Vector2(1735, 808), 11.0, PHOSPHOR if started else AMBER)
