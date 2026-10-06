extends Control

signal departure_requested
signal menu_requested
signal stage_changed(stage: String)

# Content slots only: port navigation and procedural generation arrive later.
const PAGES: Array[Dictionary] = [
	{"id": "opening", "title": "01 / 开场动画", "body": "群岛回波\nECHOES OF THE ARCHIPELAGO\n\n开场影像与音效待制作；当前仅保留 CRT 亮屏过渡。", "action": "进入准备"},
	{"id": "settings", "title": "02 / 出航设置", "body": "设置入口已预留\n\n后续接入音量、显示与操作设置。当前沿用项目默认配置：16:9 画面、键鼠操作。\n本页暂不修改或保存设置。", "action": "继续"},
	{"id": "background", "title": "03 / 背景介绍", "body": "背景叙事内容待编写\n\n这里将交代群岛局势、玩家身份及此次行动的缘由。\n正式剧情与时代设定尚未定稿。", "action": "继续"},
	{"id": "tutorial", "title": "04 / 新手教程", "body": "交互教程入口已预留\n\n当前操作提示：点击雷达回波选择接触；主动扫描与确认接触后可使用甲板炮。\n航向和航速由舰桥控制；配置出击后可驾驶飞机侦察并安全返航。\n空格暂停，页脚切换时间倍率。\n后续加入逐步演练与完成检测。", "action": "阅读完毕"},
	{"id": "orders", "title": "05 / 指令部命令", "body": "首关原型命令\n\n搜索海峡中的 A1 接触，确认其身份，并确保指挥官安全返航。\n先接受命令，再准备舰船与海域，最后从港口出航。\n正式命令文本和任务简报系统待接入。", "action": "接受命令"},
	{"id": "generation", "title": "06 / 场景生成", "body": "场景生成接口已预留\n\n当前出航将载入已有固定首关地图与舰机配置。\n后续在此接入种子、海域生成、港口与舰船初始化，以及加载进度和失败重试。\n目前不执行随机生成。", "action": "前往港口"},
	{"id": "harbor", "title": "07 / 港口出航", "body": "港口驾驶阶段已预留\n\n命令已接收，等待出航确认。\n港口地图、解缆与驶出航道尚未实现；当前确认后进入已有海上首关。\n后续以实际驶离港口触发正式任务。", "action": "确认出航（原型）"},
]

var page_index: int = 0
var stage: String = "opening"
var heading: Label
var body: Label
var progress: Label
var advance_button: Button

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
	advance_button.text = page["action"]
	advance_button.grab_focus()
	stage_changed.emit(stage)
