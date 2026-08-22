extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_neutral_rig.tscn"
const SOURCE_PATH := "res://assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png"
const OUTPUT_DIR := "res://assets/rc3/mannequin/preview/"
const WIDTH := 1500
const HEIGHT := 900
const PANEL_WIDTH := 750
const DISPLAY_SCALE := 0.58

const THEMES := [
	{"name": "task4f_front_neutral_rig.png", "background": Color("#eeeae5"), "panel": Color("#faf8f5"), "ink": Color("#27232b")},
	{"name": "task4f_front_neutral_rig_dark.png", "background": Color("#11141a"), "panel": Color("#1d222b"), "ink": Color("#f4f0eb")},
	{"name": "task4f_front_neutral_rig_magenta.png", "background": Color("#4a0c37"), "panel": Color("#68134d"), "ink": Color("#fff4fb")},
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	var source_texture := load(SOURCE_PATH) as Texture2D
	if packed == null or source_texture == null:
		printerr("Could not load Task 4F scene or source")
		quit(1)
		return
	var rendered_count := 0
	for theme in THEMES:
		if await _render_theme(packed, source_texture, theme):
			rendered_count += 1
	if rendered_count != THEMES.size():
		printerr("RENDER FAILED: wrote %d of %d previews" % [rendered_count, THEMES.size()])
		quit(1)
		return
	print("RENDER COMPLETE: %d previews" % rendered_count)
	quit(0)

func _render_theme(packed: PackedScene, source_texture: Texture2D, theme: Dictionary) -> bool:
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

	for index in 2:
		var panel := ColorRect.new()
		panel.color = theme["panel"]
		panel.position = Vector2(index * PANEL_WIDTH + 24, 94)
		panel.size = Vector2(PANEL_WIDTH - 48, 766)
		canvas.add_child(panel)

	var source := Sprite2D.new()
	source.texture = source_texture
	source.centered = false
	source.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	source.position = Vector2(PANEL_WIDTH * 0.5 - 627.0 * DISPLAY_SCALE, 105)
	canvas.add_child(source)

	var rig := packed.instantiate() as Node2D
	rig.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	rig.position = Vector2(PANEL_WIDTH + PANEL_WIDTH * 0.5 - 627.0 * DISPLAY_SCALE, 105)
	canvas.add_child(rig)

	_add_label(canvas, "APPROVED SOURCE", 0, theme["ink"])
	_add_label(canvas, "15-PART SKELETON2D", 1, theme["ink"])
	var title := Label.new()
	title.text = "KOTONE / FRONT NEUTRAL MANNEQUIN / SOURCE VS RIG"
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

func _add_label(canvas: Node2D, text: String, index: int, ink: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(index * PANEL_WIDTH + 24, 50)
	label.size = Vector2(PANEL_WIDTH - 48, 38)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", ink)
	label.add_theme_font_size_override("font_size", 28)
	canvas.add_child(label)
