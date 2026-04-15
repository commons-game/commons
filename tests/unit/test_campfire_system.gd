## Tests for CampfireSystem — PointLight2D management at campfire tile positions.
##
## Strategy: stub _chunk_mgr so _sync_lights() can run without a full world scene.
## Each stub chunk exposes a real TileMapLayer as `object_layer` and a
## `chunk_coords` Vector2i. We call _sync_lights() directly instead of waiting
## for the POLL_INTERVAL_S timer to fire.
##
## What is covered:
##   - After a scan, a PointLight2D is spawned at each campfire tile position
##   - A second scan does NOT spawn a duplicate light for the same position
##   - When a campfire tile is removed, the light is queue_freed
##   - Light properties: energy == LIGHT_ENERGY, color.r == 1.0
##   - No lights spawned when there are no campfire tiles
extends GdUnitTestSuite

const CampfireSystemScript := preload("res://world/CampfireSystem.gd")

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

## Minimal chunk: exposes chunk_coords and an actual TileMapLayer.
class StubChunk extends Node:
	var chunk_coords: Vector2i = Vector2i.ZERO
	var object_layer: TileMapLayer = null

	func _init(coords: Vector2i) -> void:
		chunk_coords = coords
		object_layer = TileMapLayer.new()

	func _ready() -> void:
		add_child(object_layer)

## Returns a configurable list of loaded chunks.
class StubChunkManager extends Node:
	var _chunks: Dictionary = {}  # Vector2i → StubChunk

	func add_chunk(chunk: StubChunk) -> void:
		_chunks[chunk.chunk_coords] = chunk

	func remove_chunk(coords: Vector2i) -> void:
		_chunks.erase(coords)

	func get_loaded_chunk_coords() -> Array:
		var keys: Array = []
		for k in _chunks:
			keys.append(k)
		return keys

	func get_chunk(coords: Vector2i):
		return _chunks.get(coords, null)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Paint a campfire tile (atlas 0,2) at the given local cell in the chunk's
## object_layer. We use source_id=0 to keep get_cell_source_id > -1.
## CampfireSystem.gd uses a preloaded TileSet; in tests the TileMapLayer has no
## TileSet, so get_cell_source_id returns -1 for any painted cell unless we set
## a TileSet. We work around this: CampfireSystem checks `source_id < 0` and
## skips the cell. To get around that, we create a minimal TileSet with one
## TileSetAtlasSource so source_id 0 is valid.
func _make_tileset_with_source() -> TileSet:
	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	# Texture is not required for the test; use a 1×1 placeholder image.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src, 0)
	return ts

## Paint a campfire tile at local_cell in chunk's object_layer.
func _paint_campfire(chunk: StubChunk, local_cell: Vector2i) -> void:
	var ts := _make_tileset_with_source()
	chunk.object_layer.tile_set = ts
	# Create the atlas tile entry so set_cell works (atlas 0,2 → tile at row 2, col 0)
	var src := ts.get_source(0) as TileSetAtlasSource
	if not src.has_tile(Vector2i(0, 2)):
		src.create_tile(Vector2i(0, 2))
	chunk.object_layer.set_cell(local_cell, 0, Vector2i(0, 2))

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

var _cs: Node              = null
var _cm: StubChunkManager  = null

func before_test() -> void:
	_cm = StubChunkManager.new()
	add_child(_cm)
	_cs = CampfireSystemScript.new()
	_cs._chunk_mgr = _cm
	# CampfireSystem calls get_parent().add_child(light) — parent must be valid.
	add_child(_cs)
	await get_tree().process_frame

func after_test() -> void:
	# Free CampfireSystem and ChunkManager.
	if is_instance_valid(_cs): _cs.queue_free()
	if is_instance_valid(_cm): _cm.queue_free()
	# Free any PointLight2D nodes left by _sync_lights() (parented to this suite).
	# Must happen synchronously before the next test counts lights.
	for child in get_children():
		if child is PointLight2D:
			child.free()
	_cs = null; _cm = null

# ---------------------------------------------------------------------------
# Helpers to add chunks to scene tree before _sync_lights is called.
# ---------------------------------------------------------------------------

