extends SceneTree
## Native current-consumer visual evidence; universal raster tools remain independent.
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var output := ""
var sprites := []
func _initialize() -> void:
	run.call_deferred()
func label(text: String, position: Vector2, size: int = 14) -> void:
	var node := Label.new()
	node.text = text
	node.position = position
	node.add_theme_font_size_override("font_size", size)
	root.add_child(node)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		printerr("usage: Godot desktop --script res://tools/render_character_review.gd -- OUTPUT")
		quit(1)
		return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(640,300)
	root.content_scale_size = Vector2i(640,300)
	var background := ColorRect.new()
	background.color = Color("293745")
	background.size = Vector2(640,300)
	root.add_child(background)
	var floor := ColorRect.new()
	floor.color = Color("94b4bf")
	floor.position = Vector2(0,236)
	floor.size = Vector2(640,1)
	root.add_child(floor)
	label("7.11 · canonical 1 px/cm · fixed ground root", Vector2(14,8), 16)
	for model in ["kotone", "yuna"]:
		var anchor := Node2D.new()
		anchor.position = Vector2(210 if model == "kotone" else 430,236)
		root.add_child(anchor)
		var sprite := AnimatedSprite2D.new()
		anchor.add_child(sprite)
		var payload := {"character_model_id":model,"body_variant_id":"standard","face_style_id":"soft","hair_style_id":"short" if model == "kotone" else "bob","hair_color_id":"chestnut" if model == "kotone" else "rose"}
		if not Appearance.install(sprite,payload):
			printerr("missing content: ",model)
			quit(1)
			return
		sprites.append(sprite)
		label(model.capitalize() + " · " + str(Appearance.Library.FrameContract.physical_height_cm(model)) + " cm", Vector2(anchor.position.x-66,258))
	await process_frame
	var step := 0
	for state in ["idle","walk_left","idle","walk_right","idle"]:
		for index in range(8):
			for sprite in sprites:
				var count: int = sprite.sprite_frames.get_frame_count(state)
				Appearance.pose(sprite,state != "idle",-1 if state == "walk_left" else 1,int(float(index)/8 * count))
			await process_frame
			await RenderingServer.frame_post_draw
			var result := root.get_texture().get_image().save_png(output.path_join("%03d.png" % step))
			if result != OK:
				quit(1)
				return
			step += 1
	print(JSON.stringify({"result":"PASS","frames":step,"output":output}))
	quit(0)
