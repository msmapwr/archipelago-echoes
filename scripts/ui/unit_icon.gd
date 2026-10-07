extends Control

const Glyph = preload("res://scripts/data/unit_glyph.gd")
var family := "ship.carrier"
var size_class := "medium"
var variant := 1
var detailed := true
var tint := Color("#a0edb5")
var heading := 0.0
var show_heading := false
var pixels := 180.0
var fit_to_bounds := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _draw() -> void:
	var extent := minf(pixels, minf(size.x, size.y) - 8) if fit_to_bounds else pixels
	Glyph.draw(self, size * 0.5, extent, family, tint, size_class, variant, detailed)
	if show_heading:
		var direction := Vector2.UP.rotated(deg_to_rad(heading))
		var tip := size * 0.5 + direction * pixels * 0.56
		draw_line(tip - direction * 12, tip, tint, 2)
		draw_line(tip, tip - direction.rotated(0.6) * 7, tint, 2)
		draw_line(tip, tip - direction.rotated(-0.6) * 7, tint, 2)
