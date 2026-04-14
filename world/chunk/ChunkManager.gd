## ChunkManager — manages loading/unloading of chunks around the player.
## Key invariant: 16-bit TileMapLayer coordinate guard stays in _load_chunk forever.
## All tile mutations go through place_tile() / remove_tile() — never set_cell() directly.
class_name ChunkManager
extends Node

const CHUNK_SCENE  := preload("res://world/chunk/Chunk.tscn")
const MAIN_TILESET := preload("res://tilesets/MainTileSet.tres")

var _loaded_chunks: Dictionary = {}  # Vector2i -> ChunkData
var _player_chunk: Vector2i = Vector2i(-9999, -9999)  # sentinel: forces load on first call

func _ready() -> void:
	_ensure_tileset_atlas_registered()
	_validate_tileset()

## Programmatically register all atlas positions used by ProceduralGenerator.
## .tres serialization of TileSetAtlasSource tile entries is unreliable in Godot 4.3
## (same class of bug as SceneReplicationConfig boolean parsing).
## Safe to call when tiles are already registered — has_tile() guards each create_tile().
func _ensure_tileset_atlas_registered() -> void:
	var source := MAIN_TILESET.get_source(0) as TileSetAtlasSource
	if source == null:
		push_error("ChunkManager: TileSet source 0 not found")
		return
	# Note: tile_size and texture_region_size are set by Chunk._ready() on each
	# instantiated chunk — GDScript const refs don't allow property mutation here.
	var needed := [
		Vector2i(0, 0),  # grass
		Vector2i(1, 0),  # dirt
		Vector2i(2, 0),  # stone
		Vector2i(3, 0),  # water
		Vector2i(0, 1),  # tree
		Vector2i(1, 1),  # rock
	]
	for coords in needed:
		if not source.has_tile(coords):
			source.create_tile(coords)

## Validate that the TileSet is in a state where tiles will actually render.
## Uses push_error (non-fatal) so misconfiguration is loud without halting.
## Godot's static analyzer rejects assert() for values we just set in the same
## scope ("redundant assert" is a fatal error in Godot debug mode).
func _validate_tileset() -> void:
	var source := MAIN_TILESET.get_source(0) as TileSetAtlasSource
	if source == null:
		push_error("TileSet has no source at index 0 — tiles will never render")
		return
	if source.texture == null:
		push_error("TileSetAtlasSource has no texture — tiles will silently not render")
	if source.texture_region_size.x <= 0:
		push_error("TileSetAtlasSource.texture_region_size is zero — tiles will silently not render")
	for coords in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	               Vector2i(0, 1), Vector2i(1, 1)]:
		if not source.has_tile(coords):
			push_error("Atlas tile %s not registered — set_cell() calls for it will silently fail" % coords)

func update_player_position(world_tile_pos: Vector2i) -> void:
	var new_chunk := CoordUtils.world_to_chunk(world_tile_pos)
	# Always load if chunk changed OR if the current chunk was evicted under the player.
	if new_chunk == _player_chunk and _loaded_chunks.has(new_chunk):
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

## set_tile satisfies the TileMutationBus tile_store interface.
## Resolves a string tile_id via TileRegistry then delegates to place_tile().
func set_tile(world_coords: Vector2i, layer: int, tile_id: String, author_id: String) -> void:
	var entry := TileRegistry.resolve(tile_id)
	if entry.is_empty():
		push_warning("ChunkManager.set_tile: unknown tile_id '%s'" % tile_id)
		return
	place_tile(world_coords, layer, entry["tile_id"], entry["atlas"], entry["alt"], author_id)

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

## Returns true if a live (non-tombstone) tile exists at world_coords on layer.
func has_tile_at(world_coords: Vector2i, layer: int) -> bool:
	var cc := CoordUtils.world_to_chunk(world_coords)
	var local := CoordUtils.world_to_local(world_coords)
	var chunk := get_chunk(cc)
	if chunk == null:
		return false
	var entry: Dictionary = chunk.crdt.get_tile(layer, local)
	return not entry.is_empty() and int(entry.get("tile_id", -1)) != -1

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
	var from_disk := not raw.is_empty()
	var entries := _deserialize_entries(raw) if from_disk \
	               else ProceduralGenerator.generate_chunk(coords, Constants.WORLD_SEED)
	if not from_disk:
		_check_generation_sanity(coords, entries)
	var chunk := CHUNK_SCENE.instantiate() as ChunkData
	add_child(chunk)
	chunk.initialize(coords, entries)
	chunk.last_visited = Time.get_unix_time_from_system()
	_loaded_chunks[coords] = chunk

