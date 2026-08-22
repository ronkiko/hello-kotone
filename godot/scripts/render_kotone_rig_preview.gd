extends SceneTree

const RIG_SCENE := "res://scenes/kotone_rig.tscn"
const OUTPUT := "res://assets/rc3/rig/preview/task4_rig_assembled.png"

func _init() -> void:
	call_deferred("_render")

func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)

	var packed := load(RIG_SCENE) as PackedScene
	if packed == null:
		push_error("Unable to load kotone_rig.tscn for preview")
		quit(1)
		return
	viewport.add_child(packed.instantiate())
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image.save_png(OUTPUT) != OK:
		push_error("Unable to save rig preview")
		quit(1)
		return
	print("Saved neutral rig preview to " + OUTPUT)
	quit(0)
