extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_right_leg_cutout_spike.tscn"
const OUTPUT_DIR := "res://assets/rc3/mannequin/preview/"
const WIDTH := 1500
const HEIGHT := 900
const PANEL_WIDTH := 500
const DISPLAY_SCALE := 0.95
const HIP_ANGLES := [-4.0, 0.0, 4.0]
const LABELS := ["4° ABDUCTION", "NEUTRAL", "4° ADDUCTION"]

const THEMES := [
	{"name": "task4e_front_right_leg_cutout.png", "background": Color("#eeeae5"), "panel": Color("#faf8f5"), "ink": Color("#27232b")},
	{"name": "task4e_front_right_leg_cutout_dark.png", "background": Color("#11141a"), "panel": Color("#1d222b"), "ink": Color("#f4f0eb")},
	{"name": "task4e_front_right_leg_cutout_magenta.png", "background": Color("#4a0c37"), "panel": Color("#68134d"), "ink": Color("#fff4fb")},
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("Could not load ", SCENE_PATH)
		quit(1)
		return
	var rendered_count := 0
	for theme in THEMES:
		if await _render_theme(packed, theme):
			rendered_count += 1
	if rendered_count != THEMES.size():
		printerr("RENDER FAILED: wrote %d of %d previews" % [rendered_count, THEMES.size()])
		quit(1)
		return
	print("RENDER COMPLETE: %d previews" % rendered_count)
	quit(0)

func _render_theme(packed: PackedScene, theme: Dictionary) -> bool:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(WIDTH, HEIGHT)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var canvas := Node2D.new()
	viewport.add_child(canvas)

	var background := ColorRect.new()
	background.color = theme["background"]
	background.size = Vector2(WIDTH, HEIGHT)
	canvas.add_child(background)

	for index in HIP_ANGLES.size():
		var panel := ColorRect.new()
		panel.color = theme["panel"]
		panel.position = Vector2(index * PANEL_WIDTH + 24, 94)
		panel.size = Vector2(PANEL_WIDTH - 48, 766)
		canvas.add_child(panel)

		var instance := packed.instantiate() as Node2D
		instance.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
		# Center the approved right-leg crop (x 430..780) in each panel.
		instance.position = Vector2(
			index * PANEL_WIDTH + PANEL_WIDTH * 0.5 - 605.0 * DISPLAY_SCALE,
			95.0 - 390.0 * DISPLAY_SCALE
		)
		canvas.add_child(instance)
		var hip := instance.get_node("Skeleton2D/pelvis/hip_right") as Bone2D
		hip.rotation = deg_to_rad(HIP_ANGLES[index])

		var label := Label.new()
		label.text = LABELS[index]
		label.position = Vector2(index * PANEL_WIDTH + 24, 50)
		label.size = Vector2(PANEL_WIDTH - 48, 38)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", theme["ink"])
		label.add_theme_font_size_override("font_size", 28)
		canvas.add_child(label)

	var title := Label.new()
	title.text = "KOTONE / FRONT ANATOMICAL RIGHT LEG (VIEWER-LEFT) / CUTOUT HIP RANGE SPIKE"
	title.position = Vector2(24, 12)
	title.size = Vector2(WIDTH - 48, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", theme["ink"])
	title.add_theme_font_size_override("font_size", 20)
	canvas.add_child(title)

	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("No rendered image: headless dummy renderer cannot rasterize; use a GL-compatible display backend")
		viewport.queue_free()
		return false
	var image := viewport.get_texture().get_image()
	if image == null:
		printerr("No rendered image returned by viewport")
		viewport.queue_free()
		return false
	var output_path: String = OUTPUT_DIR + str(theme["name"])
	var error := image.save_png(output_path)
	if error != OK:
		printerr("Could not write ", output_path, ": ", error)
	else:
		print("WROTE: ", output_path, " ", image.get_width(), "x", image.get_height())
	viewport.queue_free()
	return error == OK
