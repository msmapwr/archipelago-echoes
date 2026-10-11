extends Control

signal close_requested

var title: Label
var status: Label
var content: Label
var scroll: ScrollContainer
var close_button: Button
var tabs: Array[Button] = []
var selected_tab: int = 0
var briefing_text: String = ""
var progress_text: String = ""
var history_text: String = ""
var fire_control_text: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.012, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 36
	panel.offset_top = 24
	panel.offset_right = -36
	panel.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#071810")
	style.border_color = Color("#789c80")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	title = _label(column, "指令部 / 命令档案", 25)
	status = _label(column, "", 15)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 12)
	column.add_child(tab_row)
	for index in range(4):
		var button := Button.new()
		button.text = ["命令简报", "任务进度", "行动记录", "火控命令"][index]
		button.toggle_mode = true
		button.pressed.connect(select_tab.bind(index))
		tab_row.add_child(button)
		tabs.append(button)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	content = _label(scroll, "", 20)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button = Button.new()
	close_button.text = "关闭档案 / ESC 或 F1"
	close_button.custom_minimum_size.y = 38
	close_button.pressed.connect(func() -> void: close_requested.emit())
	column.add_child(close_button)
	select_tab(0)
	hide()

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#b1cdb5"))
	parent.add_child(label)
	return label

func present(briefing: String, progress: String, history: String, paused_before: bool, ended: bool, fire_control: String = "") -> void:
	briefing_text = briefing
	progress_text = progress
	history_text = history
	fire_control_text = fire_control
	status.text = "行动已结束；关闭后保持暂停。" if ended else "打开前已暂停；关闭后仍保持暂停。" if paused_before else "阅读期间模拟暂停；关闭后继续原来的时间倍率。"
	select_tab(selected_tab)
	show()
	close_button.grab_focus()

func select_tab(index: int) -> void:
	selected_tab = clampi(index, 0, 3)
	content.text = [briefing_text, progress_text, history_text, fire_control_text][selected_tab]
	scroll.scroll_vertical = 0
	for tab_index in range(tabs.size()):
		tabs[tab_index].set_pressed_no_signal(tab_index == selected_tab)

func cycle_focus(backwards: bool) -> void:
	var buttons: Array[Button] = tabs.duplicate()
	buttons.append(close_button)
	var index := buttons.find(get_viewport().gui_get_focus_owner())
	index = posmod(index + (-1 if backwards else 1), buttons.size())
	buttons[index].grab_focus()
