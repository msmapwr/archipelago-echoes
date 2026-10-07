extends RefCounted

# Integer rectangles are editable vector source; rasterization happens only at export.
const NAMES := {"escort_carrier":"护航航舰", "carrier":"航空母舰", "destroyer":"驱逐舰", "cruiser":"巡洋舰", "battleship":"战列舰", "submarine":"潜艇", "port":"港口", "airfield":"机场", "headquarters":"指挥部", "drydock":"船坞 / 维修设施", "city":"城市", "barracks":"兵营", "factory":"工厂", "radar_station":"雷达站"}
static var cache: Dictionary = {}

static func source(family: String, size_class: String = "medium", variant: int = 1, detailed: bool = true) -> Array:
	var key := "%s.%s.%02d.%s" % [family, size_class, variant, detailed]
	if cache.has(key): return cache[key]
	var kind := family.get_slice(".", 1)
	var grade := maxi(0, ["small", "medium", "large"].find(size_class))
	var v := clampi(variant, 1, 10) - 1
	var a: Array = []
	if family.begins_with("ship."):
		var half := 23 + grade * 3 + v % 3
		var width := 5 + grade + floori(float(v) / 3.0)
		if kind in ["carrier", "escort_carrier"]: width += 5 if kind == "carrier" else 2
		if kind == "battleship": width += 3
		if kind == "submarine": width = 4 + grade
		for y in range(-half, half + 1):
			var w := mini(width, maxi(1, (half - absi(y)) * (2 if y < 0 else 3) + 1))
			add(a, -w, y, w * 2 + 1, 1, 0.32)
			add(a, -w, y, 1, 1, 1.0)
			add(a, w, y, 1, 1, 1.0)
		if kind in ["carrier", "escort_carrier"]:
			box(a, -width + 2, -half + 6, width * 2 - 3, half * 2 - 12)
			box(a, width - 4, -7 + v, 4, 10 + grade)
			for y in range(-half + 9, half - 6, 5): add(a, -3 + v % 3, y, 1, 2)
			if detailed:
				# Fleet carriers have an angled landing lane and two deck elevators.
				if kind == "carrier":
					for y in range(-half + 8, half - 7): add(a, -width + 3 + floori(float(y + half) / 7.0), y, 1, 1)
					box(a, -width + 1, -8 - v % 3, 4, 5)
					box(a, -width + 1, 12 + v % 3, 4, 5)
				add(a, width - 3, -10 + v, 1, 6)
				add(a, width - 5, -9 + v, 5, 1)
				for n in range(2 + grade + (2 if kind == "carrier" else 0)):
					var y := -half + 10 + n * 6
					add(a, -width + 4, y, 3, 1)
					add(a, -width + 5, y - 1, 1, 3)
		elif kind == "submarine":
			box(a, -2, -6 + v % 4, 5, 10)
			add(a, -width - 4, half - 7, width * 2 + 9, 2)
			add(a, -width - 2, -half + 10 + v % 4, width * 2 + 5, 1)
			if detailed: add(a, 0, -9 + v % 4, 1, 6)
		else:
			box(a, -width + 2, -4 + v % 3, width * 2 - 3, 7 + grade)
			var guns: int = {"destroyer":2, "cruiser":3, "battleship":4}.get(kind, 2) + (1 if grade == 2 else 0)
			var stations := [-half + 7, half - 7]
			if kind == "cruiser": stations = [-half + 7, -half + 14, half - 7]
			if kind == "battleship": stations = [-half + 7, -half + 14, half - 14, half - 7]
			if grade == 2: stations.insert(2, half - 21)
			for n in range(guns):
				var y: int = stations[n]
				var radius := 3 if kind == "battleship" else 2
				box(a, -radius, y - 2, radius * 2 + 1, 4)
				for barrel in range(3 if kind == "battleship" else (2 if kind == "cruiser" else 1)):
					add(a, -radius + 1 + barrel * 2, y - 6 if y < 0 else y + 2, 1, 4)
			if detailed:
				add(a, -4, -2, 9, 1)
				add(a, 0, -5, 1, 8)
				for n in range(1 + grade): box(a, width - 2, 6 + n * 4, 2, 3)
	else:
		var shift := v % 5 * 2
		var count := 2 + grade + floori(float(v) / 5.0)
		match kind:
			"port", "drydock":
				box(a, -28, -26 + shift, 9, 46 - shift)
				for n in range(count):
					var y := -26 + floori(float(shift) / 2.0) + n * 8
					add(a, -19, y, 32 + v % 3 * 3, 3)
					if kind == "drydock":
						add(a, -19, y + 7, 32 + v % 3 * 3, 2)
						if detailed: box(a, -13, y + 3, 21, 3)
					elif detailed: box(a, -26, y + 1, 5, 5)
				add(a, 23 + v % 3, -28, 3, 48)
				add(a, 6, -28, 20, 3)
			"airfield":
				box(a, -5, -29, 10, 58)
				for y in range(-25, 27, 6): add(a, 0, y, 1, 3)
				add(a, 5, -14 + shift, 19, 2)
				box(a, 11, -11 + shift, 14, 25)
				for n in range(count): box(a, -25, -24 + n * 10 + v % 3, 12, 8)
				box(a, 20, 21 - v % 4, 5, 5)
			"headquarters":
				box(a, -13, -13, 26, 26)
				box(a, -22, -22 + shift, 9, 30 - shift)
				box(a, 13, -15 + shift, 9, 30 - shift)
				add(a, -3, -8, 6, 16)
				add(a, -8, -3, 16, 6)
				for n in range(count): box(a, -20 + n * 10, 20, 6, 5)
			"radar_station":
				for y in range(-17, 18):
					var x := roundi(sqrt(289 - y * y))
					add(a, -x, y - 7, 1, 1)
					add(a, x, y - 7, 1, 1)
				add(a, -21, -18 + shift, 42, 2)
				add(a, 0, -25, 2, 43)
				box(a, -13, 18, 26, 9)
				for n in range(count): box(a, -28 + n * 11, 28, 8, 3)
			_:
				for n in range(count + 2):
					var x := -25 + n % 3 * 18
					var y := -25 + floori(float(n) / 3.0) * 18 + v % 5
					box(a, x, y, 10 + (n + v) % 4, 12 + grade * 2)
					if detailed: add(a, x + 2, y + 3, 5, 1)
				if kind == "factory":
					for n in range(3): box(a, -20 + n * 17, 22, 5, 6)
				elif kind == "barracks": add(a, -28, 19, 55, 2)
				elif kind == "city": box(a, 15 - v, 19, 10, 12)
	cache[key] = a
	return a

