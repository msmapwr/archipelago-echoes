extends Control

@onready var radar: Control = $Content/RadarFrame/Radar
@onready var contact_status: Label = $Content/Details/ContactStatus
@onready var contact_details: Label = $Content/Details/ContactDetails
@onready var selection_details: Label = $Content/Details/SelectionDetails
@onready var event_details: Label = $Content/Details/EventDetails
@onready var ship_details: Label = $Content/Details/ShipDetails
@onready var navigation_status: Label = $Content/Details/NavigationStatus
@onready var pause_status: Label = $Footer/PauseStatus
@onready var time_status: Label = $Footer/TimeStatus
@onready var sweep_timer: Timer = $SweepTimer

var contact: ContactDefinition
var sweep_phase: int = 0
var displayed_second: int = -1
var last_observed_position_km: Vector2 = Vector2.ZERO
var last_observed_bearing_degrees: float = 0.0
var last_observed_range_km: float = 0.0
var last_observed_seconds: float = 0.0

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
	WorldState.ship_position_changed.connect(_on_ship_position_changed)
	WorldState.ship_command_changed.connect(_on_ship_command_changed)
	WorldState.navigation_blocked.connect(_on_navigation_blocked)
	_on_ship_command_changed(WorldState.ship_heading_degrees, WorldState.ship_speed_knots)
	navigation_status.text = "航行控制待命 · 转向 15° / 调速 5 kn"
	_show_sweep_phase()
	_update_pause_status()
	_on_world_time_advanced(WorldClock.elapsed_seconds)

func _on_world_time_advanced(total_seconds: float) -> void:
	var current_second := floori(total_seconds)
	if current_second != displayed_second:
		displayed_second = current_second
		time_status.text = WorldClock.formatted_time()

func _on_ship_position_changed(position_km: Vector2) -> void:
	radar.set_land_areas(WorldState.map.islands, position_km)
	if sweep_phase != 2:
		_update_radar_contact()
	_update_ship_details()

func _on_ship_command_changed(_heading_degrees: float, _speed_knots: float) -> void:
	radar.set_ship_heading(WorldState.ship_heading_degrees)
	_update_ship_details()
	navigation_status.text = "航行命令已记录 · 暂停中" if get_tree().paused else "航行命令已生效"

func _on_navigation_blocked(_position_km: Vector2) -> void:
	navigation_status.text = "航路受阻 · 已停车，请调整航向"

func _update_ship_details() -> void:
	ship_details.text = "位置  E %05.1f / S %05.1f km\n航向  %03d°    航速  %.0f / %.0f kn" % [WorldState.ship_position_km.x, WorldState.ship_position_km.y, roundi(WorldState.ship_heading_degrees), WorldState.ship_speed_knots, WorldState.ship_max_speed_knots]

func _on_turn_port_pressed() -> void:
	WorldState.set_ship_command(WorldState.ship_heading_degrees - 15.0, WorldState.ship_speed_knots)

func _on_turn_starboard_pressed() -> void:
	WorldState.set_ship_command(WorldState.ship_heading_degrees + 15.0, WorldState.ship_speed_knots)

func _on_slow_down_pressed() -> void:
	WorldState.set_ship_command(WorldState.ship_heading_degrees, maxf(0.0, WorldState.ship_speed_knots - 5.0))

func _on_speed_up_pressed() -> void:
	WorldState.set_ship_command(WorldState.ship_heading_degrees, minf(WorldState.ship_max_speed_knots, WorldState.ship_speed_knots + 5.0))

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
			_observe_contact()
			contact_status.text = "接触状态：已发现"
			_update_contact_details("未知水面回波")
			_update_radar_contact()
			EventBus.contact_discovered.emit(contact.id)
			EventBus.record("contact_discovered", {"id": contact.id, "bearing_degrees": last_observed_bearing_degrees, "range_km": last_observed_range_km})
		1:
			_observe_contact()
			contact_status.text = "接触状态：已更新"
			_update_contact_details("方位与距离已复测")
			_update_radar_contact()
			EventBus.contact_updated.emit(contact.id)
			EventBus.record("contact_updated", {"id": contact.id, "bearing_degrees": last_observed_bearing_degrees, "range_km": last_observed_range_km})
		2:
			contact_status.text = "接触状态：失联"
			_update_contact_details("本次扫描无回波 · 最后观测")
			radar.set_contact(contact.id, 0.0, 0.0, false)
			EventBus.contact_lost.emit(contact.id)
			EventBus.record("contact_lost", {"id": contact.id})

func _observe_contact() -> void:
	last_observed_position_km = WorldState.contact_position_km
	last_observed_bearing_degrees = WorldState.contact_bearing_degrees()
	last_observed_range_km = WorldState.contact_range_km()
	last_observed_seconds = WorldClock.elapsed_seconds

func _update_contact_details(summary: String) -> void:
	var seen_seconds := floori(last_observed_seconds)
	contact_details.text = "A1  %s\n方位 %03d°   距离 %.1f km\n观测 T+%02d:%02d   未确认" % [summary, roundi(last_observed_bearing_degrees), last_observed_range_km, seen_seconds / 60, seen_seconds % 60]

func _update_radar_contact() -> void:
	var relative := last_observed_position_km - WorldState.ship_position_km
	var bearing := fposmod(rad_to_deg(atan2(relative.x, -relative.y)), 360.0)
	radar.set_contact(contact.id, bearing, relative.length(), true)

func _on_contact_selected(id: String) -> void:
	selection_details.text = "已选择 %s\n可查看接触信息；尚不能下达战斗命令。" % id

func _on_contact_deselected() -> void:
	selection_details.text = "未选择接触。点击雷达标记可查看详情。"

func _on_event_recorded(_event: Dictionary) -> void:
	var lines: PackedStringArray = []
	for index in range(maxi(0, EventBus.history.size() - 4), EventBus.history.size()):
		lines.append("• " + _event_message(EventBus.history[index]))
	event_details.text = "通信日志  /  RADIO LOG\n" + "\n".join(lines)

func _event_message(event: Dictionary) -> String:
	var details: Dictionary = event.get("details", {})
	match event.get("kind", ""):
		"contact_discovered":
			return "A1 回波发现"
		"contact_updated":
			return "A1 方位复测"
		"contact_lost":
			return "A1 信号丢失"
		"ship_navigation_command":
			return "航行命令 %03d° / %.0f kn" % [roundi(details.get("heading_degrees", 0.0)), details.get("speed_knots", 0.0)]
		"ship_navigation_blocked":
			return "航路受阻，舰艇停车"
		"simulation_pause_changed":
			return "模拟暂停" if details.get("paused", false) else "模拟继续"
		_:
			return str(event.get("kind", ""))

func _update_pause_status() -> void:
	pause_status.text = "已暂停 · 空格继续" if get_tree().paused else "运行中 · 空格暂停"
