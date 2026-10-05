extends SceneTree
## Build a native SpriteFrames resource from canonical per-frame PNG folders.
##
## Invoked by character_assets.py. This script deliberately uses Godot itself to
## write .tres instead of duplicating Godot resource serialization in Python.

const PACKAGE_ROOT := "res://assets/characters"
const RESOURCE_NAME := "sprite_frames.tres"
const FRAME_PATTERN := "^\\d{3}\\.png$"

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	printerr("FAIL " + message)
	quit(1)

func _parse_bool(value: String) -> Variant:
	if value == "true":
		return true
	if value == "false":
		return false
	return null

func _parse_animation(spec: String) -> Dictionary:
	var equals := spec.find("=")
	if equals <= 0:
		return {}
	var name := spec.substr(0, equals)
	var rest := spec.substr(equals + 1)
	var colon := rest.rfind(":")
	if colon <= 0:
		return {}
	var fps_text := rest.substr(0, colon)
	var loop_text := rest.substr(colon + 1)
	if not fps_text.is_valid_float():
		return {}
	var fps := fps_text.to_float()
	var loop: Variant = _parse_bool(loop_text)
	if fps <= 0.0 or loop == null:
		return {}
	var regex := RegEx.new()
	if regex.compile("^[a-z0-9][a-z0-9_-]{0,63}$") != OK or regex.search(name) == null:
		return {}
	return {"name": name, "fps": fps, "loop": loop}

func _frame_files(directory: String) -> PackedStringArray:
	var files := DirAccess.get_files_at(directory)
	files.sort()
	var result := PackedStringArray()
	var regex := RegEx.new()
	if regex.compile(FRAME_PATTERN) != OK:
		return result
	var expected := 0
	for file in files:
		if not file.ends_with(".png"):
			continue
		if regex.search(file) == null:
			return PackedStringArray()
		var index := file.get_basename().to_int()
		if index != expected:
			return PackedStringArray()
		result.append(file)
		expected += 1
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var model_id := ""
	var animation_specs := PackedStringArray()
	var index := 0
	while index < args.size():
		match args[index]:
			"--model":
				if index + 1 >= args.size():
					_fail("--model requires a value")
					return
				model_id = args[index + 1]
				index += 2
			"--animation":
				if index + 1 >= args.size():
					_fail("--animation requires name=fps:loop")
					return
				animation_specs.append(args[index + 1])
				index += 2
			_:
				_fail("unknown argument: " + args[index])
				return

	if model_id.is_empty() or animation_specs.is_empty():
		_fail("usage: --model ID --animation name=fps:loop [...]")
		return

	var package_root := "%s/%s" % [PACKAGE_ROOT, model_id]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(package_root)):
		_fail("package directory missing: " + package_root)
		return

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	var report := {}
	for spec in animation_specs:
		var parsed := _parse_animation(spec)
		if parsed.is_empty():
			_fail("invalid animation spec: " + spec)
			return
		var name: String = parsed.name
		var animation := StringName(name)
		if frames.has_animation(animation):
			_fail("duplicate animation: " + name)
			return
		var directory := "%s/%s" % [package_root, name]
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
			_fail("animation directory missing: " + directory)
			return
		var files := _frame_files(directory)
		if files.is_empty():
			_fail("animation has no contiguous NNN.png frames: " + directory)
			return
		frames.add_animation(animation)
		frames.set_animation_speed(animation, float(parsed.fps))
		frames.set_animation_loop_mode(
			animation,
			SpriteFrames.LOOP_LINEAR if bool(parsed.loop) else SpriteFrames.LOOP_NONE,
		)
		for file in files:
			var path := "%s/%s" % [directory, file]
			var texture := load(path) as Texture2D
			if texture == null:
				_fail("failed to load texture: " + path)
				return
			frames.add_frame(animation, texture, 1.0)
		report[name] = {
			"frames": files.size(),
			"fps": parsed.fps,
			"loop": parsed.loop,
		}

	var output := "%s/%s" % [package_root, RESOURCE_NAME]
	var error := ResourceSaver.save(frames, output)
	if error != OK:
		_fail("ResourceSaver.save failed (%d): %s" % [error, output])
		return

	print(JSON.stringify({
		"result": "PASS",
		"model": model_id,
		"resource": output,
		"animations": report,
	}))
	quit(0)
