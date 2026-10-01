extends RefCounted
## Untrusted local files become usable only after wire-schema/hash/ref validation.
const Protocol = preload("res://scripts/mmo/protocol_v4.gd")
var directory := "user://mmo/maps-v1"

func path_for(reference: Dictionary) -> String:
	if not Protocol.map_reference(reference):
		return ""
	# IDs are never interpreted as paths. Immutable references have separate keys.
	return directory.path_join(JSON.stringify(reference, "", true).sha256_text() + ".json")

func load_verified(reference: Dictionary) -> Dictionary:
	var path := path_for(reference)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Protocol.MAX_FRAME_BYTES:
		return {}
	# Reuse strict duplicate-key/number/UTF-8 parsing, without relaxing framing.
	var value: Dictionary = Protocol.decode(file.get_buffer(file.get_length()))
	if not matches(value, reference):
		return {}
	return value

func store_verified(value: Dictionary, reference: Dictionary) -> bool:
	if not matches(value, reference):
		return false
	var path := path_for(reference)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "", true))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

static func matches(value: Dictionary, reference: Dictionary) -> bool:
	if not Protocol.map_reference(reference) or not Protocol.map_definition(value):
		return false
	for key in ["map_id", "content_version", "content_hash"]:
		if value[key] != reference[key]:
			return false
	return true
