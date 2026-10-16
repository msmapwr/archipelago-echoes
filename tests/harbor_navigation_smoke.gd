extends SceneTree

const Navigation = preload("res://scripts/world/harbor_navigation.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var harbor = Navigation.new()
	_check(Navigation.WATER_BOUNDS.size == Vector2(2, 1.76) and Navigation.OBSTACLES[0].size == Vector2(0.68, 0.8), "expanded harbor includes 680 m quay and 640 m departure channel")
	_check(not harbor.set_command(0, 10), "mooring rejects propulsion")
	harbor.advance(100)
	_check(harbor.position_km == Vector2.ZERO, "moored hull stays docked")
	_check(harbor.cast_off() and not harbor.cast_off(), "cast off occurs once")
	_check(not harbor.set_command(0, 11) and harbor.speed_knots == 0, "port speed limit rejects overspeed")
	_check(not harbor.set_command(NAN, 5) and not harbor.set_command(0, INF), "nonfinite commands cannot corrupt position")
	harbor.set_command(270, 10)
	harbor.advance(160)
	_check(harbor.position_km.x > -0.32 and harbor.speed_knots == 0 and harbor.grounded and harbor.hull < 100 and not harbor.departed, "swept collision stops before quay and damages hull")
	_check(not harbor.set_command(90, 10) and harbor.set_command(90, 4), "grounded ship must use low speed")
	harbor.advance(120)
	_check(not harbor.grounded, "low speed deeper-water retreat refloats ship")
	var breakwater = Navigation.new()
	breakwater.cast_off()
	breakwater.set_command(0, 10)
	breakwater.advance(120)
	breakwater.set_command(90, 10)
	breakwater.advance(140)
	_check(breakwater.position_km.x < 0.32 and breakwater.speed_knots == 0 and breakwater.hull < 100, "breakwater blocks lateral passage with damage")
	var departing = Navigation.new()
	departing.cast_off()
	departing.set_command(0, 10)
	departing.advance(10000)
	_check(departing.departed and departing.position_km.is_equal_approx(Vector2(0, -1.28)), "large step clamps movement to departure gate")
	var exit_position: Vector2 = departing.position_km
	_check(not departing.advance(100) and departing.position_km == exit_position and not departing.set_command(180, 10), "departure is terminal and cannot trigger twice")
	var off_route = Navigation.new()
	off_route.cast_off()
	off_route.set_command(180, 10)
	off_route.advance(400)
	_check(Navigation.WATER_BOUNDS.has_point(off_route.position_km) and not off_route.departed and off_route.speed_knots == 0, "leaving harbor bounds cannot bypass departure gate")
	if failures.is_empty():
		print("Harbor navigation smoke test passed")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
