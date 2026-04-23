## Tests for Player._tile_dist — the arm-reach range check.
##
## Catches the regression where tiles far outside arm range were harvestable
## because _do_attack had no distance gate. The fix added:
##   if _tile_dist(tile_pos, facing_tile) <= ATTACK_RANGE
## This suite documents which tile offsets are inside/outside that gate so
## any future change to the threshold or distance formula breaks explicitly.
extends GdUnitTestSuite

const PlayerScript := preload("res://player/Player.gd")

var _player: Node = null

func before_test() -> void:
	_player = PlayerScript.new()
	add_child(_player)
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_player): _player.queue_free()
	_player = null

# ATTACK_RANGE = 1.5 tiles — tiles at or below this distance are harvestable.
const ARM_REACH := 1.5

# ---------------------------------------------------------------------------
# Tiles within arm reach
# ---------------------------------------------------------------------------

func test_adjacent_east_is_in_range() -> void:
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(1, 0))).is_less_equal(ARM_REACH)

func test_adjacent_west_is_in_range() -> void:
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(-1, 0))).is_less_equal(ARM_REACH)

func test_adjacent_north_is_in_range() -> void:
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(0, -1))).is_less_equal(ARM_REACH)

func test_adjacent_south_is_in_range() -> void:
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(0, 1))).is_less_equal(ARM_REACH)

func test_diagonal_adjacent_is_in_range() -> void:
	# sqrt(2) ≈ 1.41 — just within arm reach
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(1, 1))).is_less_equal(ARM_REACH)

func test_same_tile_is_zero_distance() -> void:
	assert_float(_player._tile_dist(Vector2i(5, 5), Vector2i(5, 5))).is_equal(0.0)

# ---------------------------------------------------------------------------
# Tiles outside arm reach — the regression case
# ---------------------------------------------------------------------------

func test_two_tiles_away_is_out_of_range() -> void:
	# Distance = 2.0 — was previously harvestable before the range gate was added
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(2, 0))).is_greater(ARM_REACH)

func test_diagonal_two_tiles_is_out_of_range() -> void:
	# sqrt(8) ≈ 2.83
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(2, 2))).is_greater(ARM_REACH)

func test_offset_2_1_is_out_of_range() -> void:
	# sqrt(5) ≈ 2.24 — the corner case that most players would stumble into
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(2, 1))).is_greater(ARM_REACH)

func test_three_tiles_away_is_out_of_range() -> void:
	assert_float(_player._tile_dist(Vector2i(0, 0), Vector2i(3, 0))).is_greater(ARM_REACH)

# ---------------------------------------------------------------------------
# Symmetry and translation invariance
# ---------------------------------------------------------------------------

func test_tile_dist_is_symmetric() -> void:
	var a := Vector2i(3, 7)
	var b := Vector2i(5, 4)
	var d1: float = _player._tile_dist(a, b)
	var d2: float = _player._tile_dist(b, a)
	assert_float(d1).is_equal(d2)

func test_tile_dist_is_translation_invariant() -> void:
	var offset := Vector2i(100, -200)
	var base: float  = _player._tile_dist(Vector2i(0, 0), Vector2i(1, 1))
	var moved: float = _player._tile_dist(offset, offset + Vector2i(1, 1))
	assert_float(moved).is_equal(base)
