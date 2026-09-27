extends Control

@onready var radar: Control = $Content/RadarFrame/Radar
@onready var contact_status: Label = $Content/Details/ContactStatus
@onready var contact_details: Label = $Content/Details/ContactDetails
@onready var selection_details: Label = $Content/Details/SelectionDetails
@onready var event_details: Label = $Content/Details/EventDetails
@onready var pause_status: Label = $Footer/PauseStatus
@onready var time_status: Label = $Footer/TimeStatus
@onready var sweep_timer: Timer = $SweepTimer

var contact: ContactDefinition
var sweep_phase: int = 0
var displayed_second: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	contact = DataManager.get_definition("contact.alpha") as ContactDefinition
	if contact == null or not DataManager.errors.is_empty():
		contact_status.text = "数据加载失败"
		contact_details.text = "请查看 Godot 输出中的 DataManager 错误。"
		sweep_timer.stop()
		return
	radar.contact_selected.connect(_on_contact_selected)
	radar.contact_deselected.connect(_on_contact_deselected)
	EventBus.event_recorded.connect(_on_event_recorded)
	if WorldState.map == null:
		contact_status.text = "场景加载失败"
		contact_details.text = "请查看 Godot 输出中的 WorldState 错误。"
		sweep_timer.stop()
		return
	radar.set_land_areas(WorldState.map.islands, WorldState.ship_position_km)
	WorldClock.time_advanced.connect(_on_world_time_advanced)
	_show_sweep_phase()
	_update_pause_status()
	_on_world_time_advanced(WorldClock.elapsed_seconds)

func _on_world_time_advanced(total_seconds: float) -> void:
	var current_second := floori(total_seconds)
	if current_second != displayed_second:
		displayed_second = current_second
		time_status.text = WorldClock.formatted_time()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		radar.clear_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_simulation"):
		GameManager.set_paused(not get_tree().paused)
		_update_pause_status()
		get_viewport().set_input_as_handled()

func _on_sweep_timer_timeout() -> void:
	if not get_tree().paused:
		advance_sweep()

func _on_next_sweep_pressed() -> void:
	if not get_tree().paused:
		advance_sweep()

func advance_sweep() -> void:
	sweep_phase = (sweep_phase + 1) % 3
	_show_sweep_phase()

func _show_sweep_phase() -> void:
	match sweep_phase:
		0:
			contact_status.text = "接触状态：已发现"
			contact_details.text = "A1  未知水面目标\n方位 %03d°   距离 %.1f km" % [roundi(contact.bearing_degrees), contact.range_km]
			radar.set_contact(contact.id, contact.bearing_degrees, contact.range_km, true)
			EventBus.contact_discovered.emit(contact.id)
			EventBus.record("contact_discovered", {"id": contact.id})
		1:
			contact_status.text = "接触状态：已更新"
			contact_details.text = "A1  方位与距离已更新\n方位 %03d°   距离 %.1f km" % [roundi(contact.bearing_degrees + 3.0), contact.range_km - 0.5]
			radar.set_contact(contact.id, contact.bearing_degrees + 3.0, contact.range_km - 0.5, true)
			EventBus.contact_updated.emit(contact.id)
			EventBus.record("contact_updated", {"id": contact.id})
		2:
			contact_status.text = "接触状态：失联"
			contact_details.text = "A1  当前扫描未收到回波。\n最后位置仅供参考，目标尚未确认。"
			radar.set_contact(contact.id, contact.bearing_degrees + 3.0, contact.range_km - 0.5, false)
			EventBus.contact_lost.emit(contact.id)
			EventBus.record("contact_lost", {"id": contact.id})

func _on_contact_selected(id: String) -> void:
	selection_details.text = "已选择 %s\n可查看接触信息；尚不能下达战斗命令。" % id

func _on_contact_deselected() -> void:
	selection_details.text = "未选择接触。点击雷达标记可查看详情。"

func _on_event_recorded(_event: Dictionary) -> void:
	var lines: PackedStringArray = []
	for index in range(maxi(0, EventBus.history.size() - 4), EventBus.history.size()):
		lines.append("• " + str(EventBus.history[index].get("kind", "")))
	event_details.text = "最近事件\n" + "\n".join(lines)

func _update_pause_status() -> void:
	pause_status.text = "已暂停 · 空格继续" if get_tree().paused else "运行中 · 空格暂停"