static func add(a: Array, x: int, y: int, w: int, h: int, ink: float = 1.0) -> void:
	a.append([x, y, w, h, ink])

static func box(a: Array, x: int, y: int, w: int, h: int) -> void:
	add(a, x, y, w, h, 0.22)
	add(a, x, y, w, 1)
	add(a, x, y + h - 1, w, 1)
	add(a, x, y, 1, h)
	add(a, x + w - 1, y, 1, h)

static func draw(canvas: CanvasItem, center: Vector2, pixels: float, family: String, tint: Color, size_class: String = "medium", variant: int = 1, detailed: bool = false) -> void:
	var scale := pixels / 64.0
	for cell in source(family, size_class, variant, detailed):
		canvas.draw_rect(Rect2(center + Vector2(cell[0], cell[1]) * scale, Vector2(cell[2], cell[3]) * scale), Color(tint, tint.a * cell[4]))

static func unknown(canvas: CanvasItem, center: Vector2, tint: Color) -> void:
	# No family, size, model or variant input: hidden identity cannot affect the echo.
	for cell in [[-3,-7,3,2], [2,-4,2,4], [-4,2,2,3], [0,6,3,2]]:
		canvas.draw_rect(Rect2(center + Vector2(cell[0], cell[1]), Vector2(cell[2], cell[3])), tint)

static func export_icon(family: String, size_class: String, variant: int, directory: String = "user://icons") -> Error:
	var stem := directory.path_join("%s.%s.%02d" % [family, size_class, variant])
	DirAccess.make_dir_recursive_absolute(directory)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-32 -32 64 64" shape-rendering="crispEdges">'
	for c in source(family, size_class, variant):
		img.fill_rect(Rect2i(c[0] + 32, c[1] + 32, c[2], c[3]), Color(1, 1, 1, c[4]))
		svg += '<rect x="%d" y="%d" width="%d" height="%d" fill="white" opacity="%s"/>' % c
	var file := FileAccess.open(stem + ".svg", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(svg + "</svg>")
	file = FileAccess.open(stem + ".json", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version":1, "family":family,"size":size_class,"variant":variant,"rectangles":source(family,size_class,variant)}, "\t"))
	return img.save_png(stem + ".png")

static func export_atlas(directory: String = "user://icons") -> Error:
	var catalog = preload("res://scripts/data/unit_visual_catalog.gd")
	var atlas := Image.create(1280, 1344, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var manifest: Array = []
	var index := 0
	for kind in catalog.SHIP_KINDS + catalog.BUILDING_KINDS:
		var family: String = ("ship." if catalog.SHIP_KINDS.has(kind) else "building.") + kind
		for grade in catalog.SIZE_CLASSES:
			for variant in range(1, 11):
				var origin := Vector2i(index % 20 * 64, floori(float(index) / 20.0) * 64)
				for c in source(family, grade, variant):
					atlas.fill_rect(Rect2i(origin + Vector2i(c[0] + 32, c[1] + 32), Vector2i(c[2], c[3])), Color(1, 1, 1, c[4]))
				manifest.append({"id":"%s.%s.%02d" % [family, grade, variant], "x":origin.x,"y":origin.y,"width":64,"height":64})
				index += 1
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("atlas.json"), FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version":1,"items":manifest}, "\t"))
	return atlas.save_png(directory.path_join("atlas.png"))
