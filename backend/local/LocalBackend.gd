## LocalBackend — file-system persistence using user://chunks/.
## Phase 1 backend. Swap to FreenetBackend in Phase 6.
class_name LocalBackend
extends IBackend

var _chunk_dir: String = "user://chunks/"

func initialize(chunk_dir: String = "user://chunks/") -> void:
	_chunk_dir = chunk_dir
	DirAccess.make_dir_recursive_absolute(_chunk_dir)

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

func _path(coords: Vector2i) -> String:
	return _chunk_dir + "%d_%d.json" % [coords.x, coords.y]
