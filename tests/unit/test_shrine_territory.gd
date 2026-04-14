## Tests for ShrineTerritory — organic territory expansion and contested boundaries.
## The territory rules:
##   - A chunk joins shrine S's territory if it is the shrine chunk itself,
##     OR it is modified AND adjacent to a chunk already in S's territory.
##   - When two shrine territories would claim the same chunk: CONTESTED.
##   - A chunk can only belong to one shrine (first claim wins on same tick;
##     contested when two shrines both have adjacency).
extends GdUnitTestSuite

const ShrineTerritoryScript := preload("res://mods/ShrineTerritory.gd")

func _territory() -> Object:
	return ShrineTerritoryScript.new()

# --- Shrine chunk registration ---

func test_shrine_chunk_joins_territory_on_register() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	assert_that(t.get_shrine_for_chunk(Vector2i(0, 0))).is_equal("shrine_A")

func test_unregistered_chunk_is_wilderness() -> void:
	var t = _territory()
	assert_that(t.get_shrine_for_chunk(Vector2i(5, 5))).is_null()

# --- Territory expansion through modification ---

func test_modified_adjacent_chunk_joins_territory() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	# (1,0) is adjacent to shrine chunk (0,0), and is modified.
	t.on_chunk_modified(Vector2i(1, 0))
	assert_that(t.get_shrine_for_chunk(Vector2i(1, 0))).is_equal("shrine_A")

func test_modified_non_adjacent_chunk_stays_wilderness() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	# (5,5) is not adjacent to any shrine territory — stays wilderness.
	t.on_chunk_modified(Vector2i(5, 5))
	assert_that(t.get_shrine_for_chunk(Vector2i(5, 5))).is_null()

func test_territory_expands_transitively() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.on_chunk_modified(Vector2i(1, 0))  # joins via (0,0)
	t.on_chunk_modified(Vector2i(2, 0))  # joins via (1,0)
	assert_that(t.get_shrine_for_chunk(Vector2i(2, 0))).is_equal("shrine_A")

func test_diagonal_chunk_does_not_expand_territory() -> void:
	# Only cardinal neighbors count (no diagonals).
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.on_chunk_modified(Vector2i(1, 1))  # diagonal — not adjacent
	assert_that(t.get_shrine_for_chunk(Vector2i(1, 1))).is_null()

# --- Two shrines, no overlap ---

func test_two_shrines_separate_territories() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.register_shrine("shrine_B", Vector2i(10, 0))
	assert_that(t.get_shrine_for_chunk(Vector2i(0, 0))).is_equal("shrine_A")
	assert_that(t.get_shrine_for_chunk(Vector2i(10, 0))).is_equal("shrine_B")

# --- Contested boundary ---

func test_contested_chunk_when_both_shrines_adjacent() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.register_shrine("shrine_B", Vector2i(2, 0))
	# (1,0) is adjacent to both shrines — contested.
	t.on_chunk_modified(Vector2i(1, 0))
	assert_that(t.get_shrine_for_chunk(Vector2i(1, 0))).is_equal("CONTESTED")

func test_contested_chunk_has_no_active_mod_set() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.register_shrine("shrine_B", Vector2i(2, 0))
	t.on_chunk_modified(Vector2i(1, 0))
	assert_that(t.get_active_mod_set(Vector2i(1, 0))).is_null()

# --- Shrine removal ---

func test_shrine_removal_dissolves_territory() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.on_chunk_modified(Vector2i(1, 0))
	t.on_chunk_modified(Vector2i(2, 0))
	t.unregister_shrine("shrine_A")
	assert_that(t.get_shrine_for_chunk(Vector2i(0, 0))).is_null()
	assert_that(t.get_shrine_for_chunk(Vector2i(1, 0))).is_null()
	assert_that(t.get_shrine_for_chunk(Vector2i(2, 0))).is_null()

# --- get_active_mod_set ---

func test_active_mod_set_returns_shrine_id_for_owned_chunk() -> void:
	var t = _territory()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	# The mod set for a shrine chunk is identified by the shrine id.
	assert_that(t.get_active_mod_set(Vector2i(0, 0))).is_equal("shrine_A")

func test_active_mod_set_returns_null_for_wilderness() -> void:
	var t = _territory()
	assert_that(t.get_active_mod_set(Vector2i(99, 99))).is_null()
