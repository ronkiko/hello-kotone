extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_neutral_rig.tscn"
const OUTPUT_DIR := "res://assets/rc3/mannequin/preview/"
const WIDTH := 2000
const HEIGHT := 900
const PANEL_WIDTH := 500
const DISPLAY_SCALE := 0.52
const LABELS := ["NEUTRAL", "SHOULDERS DOWN 12°", "ELBOWS DOWN 18°", "HIPS ABDUCT 4°"]

const THEMES := [
	{"name": "task4g_front_articulation.png", "background": Color("#eeeae5"), "panel": Color("#faf8f5"), "ink": Color("#27232b")},
	{"name": "task4g_front_articulation_dark.png", "background": Color("#11141a"), "panel": Color("#1d222b"), "ink": Color("#f4f0eb")},
	{"name": "task4g_front_articulation_magenta.png", "background": Color("#4a0c37"), "panel": Color("#68134d"), "ink": Color("#fff4fb")},
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

	for index in 4:
		var panel := ColorRect.new()
		panel.color = theme["panel"]
		panel.position = Vector2(index * PANEL_WIDTH + 24, 94)
		panel.size = Vector2(PANEL_WIDTH - 48, 766)
		canvas.add_child(panel)

		var rig := packed.instantiate() as Node2D
		rig.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
		rig.position = Vector2(
			index * PANEL_WIDTH + PANEL_WIDTH * 0.5 - 627.0 * DISPLAY_SCALE,
			105
		)
		canvas.add_child(rig)
		_apply_pose(rig, index)
		_add_label(canvas, LABELS[index], index, theme["ink"])

	var title := Label.new()
	title.text = "KOTONE / FRONT MANNEQUIN / CONTROLLED IN-PLANE ARTICULATION"
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

func _apply_pose(rig: Node2D, index: int) -> void:
	if index == 1:
		(rig.get_node("Skeleton2D/pelvis/torso/upper_arm_right") as Bone2D).rotation = deg_to_rad(-12.0)
		(rig.get_node("Skeleton2D/pelvis/torso/upper_arm_left") as Bone2D).rotation = deg_to_rad(12.0)
	elif index == 2:
		(rig.get_node("Skeleton2D/pelvis/torso/upper_arm_right/forearm_right") as Bone2D).rotation = deg_to_rad(-18.0)
		(rig.get_node("Skeleton2D/pelvis/torso/upper_arm_left/forearm_left") as Bone2D).rotation = deg_to_rad(18.0)
	elif index == 3:
		(rig.get_node("Skeleton2D/pelvis/hip_right") as Bone2D).rotation = deg_to_rad(4.0)
		(rig.get_node("Skeleton2D/pelvis/hip_left") as Bone2D).rotation = deg_to_rad(-4.0)

func _add_label(canvas: Node2D, text: String, index: int, ink: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(index * PANEL_WIDTH + 24, 52)
	label.size = Vector2(PANEL_WIDTH - 48, 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", ink)
	label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(label)
