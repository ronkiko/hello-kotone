extends Control
var bars: Array[ColorRect] = []
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-34, 8)
	for index in range(4):
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(index * 6, 12 - index * 3)
		bar.size = Vector2(4, 4 + index * 3)
		add_child(bar)
		bars.append(bar)
	MmoClient.frame_health_changed.connect(update_signal)
	update_signal(MmoClient.frame_health.bars)
func update_signal(count: int) -> void:
	var colors := [Color.DIM_GRAY, Color.RED, Color.ORANGE, Color.YELLOW_GREEN, Color.LIME_GREEN]
	for index in range(bars.size()):
		bars[index].color = colors[count] if index < count else Color(0.22, 0.25, 0.28)
