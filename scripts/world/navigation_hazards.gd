extends RefCounted

const SAMPLE_KM := 0.02
const REFLOAT_SPEED_KNOTS := 4.0

static func impact_damage(speed_knots: float, kind: String) -> float:
	if kind == "boundary": return 0.0
	return minf(100, 6.0 + speed_knots * speed_knots * (0.35 if kind == "collision" else 0.22))

static func trace(from: Vector2, to: Vector2, draft_m: float, depth: Callable, bounds: Rect2, escaping: bool = false) -> Dictionary:
	var steps := maxi(1, ceili(from.distance_to(to) / SAMPLE_KM))
	var safe := from
	var start_depth: float = depth.call(from)
	for index in range(1, steps + 1):
		var point := from.lerp(to, float(index) / steps)
		if not bounds.has_point(point): return {"kind":"boundary", "position":safe, "depth_m":0.0}
		var water_depth: float = depth.call(point)
		if water_depth <= 0:
			return {"kind":"collision", "position":safe, "depth_m":water_depth}
		if water_depth < draft_m and not (escaping and water_depth >= start_depth):
			return {"kind":"grounding", "position":safe, "depth_m":water_depth}
		safe = point
	return {}
