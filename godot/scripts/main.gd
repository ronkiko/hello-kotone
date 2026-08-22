extends Node2D

const VIEWPORT_SIZE := Vector2(482, 270)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color("111720"))
	draw_rect(Rect2(12, 14, 458, 226), Color("465161"))
	draw_rect(Rect2(12, 48, 458, 140), Color("abb1b9"))
	draw_rect(Rect2(12, 188, 458, 47), Color("a87869"))
	draw_rect(Rect2(12, 240, 458, 30), Color("121822"))
	draw_line(Vector2(12, 188), Vector2(470, 188), Color("55505a"), 2.0)
	draw_line(Vector2(12, 240), Vector2(470, 240), Color("303641"), 5.0)
