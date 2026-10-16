extends RefCounted

# Pure geometry shared by chart projections; returns no gameplay state.
static func clip_polygon_circle(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	# Clip against an inscribed scope polygon; filled coast never leaks past glass.
	var contained := true
	var inner_radius_squared := radius * radius * pow(cos(PI / 96.0), 2)
	for point in points:
		if point.length_squared() > inner_radius_squared:
			contained = false
			break
	if contained: return points
	var clipped := points
	for edge in range(96):
		if clipped.size() < 3: return PackedVector2Array()
		var normal := Vector2.from_angle(TAU * (edge + 0.5) / 96.0)
		var limit := radius * cos(PI / 96.0)
		var output := PackedVector2Array()
		var previous := clipped[-1]
		var previous_distance := previous.dot(normal) - limit
		for point in clipped:
			var distance := point.dot(normal) - limit
			if (distance <= 0) != (previous_distance <= 0):
				output.append(previous.lerp(point, previous_distance / (previous_distance - distance)))
			if distance <= 0: output.append(point)
			previous = point
			previous_distance = distance
		clipped = output
	return clipped

static func clip_circle(from: Vector2, to: Vector2, radius: float) -> PackedVector2Array:
	var direction := to - from
	var a := direction.length_squared()
	if a < 0.000001 or radius <= 0: return PackedVector2Array()
	if minf(from.x, to.x) > radius or maxf(from.x, to.x) < -radius or minf(from.y, to.y) > radius or maxf(from.y, to.y) < -radius: return PackedVector2Array()
	if from.length_squared() <= radius * radius and to.length_squared() <= radius * radius: return PackedVector2Array([from, to])
	var b := 2.0 * from.dot(direction)
	var c := from.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0: return PackedVector2Array()
	var low := maxf(0, (-b - sqrt(discriminant)) / (2.0 * a))
	var high := minf(1, (-b + sqrt(discriminant)) / (2.0 * a))
	if low >= high: return PackedVector2Array()
	return PackedVector2Array([from + direction * low, from + direction * high])

static func grid_contours(bounds: Rect2, depth: Callable, clear_segment: Callable, levels: Array, columns: int = 40, rows: int = 32) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var step := bounds.size / Vector2(columns, rows)
	var samples: Array[float] = []
	for y in range(rows + 1):
		for x in range(columns + 1): samples.append(depth.call(bounds.position + Vector2(x, y) * step))
	for level in levels:
		var segments: Array[PackedVector2Array] = []
		for y in range(rows):
			for x in range(columns):
				var origin := bounds.position + Vector2(x, y) * step
				var points := [origin, origin + Vector2(step.x, 0), origin + step, origin + Vector2(0, step.y)]
				var values := [samples[y * (columns + 1) + x], samples[y * (columns + 1) + x + 1], samples[(y + 1) * (columns + 1) + x + 1], samples[(y + 1) * (columns + 1) + x]]
				var crossings: Array[Vector2] = []
				for edge in range(4):
					var next := (edge + 1) % 4
					if (values[edge] < level) != (values[next] < level): crossings.append(points[edge].lerp(points[next], (level - values[edge]) / (values[next] - values[edge])))
				for index in range(0, crossings.size() - 1, 2):
					if clear_segment.call(crossings[index], crossings[index + 1]): segments.append(PackedVector2Array([crossings[index], crossings[index + 1]]))
		result.append({"depth_m": level, "segments": segments})
	return result
