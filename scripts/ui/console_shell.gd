extends Control

const CRT_SCENE: PackedScene = preload("res://scenes/main/crt_main.tscn")
const VOID := Color("#070c0f")
const SHELL := Color("#252e30")
const SHELL_LIGHT := Color("#3b4645")
const RECESS := Color("#0a1113")
const EDGE := Color("#748079")
const IVORY := Color("#d9decf")
const PHOSPHOR := Color("#83e8aa")
const AMBER := Color("#e8b968")
const RED := Color("#d86d5d")

@onready var menu_crt: Control = $MenuCRT
@onready var game_crt_slot: Control = $GameCRTSlot
@onready var start_button: Button = $StartButton
@onready var top_message: Label = $TopMessage
@onready var time_value: Label = $TimeValue
@onready var ammo_value: Label = $AmmoValue
@onready var mode_value: Label = $ModeValue
@onready var hull_value: Label = $HullValue
@onready var video_monitor: Control = $VideoMonitor
@onready var aux_status: Label = $AuxStatus
@onready var start_caption: Label = $StartCaption
@onready var menu_status: Label = $MenuCRT/MenuStatus
@onready var self_test: Label = $MenuCRT/SelfTest

var started: bool = false
var _displayed_second: int = -1
var _instrument_font: Font
var _boot_seconds: float = 0.0
var _boot_phase: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var display_font := SystemFont.new()
	display_font.font_names = PackedStringArray(["Bahnschrift", "Microsoft YaHei", "Arial"])
	var mono_font := SystemFont.new()
	mono_font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Microsoft YaHei"])
	_instrument_font = mono_font
	var console_theme := Theme.new()
	console_theme.default_font = display_font
	console_theme.default_font_size = 20
	theme = console_theme
	for label in [top_message, time_value, ammo_value, mode_value, hull_value]:
		label.add_theme_font_override("font", mono_font)
	_style_start_button()
	menu_crt.modulate.a = 0.06
	self_test.text = ""
	get_tree().paused = true
	start_button.pressed.connect(_start_game)
	start_button.grab_focus()
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	MissionController.state_changed.connect(_refresh_status)
	WorldState.ship_command_changed.connect(func(_heading: float, _speed: float) -> void: _refresh_status())
	_refresh_status()

func _style_start_button() -> void:
	start_button.add_theme_stylebox_override("normal", _button_style(Color("#642c29"), Color("#f3a784")))
	start_button.add_theme_stylebox_override("hover", _button_style(Color("#94423a"), Color("#ffe0b1")))
	start_button.add_theme_stylebox_override("pressed", _button_style(Color("#e79a77"), Color("#ffe5c3")))
	var focus := _button_style(Color.TRANSPARENT, Color("#fff0d2"))
	focus.draw_center = false
	start_button.add_theme_stylebox_override("focus", focus)
	start_button.add_theme_color_override("font_color", Color("#ffe4c4"))
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	start_button.add_theme_color_override("font_pressed_color", Color("#301915"))
	start_button.add_theme_font_size_override("font_size", 25)

func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 11.0
	style.content_margin_bottom = 11.0
	return style

func _process(delta: float) -> void:
	if started or _boot_seconds >= 2.2:
		return
	_boot_seconds += delta
	menu_crt.modulate.a = clampf(_boot_seconds / 0.9, 0.06, 1.0)
	var phase := mini(4, floori(_boot_seconds / 0.44))
	if phase == _boot_phase:
		return
	_boot_phase = phase
	var checks := [
		"RADAR ARRAY       ........  READY",
		"NAVIGATION        ........  READY",
		"FIRE CONTROL      ........  READY",
		"COMMUNICATION     ........  READY",
	]
	var visible_checks := PackedStringArray()
	for index in range(phase):
		visible_checks.append(checks[index])
	self_test.text = "\n".join(visible_checks)
	menu_status.text = "SYSTEM 07  /  高压启动中                                        SELF TEST / RUNNING" if phase < 4 else "SYSTEM 07  /  作战情报中心                                         SELF TEST / COMPLETE"

func _start_game() -> void:
	if started:
		return
	started = true
	menu_crt.hide()
	start_button.hide()
	MissionController.restart_scenario()
	game_crt_slot.add_child(CRT_SCENE.instantiate())
	game_crt_slot.show()
	aux_status.show()
	start_caption.text = "SYSTEM  /  ACTIVE"
	video_monitor.set("active", true)
	video_monitor.queue_redraw()
	_refresh_status()

func _on_world_time_advanced(total_seconds: float) -> void:
	var second := floori(total_seconds)
	if started and second != _displayed_second:
		_displayed_second = second
		_refresh_status()