func _add_chunk(coords: Vector2i) -> StubChunk:
	var chunk := StubChunk.new(coords)
	_cm.add_chunk(chunk)
	add_child(chunk)
	return chunk

# ---------------------------------------------------------------------------
# No campfire tiles → no lights
# ---------------------------------------------------------------------------

func test_no_campfires_no_lights_spawned() -> void:
	_cs._sync_lights()
	# CampfireSystem parents lights to its parent (the test suite node).
	# Count PointLight2D children added.
	var lights := _count_lights()
	assert_int(lights).is_equal(0)

func test_empty_chunk_yields_no_lights() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(0)
	chunk.queue_free()

# ---------------------------------------------------------------------------
# Campfire tile → light spawned
# ---------------------------------------------------------------------------

func test_one_campfire_spawns_one_light() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(1)
	chunk.queue_free()

func test_two_campfires_in_same_chunk_spawn_two_lights() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(2, 2))
	await get_tree().process_frame
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(2)
	chunk.queue_free()

func test_campfires_in_two_chunks_each_spawn_light() -> void:
	var c1 := _add_chunk(Vector2i(0, 0))
	var c2 := _add_chunk(Vector2i(1, 0))
	_paint_campfire(c1, Vector2i(0, 0))
	_paint_campfire(c2, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(2)
	c1.queue_free()
	c2.queue_free()

# ---------------------------------------------------------------------------
# No duplicate lights on second scan
# ---------------------------------------------------------------------------

func test_second_scan_does_not_duplicate_lights() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(1)
	chunk.queue_free()

func test_three_scans_still_one_light() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	_cs._sync_lights()
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(1)
	chunk.queue_free()

# ---------------------------------------------------------------------------
# Campfire removed → light cleaned up
# ---------------------------------------------------------------------------

func test_removing_campfire_tile_removes_light() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(1)
	# Remove the tile from the map.
	chunk.object_layer.erase_cell(Vector2i(0, 0))
	_cs._sync_lights()
	await get_tree().process_frame
	assert_int(_count_lights()).is_equal(0)
	chunk.queue_free()

func test_removing_one_of_two_campfires_leaves_one_light() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(2, 2))
	await get_tree().process_frame
	_cs._sync_lights()
	assert_int(_count_lights()).is_equal(2)
	chunk.object_layer.erase_cell(Vector2i(0, 0))
	_cs._sync_lights()
	await get_tree().process_frame
	assert_int(_count_lights()).is_equal(1)
	chunk.queue_free()

# ---------------------------------------------------------------------------
# Light properties
# ---------------------------------------------------------------------------

func test_light_energy_matches_constant() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	var light := _first_light()
	assert_float(light.energy).is_equal_approx(CampfireSystemScript.LIGHT_ENERGY, 0.001)
	chunk.queue_free()

func test_light_color_r_is_1() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	var light := _first_light()
	assert_float(light.color.r).is_equal_approx(1.0, 0.001)
	chunk.queue_free()

func test_light_color_matches_constant() -> void:
	var chunk := _add_chunk(Vector2i(0, 0))
	_paint_campfire(chunk, Vector2i(0, 0))
	await get_tree().process_frame
	_cs._sync_lights()
	var light := _first_light()
	assert_float(light.color.r).is_equal_approx(CampfireSystemScript.LIGHT_COLOR.r, 0.001)
	assert_float(light.color.g).is_equal_approx(CampfireSystemScript.LIGHT_COLOR.g, 0.001)
	assert_float(light.color.b).is_equal_approx(CampfireSystemScript.LIGHT_COLOR.b, 0.001)
	chunk.queue_free()

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

## Count PointLight2D nodes that are direct children of this test suite
## (where CampfireSystem.get_parent() resolves to).
func _count_lights() -> int:
	var n := 0
	for child in get_children():
		if child is PointLight2D and is_instance_valid(child):
			n += 1
	return n

func _first_light() -> PointLight2D:
	for child in get_children():
		if child is PointLight2D and is_instance_valid(child):
			return child as PointLight2D
	return null
