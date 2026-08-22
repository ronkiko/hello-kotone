extends SceneTree

const RIGID_SCENE_PATH := "res://scenes/mannequin/kotone_front_neutral_rig.tscn"
const WEIGHTED_SCENE_PATH := "res://scenes/mannequin/kotone_front_right_arm_weighted_mesh_spike.tscn"
const OUTPUT_DIR := "res://assets/rc3/mannequin/preview/"
const WIDTH := 1800
const HEIGHT := 760
const PANEL_WIDTH := 600
const RIG_SCALE := 1.25
const ELBOW_ANGLE := -18.0

const THEMES := [
	{"name": "task4h_front_right_arm_weighted_mesh.png", "background": Color("#eeeae5"), "panel": Color("#faf8f5"), "ink": Color("#27232b"), "rule": Color("#c6beb5")},
	{"name": "task4h_front_right_arm_weighted_mesh_dark.png", "background": Color("#11141a"), "panel": Color("#1d222b"), "ink": Color("#f4f0eb"), "rule": Color("#46505d")},
	{"name": "task4h_front_right_arm_weighted_mesh_magenta.png", "background": Color("#4a0c37"), "panel": Color("#68134d"), "ink": Color("#fff4fb"), "rule": Color("#d66aae")}
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var rigid_packed := load(RIGID_SCENE_PATH) as PackedScene
	var weighted_packed := load(WEIGHTED_SCENE_PATH) as PackedScene
	if rigid_packed == null or weighted_packed == null:
		printerr("Could not load required spike scenes")
		quit(1)
		return
	var rendered_count := 0
	for theme in THEMES:
		if await _render_theme(rigid_packed, weighted_packed, theme):
			rendered_count += 1
	if rendered_count != THEMES.size():
		printerr("RENDER FAILED: wrote %d of %d previews" % [rendered_count, THEMES.size()])
		quit(1)
		return
	print("RENDER COMPLETE: %d Task 4H previews" % rendered_count)
	quit(0)

func _render_theme(rigid_packed: PackedScene, weighted_packed: PackedScene, theme: Dictionary) -> bool:
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
	for panel_index in 3:
		_add_panel(canvas, panel_index, theme)
	var neutral := rigid_packed.instantiate() as Node2D
	_place_rig(neutral, 0)
	canvas.add_child(neutral)
	var rigid_bend := rigid_packed.instantiate() as Node2D
	_place_rig(rigid_bend, 1)
	canvas.add_child(rigid_bend)
	(rigid_bend.get_node("Skeleton2D/pelvis/torso/upper_arm_right/forearm_right") as Bone2D).rotation = deg_to_rad(ELBOW_ANGLE)
	var weighted_bend := weighted_packed.instantiate() as Node2D
	_place_rig(weighted_bend, 2)
	canvas.add_child(weighted_bend)
	(weighted_bend.get_node("BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right") as Bone2D).rotation = deg_to_rad(ELBOW_ANGLE)
	_add_label(canvas, 0, "NEUTRAL REFERENCE", theme)
	_add_label(canvas, 1, "RIGID CUTOUT / 18° / REJECTED", theme)
	_add_label(canvas, 2, "WEIGHTED MESH / 18° / REVIEW", theme)
	var title := Label.new()
	title.text = "TASK 4H / ANATOMICAL-RIGHT ELBOW / RIGID VERSUS WEIGHTED"
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

func _place_rig(rig: Node2D, panel_index: int) -> void:
	rig.scale = Vector2(RIG_SCALE, RIG_SCALE)
	rig.position = Vector2(panel_index * PANEL_WIDTH + PANEL_WIDTH * 0.5 - 414.0 * RIG_SCALE, 130.0 - 245.0 * RIG_SCALE)

func _add_panel(canvas: Node2D, panel_index: int, theme: Dictionary) -> void:
	var panel := ColorRect.new()
	panel.color = theme["panel"]
	panel.position = Vector2(panel_index * PANEL_WIDTH + 24, 88)
	panel.size = Vector2(PANEL_WIDTH - 48, HEIGHT - 118)
	canvas.add_child(panel)
	var rule := ColorRect.new()
	rule.color = theme["rule"]
	rule.position = Vector2(panel_index * PANEL_WIDTH + 24, 88)
	rule.size = Vector2(PANEL_WIDTH - 48, 1)
	canvas.add_child(rule)

func _add_label(canvas: Node2D, panel_index: int, label_text: String, theme: Dictionary) -> void:
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(panel_index * PANEL_WIDTH + 24, 48)
	label.size = Vector2(PANEL_WIDTH - 48, 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", theme["ink"])
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
