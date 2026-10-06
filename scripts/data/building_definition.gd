extends GameDefinition
class_name BuildingDefinition

@export var building_kind: String = "port"
@export var size_class: String = "medium"
@export var symbol_id: String = ""
@export var visual_family_id: String = "building.port"
@export_range(1, 10) var shape_variant: int = 1
@export var symbol_texture: Texture2D
@export var silhouette_scene: PackedScene
