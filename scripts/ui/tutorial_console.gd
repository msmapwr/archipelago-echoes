extends VBoxContainer

signal readiness_changed
signal completed

const Simulation = preload("res://scripts/core/tutorial_simulation.gd")
const Decay = preload("res://scripts/ui/phosphor_decay.gd")
var simulation = Simulation.new()
var lesson: Label
var instruction: Label
var feedback: Label
var telemetry: Label
var scope: Control
var controls: HBoxContainer
var action_buttons: Dictionary = {}
var skip_button: Button
var replay_button: Button

class TrainingScope extends Control:
	signal echo_selected
	var simulation: RefCounted
	const Decay = preload("res://scripts/ui/phosphor_decay.gd")
	func echo_position() -> Vector2:
		return size * Vector2(0.67, 0.26)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if simulation.scans > 0 and event.position.distance_to(echo_position()) <= 28.0:
				echo_selected.emit()
				accept_event()
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.43
		draw_rect(Rect2(Vector2.ZERO, size), Color("#03100a"))
		for index in range(1, 4):
			draw_arc(center, radius * index / 3.0, 0, TAU, 64, Color("#163d28"), 1, true)
		draw_line(Vector2(center.x, 12), Vector2(center.x, size.y - 12), Color("#163d28"))
		draw_line(Vector2(12, center.y), Vector2(size.x - 12, center.y), Color("#163d28"))
		var bow := Vector2.UP.rotated(deg_to_rad(simulation.heading_degrees))
		draw_line(center - bow * 8, center + bow * 15, Color("#b8edc3"), 3, true)
		if simulation.scans > 0:
			var echo := echo_position()
			var energy := Decay.energy(simulation.echo_age, 15.0)
			draw_circle(echo, 13, Color(0.3, 1.0, 0.5, energy * 0.12))
			draw_circle(echo, 4, Color(0.5, 1.0, 0.65, 0.08 + energy * 0.92))
			if simulation.selected:
				draw_arc(echo, 20, 0, TAU, 32, Color("#749986"), 1, true)
			draw_string(ThemeDB.fallback_font, echo + Vector2(24, 6), "A1 / HOSTILE" if simulation.identified else "A1 / ?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#8aae97"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	lesson = _label(self, "", 23)
	instruction = _label(self, "", 18)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	scope = TrainingScope.new()
	scope.custom_minimum_size = Vector2(440, 120)
	scope.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scope.simulation = simulation
	scope.echo_selected.connect(func() -> void: perform("select"))
	row.add_child(scope)
	var readout := VBoxContainer.new()
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(readout)
	telemetry = _label(readout, "", 19)
	feedback = _label(readout, "", 19)
	controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	add_child(controls)
	for entry in [["scan", "主动扫描"], ["select", "选择 A1"], ["identify", "确认接触"], ["fire", "甲板炮"], ["turn", "右转 15°"], ["throttle", "加速至 6 kn"], ["pause", "暂停"], ["launch", "配置并出击"], ["return", "返航"], ["land", "降落回舰"]]:
		var button := Button.new()
		button.text = entry[1]
		button.custom_minimum_size = Vector2(160, 42)
		button.pressed.connect(perform.bind(entry[0]))
		controls.add_child(button)
		action_buttons[entry[0]] = button
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 18)
	add_child(navigation)
	skip_button = Button.new()
	skip_button.text = "跳过训练"
	skip_button.pressed.connect(skip)
	navigation.add_child(skip_button)
	replay_button = Button.new()
	replay_button.text = "重播训练"
	replay_button.pressed.connect(replay)
	navigation.add_child(replay_button)
	_refresh()

func _label(parent: Node, caption: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#a4c6af"))
	parent.add_child(label)
	return label

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	simulation.advance_time(delta)
	scope.queue_redraw()
	_refresh_telemetry()

func perform(action: String) -> void:
	var was_complete: bool = simulation.ready_to_continue()
	simulation.act(action)
	_refresh()
	if not was_complete and simulation.ready_to_continue() and not simulation.skipped:
		completed.emit()
	readiness_changed.emit()

func skip() -> void:
	simulation.skip()
	_refresh()
	readiness_changed.emit()

func replay() -> void:
	simulation = Simulation.new()
	scope.simulation = simulation
	_refresh()
	readiness_changed.emit()

func _refresh() -> void:
	var complete: bool = simulation.ready_to_continue()
	lesson.text = "TRAINING / 已跳过" if simulation.skipped else "TRAINING / 全部完成" if complete else "TRAINING / %02d / 07 · %s" % [simulation.step + 1, Simulation.LESSONS[simulation.step][0]]
	instruction.text = "继续阅读命令简报，接受后再生成海域与驾驶离港。" if complete else Simulation.LESSONS[simulation.step][1]
	feedback.text = simulation.message
	var visible_actions: Array = []
	if not complete:
		visible_actions = [["scan"], ["select", "scan"], ["scan", "identify"], ["fire", "scan"], ["turn", "throttle"], ["pause"], ["launch", "return", "land"]][simulation.step]
	for action in action_buttons:
		var button: Button = action_buttons[action]
		button.visible = action in visible_actions
		button.disabled = action == "return" and simulation.flight != "airborne" or action == "land" and simulation.flight != "approach" or action == "launch" and simulation.flight != "deck"
	action_buttons["pause"].text = "恢复" if simulation.paused else "暂停"
	skip_button.disabled = complete
	_refresh_telemetry()
	scope.queue_redraw()

func _refresh_telemetry() -> void:
	telemetry.text = "SIM / 训练数据，不计入任务\nHDG %03.0f°   SPD %.0f kn\n观测 %d 次 · %s\nAIR / %s" % [simulation.heading_degrees, simulation.speed_knots, simulation.scans, "未扫描" if simulation.scans == 0 else "已过期，请重新扫描" if simulation.echo_age > 15 else "余辉 %.0f%%" % (Decay.energy(simulation.echo_age, 15) * 100), {"deck": "甲板待命", "airborne": "空中", "approach": "进近", "recovered": "安全回收"}[simulation.flight]]
