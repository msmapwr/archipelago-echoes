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
	_check(harbor.position_km == Vector2.ZERO and harbor.speed_knots == 0 and not harbor.departed, "segment collision prevents tunneling through dock")
	harbor.set_command(0, 10)
	harbor.advance(120)
	var safe_position: Vector2 = harbor.position_km
	harbor.set_command(90, 10)
	harbor.advance(140)
	_check(harbor.position_km == safe_position and harbor.speed_knots == 0, "breakwater blocks lateral passage")
	harbor.set_command(0, 10)
	harbor.advance(10000)
	_check(harbor.departed and harbor.position_km.is_equal_approx(Vector2(0, -1.28)), "large step clamps movement to departure gate")
	var exit_position: Vector2 = harbor.position_km
	_check(not harbor.advance(100) and harbor.position_km == exit_position and not harbor.set_command(180, 10), "departure is terminal and cannot trigger twice")
	var off_route = Navigation.new()
	off_route.cast_off()
	off_route.set_command(180, 10)
	off_route.advance(400)
	_check(off_route.position_km == Vector2.ZERO and not off_route.departed and off_route.speed_knots == 0, "leaving harbor bounds cannot bypass departure gate")
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
