extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_right_arm_anatomical_mesh_spike.tscn"
const OUTPUT_DIR := "res://assets/rc3/mannequin/preview/"
const WIDTH := 2000
const HEIGHT := 820
const PANEL_WIDTH := 500
const RIG_SCALE := 1.16
const POSE_ANGLES := [0.0, -30.0, -60.0, -90.0]

const THEMES := [
	{"name": "task4i_front_right_elbow_anatomical.png", "background": Color("#eeeae5"), "panel": Color("#faf8f5"), "ink": Color("#27232b"), "rule": Color("#c6beb5")},
	{"name": "task4i_front_right_elbow_anatomical_dark.png", "background": Color("#11141a"), "panel": Color("#1d222b"), "ink": Color("#f4f0eb"), "rule": Color("#46505d")},
	{"name": "task4i_front_right_elbow_anatomical_magenta.png", "background": Color("#4a0c37"), "panel": Color("#68134d"), "ink": Color("#fff4fb"), "rule": Color("#d66aae")}
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
	print("RENDER COMPLETE: %d Task 4I previews" % rendered_count)
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
	for panel_index in POSE_ANGLES.size():
		_add_panel(canvas, panel_index, theme)
		var rig := packed.instantiate() as Node2D
		rig.scale = Vector2(RIG_SCALE, RIG_SCALE)
		rig.position = Vector2(panel_index * PANEL_WIDTH + PANEL_WIDTH * 0.5 - 414.0 * RIG_SCALE, 140.0 - 245.0 * RIG_SCALE)
		canvas.add_child(rig)
		var elbow := rig.get_node("BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right") as Bone2D
		elbow.rotation = deg_to_rad(POSE_ANGLES[panel_index])
		_add_label(canvas, panel_index, "%d° ELBOW" % int(absf(POSE_ANGLES[panel_index])), theme)
	var title := Label.new()
	title.text = "TASK 4I / ANATOMICAL-RIGHT ELBOW / JOINT-LOCAL TOPOLOGY"
	title.position = Vector2(30, 12)
	title.size = Vector2(WIDTH - 60, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", theme["ink"])
	title.add_theme_font_size_override("font_size", 18)
	canvas.add_child(title)
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("No rendered image: headless dummy renderer cannot rasterize; use GL/Xvfb")
		viewport.queue_free()
		return false
	var image := viewport.get_texture().get_image()
	if image == null:
		printerr("No rendered image returned by viewport")
		viewport.queue_free()
		return false
	var output_path: String = OUTPUT_DIR + str(theme["name"])
	var error := image.save_png(output_path)
	if error == OK:
		print("WROTE: ", output_path, " ", image.get_width(), "x", image.get_height())
	else:
		printerr("Could not write ", output_path, ": ", error)
	viewport.queue_free()
	return error == OK

func _add_panel(canvas: Node2D, panel_index: int, theme: Dictionary) -> void:
	var panel := ColorRect.new()
	panel.color = theme["panel"]
	panel.position = Vector2(panel_index * PANEL_WIDTH + 20, 90)
	panel.size = Vector2(PANEL_WIDTH - 40, HEIGHT - 120)
	canvas.add_child(panel)
	var rule := ColorRect.new()
	rule.color = theme["rule"]
	rule.position = Vector2(panel_index * PANEL_WIDTH + 20, 90)
	rule.size = Vector2(PANEL_WIDTH - 40, 1)
	canvas.add_child(rule)

func _add_label(canvas: Node2D, panel_index: int, label_text: String, theme: Dictionary) -> void:
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(panel_index * PANEL_WIDTH + 20, 50)
	label.size = Vector2(PANEL_WIDTH - 40, 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", theme["ink"])
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
