extends SceneTree

const Glyph = preload("res://scripts/data/unit_glyph.gd")
const Catalog = preload("res://scripts/data/unit_visual_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var count := 0
	for kind in Catalog.SHIP_KINDS + Catalog.BUILDING_KINDS:
		var family: String = ("ship." if Catalog.SHIP_KINDS.has(kind) else "building.") + kind
		for grade in Catalog.SIZE_CLASSES:
			var seen: Dictionary = {}
			for variant in range(1, 11):
				var cells := Glyph.source(family, grade, variant)
				var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
				image.fill(Color.TRANSPARENT)
				for c in cells:
					check(c[2] > 0 and c[3] > 0 and c[0] >= -32 and c[1] >= -32 and c[0] + c[2] <= 32 and c[1] + c[3] <= 32, "out of bounds: %s/%s/%d %s" % [family,grade,variant,c])
					image.fill_rect(Rect2i(c[0]+32,c[1]+32,c[2],c[3]),Color(1,1,1,c[4]))
				var signature := image.get_data().hex_encode().sha256_text()
				check(not seen.has(signature), "duplicate rendered variant: %s/%s/%d" % [family,grade,variant])
				seen[signature] = true
				count += 1
	check(count == 420, "complete library")
	var library: Control = load("res://scenes/unit_showcase.tscn").instantiate()
	root.add_child(library)
	await process_frame
	check(library.tiles.size() == 10 and library.previews.size() == 2, "gallery has variants and both detail levels")
	library.family_picker.select(9)
	library.variant_picker.select(9)
	library.refresh()
	check(library.previews[0].variant == 10, "filters update actual geometry")
	# Export only fixtures; never overwrite a user's exported icon.
	var test_image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	test_image.fill(Color.TRANSPARENT)
	for c in Glyph.source("ship.carrier", "large", 10):
		test_image.fill_rect(Rect2i(c[0]+32,c[1]+32,c[2],c[3]), Color(1,1,1,c[4]))
	check(test_image.get_pixel(0,0).a == 0, "transparent canvas")
	check(JSON.parse_string(JSON.stringify(Glyph.source("building.airfield"))) != null, "vector source serializable")
	var fixture := "user://qa-icons-%d" % Time.get_ticks_usec()
	check(Glyph.export_icon("ship.carrier", "large", 10, fixture) == OK, "PNG SVG JSON export")
	check(Glyph.export_atlas(fixture) == OK, "atlas export")
	var exported := Image.load_from_file(fixture.path_join("ship.carrier.large.10.png"))
	check(exported != null and exported.get_pixel(0,0).a == 0, "export retains transparency")
	var data = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("ship.carrier.large.10.json")))
	check(data != null and data.version == 1 and data.variant == 10, "versioned export can be read")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("atlas.json")))
	check(manifest != null and manifest.items.size() == 420, "atlas indexes every form")
	for file in ["ship.carrier.large.10.png", "ship.carrier.large.10.svg", "ship.carrier.large.10.json", "atlas.png", "atlas.json"]:
		DirAccess.remove_absolute(fixture.path_join(file))
	DirAccess.remove_absolute(fixture)
	if failures.is_empty():
		print("Unit icon smoke passed: 420 distinct bounded structural forms")
		quit(0)
	else:
		for failure in failures: printerr(failure)
		quit(1)

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
