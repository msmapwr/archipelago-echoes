extends SceneTree

const Decay = preload("res://scripts/ui/phosphor_decay.gd")
const Catalog = preload("res://scripts/data/unit_visual_catalog.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Decay.energy(0, 95) == 1 and Decay.energy(95, 95) == 0, "fresh echoes are bright and expired echoes are dark")
	_check(Decay.energy(10, 95) > Decay.energy(45, 95) and Decay.energy(45, 95) > Decay.energy(80, 95), "echo energy decreases monotonically")
	_check(Decay.energy(100, 95) == 0 and Decay.energy(-10, 95) == 1, "age remains clamped")
	var symbols: Dictionary = {}
	for prefix in ["ship", "building"]:
		var kinds: Array = Catalog.SHIP_KINDS if prefix == "ship" else Catalog.BUILDING_KINDS
		for kind in kinds:
			var family: String = prefix + "." + kind
			var outline := str(Catalog.symbol_outline(family))
			_check(not symbols.has(outline), "category symbol is distinct: " + family)
			symbols[outline] = family
			for size_class in Catalog.SIZE_CLASSES:
				var slots := Catalog.variant_slots(family, size_class)
				_check(slots.size() >= 10 and slots[0] != slots[9], "ten asset slots per family and size: " + family + "." + size_class)
	_check(Catalog.variant_slots("ship.invalid", "small").is_empty(), "invalid asset family has no slots")
	var data: Node = root.get_node("DataManager")
	_check(data.errors.is_empty(), "warship metadata and references load")
	for ship_id in ["ship.haven", "ship.carrier", "ship.destroyer", "ship.cruiser", "ship.battleship", "ship.submarine"]:
		var ship: Resource = data.get_definition(ship_id)
		_check(ship != null and ship.symbol_id == ship_id, "ship has a stable unique symbol key: " + ship_id)
	var mission: Node = root.get_node("MissionController")
	var clock: Node = root.get_node("WorldClock")
	mission.restart_scenario()
	var radar: Control = load("res://scripts/ui/radar_display.gd").new()
	root.add_child(radar)
	mission.scan()
	_check(mission.last_contact_heading_degrees == mission.enemy_heading_degrees, "scan captures contact heading")
	var observed_heading: float = mission.last_contact_heading_degrees
	mission.enemy_heading_degrees = fposmod(observed_heading + 180, 360)
	_check(mission.last_contact_heading_degrees == observed_heading, "hidden heading change cannot rotate last observed target")
	var bright: float = radar.contact_energy()
	clock.advance(45)
	var dim: float = radar.contact_energy()
	_check(bright == 1 and dim > 0 and dim < bright, "live radar target dims since last observation")
	paused = true
	clock.advance(20)
	_check(radar.contact_energy() == dim, "pause freezes game phosphor age")
	paused = false
	mission.scan()
	_check(radar.contact_energy() == 1, "rescan restores target brightness")
	var menu: Control = load("res://scripts/ui/menu_scope.gd").new()
	root.add_child(menu)
	menu._sweep_degrees = 50
	menu._echo_age = 0
	menu._process(2)
	_check(menu._echo_age == 2, "menu target ages instead of pulsing")
	menu._sweep_degrees = 38
	menu._process(0.1)
	_check(menu._echo_age < 0.1, "menu sweep refreshes the echo")
	if failures.is_empty():
		print("Radar visual smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
