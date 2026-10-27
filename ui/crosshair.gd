extends Control
# Small dot in the center of the screen.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, 3.5, Color(0.0, 0.0, 0.0, 0.7))
	draw_circle(c, 2.0, Color(1.0, 1.0, 1.0, 0.95))
