## LocalBackend — file-system persistence using user://chunks/.
## Phase 1 backend. Swap to FreenetBackend in Phase 6.
class_name LocalBackend
extends IBackend

var _chunk_dir: String = "user://chunks/"
## Path for the reputation JSON file. Exposed so tests can inspect or pre-write it.
var reputation_path: String = "user://reputation.json"

func initialize(chunk_dir: String = "user://chunks/") -> void:
	_chunk_dir = chunk_dir
	DirAccess.make_dir_recursive_absolute(_chunk_dir)
	# Derive reputation path alongside the chunk dir's parent
	reputation_path = _chunk_dir.get_base_dir().path_join("reputation.json")

func store_chunk(chunk_coords: Vector2i, crdt_data: PackedByteArray) -> void:
	var file := FileAccess.open(_path(chunk_coords), FileAccess.WRITE)
	if file:
		file.store_buffer(crdt_data)
		file.close()
	else:
		push_error("LocalBackend: write failed for %s: %d" % [_path(chunk_coords), FileAccess.get_open_error()])

func retrieve_chunk(chunk_coords: Vector2i) -> PackedByteArray:
	if not FileAccess.file_exists(_path(chunk_coords)):
		return PackedByteArray()
	var file := FileAccess.open(_path(chunk_coords), FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var data := file.get_buffer(file.get_length())
	file.close()
	return data

func delete_chunk(chunk_coords: Vector2i) -> void:
	if FileAccess.file_exists(_path(chunk_coords)):
		DirAccess.remove_absolute(_path(chunk_coords))

func save_reputation(data: Dictionary) -> void:
	var file := FileAccess.open(reputation_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
	else:
		push_error("LocalBackend: could not write reputation file: %s" % reputation_path)

func load_reputation() -> Dictionary:
	if not FileAccess.file_exists(reputation_path):
		return {}
	var file := FileAccess.open(reputation_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return {}
	return result as Dictionary

func save_equipment(data: Dictionary) -> void:
	var path: String = _chunk_dir.get_base_dir().path_join("equipment.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
	else:
		push_error("LocalBackend: could not write equipment file: %s" % path)

func load_equipment() -> Dictionary:
	var path: String = _chunk_dir.get_base_dir().path_join("equipment.json")
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return {}
	return result as Dictionary

func _path(coords: Vector2i) -> String:
	return _chunk_dir + "%d_%d.json" % [coords.x, coords.y]
