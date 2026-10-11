extends RefCounted

# Per-instance tactical memory; caller owns position, health and simulation time.
var withdrawing := false
var threat_known := false
var threat_position_km := Vector2.ZERO

func reset() -> void:
	withdrawing = false
	threat_known = false
	threat_position_km = Vector2.ZERO

func observe_threat(position_km: Vector2) -> void:
	if position_km.is_finite():
		threat_known = true
		threat_position_km = position_km

func react_to_damage(health: float, threshold: float) -> bool:
	if health > 0 and health <= threshold and not withdrawing:
		withdrawing = true
		return true
	return false

func advance(position: Vector2, heading: float, speed: float, delta: float, turn_rate: float, map: RefCounted) -> Dictionary:
	if delta <= 0 or not withdrawing: return {"position": position, "heading": heading, "blocked": false}
	var remaining := delta
	var blocked := false
	# Fixed small steps keep collision checks and finite turns safe under x10/large ticks.
	while remaining > 0.000001:
		var step := minf(remaining, 1.0)
		remaining -= step
		var away := position - threat_position_km if threat_known else Vector2(sin(deg_to_rad(heading)), -cos(deg_to_rad(heading)))
		var desired := wrapf(rad_to_deg(atan2(away.x, -away.y)), 0, 360) if away.length_squared() > 0.000001 else heading
		var difference := wrapf(desired - heading, -180, 180)
		var candidate_heading := wrapf(heading + clampf(difference, -turn_rate * step, turn_rate * step), 0, 360)
		var direction := Vector2(sin(deg_to_rad(candidate_heading)), -cos(deg_to_rad(candidate_heading)))
		var destination := position + direction * speed * 1.852 / 3600.0 * step
		if map.can_navigate_segment(position, destination):
			heading = candidate_heading
			position = destination
			blocked = false
		else:
			# Hold position while turning along the coast; never teleport through land.
			heading = wrapf(heading + turn_rate * step, 0, 360)
			blocked = true
	return {"position": position, "heading": heading, "blocked": blocked}
