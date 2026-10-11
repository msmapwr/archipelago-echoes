extends RefCounted

const MIN_INTERVAL := 1.0
const MAX_AGE := 45.0
const MAX_SPEED_KM_S := 80.0 * 1.852 / 3600.0
var latest_position := Vector2.ZERO
var latest_seconds := -1.0
var velocity := Vector2.ZERO
var interval := 0.0
var has_velocity := false

func reset() -> void:
	latest_seconds = -1.0
	has_velocity = false
	interval = 0.0
	velocity = Vector2.ZERO

func observe(position: Vector2, seconds: float) -> void:
	if not position.is_finite() or not is_finite(seconds) or seconds < 0:
		reset()
		return
	if latest_seconds >= 0:
		var gap := seconds - latest_seconds
		if gap >= 0 and gap < MIN_INTERVAL:
			return # Repeated scans in the same instant are not independent motion samples.
		has_velocity = false
		if gap >= MIN_INTERVAL and gap <= MAX_AGE:
			var measured := (position - latest_position) / gap
			if measured.length() <= MAX_SPEED_KM_S:
				velocity = measured
				interval = gap
				has_velocity = true
	latest_position = position
	latest_seconds = seconds

func solve(origin: Vector2, seconds: float, projectile_speed: float) -> Dictionary:
	var result := {"valid": false, "reason": "提前量需要两次间隔至少 1 秒的有效观测"}
	if not origin.is_finite() or not is_finite(seconds) or not is_finite(projectile_speed) or projectile_speed <= 0:
		result.reason = "解算参数无效"
		return result
	var age := seconds - latest_seconds
	if latest_seconds < 0:
		return result
	if age < 0 or age > MAX_AGE:
		result.reason = "运动观测已过期；重新积累两次观测"
		return result
	if not has_velocity:
		return result
	var current := latest_position + velocity * age
	var relative := current - origin
	var a := velocity.length_squared() - projectile_speed * projectile_speed
	var b := 2.0 * relative.dot(velocity)
	var c := relative.length_squared()
	var flight_time := 0.0
	if c > 0:
		if absf(a) < 0.000000001:
			if b >= 0:
				result.reason = "目标运动无法形成拦截解"
				return result
			flight_time = -c / b
		else:
			var discriminant := b * b - 4.0 * a * c
			if discriminant < 0:
				result.reason = "目标运动无法形成拦截解"
				return result
			var t1 := (-b - sqrt(discriminant)) / (2.0 * a)
			var t2 := (-b + sqrt(discriminant)) / (2.0 * a)
			flight_time = minf(t1, t2) if t1 >= 0 and t2 >= 0 else maxf(t1, t2)
			if flight_time < 0 or not is_finite(flight_time):
				result.reason = "目标运动无法形成拦截解"
				return result
	var aim := current + velocity * flight_time
	if not is_finite(flight_time) or not aim.is_finite():
		result.reason = "解算超出有效数值范围"
		return result
	return {"valid": true, "reason": "", "aim_position_km": aim,
		"velocity_km_s": velocity, "speed_knots": velocity.length() * 3600.0 / 1.852,
		"age_seconds": age, "sample_interval_seconds": interval, "observation_seconds": latest_seconds,
		"flight_seconds": flight_time, "confidence": "新鲜" if age <= 15 else "老化"}
