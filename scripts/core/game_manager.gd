extends Node

const TRANSITIONS: Dictionary = {
	"bridge": ["configuration", "settlement", "campaign_failed"],
	"configuration": ["bridge", "switching", "campaign_failed"],
	"switching": ["configuration", "cockpit", "campaign_failed"],
	"cockpit": ["returning", "campaign_failed"],
	"returning": ["cockpit", "bridge", "recovered", "campaign_failed"],
	"recovered": ["settlement", "campaign_failed"],
	"settlement": ["bridge", "campaign_failed"],
	"campaign_failed": [],
}

var mode: String = "bridge"
var player_alive: bool = true
var ship_afloat: bool = true
var aircraft_operational: bool = true
var target_identified: bool = false
var player_recovered: bool = false
var recovery_site: String = ""
var current_task_id: String = "task.first_recon"
var task_settled: bool = false
var last_death_reason: String = ""

func reset_for_new_scenario() -> void:
	mode = "bridge"
	player_alive = true
	ship_afloat = true
	aircraft_operational = true
	target_identified = false
	player_recovered = false
	recovery_site = ""
	current_task_id = "task.first_recon"
	task_settled = false
	last_death_reason = ""
	get_tree().paused = false
	EventBus.record("scenario_started", {"task_id": current_task_id})

func change_mode(next_mode: String) -> bool:
	if next_mode == "settlement":
		push_warning("[GameManager] use settle() to enter settlement")
		return false
	return _transition(next_mode)

func _transition(next_mode: String) -> bool:
	if not TRANSITIONS.has(next_mode) or not TRANSITIONS[mode].has(next_mode):
		push_warning("[GameManager] forbidden transition: %s -> %s" % [mode, next_mode])
		return false
	if next_mode == "bridge" and not ship_afloat:
		push_warning("[GameManager] cannot return to a sunken ship")
		return false
	if mode == "returning" and next_mode == "bridge" and (not player_recovered or recovery_site != "ship"):
		push_warning("[GameManager] return to bridge requires ship recovery")
		return false
	if next_mode == "settlement" and (not target_identified or not player_recovered):
		push_warning("[GameManager] settlement requires identified target and safe recovery")
		return false
	if next_mode == "campaign_failed" and player_alive:
		push_warning("[GameManager] campaign failure requires player death")
		return false
	var previous_mode := mode
	mode = next_mode
	EventBus.mode_changed.emit(previous_mode, mode)
	EventBus.record("mode_changed", {"from": previous_mode, "to": mode})
	return true

func report_player_death(reason: String) -> void:
	player_alive = false
	last_death_reason = reason
	EventBus.record("player_death", {"reason": reason})
	change_mode("campaign_failed")

func report_ship_sunk() -> void:
	ship_afloat = false
	EventBus.record("ship_sunk", {})
	if mode == "bridge" or mode == "configuration" or mode == "switching":
		report_player_death("ship_sunk_with_player_aboard")

func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	EventBus.record("simulation_pause_changed", {"paused": paused})

func identify_target(contact_id: String) -> bool:
	if not player_alive or mode in ["settlement", "campaign_failed"] or target_identified:
		return false
	var task: TaskDefinition = DataManager.get_definition(current_task_id) as TaskDefinition
	if task == null or task.target_contact_id != contact_id:
		return false
	target_identified = true
	EventBus.record("target_identified", {"contact_id": contact_id})
	return true

func recover_player(site: String) -> bool:
	if mode != "returning" or not player_alive:
		return false
	if site == "ship":
		if not ship_afloat:
			return false
		player_recovered = true
		recovery_site = site
		if not change_mode("bridge"):
			player_recovered = false
			recovery_site = ""
			return false
	elif site == "friendly_airfield" or site == "rescue":
		player_recovered = true
		recovery_site = site
		if not change_mode("recovered"):
			player_recovered = false
			recovery_site = ""
			return false
	else:
		return false
	EventBus.record("player_recovered", {"site": site})
	return true

func settle(result: String) -> bool:
	if not player_alive or not target_identified or not player_recovered or task_settled:
		return false
	if mode != "bridge" and mode != "recovered":
		return false
	task_settled = true
	if not _transition("settlement"):
		task_settled = false
		return false
	EventBus.task_settled.emit(current_task_id, result)
	EventBus.record("task_settled", {"task_id": current_task_id, "result": result})
	return true
