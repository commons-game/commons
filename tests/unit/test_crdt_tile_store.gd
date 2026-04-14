## Tests for CRDTTileStore — all 6 CRDT invariants.
## These MUST stay green — Phase 3 multiplayer depends entirely on CRDT correctness.
extends GdUnitTestSuite

# Helper: create a store with one tile entry at a given timestamp.
func _make_store_with_tile(layer: int, lx: int, ly: int, tile_id: int, ts: float, author: String) -> CRDTTileStore:
	var store := CRDTTileStore.new()
	var key := CoordUtils.make_crdt_key(layer, lx, ly)
	store._data[key] = {
		"tile_id": tile_id, "atlas_x": 0, "atlas_y": 0,
		"alt_tile": 0, "timestamp": ts, "author_id": author
	}
	return store

# --- Invariant 1: set_tile then get_tile returns the entry ---

func test_set_and_get_tile() -> void:
	var store := CRDTTileStore.new()
	store.set_tile(0, Vector2i(3, 5), 0, Vector2i(1, 0), 0, "player-1")
	var result := store.get_tile(0, Vector2i(3, 5))
	assert_that(result.is_empty()).is_false()
	assert_that(result["tile_id"]).is_equal(0)
	assert_that(result["atlas_x"]).is_equal(1)
	assert_that(result["author_id"]).is_equal("player-1")

# --- Invariant 2: remove_tile writes a tombstone (tile_id == -1) ---

func test_remove_tile_writes_tombstone() -> void:
	var store := CRDTTileStore.new()
	store.set_tile(0, Vector2i(2, 2), 0, Vector2i(0, 0), 0, "player-1")
	store.remove_tile(0, Vector2i(2, 2), "player-1")
	var result := store.get_tile(0, Vector2i(2, 2))
	assert_that(result.is_empty()).is_false()
	assert_that(result["tile_id"]).is_equal(-1)

# --- Invariant 3: Older placement does not overwrite newer tombstone ---

func test_older_placement_does_not_overwrite_newer_tombstone() -> void:
	# Tombstone at ts=200, then attempt set_tile with ts=100 — tombstone must win.
	var store := CRDTTileStore.new()
	var key := CoordUtils.make_crdt_key(0, 5, 5)
	# Directly inject tombstone with future timestamp
	store._data[key] = {
		"tile_id": -1, "atlas_x": 0, "atlas_y": 0,
		"alt_tile": 0, "timestamp": 200.0, "author_id": "player-1"
	}
	# Attempt to overwrite with older placement
	store._data[key] = store._data.get(key)  # confirm tombstone is there
	var ts_check: float = store._data[key]["timestamp"]
	# Simulate set_tile with older timestamp by checking the logic manually:
	# set_tile only writes if ts > existing timestamp.
	# Since we can't control Time.get_unix_time_from_system() directly,
	# we test the merge path instead (which uses explicit timestamps).
	var new_store := _make_store_with_tile(0, 5, 5, 0, 100.0, "player-2")
	store.merge(new_store)
	# Tombstone at ts=200 should survive merge against placement at ts=100
	assert_that(store.get_tile(0, Vector2i(5, 5))["tile_id"]).is_equal(-1)
	assert_that(store.get_tile(0, Vector2i(5, 5))["timestamp"]).is_equal(200.0)

# --- Invariant 4: Merge commutativity: A.merge(B) result == B.merge(A) result ---