## Sanity-check a freshly-generated chunk's entries.
## Fires push_warning (non-fatal) so miscalibration is visible without crashing.
## Would have caught the TYPE_CELLULAR threshold bug immediately.
func _check_generation_sanity(coords: Vector2i, entries: Dictionary) -> void:
	var grass := 0
	var stone := 0
	var trees := 0
	var rocks := 0
	for k in entries:
		var layer := (int(k) >> 16) & 0xFF
		var ax: int = entries[k].get("atlas_x", -1)
		if layer == 0:
			if ax == 0: grass += 1
			elif ax == 2: stone += 1
		elif layer == 1:
			if ax == 0: trees += 1
			elif ax == 1: rocks += 1
	# At ~35% tree density: 50 grass tiles should yield ~17 trees.
	# Zero trees with that many grass tiles is a strong signal of miscalibration.
	if grass > 50 and trees == 0:
		push_warning(
			"Chunk %s: %d grass tiles but 0 trees — ProceduralGenerator may be miscalibrated "
			% [coords, grass]
			+ "(check noise_objects type and threshold)")
	# Stone is rarer; warn only at a lower floor.
	if stone > 30 and rocks == 0 and grass == 0:
		push_warning(
			"Chunk %s: %d stone tiles but 0 rocks — ProceduralGenerator may be miscalibrated"
			% [coords, stone])

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

## Return a flat Array of all CRDT records across all loaded chunks.
## Format: [{chunk_x, chunk_y, layer, lx, ly, tile_id, atlas_x, atlas_y,
##            alt_tile, timestamp, author_id}, ...]
## Used by MergeRPCBus.send_snapshot() for CRDT exchange.
func get_crdt_snapshot() -> Array:
	var records: Array = []
	for cc in _loaded_chunks:
		var chunk := _loaded_chunks[cc] as ChunkData
		for key in chunk.crdt.get_all_entries():
			var e: Dictionary = chunk.crdt.get_all_entries()[key]
			records.append({
				"chunk_x":   cc.x,
				"chunk_y":   cc.y,
				"layer":     (key >> 16) & 0xFF,
				"lx":        (key >> 8) & 0xFF,
				"ly":        key & 0xFF,
				"tile_id":   e["tile_id"],
				"atlas_x":   e["atlas_x"],
				"atlas_y":   e["atlas_y"],
				"alt_tile":  e["alt_tile"],
				"timestamp": e["timestamp"],
				"author_id": e["author_id"],
			})
	return records

## Merge a flat snapshot Array (from MergeRPCBus) into loaded chunks via LWW.
## Records for unloaded chunks are skipped — they reconcile when loaded.
func apply_crdt_snapshot(records: Array) -> void:
	# Group records by chunk coords, keyed by CRDT key within each chunk
	var by_chunk: Dictionary = {}
	for r in records:
		var cc := Vector2i(int(r.get("chunk_x", 0)), int(r.get("chunk_y", 0)))
		if not by_chunk.has(cc):
			by_chunk[cc] = {}
		var key := CoordUtils.make_crdt_key(
			int(r.get("layer", 0)), int(r.get("lx", 0)), int(r.get("ly", 0)))
		by_chunk[cc][key] = {
			"tile_id":   int(r.get("tile_id",   0)),
			"atlas_x":   int(r.get("atlas_x",   0)),
			"atlas_y":   int(r.get("atlas_y",   0)),
			"alt_tile":  int(r.get("alt_tile",  0)),
			"timestamp": float(r.get("timestamp", 0.0)),
			"author_id": str(r.get("author_id",  "")),
		}
	for cc in by_chunk:
		var chunk := get_chunk(cc)
		if chunk == null:
			continue  # skip unloaded chunks
		var temp := CRDTTileStore.new()
		temp.load_from_entries(by_chunk[cc])
		chunk.crdt.merge(temp)
		chunk._render_all()

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
