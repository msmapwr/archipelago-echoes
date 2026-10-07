extends PanelContainer

signal close_requested
const Catalog = preload("res://scripts/data/unit_visual_catalog.gd")
const Glyph = preload("res://scripts/data/unit_glyph.gd")
const Icon = preload("res://scripts/ui/unit_icon.gd")
var family_picker: OptionButton
var size_picker: OptionButton
var variant_picker: OptionButton
var previews: Array = []
var tiles: Array = []
var caption: Label
var result: Label
var zoom := 180.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("#071b12")
	skin.border_color = Color("#497554")
	skin.set_border_width_all(2)
	skin.set_corner_radius_all(16)
	skin.content_margin_left = 24
	skin.content_margin_right = 24
	skin.content_margin_top = 18
	skin.content_margin_bottom = 18
	add_theme_stylebox_override("panel", skin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var title := Label.new()
	title.text = "单位图鉴 / STRUCTURAL ARCHIVE   ·   420 形态"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var filters := HBoxContainer.new()
	column.add_child(filters)
	family_picker = OptionButton.new()
	for kind in Catalog.SHIP_KINDS + Catalog.BUILDING_KINDS:
		family_picker.add_item(Glyph.NAMES[kind])
		family_picker.set_item_metadata(family_picker.item_count - 1, ("ship." if Catalog.SHIP_KINDS.has(kind) else "building.") + kind)
	filters.add_child(family_picker)
	size_picker = OptionButton.new()
	for text in ["小型", "中型", "大型"]: size_picker.add_item(text)
	size_picker.selected = 1
	filters.add_child(size_picker)
	variant_picker = OptionButton.new()
	for n in range(10): variant_picker.add_item("形态 %02d" % (n + 1))
	filters.add_child(variant_picker)
	for picker in [family_picker, size_picker, variant_picker]:
		picker.item_selected.connect(func(_index: int) -> void: refresh())
	var close := Button.new()
	close.text = "关闭图鉴 / F2"
	close.pressed.connect(request_close)
	filters.add_child(close)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for detail in [false, true]:
		var frame := VBoxContainer.new()
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(frame)
		var label := Label.new()
		label.text = "雷达识别图 / 固定舰体" if not detail else "完整结构图 / 武器与设施"
		frame.add_child(label)
		var icon := Icon.new()
		icon.custom_minimum_size = Vector2(240, 190)
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon.detailed = detail
		icon.fit_to_bounds = false
		frame.add_child(icon)
		previews.append(icon)
	caption = Label.new()
	column.add_child(caption)
	var grid := HBoxContainer.new()
	column.add_child(grid)
	for n in range(10):
		var button := Button.new()
		button.custom_minimum_size = Vector2(70, 72)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%02d" % (n + 1)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: variant_picker.selected = n; refresh())
		grid.add_child(button)
		var icon := Icon.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.pixels = 64
		button.add_child(icon)
		tiles.append(icon)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	for delta in [-32, 32]:
		var button := Button.new()
		button.text = "缩小" if delta < 0 else "放大"
		button.pressed.connect(func() -> void: zoom = clampf(zoom + delta, 96, 320); refresh())
		actions.add_child(button)
	var mono := CheckButton.new()
	mono.text = "灰度检查"
	mono.toggled.connect(func(enabled: bool) -> void:
		for icon in previews + tiles:
			icon.tint = Color.WHITE if enabled else Color("#a0edb5")
			icon.queue_redraw())
	actions.add_child(mono)
	var export_button := Button.new()
	export_button.text = "导出 PNG / SVG / JSON"
	export_button.pressed.connect(func() -> void:
		var error := Glyph.export_icon(family(), Catalog.SIZE_CLASSES[size_picker.selected], variant_picker.selected + 1)
		result.text = "导出位置：" + ProjectSettings.globalize_path("user://icons") if error == OK else "导出失败：" + error_string(error))
	actions.add_child(export_button)
	var atlas_button := Button.new()
	atlas_button.text = "导出全部图集"
	atlas_button.pressed.connect(func() -> void:
		var error := Glyph.export_atlas()
		result.text = "图集已导出：" + ProjectSettings.globalize_path("user://icons/atlas.png") if error == OK else "图集导出失败：" + error_string(error))
	actions.add_child(atlas_button)
	result = Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.text = "样板：护航航舰 / 驱逐舰 / 港口 / 机场。图示装备为视觉结构，不等于实装战斗能力。"
	column.add_child(result)
	refresh()

func family() -> String:
	return family_picker.get_item_metadata(family_picker.selected)

func request_close() -> void:
	if close_requested.get_connections().is_empty():
		get_tree().quit()
	else:
		close_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F2, KEY_ESCAPE]:
		request_close()
		get_viewport().set_input_as_handled()

func refresh() -> void:
	for icon in previews:
		icon.family = family()
		icon.size_class = Catalog.SIZE_CLASSES[size_picker.selected]
		icon.variant = variant_picker.selected + 1
		icon.pixels = zoom
		icon.queue_redraw()
	for n in range(tiles.size()):
		tiles[n].family = family()
		tiles[n].size_class = Catalog.SIZE_CLASSES[size_picker.selected]
		tiles[n].variant = n + 1
		tiles[n].queue_redraw()
	caption.text = "%s.%s.%02d   ·   俯视 / 单色 / 可编辑整数结构" % [family(), Catalog.SIZE_CLASSES[size_picker.selected], variant_picker.selected + 1]
