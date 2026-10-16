extends RefCounted

const KNOT_TO_KM_PER_SECOND := 1.852 / 3600.0
const MAX_SPEED_KNOTS := 10.0
const EXIT_Y_KM := -1.28
const EXIT_HALF_WIDTH_KM := 0.32
const WATER_BOUNDS := Rect2(-1.0, -1.44, 2.0, 1.76)
const OBSTACLES: Array[Rect2] = [Rect2(-1.0, -0.48, 0.68, 0.8), Rect2(0.32, -0.80, 0.68, 0.32)]
const Hazards = preload("res://scripts/world/navigation_hazards.gd")

var position_km := Vector2.ZERO
var heading_degrees: float = 0.0
var speed_knots: float = 0.0
var elapsed_seconds: float = 0.0
var moored: bool = true
var departed: bool = false
var message: String = "命令已接收。先解缆，再沿中央航道向北驶出。"
var map_seed := 270928
var hull := 100.0
var grounded := false
var failed := false
var impacts: Array[Dictionary] = []

static func depth_at(point: Vector2, chart_seed: int = 270928) -> float:
	if not WATER_BOUNDS.has_point(point): return 0.0
	var distance := minf(point.x - WATER_BOUNDS.position.x, WATER_BOUNDS.end.x - point.x)
	distance = minf(distance, WATER_BOUNDS.end.y - point.y)
	for quay in OBSTACLES:
		if quay.has_point(point): return 0.0
		var outside := (point - quay.get_center()).abs() - quay.size * 0.5
		distance = minf(distance, Vector2(maxf(0, outside.x), maxf(0, outside.y)).length())
	var phase := fposmod(float(chart_seed) * 0.618, TAU)
	return maxf(0, distance) * 30.0 / (1.0 + 0.19 * sin(point.x * 8 + point.y * 4 + phase) + 0.13 * cos(point.y * 9 - point.x * 3 - phase))

func sample_depth(point: Vector2) -> float:
	return depth_at(point, map_seed)

func cast_off() -> bool:
	if not moored or departed or failed:
		return false
	moored = false
	message = "已解缆。加速后向北航行；港内限速 10 kn。"
	return true

func set_command(heading: float, speed: float) -> bool:
	if failed: return false
	if grounded and speed > Hazards.REFLOAT_SPEED_KNOTS:
		message = "搁浅：转向深水，以不超过 4 kn 脱浅。"
		return false
	if moored or departed:
		message = "请先解缆。" if moored else "已离港。"
		return false
	if not is_finite(heading) or not is_finite(speed) or speed < 0.0 or speed > MAX_SPEED_KNOTS:
		message = "港内航速必须在 0–10 kn 之间。"
		return false
	heading_degrees = fposmod(heading, 360.0)
	speed_knots = speed
	message = "航行命令已生效。沿中央航道通过北侧离港线。"
	return true

func advance(delta: float) -> bool:
	if departed or failed or not is_finite(delta) or delta <= 0.0:
		return false
	elapsed_seconds += delta
	if moored or speed_knots <= 0.0:
		return false
	var direction := Vector2(sin(deg_to_rad(heading_degrees)), -cos(deg_to_rad(heading_degrees)))
	var destination := position_km + direction * speed_knots * KNOT_TO_KM_PER_SECOND * delta
	var crosses_exit := position_km.y > EXIT_Y_KM and destination.y <= EXIT_Y_KM
	if crosses_exit:
		var fraction := (EXIT_Y_KM - position_km.y) / (destination.y - position_km.y)
		destination = position_km.lerp(destination, fraction)
	var impact := Hazards.trace(position_km, destination, 4.0, sample_depth, WATER_BOUNDS, grounded)
	if not impact.is_empty() or not _clear_segment(position_km, destination) or (crosses_exit and absf(destination.x) > EXIT_HALF_WIDTH_KM):
		if not impact.is_empty() and impact.kind != "boundary":
			position_km = impact.position
			grounded = true
			impact.speed_knots = speed_knots
			impact.damage = Hazards.impact_damage(speed_knots, impact.kind)
			hull = maxf(0, hull - impact.damage)
			impact.hull = hull
			impact.harbor_seconds = elapsed_seconds
			impacts.append(impact)
			failed = hull <= 0
		speed_knots = 0.0
		message = "港内撞毁；返回主菜单重新准备。" if failed else "触浅受损，已停车。转向深水，以不超过 4 kn 脱浅。" if grounded else "航路受阻，已停车。调整航向并沿中央航道重试。"
		return false
	position_km = destination
	if grounded and sample_depth(position_km) >= 5.0:
		grounded = false
		message = "已脱浅；损伤将带入海上任务，必要时投入损管。"
	if crosses_exit:
		departed = true
		message = "已驶离港口，移交海上任务。"
	return departed

func _clear_segment(from: Vector2, to: Vector2) -> bool:
	if not WATER_BOUNDS.has_point(to):
		return false
	for obstacle in OBSTACLES:
		if obstacle.has_point(to):
			return false
		var corners := [obstacle.position, Vector2(obstacle.end.x, obstacle.position.y), obstacle.end, Vector2(obstacle.position.x, obstacle.end.y)]
		for index in range(4):
			if Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % 4]) != null:
				return false
	return true
