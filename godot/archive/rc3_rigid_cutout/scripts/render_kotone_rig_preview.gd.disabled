extends SceneTree

const RIG_SCENE := "res://scenes/kotone_rig.tscn"
const OUTPUT := "res://assets/rc3/rig/preview/task4_rig_assembled.png"
const MASTER := "res://assets/rc3/rig/master/kotone_side_right_master.png"
const COMPARISON := "res://assets/rc3/rig/preview/task4_master_comparison.png"
const CANVAS_SIZE := Vector2i(1024, 1024)
const BACKGROUND := Color(0.18, 0.2, 0.23, 1)

func _init() -> void:
	call_deferred("_render")

func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = CANVAS_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)

	var packed := load(RIG_SCENE) as PackedScene
	if packed == null:
		push_error("Unable to load kotone_rig.tscn for preview")
		quit(1)
		return
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.position = Vector2.ZERO
	background.size = Vector2(CANVAS_SIZE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -100
	viewport.add_child(background)
	var rig := packed.instantiate()
	viewport.add_child(rig)
	await process_frame
	await process_frame
	var image: Image = null
	if DisplayServer.get_name() != "headless" and viewport.get_texture() != null:
		image = viewport.get_texture().get_image()
	if image == null:
		image = _compose_static_rig(rig)
	if image.save_png(OUTPUT) != OK:
		push_error("Unable to save rig preview")
		quit(1)
		return
	var master_texture := load(MASTER) as Texture2D
	if master_texture == null:
		push_error("Unable to load master for comparison")
		quit(1)
		return
	var comparison := Image.create(CANVAS_SIZE.x * 2, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	comparison.fill(BACKGROUND)
	var master_image := master_texture.get_image()
	comparison.blend_rect(master_image, Rect2i(Vector2i.ZERO, master_image.get_size()), Vector2i.ZERO)
	comparison.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(CANVAS_SIZE.x, 0))
	if comparison.save_png(COMPARISON) != OK:
		push_error("Unable to save master comparison")
		quit(1)
		return
	print("Saved neutral rig preview to " + OUTPUT)
	print("Saved master comparison to " + COMPARISON)
	quit(0)

func _compose_static_rig(rig: Node) -> Image:
	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(BACKGROUND)
	var sprites: Array[Sprite2D] = []
	_collect_sprites(rig, sprites)
	sprites.sort_custom(func(a: Sprite2D, b: Sprite2D) -> bool:
		return a.z_index < b.z_index
	)
	for sprite in sprites:
		if not sprite.visible or sprite.texture == null:
			continue
		var source := sprite.texture.get_image()
		if sprite.flip_h:
			source.flip_x()
		var destination := Vector2i(round(sprite.global_position.x - source.get_width() * 0.5), round(sprite.global_position.y - source.get_height() * 0.5))
		canvas.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), destination)
	return canvas

func _collect_sprites(node: Node, result: Array[Sprite2D]) -> void:
	if node is Sprite2D:
		result.append(node)
	for child in node.get_children():
		_collect_sprites(child, result)
