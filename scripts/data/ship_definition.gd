extends GameDefinition
class_name ShipDefinition

@export var max_speed_knots: float = 20.0
@export var armor_mm: float = 70.0
@export var aircraft_ids: PackedStringArray = []
@export var weapon_ids: PackedStringArray = []
@export var ship_kind: String = "escort_carrier"
@export var size_class: String = "medium"
@export var symbol_id: String = ""
@export var visual_family_id: String = "ship.escort_carrier"
@export_range(1, 10) var shape_variant: int = 1
@export var symbol_texture: Texture2D
@export var silhouette_scene: PackedScene
