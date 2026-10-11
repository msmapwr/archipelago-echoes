extends GameDefinition
class_name ContactDefinition

@export var bearing_degrees: float = 0.0
@export var range_km: float = 10.0
@export var faction_id: String = "unknown"
@export var identified_ship_id: String = ""
@export_range(1, 99) var withdrawal_health: float = 40.0
@export var withdrawal_speed_knots: float = 18.0
@export var withdrawal_turn_degrees: float = 5.0
