## ChunkManager — manages loading/unloading of chunks around the player.
## Key invariant: 16-bit TileMapLayer coordinate guard stays in _load_chunk forever.
## All tile mutations go through place_tile() / remove_tile() — never set_cell() directly.
class_name ChunkManager
extends Node

const CHUNK_SCENE := preload("res://world/chunk/Chunk.tscn")

var _loaded_chunks: Dictionary = {}  # Vector2i -> ChunkData
var _player_chunk: Vector2i = Vector2i.ZERO

func update_player_position(world_tile_pos: Vector2i) -> void:
	var new_chunk := CoordUtils.world_to_chunk(world_tile_pos)
	if new_chunk == _player_chunk:
		return
	_player_chunk = new_chunk
	_load_chunks_in_radius(new_chunk, Constants.LOAD_RADIUS)
	_unload_chunks_outside_radius(new_chunk, Constants.UNLOAD_RADIUS)

func update_player_last_visited(world_tile_pos: Vector2i) -> void:
	## Phase 1: update last_visited on player-adjacent chunks.
	var now := Time.get_unix_time_from_system()
	var pc := CoordUtils.world_to_chunk(world_tile_pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk := get_chunk(pc + Vector2i(dx, dy))
			if chunk:
				chunk.last_visited = now

func place_tile(world_coords: Vector2i, layer: int, tile_id: int,
                atlas: Vector2i, alt: int, author: String) -> void:
	var cc := CoordUtils.world_to_chunk(world_coords)
	var local := CoordUtils.world_to_local(world_coords)
	var chunk := get_chunk(cc)
	if chunk == null:
		push_warning("place_tile on unloaded chunk %s" % cc)
		return
	chunk.crdt.set_tile(layer, local, tile_id, atlas, alt, author)
	chunk.apply_mutation(layer, local, chunk.crdt.get_tile(layer, local))
	chunk.modification_count += 1

func remove_tile(world_coords: Vector2i, layer: int, author: String) -> void:
	var cc := CoordUtils.world_to_chunk(world_coords)
	var local := CoordUtils.world_to_local(world_coords)
	var chunk := get_chunk(cc)
	if chunk == null:
		return
	chunk.crdt.remove_tile(layer, local, author)
	chunk.apply_mutation(layer, local, {"tile_id": -1})
	chunk.modification_count += 1

func get_chunk(coords: Vector2i) -> ChunkData:
	return _loaded_chunks.get(coords, null)

func get_loaded_chunk_coords() -> Array:
	return _loaded_chunks.keys()

func force_unload_chunk_no_persist(coords: Vector2i) -> void:
	var chunk := _loaded_chunks.get(coords) as ChunkData
	if chunk:
		chunk.queue_free()
	_loaded_chunks.erase(coords)

func _persist_all_loaded_chunks() -> void:
	## Phase 0: no-op (Backend stub does nothing).
	## Phase 1: stores all loaded chunks to disk on quit.
	for coords in _loaded_chunks:
		var chunk := _loaded_chunks[coords] as ChunkData
		Backend.store_chunk(coords, _serialize_chunk(chunk))

func _load_chunks_in_radius(center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coords := center + Vector2i(dx, dy)
			if not _loaded_chunks.has(coords):
				_load_chunk(coords)

func _load_chunk(coords: Vector2i) -> void:
	## 16-bit TileMapLayer coordinate guard — never exceed signed 16-bit range.
	assert(abs(coords.x) <= 2047 and abs(coords.y) <= 2047,
	       "Chunk coords %s would exceed 16-bit TileMapLayer limit" % coords)
	var raw := Backend.retrieve_chunk(coords)
	var entries := _deserialize_entries(raw) if not raw.is_empty() \
	               else ProceduralGenerator.generate_chunk(coords, Constants.WORLD_SEED)
	var chunk := CHUNK_SCENE.instantiate() as ChunkData
	add_child(chunk)
	chunk.initialize(coords, entries)
	chunk.last_visited = Time.get_unix_time_from_system()
	_loaded_chunks[coords] = chunk

func _unload_chunks_outside_radius(center: Vector2i, radius: int) -> void:
	var to_unload: Array[Vector2i] = []
	for coords in _loaded_chunks:
		if abs(coords.x - center.x) > radius or abs(coords.y - center.y) > radius:
			to_unload.append(coords)
	for coords in to_unload:
		_unload_chunk(coords)

func _unload_chunk(coords: Vector2i) -> void:
	var chunk := get_chunk(coords)
	if chunk:
		Backend.store_chunk(coords, _serialize_chunk(chunk))
		chunk.queue_free()
	_loaded_chunks.erase(coords)

func _serialize_chunk(chunk: ChunkData) -> PackedByteArray:
	var list := []
	for key in chunk.crdt.get_all_entries():
		var e: Dictionary = chunk.crdt.get_all_entries()[key]
		list.append({"layer": (key >> 16) & 0xFF, "lx": (key >> 8) & 0xFF, "ly": key & 0xFF,
		             "tile_id": e["tile_id"], "atlas_x": e["atlas_x"], "atlas_y": e["atlas_y"],
		             "alt_tile": e["alt_tile"], "timestamp": e["timestamp"],
		             "author_id": e["author_id"]})
	return JSON.stringify({
		"chunk_x": chunk.chunk_coords.x, "chunk_y": chunk.chunk_coords.y,
		"world_seed": Constants.WORLD_SEED, "version": 1,
		"entries": list
	}).to_utf8_buffer()

func _deserialize_entries(data: PackedByteArray) -> Dictionary:
	var payload = JSON.parse_string(data.get_string_from_utf8())
	if payload == null:
		return {}
	var entries := {}
	for item in payload.get("entries", []):
		entries[CoordUtils.make_crdt_key(item["layer"], item["lx"], item["ly"])] = {
		    "tile_id": item["tile_id"], "atlas_x": item["atlas_x"], "atlas_y": item["atlas_y"],
		    "alt_tile": item["alt_tile"], "timestamp": item["timestamp"],
		    "author_id": item["author_id"]}
	return entries
