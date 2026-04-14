## Integration tests for Chunk tile collision.
##
## Rules:
##   - Player-like CharacterBody2D can move freely on open ground (no collision).
##   - Player is stopped by tree/rock tiles on ObjectLayer.
##   - GroundLayer tiles (grass, dirt, stone) never block movement.
##
## Why these tests: collision broke silently when `_render_all()` toggled
## `object_layer.collision_enabled = false/true` — physics bodies were not
## regenerated after the toggle in Godot 4.3. These tests catch that class of bug.
extends GdUnitTestSuite

const ChunkScene := preload("res://world/chunk/Chunk.tscn")

# Tile atlas coords (must match ProceduralGenerator / Chunk.ATLAS_TILES)
const GRASS := Vector2i(0, 0)
const TREE  := Vector2i(0, 1)
const ROCK  := Vector2i(1, 1)

var _nodes_to_free: Array = []

func after_test() -> void:
	for n in _nodes_to_free:
		if is_instance_valid(n):
			n.queue_free()
	_nodes_to_free.clear()
	# Physics cleanup — flush any deferred frees
	await get_tree().physics_frame

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Spawn a chunk at world origin with the given CRDT entries and return it.
func _make_chunk(entries: Dictionary) -> ChunkData:
	var chunk := ChunkScene.instantiate() as ChunkData
	add_child(chunk)
	_nodes_to_free.append(chunk)
	chunk.initialize(Vector2i(0, 0), entries)
	return chunk

## Build a minimal CRDT entry dict: one ground tile + one optional object tile.
## ground_at and object_at are TileMapLayer local coords (Vector2i).
func _entries_with_tree(ground_at: Vector2i, tree_at: Vector2i) -> Dictionary:
	var entries := {}
	# Layer 0 (ground): grass everywhere in range 0..3
	for y in range(4):
		for x in range(4):
			var key := CoordUtils.make_crdt_key(0, x, y)
			entries[key] = {"tile_id": 0, "atlas_x": GRASS.x, "atlas_y": GRASS.y,
			                "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
	# Layer 1 (object): tree at specified position
	var obj_key := CoordUtils.make_crdt_key(1, tree_at.x, tree_at.y)
	entries[obj_key] = {"tile_id": 0, "atlas_x": TREE.x, "atlas_y": TREE.y,
	                    "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
	return entries

## Spawn a 12×12 CharacterBody2D at the given position and return it.
func _make_player(pos: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 12)
	shape.shape = rect
	body.add_child(shape)
	body.position = pos
	add_child(body)
	_nodes_to_free.append(body)
	return body

## Run N physics frames while applying velocity to body each frame.
func _move_for_frames(body: CharacterBody2D, velocity: Vector2, frames: int) -> void:
	body.velocity = velocity
	for _i in range(frames):
		body.move_and_slide()
		await get_tree().physics_frame

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## Player moves freely on open ground — no GroundLayer collision.
func test_movement_on_open_ground() -> void:
	# Grass-only chunk (no object tiles).
	var entries := {}
	for y in range(4):
		for x in range(4):
			var key := CoordUtils.make_crdt_key(0, x, y)
			entries[key] = {"tile_id": 0, "atlas_x": GRASS.x, "atlas_y": GRASS.y,
			                "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
	_make_chunk(entries)

	# Player starts at center of the 4×4 tile area (pixel 32, 32), moves right.
	var player := _make_player(Vector2(32, 32))
	var start_x := player.position.x
	await _move_for_frames(player, Vector2(100, 0), 5)

	# Must have moved at least a few pixels — GroundLayer never blocks.
	# (5 physics frames at 100px/s ≈ 8px; use 5px as safe lower bound)
	assert_float(player.position.x).is_greater(start_x + 5.0)

## Player is stopped by a tree on ObjectLayer.
func test_tree_blocks_movement() -> void:
	# Tree at tile (2, 1). Tile pixel origin: (32, 16). Collision bottom-half
	# in TileData local space (y=0→8) → world y=24→32, x=26.4→37.6.
	var entries := _entries_with_tree(Vector2i(0, 0), Vector2i(2, 1))
	_make_chunk(entries)

	# Player just left of the tree, vertically in the collision zone (y=28).
	var player := _make_player(Vector2(18, 28))
	await _move_for_frames(player, Vector2(150, 0), 10)

	# Player must not have passed through the tree's left collision edge (~26.4).
	assert_float(player.position.x).is_less(38.0)
	# And must have moved at least a little (not stuck from the start).
	assert_float(player.position.x).is_greater(18.0)

## Player approaching from ABOVE the collision zone passes the tree freely
## (top half of tree tile has no collision — intentional design).
func test_tree_top_half_is_passable() -> void:
	var entries := _entries_with_tree(Vector2i(0, 0), Vector2i(2, 1))
	_make_chunk(entries)

	# Player at y=8 — above the bottom-half collision zone (y=24..32 for this tile).
	# Moving rightward should not be stopped by the tree.
	var player := _make_player(Vector2(18, 8))
	await _move_for_frames(player, Vector2(150, 0), 10)

	# Should have passed the tree's x range freely.
	assert_float(player.position.x).is_greater(40.0)

## Verify collision_enabled stays true on ObjectLayer after _render_all().
## This is the regression guard for the false/true toggle bug.
func test_object_layer_collision_enabled_after_init() -> void:
	var entries := _entries_with_tree(Vector2i(0, 0), Vector2i(0, 0))
	var chunk := _make_chunk(entries)
	assert_bool(chunk.object_layer.collision_enabled).is_true()
	assert_bool(chunk.ground_layer.collision_enabled).is_false()
