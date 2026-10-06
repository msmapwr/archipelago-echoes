extends Control

signal departure_requested
signal menu_requested
signal stage_changed(stage: String)

# Narrative/settings slots; the final page hands control to the harbor.
const PAGES: Array[Dictionary] = [
	{"id": "opening", "title": "01 / 开场动画", "body": "群岛回波\nECHOES OF THE ARCHIPELAGO\n\n开场影像与音效待制作；当前仅保留 CRT 亮屏过渡。", "action": "进入准备"},
	{"id": "settings", "title": "02 / 出航设置", "body": "", "action": "继续"},
	{"id": "background", "title": "03 / 背景介绍", "body": "背景叙事内容待编写\n\n这里将交代群岛局势、玩家身份及此次行动的缘由。\n正式剧情与时代设定尚未定稿。", "action": "继续"},
	{"id": "tutorial", "title": "04 / 新手教程", "body": "交互教程入口已预留\n\n当前操作提示：点击雷达回波选择接触；主动扫描与确认接触后可使用甲板炮。\n航向和航速由舰桥控制；配置出击后可驾驶飞机侦察并安全返航。\n空格暂停，页脚切换时间倍率。\n后续加入逐步演练与完成检测。", "action": "阅读完毕"},
	{"id": "orders", "title": "05 / 指令部命令", "body": "首关原型命令\n\n搜索海峡中的 A1 接触，确认其身份，并确保指挥官安全返航。\n先接受命令，再准备舰船与海域，最后从港口出航。\n正式命令文本和任务简报系统待接入。", "action": "接受命令"},
	{"id": "generation", "title": "06 / 场景生成", "body": "", "action": "前往港口"},
	{"id": "harbor", "title": "07 / 港口出航", "body": "命令已接收，舰船在码头待命。\n\n进入港口后先解缆，再加速沿中央航道向北航行。\n港内限速 10 kn，注意码头与防波堤；驶过离港线后自动进入海上首关。\n当前港口采用固定布局，随机生成后续接入。", "action": "进入港口驾驶"},
]

var page_index: int = 0
var stage: String = "opening"
var heading: Label
var body: Label
var progress: Label
var advance_button: Button
var settings_form: VBoxContainer
var generation_form: VBoxContainer
var volume_input: HSlider
var volume_caption: Label
var window_input: OptionButton
var fullscreen_input: CheckBox
var reduced_input: CheckBox
var settings_status: Label
var apply_button: Button
var defaults_button: Button
var seed_input: SpinBox
var generate_button: Button
var random_button: Button
var generation_status: Label
var generation_ready: bool = false

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
	glass.border_color = Color("#527760")
	glass.set_border_width_all(1)
	glass.set_corner_radius_all(22)
	glass.content_margin_left = 56
	glass.content_margin_right = 56
	glass.content_margin_top = 36
	glass.content_margin_bottom = 36
	panel.add_theme_stylebox_override("panel", glass)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	panel.add_child(column)
	progress = Label.new()
	progress.add_theme_color_override("font_color", Color("#83e8aa"))
	column.add_child(progress)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 36)
	heading.add_theme_color_override("font_color", Color("#d9decf"))
	column.add_child(heading)
	body = Label.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 23)
	body.add_theme_color_override("font_color", Color("#a4c6af"))
	column.add_child(body)
	_build_settings_form(column)
	_build_generation_form(column)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 24)
	column.add_child(actions)
	var menu_button := Button.new()
	menu_button.text = "返回主菜单"
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	actions.add_child(menu_button)
	advance_button = Button.new()
	advance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advance_button.pressed.connect(advance)
	actions.add_child(advance_button)
	_refresh_page()
	panel.modulate.a = 0.1
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.6)

func advance() -> void:
	if stage == "generation":
		seed_input.apply()
		if not generation_ready:
			return
	if page_index == PAGES.size() - 1:
		departure_requested.emit()
		return
	page_index += 1
	_refresh_page()

func _refresh_page() -> void:
	var page: Dictionary = PAGES[page_index]
	stage = page["id"]
	progress.text = "CIC / 出航准备    ·    %02d / %02d    ·    模拟时间冻结" % [page_index + 1, PAGES.size()]
	heading.text = page["title"]
	body.text = page["body"]
	body.visible = stage != "settings" and stage != "generation"
	settings_form.visible = stage == "settings"
	generation_form.visible = stage == "generation"
	advance_button.text = page["action"]
	advance_button.disabled = stage == "generation" and not generation_ready
	advance_button.grab_focus()
	stage_changed.emit(stage)
	if stage == "generation":
		generate_world()

func _form(parent: Node) -> VBoxContainer:
	var form := VBoxContainer.new()
	form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 14)
	form.hide()
	parent.add_child(form)
	return form

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("#a4c6af"))
	parent.add_child(label)
	return label

