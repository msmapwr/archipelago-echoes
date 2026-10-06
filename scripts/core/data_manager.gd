extends Node

const VisualCatalog = preload("res://scripts/data/unit_visual_catalog.gd")

const DEFINITION_PATHS: PackedStringArray = [
	"res://data/ships/escort_carrier.tres",
	"res://data/ships/fleet_carrier.tres",
	"res://data/ships/destroyer.tres",
	"res://data/ships/cruiser.tres",
	"res://data/ships/battleship.tres",
	"res://data/ships/submarine.tres",
	"res://data/aircraft/scout_plane.tres",
	"res://data/weapons/defensive_gun.tres",
	"res://data/contacts/unknown_vessel.tres",
	"res://data/tasks/first_recon.tres",
]

var definitions: Dictionary = {}
var errors: PackedStringArray = []

func _ready() -> void:
	reload()

func reload() -> bool:
	definitions.clear()
	errors.clear()
	for path in DEFINITION_PATHS:
		var resource := ResourceLoader.load(path)
		if resource == null:
			errors.append("%s: cannot load resource" % path)
			continue
		register_definition(resource, path)
	var symbol_owners: Dictionary = {}
	for definition in definitions.values():
		if definition is ShipDefinition or definition is BuildingDefinition:
			var symbol_key: String = definition.symbol_id if not definition.symbol_id.is_empty() else definition.id
			if symbol_owners.has(symbol_key):
				errors.append("%s: duplicate unit symbol id %s" % [definition.id, symbol_key])
			symbol_owners[symbol_key] = definition.id
			var kind: String = definition.ship_kind if definition is ShipDefinition else definition.building_kind
			var prefix: String = "ship" if definition is ShipDefinition else "building"
			var slots := VisualCatalog.variant_slots(definition.visual_family_id, definition.size_class)
			if definition.visual_family_id != prefix + "." + kind or slots.is_empty() or definition.shape_variant < 1 or definition.shape_variant > slots.size():
				errors.append("%s: invalid unit visual family, size or variant" % definition.id)
		if definition is ShipDefinition:
			for aircraft_id in definition.aircraft_ids:
				_require_reference(definition.id, aircraft_id, AircraftDefinition)
			for weapon_id in definition.weapon_ids:
				_require_reference(definition.id, weapon_id, WeaponDefinition)
		elif definition is TaskDefinition:
			_require_reference(definition.id, definition.ship_id, ShipDefinition)
			_require_reference(definition.id, definition.aircraft_id, AircraftDefinition)
			_require_reference(definition.id, definition.target_contact_id, ContactDefinition)
		elif definition is ContactDefinition and not definition.identified_ship_id.is_empty():
			_require_reference(definition.id, definition.identified_ship_id, ShipDefinition)
	for error in errors:
		push_error("[DataManager] " + error)
	return errors.is_empty()

func register_definition(resource: Resource, source: String) -> bool:
	if not resource is GameDefinition:
		errors.append("%s: expected GameDefinition" % source)
		return false
	var definition: GameDefinition = resource
	if definition.id.strip_edges().is_empty():
		errors.append("%s: missing id" % source)
		return false
	if definition.display_name.strip_edges().is_empty():
		errors.append("%s: missing display_name" % source)
		return false
	if definition.schema_version != 1:
		errors.append("%s: unsupported schema_version %d" % [source, definition.schema_version])
		return false
	if definitions.has(definition.id):
		errors.append("%s: duplicate id %s" % [source, definition.id])
		return false
	definitions[definition.id] = definition
	return true

func get_definition(id: String) -> GameDefinition:
	if not definitions.has(id):
		push_error("[DataManager] unknown id: " + id)
		return null
	return definitions[id]

func _require_reference(owner_id: String, id: String, expected_type: Variant) -> void:
	if not definitions.has(id):
		errors.append("%s: missing reference %s" % [owner_id, id])
	elif not is_instance_of(definitions[id], expected_type):
		errors.append("%s: reference %s has wrong type" % [owner_id, id])
