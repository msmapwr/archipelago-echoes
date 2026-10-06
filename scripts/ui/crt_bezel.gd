extends Control

const FRAME_DARK := Color("#111a1b")
const FRAME_STEEL := Color("#3b4743")
const FRAME_FACE := Color("#202c28")
const FRAME_EDGE := Color("#8a9888")
const SCREEN_RECESS := Color("#020807")
const LED := Color("#7cff9b")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var width := size.x
	var height := size.y
	draw_rect(Rect2(Vector2.ZERO, size), FRAME_DARK)
	draw_rect(Rect2(8, 7, width - 16, height - 14), FRAME_STEEL)
	draw_rect(Rect2(14, 13, width - 28, height - 26), FRAME_FACE)
	draw_line(Vector2(14, 13), Vector2(width - 14, 13), FRAME_EDGE, 2.0)
	draw_line(Vector2(14, 13), Vector2(14, height - 13), Color("#63766b"), 2.0)
	draw_line(Vector2(width - 14, 14), Vector2(width - 14, height - 13), Color("#0b1110"), 3.0)
	draw_line(Vector2(15, height - 13), Vector2(width - 15, height - 13), Color("#0a100e"), 3.0)
	draw_rect(Rect2(31, 32, width - 62, height - 64), SCREEN_RECESS)
	draw_rect(Rect2(35, 36, width - 70, height - 72), Color("#557361"), false, 1.0)
	draw_line(Vector2(35, 36), Vector2(width - 35, 36), Color("#172a1e"), 2.0)
	draw_line(Vector2(36, height - 36), Vector2(width - 36, height - 36), Color("#617d67"), 1.0)
	for screw in [Vector2(23, 22), Vector2(width - 23, 22), Vector2(23, height - 22), Vector2(width - 23, height - 22)]:
		draw_circle(screw, 6.0, Color("#080f0e"))
		draw_arc(screw, 5.0, 0.0, TAU, 24, Color("#a3ad9b"), 1.0)
		draw_line(screw + Vector2(-3, 2), screw + Vector2(3, -2), Color("#758376"), 1.2, true)
	draw_circle(Vector2(width - 69, height - 21), 5.0, LED)
	draw_circle(Vector2(width - 69, height - 21), 10.0, Color(0.49, 1.0, 0.61, 0.09))
	draw_line(Vector2(63, height - 23), Vector2(185, height - 23), Color("#7d8e7a"), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(195, height - 18), "CIC 07 / CRT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9da996"))
