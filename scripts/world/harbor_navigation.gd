extends RefCounted

const KNOT_TO_KM_PER_SECOND := 1.852 / 3600.0
const MAX_SPEED_KNOTS := 10.0
const EXIT_Y_KM := -0.32
const EXIT_HALF_WIDTH_KM := 0.08
const WATER_BOUNDS := Rect2(-0.25, -0.36, 0.5, 0.44)
const OBSTACLES: Array[Rect2] = [Rect2(-0.25, -0.12, 0.17, 0.2), Rect2(0.08, -0.20, 0.17, 0.08)]

var position_km := Vector2.ZERO
var heading_degrees: float = 0.0
var speed_knots: float = 0.0
var elapsed_seconds: float = 0.0
var moored: bool = true
var departed: bool = false
var message: String = "命令已接收。先解缆，再沿中央航道向北驶出。"

func cast_off() -> bool:
	if not moored or departed:
		return false
	moored = false
	message = "已解缆。加速后向北航行；港内限速 10 kn。"
	return true

func set_command(heading: float, speed: float) -> bool:
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
	if departed or not is_finite(delta) or delta <= 0.0:
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
	if not _clear_segment(position_km, destination) or (crosses_exit and absf(destination.x) > EXIT_HALF_WIDTH_KM):
		speed_knots = 0.0
		message = "航路受阻，已停车。调整航向并沿中央航道重试。"
		return false
	position_km = destination
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
