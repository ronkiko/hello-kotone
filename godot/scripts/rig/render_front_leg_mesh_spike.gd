extends SceneTree

const SCENE_PATH := "res://scenes/rig/kotone_front_leg_mesh_spike.tscn"
const OUTPUT_DIR := "res://assets/rc3/rig/preview/"
const WIDTH := 1440
const HEIGHT := 760
const PANEL_WIDTH := 480
const SCALE := 0.9
const POSES := [0.0, 20.0, 45.0]

const THEMES := [
	{"name": "task4b_leg_mesh_spike.png", "background": Color("#eeeae5"), "panel": Color("#faf8f5"), "ink": Color("#27232b"), "rule": Color("#c6beb5")},
	{"name": "task4b_leg_mesh_spike_dark.png", "background": Color("#11141a"), "panel": Color("#1d222b"), "ink": Color("#f4f0eb"), "rule": Color("#46505d")},
	{"name": "task4b_leg_mesh_spike_magenta.png", "background": Color("#4a0c37"), "panel": Color("#68134d"), "ink": Color("#fff4fb"), "rule": Color("#d66aae")}
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("Could not load ", SCENE_PATH)
		quit(1)
		return
	for theme in THEMES:
		await _render_theme(packed, theme)
	print("RENDER COMPLETE: %d previews" % THEMES.size())
	quit(0)

func _render_theme(packed: PackedScene, theme: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(WIDTH, HEIGHT)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var canvas := Node2D.new()
	viewport.add_child(canvas)
	var background := ColorRect.new()
	background.color = theme["background"]
	background.position = Vector2.ZERO
	background.size = Vector2(WIDTH, HEIGHT)
	canvas.add_child(background)
	for index in 3:
		var panel := ColorRect.new()
		panel.color = theme["panel"]
		panel.position = Vector2(index * PANEL_WIDTH + 24, 94)
		panel.size = Vector2(PANEL_WIDTH - 48, 610)
		canvas.add_child(panel)
		var rule := ColorRect.new()
		rule.color = theme["rule"]
		rule.position = Vector2(index * PANEL_WIDTH + 24, 94)
		rule.size = Vector2(PANEL_WIDTH - 48, 1)
		canvas.add_child(rule)
		var instance := packed.instantiate()
		instance.scale = Vector2(SCALE, SCALE)
		instance.position = Vector2(index * PANEL_WIDTH + PANEL_WIDTH * 0.5 - 555.0 * SCALE, 120.0 - 575.0 * SCALE)
		canvas.add_child(instance)
		var knee := instance.get_node("Skeleton2D/pelvis/hip_right/knee_right") as Bone2D
		knee.rotation = deg_to_rad(POSES[index])
		var label := Label.new()
		label.text = "%d°" % [int(POSES[index])]
		label.position = Vector2(index * PANEL_WIDTH + 24, 42)
		label.size = Vector2(PANEL_WIDTH - 48, 44)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", theme["ink"])
		label.add_theme_font_size_override("font_size", 30)
		canvas.add_child(label)
	var title := Label.new()
	title.text = "KOTONE / FRONT RIGHT LEG / WEIGHTED POLYGON2D"
	title.position = Vector2(24, 12)
	title.size = Vector2(WIDTH - 48, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", theme["ink"])
	title.add_theme_font_size_override("font_size", 16)
	canvas.add_child(title)
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("No rendered image: headless dummy renderer cannot rasterize; use a GL-compatible display backend")
		viewport.queue_free()
		return
	var viewport_texture := viewport.get_texture()
	if viewport_texture == null:
		printerr("No viewport texture: headless dummy renderer cannot rasterize; use a GL-compatible display backend")
		viewport.queue_free()
		return
	var image := viewport_texture.get_image()
	if image == null:
		printerr("No rendered image returned by viewport")
		viewport.queue_free()
		return
	var output_path: String = OUTPUT_DIR + str(theme["name"])
	var error := image.save_png(output_path)
	if error != OK:
		printerr("Could not write ", output_path, ": ", error)
	else:
		print("WROTE: ", output_path, " ", image.get_width(), "x", image.get_height())
	viewport.queue_free()
