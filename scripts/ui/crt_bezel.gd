extends Control

const OUTER := Color("111a17")
const STEEL := Color("27332d")
const EDGE := Color("4b5a4d")
const RECESS := Color("030806")
const LED := Color("8be6a3")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, OUTER)
	draw_rect(Rect2(Vector2(13, 12), size - Vector2(26, 24)), STEEL)
	draw_rect(Rect2(Vector2(22, 20), size - Vector2(44, 40)), EDGE, false, 2.0)
	draw_rect(Rect2(Vector2(39, 39), size - Vector2(78, 78)), RECESS)
	for screw in [Vector2(28, 28), Vector2(size.x - 28, 28), Vector2(28, size.y - 28), Vector2(size.x - 28, size.y - 28)]:
		draw_circle(screw, 6.0, Color("0b100d"))
		draw_line(screw + Vector2(-3, 2), screw + Vector2(3, -2), EDGE, 1.5, true)
	draw_circle(Vector2(size.x - 66, size.y - 28), 4.0, LED)
	draw_line(Vector2(66, size.y - 29), Vector2(226, size.y - 29), Color("6d7867"), 2.0)
