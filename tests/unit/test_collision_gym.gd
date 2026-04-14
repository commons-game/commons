## CollisionGym — controlled physics test environment.
##
## A "gym" chunk: player placed inside a tight box of rock tiles on the ObjectLayer.
## The box walls should be impassable in all four directions.
##
## Purpose: isolate whether TileMapLayer collision actually stops movement,
## independent of ProceduralGenerator, chunk loading, or game bootstrap.
## If these tests fail, the collision pipeline is broken at the Chunk level.
## If these tests pass but the game doesn't collide, the issue is upstream
## (wrong binary, persisted data, or game-path TileSet setup differs from test-path).
##
## Box layout (tiles, each 16px):
##
##   R R R R R R R R   (row 0 — rock wall)
##   R . . . . . . R   (rows 1-6 — open ground)
##   R . . . . . . R
##   R . . P . . . R   (P = player start, tile 3,3 → pixel 56,56)
##   R . . . . . . R
##   R . . . . . . R
##   R . . . . . . R
##   R R R R R R R R   (row 7 — rock wall)
##
## Rock tiles have bottom-half collision (y: 0→h, x: ±0.7h).
## All four walls stop the player before they reach the tile boundary.
extends GdUnitTestSuite

const ChunkScene := preload("res://world/chunk/Chunk.tscn")

const STONE := Vector2i(2, 0)   # ground layer (no collision)
const ROCK  := Vector2i(1, 1)   # object layer (bottom-half collision)

# Pixel margin: player is considered "escaped" if it crosses this far
# toward a wall.  The right collision edge of tile col=7 is at
# world x = 7*16 + 8 - 0.7*8 = 112 + 8 - 5.6 = 114.4.
# With a 12px-wide player (half=6), movement stops at ~108.4.
# We use 112 as a generous upper bound (still well inside the wall).
const BOX_RIGHT  := 114.0   # must stay left  of this (wall collision edge ≈ 114.4)
const BOX_LEFT   :=  18.0   # must stay right of this (wall collision edge ≈ 13.6, +6 half-width)
const BOX_BOTTOM := 118.0   # must stay above this (wall collision top edge = tile-center y=120, -6 half)
const BOX_TOP    :=  22.0   # must stay below this (top-wall collision bottom edge = y=16, +6 half)

var _nodes_to_free: Array = []

func after_test() -> void:
	for n in _nodes_to_free:
		if is_instance_valid(n):
			n.queue_free()
	_nodes_to_free.clear()
	await get_tree().physics_frame

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_gym_chunk() -> ChunkData:
	var entries := {}
	for y in range(8):
		for x in range(8):
			# Ground (stone) everywhere on layer 0.
			var gkey := CoordUtils.make_crdt_key(0, x, y)
			entries[gkey] = {"tile_id": 0, "atlas_x": STONE.x, "atlas_y": STONE.y,
			                 "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
			# Rock on every border tile on layer 1.
			if x == 0 or x == 7 or y == 0 or y == 7:
				var rkey := CoordUtils.make_crdt_key(1, x, y)
				entries[rkey] = {"tile_id": 0, "atlas_x": ROCK.x, "atlas_y": ROCK.y,
				                 "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
	var chunk := ChunkScene.instantiate() as ChunkData
	add_child(chunk)
	_nodes_to_free.append(chunk)
	chunk.initialize(Vector2i(0, 0), entries)
	return chunk

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

func _push(body: CharacterBody2D, vel: Vector2, frames: int) -> void:
	body.velocity = vel
	for _i in range(frames):
		body.move_and_slide()
		await get_tree().physics_frame

# ---------------------------------------------------------------------------
# Gym sanity check
# ---------------------------------------------------------------------------

## Confirm the gym chunk is set up correctly before running movement tests.
func test_gym_chunk_has_rock_border() -> void:
	var chunk := _make_gym_chunk()
	var used := chunk.object_layer.get_used_cells()
	# Border = 4 sides of an 8×8 box = 4*8 - 4 corners = 28 tiles
	assert_int(used.size()).is_equal(28)
	# All four corners must be rocks.
	assert_bool(chunk.object_layer.get_cell_source_id(Vector2i(0, 0)) != -1).is_true()
	assert_bool(chunk.object_layer.get_cell_source_id(Vector2i(7, 0)) != -1).is_true()
	assert_bool(chunk.object_layer.get_cell_source_id(Vector2i(0, 7)) != -1).is_true()
	assert_bool(chunk.object_layer.get_cell_source_id(Vector2i(7, 7)) != -1).is_true()
	# Interior tile (3,3) must be empty on the object layer.
	assert_bool(chunk.object_layer.get_cell_source_id(Vector2i(3, 3)) == -1).is_true()

func test_object_layer_collision_enabled() -> void:
	var chunk := _make_gym_chunk()
	assert_bool(chunk.object_layer.collision_enabled).is_true()
	assert_bool(chunk.ground_layer.collision_enabled).is_false()

# ---------------------------------------------------------------------------
# Movement tests — player cannot escape the box
# ---------------------------------------------------------------------------

## Player starts in the center of the box and cannot push through the RIGHT wall.
func test_cannot_escape_right() -> void:
	_make_gym_chunk()
	var player := _make_player(Vector2(56, 56))
	await _push(player, Vector2(600, 0), 30)
	assert_float(player.position.x).is_less(BOX_RIGHT)

## Player starts in the center of the box and cannot push through the LEFT wall.
func test_cannot_escape_left() -> void:
	_make_gym_chunk()
	var player := _make_player(Vector2(56, 56))
	await _push(player, Vector2(-600, 0), 30)
	assert_float(player.position.x).is_greater(BOX_LEFT)

## Player starts in the center of the box and cannot push through the BOTTOM wall.
func test_cannot_escape_bottom() -> void:
	_make_gym_chunk()
	var player := _make_player(Vector2(56, 56))
	await _push(player, Vector2(0, 600), 30)
	assert_float(player.position.y).is_less(BOX_BOTTOM)

## Player starts in the center of the box and cannot push through the TOP wall.
## Top wall tiles have bottom-half collision; approaching from below (positive y)
## still hits that lower portion of the tile before the player exits the box.
func test_cannot_escape_top() -> void:
	_make_gym_chunk()
	var player := _make_player(Vector2(56, 56))
	await _push(player, Vector2(0, -600), 30)
	assert_float(player.position.y).is_greater(BOX_TOP)

## Player can move freely inside the box — not stuck from the start.
func test_can_move_inside_box() -> void:
	_make_gym_chunk()
	var player := _make_player(Vector2(56, 56))
	var start := player.position
	await _push(player, Vector2(200, 0), 5)
	assert_float(player.position.x).is_greater(start.x + 4.0)
