extends Node

signal event_recorded(event: Dictionary)
signal contact_discovered(contact_id: String)
signal contact_updated(contact_id: String)
signal contact_lost(contact_id: String)
signal command_issued(command_id: String)
signal weapon_fired(weapon_id: String)
signal damage_reported(entity_id: String)
signal mode_changed(previous_mode: String, current_mode: String)
signal task_settled(task_id: String, result: String)

var history: Array[Dictionary] = []

func record(kind: String, details: Dictionary = {}, simulation_seconds: float = -1.0) -> void:
	var event: Dictionary = {"kind": kind, "details": details.duplicate(true), "time_msec": Time.get_ticks_msec()}
	var clock := get_node_or_null("/root/WorldClock")
	if clock != null:
		event["simulation_seconds"] = simulation_seconds if is_finite(simulation_seconds) and simulation_seconds >= 0 else clock.elapsed_seconds
	history.append(event)
	event_recorded.emit(event)
	print("[EventBus] %s %s" % [kind, JSON.stringify(details)])
