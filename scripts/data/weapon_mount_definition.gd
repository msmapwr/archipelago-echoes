extends Resource
class_name WeaponMountDefinition

@export var mount_id: String = "fore"
@export var display_name: String = "前炮"
@export var weapon_id: String = "weapon.deck_gun"
@export var local_position_km := Vector2(0, -0.03)
@export var relative_heading_degrees: float = 0.0
@export var half_arc_degrees: float = 70.0
@export var reload_seconds: float = 30.0
@export var capacity: int = 6