func _refresh_status() -> void:
	if not is_node_ready():
		return
	if started:
		top_message.text = "CIC  /  指挥链路已建立     ·     作战情报中心在线"
		time_value.text = WorldClock.formatted_time()
		ammo_value.text = "甲板炮 %02d/06   ·   对海弹 %01d/01" % [MissionController.ship_ammo, MissionController.aircraft_bombs]
		mode_value.text = "MODE  /  %s" % GameManager.mode.to_upper()
		hull_value.text = "HULL   %03.0f%%" % MissionController.ship_health
		aux_status.text = "CIC   /   LIVE\nRADAR /   %s\nLINK  /   STABLE" % ("ACTIVE" if MissionController.radar_emitting else "SILENT")
	else:
		top_message.text = "CIC  /  指挥终端待机     ·     等待舰桥授权"
		time_value.text = "T+00:00"
		ammo_value.text = "甲板炮 --/06   ·   对海弹 --/01"
		mode_value.text = "MODE  /  STANDBY"
		hull_value.text = "HULL   ---"
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), VOID)
	_draw_housing()
	_draw_top_rail()
	_draw_instrument_bank()
	_draw_auxiliary_bank()
	_draw_footer()
	_draw_fasteners()

func _draw_housing() -> void:
	draw_rect(Rect2(18, 16, 1884, 1048), Color("#11191c"))
	draw_rect(Rect2(24, 22, 1872, 1036), SHELL)
	draw_line(Vector2(24, 22), Vector2(1896, 22), SHELL_LIGHT, 3.0)
	draw_line(Vector2(24, 22), Vector2(24, 1058), Color("#59645f"), 2.0)
	draw_line(Vector2(1896, 24), Vector2(1896, 1058), Color("#0d1415"), 4.0)
	draw_line(Vector2(24, 1058), Vector2(1896, 1058), Color("#0b1011"), 5.0)
	draw_rect(Rect2(39, 38, 1842, 1004), Color("#151e20"))
	draw_rect(Rect2(48, 47, 1824, 986), Color("#202a2b"), false, 2.0)
	for index in range(34):
		var x := 48.0 + float(index) * 54.0
		draw_line(Vector2(x, 49), Vector2(x + 10, 49), Color("#4d5a56"), 1.0)
		draw_line(Vector2(x, 1030), Vector2(x + 10, 1030), Color("#0b1213"), 1.0)
	draw_rect(Rect2(302, 151, 1316, 755), Color("#080e10"))
	draw_rect(Rect2(309, 158, 1302, 741), Color("#69716c"), false, 2.0)
	draw_line(Vector2(309, 158), Vector2(1611, 158), Color("#a0a79b"), 1.0)
	draw_line(Vector2(1611, 158), Vector2(1611, 899), Color("#0a1112"), 3.0)

func _draw_top_rail() -> void:
	_panel(Rect2(62, 62, 226, 76), Color("#111a1c"), Color("#65726b"))
	_panel(Rect2(307, 62, 1306, 76), Color("#0a1315"), Color("#5e7067"))
	_panel(Rect2(1632, 62, 226, 76), Color("#111a1c"), Color("#65726b"))
	draw_rect(Rect2(76, 76, 4, 47), AMBER)
	_caption(Vector2(92, 94), "OPERATIONS  /  07", IVORY, 17)
	_caption(Vector2(92, 120), "PACIFIC SECTOR", Color("#92a399"), 13)
	draw_circle(Vector2(1661, 99), 7.0, PHOSPHOR if started else AMBER)
	draw_circle(Vector2(1661, 99), 13.0, Color(0.45, 0.95, 0.64, 0.07))
	_caption(Vector2(1682, 105), "LINK   /   01", IVORY, 17)

func _draw_instrument_bank() -> void:
	_panel(Rect2(62, 165, 226, 729), Color("#121b1c"), Color("#65746c"))
	draw_rect(Rect2(69, 171, 212, 35), Color("#263230"))
	draw_line(Vector2(70, 207), Vector2(280, 207), Color("#59675f"), 1.0)
	_draw_gauge(Vector2(175, 284), "HEADING", 0.25 if not started else WorldState.ship_heading_degrees / 360.0, "---" if not started else "%03.0f°" % WorldState.ship_heading_degrees, AMBER)
	_draw_gauge(Vector2(175, 499), "SPEED", 0.0 if not started else WorldState.ship_speed_knots / maxf(1.0, WorldState.ship_max_speed_knots), "--" if not started else "%02.0f kn" % WorldState.ship_speed_knots, PHOSPHOR)
	_draw_gauge(Vector2(175, 714), "HULL", 1.0 if not started else MissionController.ship_health / 100.0, "---" if not started else "%03.0f%%" % MissionController.ship_health, PHOSPHOR if not started or MissionController.ship_health >= 50.0 else RED)

func _draw_gauge(center: Vector2, label: String, fraction: float, readout: String, accent: Color) -> void:
	draw_circle(center, 67.0, Color("#364240"))
	draw_circle(center, 62.0, Color("#101a1b"))
	draw_arc(center, 59.0, 0.0, TAU, 88, Color("#819086"), 1.0, true)
	draw_circle(center, 49.0, Color("#081112"))
	draw_arc(center, 45.0, PI * 0.78, PI * 2.22, 58, Color("#55665c"), 2.0, true)
	for mark in range(11):
		var angle := PI * (0.78 + float(mark) * 1.44 / 10.0)
		var vector := Vector2(cos(angle), sin(angle))
		draw_line(center + vector * 48.0, center + vector * (57.0 if mark % 2 == 0 else 54.0), Color("#aab4a3"), 2.0 if mark % 2 == 0 else 1.0, true)
	var needle_angle := PI * (0.78 + clampf(fraction, 0.0, 1.0) * 1.44)
	var needle := Vector2(cos(needle_angle), sin(needle_angle))
	draw_line(center - needle * 10.0, center + needle * 42.0, accent.darkened(0.45), 5.0, true)
	draw_line(center - needle * 10.0, center + needle * 42.0, accent, 2.0, true)
	draw_circle(center, 6.0, Color("#d3ddc6"))
	_caption(center + Vector2(-40, 88), label, Color("#9fb1a4"), 15)
	_caption(center + Vector2(-43, 115), readout, IVORY, 25)