func _build_settings_form(parent: Node) -> void:
	settings_form = _form(parent)
	volume_caption = _label(settings_form, "主音量")
	volume_input = HSlider.new()
	volume_input.max_value = 100
	volume_input.step = 1
	volume_input.custom_minimum_size.y = 24
	volume_input.value_changed.connect(func(value: float) -> void: volume_caption.text = "主音量 / %.0f%%" % value)
	settings_form.add_child(volume_input)
	window_input = OptionButton.new()
	for caption in ["窗口 1280 × 720", "窗口 1600 × 900", "窗口 1920 × 1080"]:
		window_input.add_item(caption)
	settings_form.add_child(window_input)
	fullscreen_input = CheckBox.new()
	fullscreen_input.text = "全屏显示（保持 16:9 内容比例）"
	settings_form.add_child(fullscreen_input)
	reduced_input = CheckBox.new()
	reduced_input.text = "减弱 CRT 扫描线、反光与边缘暗化"
	settings_form.add_child(reduced_input)
	var actions := HBoxContainer.new()
	settings_form.add_child(actions)
	apply_button = Button.new()
	apply_button.text = "应用并保存"
	apply_button.pressed.connect(save_settings)
	actions.add_child(apply_button)
	defaults_button = Button.new()
	defaults_button.text = "恢复默认草稿"
	defaults_button.pressed.connect(func() -> void: _populate_settings(UserSettings.Preferences.new()); settings_status.text = "默认值已填入；点击应用并保存后生效。")
	actions.add_child(defaults_button)
	settings_status = _label(settings_form, "点击应用并保存后生效；继续或返回不会保存未应用的修改。")
	_populate_settings(UserSettings.preferences)
	if not UserSettings.preferences.last_error.is_empty():
		settings_status.text = UserSettings.preferences.last_error

func _populate_settings(preferences: RefCounted) -> void:
	volume_input.value = preferences.master_volume
	window_input.select(preferences.window_preset)
	fullscreen_input.button_pressed = preferences.fullscreen
	reduced_input.button_pressed = preferences.reduced_crt

func save_settings() -> void:
	var candidate = UserSettings.Preferences.new()
	candidate.master_volume = volume_input.value
	candidate.window_preset = window_input.selected
	candidate.fullscreen = fullscreen_input.button_pressed
	candidate.reduced_crt = reduced_input.button_pressed
	if UserSettings.save_and_apply(candidate):
		settings_status.text = "设置已应用并保存，下次启动自动恢复。"
	else:
		settings_status.text = candidate.last_error

func _build_generation_form(parent: Node) -> void:
	generation_form = _form(parent)
	_label(generation_form, "海域种子 / 同一种子可复现岛屿位置与半径")
	seed_input = SpinBox.new()
	seed_input.max_value = 2147483647
	seed_input.step = 1
	seed_input.value = WorldState.scenario_seed
	seed_input.value_changed.connect(func(value: float) -> void: seed_input.get_line_edit().text = str(int(value)); _invalidate_generation())
	seed_input.get_line_edit().text_changed.connect(func(_text: String) -> void: _invalidate_generation())
	generation_form.add_child(seed_input)
	var actions := HBoxContainer.new()
	generation_form.add_child(actions)
	generate_button = Button.new()
	generate_button.text = "生成／重新生成海域"
	generate_button.pressed.connect(generate_world)
	actions.add_child(generate_button)
	random_button = Button.new()
	random_button.text = "随机种子并生成"
	random_button.pressed.connect(func() -> void: var rng := RandomNumberGenerator.new(); rng.randomize(); seed_input.value = rng.randi_range(0, 2147483647); generate_world())
	actions.add_child(random_button)
	generation_status = _label(generation_form, "等待生成。")
	_label(generation_form, "当前生成五个岛屿的偏移和半径，校验舰船／目标出生点与离港航道。\n港口布局、任务目标、舰机配置仍沿用首关原型；后续扩展地形与任务生成。")

func generate_world() -> void:
	seed_input.apply()
	generation_ready = false
	if not DataManager.errors.is_empty():
		generation_status.text = "数据加载失败，无法生成。请检查 Godot 输出或返回主菜单重试。"
	elif WorldState.load_first_scenario(int(seed_input.value)):
		generation_ready = true
		generation_status.text = "生成完成 / 种子 %d\n%d 个岛屿 · 舰船与目标出生点有效 · 离港航道通畅。" % [WorldState.scenario_seed, WorldState.map.islands.size()]
	else:
		generation_status.text = WorldState.generation_error
	advance_button.disabled = not generation_ready

func _invalidate_generation() -> void:
	generation_ready = false
	advance_button.disabled = true
	generation_status.text = "种子已更改，请生成并校验海域。"
