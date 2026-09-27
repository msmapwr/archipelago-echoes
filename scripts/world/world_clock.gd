extends Node

signal time_advanced(total_seconds: float)

var elapsed_seconds: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> bool:
	if get_tree().paused or delta <= 0.0:
		return false
	elapsed_seconds += delta
	time_advanced.emit(elapsed_seconds)
	return true

func reset() -> void:
	elapsed_seconds = 0.0
	time_advanced.emit(elapsed_seconds)

func formatted_time() -> String:
	var whole_seconds := floori(elapsed_seconds)
	return "T+%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