func _draw_auxiliary_bank() -> void:
	_panel(Rect2(1632, 165, 226, 729), Color("#121b1c"), Color("#65746c"))
	draw_rect(Rect2(1639, 171, 212, 35), Color("#263230"))
	draw_line(Vector2(1640, 207), Vector2(1850, 207), Color("#59675f"), 1.0)
	var video_frame := StyleBoxFlat.new()
	video_frame.bg_color = Color("#050a0b")
	video_frame.border_color = Color("#53635b")
	video_frame.set_border_width_all(1)
	video_frame.set_corner_radius_all(18)
	draw_style_box(video_frame, Rect2(1644, 233, 202, 168))
	_panel(Rect2(1644, 422, 202, 176), Color("#24251e"), Color("#7e806f"))
	draw_rect(Rect2(1650, 629, 190, 59), Color("#0b1213"))
	draw_rect(Rect2(1650, 629, 190, 59), Color("#4f5e55"), false, 1.0)
	for index in range(3):
		var x := 1675.0 + float(index) * 67.0
		draw_circle(Vector2(x, 659), 15.0, Color("#2a3836"))
		draw_arc(Vector2(x, 659), 14.0, 0.0, TAU, 32, Color("#708179"), 1.0)
		draw_line(Vector2(x, 659), Vector2(x + 9, 650), Color("#d8c9a9"), 2.0)
	draw_rect(Rect2(1648, 716, 198, 116), Color("#080e10"))
	draw_rect(Rect2(1648, 716, 198, 116), Color("#587963") if started else Color("#a9544b"), false, 2.0)
	draw_line(Vector2(1656, 720), Vector2(1838, 720), PHOSPHOR if started else Color("#efaa82"), 2.0)
	for x in [1658.0, 1836.0]:
		draw_circle(Vector2(x, 720), 4.0, Color("#d9bd8d"))
		draw_circle(Vector2(x, 827), 4.0, Color("#d9bd8d"))
	_caption(Vector2(1660, 869), "ARMED   /   COMMAND", Color("#b89d88"), 14)

func _draw_footer() -> void:
	_panel(Rect2(62, 914, 226, 116), Color("#0b1416"), Color("#64736b"))
	_panel(Rect2(307, 914, 1145, 116), Color("#0b1416"), Color("#64736b"))
	_panel(Rect2(1471, 914, 387, 116), Color("#0b1416"), Color("#64736b"))
	draw_line(Vector2(465, 925), Vector2(465, 1017), Color("#40534a"), 1.0)
	draw_line(Vector2(891, 925), Vector2(891, 1017), Color("#40534a"), 1.0)
	_caption(Vector2(326, 948), "ORDNANCE  /  库存", Color("#8eaa96"), 15)
	_caption(Vector2(911, 948), "COMMAND STATE", Color("#8eaa96"), 15)
	_caption(Vector2(1490, 948), "VESSEL INTEGRITY", Color("#8eaa96"), 15)
	for index in range(6):
		var x := 1325.0 + float(index) * 17.0
		draw_rect(Rect2(x, 975, 10, 23), AMBER if started and index < MissionController.ship_ammo else Color("#2a3935"))

func _draw_fasteners() -> void:
	for screw in [Vector2(49, 50), Vector2(1871, 50), Vector2(49, 1030), Vector2(1871, 1030), Vector2(79, 184), Vector2(1841, 184), Vector2(79, 877), Vector2(1841, 877)]:
		draw_circle(screw, 6.0, Color("#091011"))
		draw_arc(screw, 5.0, 0.0, TAU, 24, Color("#9da99b"), 1.0)
		draw_line(screw + Vector2(-3, 2), screw + Vector2(3, -2), Color("#7f8b81"), 1.4, true)

func _panel(rect: Rect2, fill: Color, edge: Color) -> void:
	draw_rect(rect, Color("#05090a"))
	draw_rect(rect.grow(-3.0), fill)
	draw_rect(rect, edge, false, 1.0)
	draw_line(rect.position + Vector2(3, 3), Vector2(rect.end.x - 3, rect.position.y + 3), edge.lightened(0.1), 1.0)
	draw_line(Vector2(rect.end.x - 3, rect.position.y + 3), rect.end - Vector2(3, 3), Color("#0a1112"), 2.0)

func _caption(origin: Vector2, value: String, tint: Color, font_size: int) -> void:
	if _instrument_font != null:
		draw_string(_instrument_font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