func test_merge_commutativity() -> void:
	var a := _make_store_with_tile(0, 1, 1, 0, 100.0, "player-1")
	var b := _make_store_with_tile(0, 1, 1, 1, 200.0, "player-2")
	# Also add different keys
	a._data[CoordUtils.make_crdt_key(0, 2, 2)] = {
		"tile_id": 2, "atlas_x": 0, "atlas_y": 0,
		"alt_tile": 0, "timestamp": 50.0, "author_id": "player-1"
	}
	b._data[CoordUtils.make_crdt_key(0, 3, 3)] = {
		"tile_id": 3, "atlas_x": 0, "atlas_y": 0,
		"alt_tile": 0, "timestamp": 75.0, "author_id": "player-2"
	}

	# A merged with B
	var a2 := CRDTTileStore.new()
	a2._data = a._data.duplicate(true)
	a2.merge(b)

	# B merged with A
	var b2 := CRDTTileStore.new()
	b2._data = b._data.duplicate(true)
	b2.merge(a)

	# Results should be identical
	for key in a2._data:
		assert_that(b2._data.has(key)).is_true()
		assert_that(a2._data[key]["tile_id"]).is_equal(b2._data[key]["tile_id"])
		assert_that(a2._data[key]["timestamp"]).is_equal(b2._data[key]["timestamp"])
	for key in b2._data:
		assert_that(a2._data.has(key)).is_true()

# --- Invariant 5: Merge idempotency: A.merge(A) leaves A unchanged ---

func test_merge_idempotency() -> void:
	var store := _make_store_with_tile(0, 4, 4, 0, 100.0, "player-1")
	store._data[CoordUtils.make_crdt_key(0, 5, 5)] = {
		"tile_id": -1, "atlas_x": 0, "atlas_y": 0,
		"alt_tile": 0, "timestamp": 200.0, "author_id": "player-1"
	}
	var original_data := store._data.duplicate(true)
	store.merge(store)
	# Data should be identical
	assert_that(store._data.size()).is_equal(original_data.size())
	for key in original_data:
		assert_that(store._data.has(key)).is_true()
		assert_that(store._data[key]["tile_id"]).is_equal(original_data[key]["tile_id"])
		assert_that(store._data[key]["timestamp"]).is_equal(original_data[key]["timestamp"])

# --- Invariant 6: Merge associativity: (A.merge(B)).merge(C) == A.merge(B.merge(C)) ---

func test_merge_associativity() -> void:
	var a := _make_store_with_tile(0, 1, 1, 10, 100.0, "p1")
	var b := _make_store_with_tile(0, 1, 1, 20, 200.0, "p2")
	var c := _make_store_with_tile(0, 1, 1, 30, 150.0, "p3")
	# Also add unique keys to each
	a._data[CoordUtils.make_crdt_key(0, 2, 0)] = {
		"tile_id": 1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0, "timestamp": 10.0, "author_id": "p1"}
	b._data[CoordUtils.make_crdt_key(0, 3, 0)] = {
		"tile_id": 2, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0, "timestamp": 20.0, "author_id": "p2"}
	c._data[CoordUtils.make_crdt_key(0, 4, 0)] = {
		"tile_id": 3, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0, "timestamp": 30.0, "author_id": "p3"}

	# (A.merge(B)).merge(C)
	var ab := CRDTTileStore.new()
	ab._data = a._data.duplicate(true)
	ab.merge(b)
	ab.merge(c)

	# A.merge(B.merge(C))
	var bc := CRDTTileStore.new()
	bc._data = b._data.duplicate(true)
	bc.merge(c)
	var a_bc := CRDTTileStore.new()
	a_bc._data = a._data.duplicate(true)
	a_bc.merge(bc)

	# Results must be identical
	assert_that(ab._data.size()).is_equal(a_bc._data.size())
	for key in ab._data:
		assert_that(a_bc._data.has(key)).is_true()
		assert_that(ab._data[key]["tile_id"]).is_equal(a_bc._data[key]["tile_id"])
		assert_that(ab._data[key]["timestamp"]).is_equal(a_bc._data[key]["timestamp"])

# --- load_from_entries / get_all_entries ---

func test_load_from_entries() -> void:
	var store := CRDTTileStore.new()
	var entries := {
		CoordUtils.make_crdt_key(0, 1, 2): {
			"tile_id": 5, "atlas_x": 2, "atlas_y": 0,
			"alt_tile": 0, "timestamp": 999.0, "author_id": "gen"
		}
	}
	store.load_from_entries(entries)
	var all := store.get_all_entries()
	assert_that(all.size()).is_equal(1)
	assert_that(all[CoordUtils.make_crdt_key(0, 1, 2)]["tile_id"]).is_equal(5)
