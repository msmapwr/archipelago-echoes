extends RefCounted

# Stable structural asset IDs. Instances retain their own ID.
const SHIP_KINDS := ["escort_carrier", "carrier", "destroyer", "cruiser", "battleship", "submarine"]
const BUILDING_KINDS := ["port", "airfield", "headquarters", "city", "barracks", "factory", "radar_station", "drydock"]
const SIZE_CLASSES := ["small", "medium", "large"]
const MIN_VARIANTS := 10

static func variant_slots(family: String, size_class: String) -> PackedStringArray:
	var parts := family.split(".")
	if parts.size() != 2 or not SIZE_CLASSES.has(size_class):
		return []
	if (parts[0] != "ship" or not SHIP_KINDS.has(parts[1])) and (parts[0] != "building" or not BUILDING_KINDS.has(parts[1])):
		return []
	var slots := PackedStringArray()
	for index in range(MIN_VARIANTS):
		slots.append("%s.%s.%02d" % [family, size_class, index + 1])
	return slots

static func symbol_outline(family: String) -> PackedVector2Array:
	# Legacy outline API; live UI renders the structural source in unit_glyph.gd.
	match family:
		"ship.escort_carrier": return PackedVector2Array([Vector2(-5,-10), Vector2(5,-10), Vector2(5,8), Vector2(0,11), Vector2(-5,8), Vector2(-5,-10)])
		"ship.carrier": return PackedVector2Array([Vector2(-7,-11), Vector2(7,-11), Vector2(7,9), Vector2(-7,9), Vector2(-7,-11)])
		"ship.destroyer": return PackedVector2Array([Vector2(0,-12), Vector2(4,6), Vector2(0,10), Vector2(-4,6), Vector2(0,-12)])
		"ship.cruiser": return PackedVector2Array([Vector2(0,-12), Vector2(6,-4), Vector2(6,7), Vector2(0,11), Vector2(-6,7), Vector2(-6,-4), Vector2(0,-12)])
		"ship.battleship": return PackedVector2Array([Vector2(-3,-11), Vector2(3,-11), Vector2(8,-4), Vector2(8,8), Vector2(-8,8), Vector2(-8,-4), Vector2(-3,-11)])
		"ship.submarine": return PackedVector2Array([Vector2(0,-12), Vector2(3,-7), Vector2(3,7), Vector2(0,12), Vector2(-3,7), Vector2(-3,-7), Vector2(0,-12)])
		"building.port": return PackedVector2Array([Vector2(-9,-9),Vector2(-9,9),Vector2(9,9),Vector2(9,-9)])
		"building.airfield": return PackedVector2Array([Vector2(0,-11),Vector2(0,11),Vector2.ZERO,Vector2(-11,0),Vector2(11,0)])
		"building.headquarters": return PackedVector2Array([Vector2(0,-11),Vector2(10,-2),Vector2(10,9),Vector2(-10,9),Vector2(-10,-2),Vector2(0,-11)])
		"building.city": return PackedVector2Array([Vector2(-10,10),Vector2(-10,-3),Vector2(-3,-3),Vector2(-3,-11),Vector2(4,-11),Vector2(4,0),Vector2(10,0),Vector2(10,10),Vector2(-10,10)])
		"building.barracks": return PackedVector2Array([Vector2(-10,8),Vector2(0,-8),Vector2(10,8),Vector2(-10,8)])
		"building.factory": return PackedVector2Array([Vector2(-10,9),Vector2(-10,-3),Vector2(-3,-9),Vector2(-3,-3),Vector2(4,-9),Vector2(4,-3),Vector2(10,-3),Vector2(10,9),Vector2(-10,9)])
		"building.radar_station": return PackedVector2Array([Vector2(-9,-7),Vector2(0,2),Vector2(9,-7),Vector2(0,2),Vector2(0,11)])
	return PackedVector2Array([Vector2(0,-5),Vector2(5,0),Vector2(0,5),Vector2(-5,0),Vector2(0,-5)])
