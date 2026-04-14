## Tests for TileMutationBus — single path for all tile changes.
## The bus decouples mutation logic from RPC transport.
##
## Rules:
##   - request_place_tile() applies the mutation locally and enqueues an outbound record.
##   - request_remove_tile() does the same for removals.
##   - apply_remote_mutation() applies an inbound mutation dict to the local store.
##   - Outbound mutations include: type, world_coords, layer, tile_id, author_id, timestamp.
##   - apply_remote_mutation() is idempotent (CRDT — applying twice yields the same state).
##   - flush_outbound() returns the pending outbound queue and clears it.
##
## The bus does NOT test actual RPC — that requires a running multiplayer scene.
## It only tests the mutation record protocol and local application.
extends GdUnitTestSuite

const TileMutationBusScript := preload("res://networking/TileMutationBus.gd")

var _to_free: Array = []

func after_test() -> void:
	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()

# Minimal stub that records calls so we can verify the bus applied mutations.
class MockTileStore:
	var placed: Array = []   # Array of {coords, layer, tile_id, author_id}
	var removed: Array = []  # Array of {coords, layer, author_id}

	func set_tile(world_coords: Vector2i, layer: int, tile_id: String, author_id: String) -> void:
		placed.append({"coords": world_coords, "layer": layer, "tile_id": tile_id, "author": author_id})

	func remove_tile(world_coords: Vector2i, layer: int, author_id: String) -> void:
		removed.append({"coords": world_coords, "layer": layer, "author": author_id})

func _make_bus() -> Array:  # returns [bus, store]
	var store = MockTileStore.new()
	var bus = TileMutationBusScript.new()
	bus.tile_store = store
	bus.local_author_id = "player_local"
	_to_free.append(bus)
	return [bus, store]

# --- Place tile ---

func test_place_applies_to_local_store() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus.request_place_tile(Vector2i(3, 4), 0, "grass")
	assert_that(store.placed.size()).is_equal(1)
	assert_that(store.placed[0]["tile_id"]).is_equal("grass")
	assert_that(store.placed[0]["coords"]).is_equal(Vector2i(3, 4))

func test_place_enqueues_outbound_record() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus.request_place_tile(Vector2i(1, 2), 1, "stone")
	var outbound: Array = bus.flush_outbound()
	assert_that(outbound.size()).is_equal(1)
	assert_that(outbound[0]["type"]).is_equal("place")
	assert_that(outbound[0]["tile_id"]).is_equal("stone")
	assert_that(outbound[0]["world_coords"]).is_equal(Vector2i(1, 2))
	assert_that(outbound[0]["layer"]).is_equal(1)

func test_place_record_includes_author_and_timestamp() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus.request_place_tile(Vector2i(0, 0), 0, "dirt")
	var outbound: Array = bus.flush_outbound()
	assert_that(outbound[0]["author_id"]).is_equal("player_local")
	assert_bool(outbound[0].has("timestamp")).is_true()

# --- Remove tile ---

func test_remove_applies_to_local_store() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus.request_remove_tile(Vector2i(5, 6), 0)
	assert_that(store.removed.size()).is_equal(1)
	assert_that(store.removed[0]["coords"]).is_equal(Vector2i(5, 6))

func test_remove_enqueues_outbound_record() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus.request_remove_tile(Vector2i(7, 8), 1)
	var outbound: Array = bus.flush_outbound()
	assert_that(outbound.size()).is_equal(1)
	assert_that(outbound[0]["type"]).is_equal("remove")
	assert_that(outbound[0]["world_coords"]).is_equal(Vector2i(7, 8))

# --- apply_remote_mutation ---

func test_apply_remote_place_calls_store() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus.apply_remote_mutation({
		"type": "place",
		"world_coords": Vector2i(2, 3),
		"layer": 0,
		"tile_id": "water",
		"author_id": "peer_99",
		"timestamp": 1000
	})
	assert_that(store.placed.size()).is_equal(1)
	assert_that(store.placed[0]["tile_id"]).is_equal("water")

func test_apply_remote_remove_calls_store() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus.apply_remote_mutation({
		"type": "remove",
		"world_coords": Vector2i(4, 5),
		"layer": 0,
		"author_id": "peer_99",
		"timestamp": 1001
	})
	assert_that(store.removed.size()).is_equal(1)
	assert_that(store.removed[0]["coords"]).is_equal(Vector2i(4, 5))

func test_apply_remote_does_not_enqueue_outbound() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus.apply_remote_mutation({
		"type": "place", "world_coords": Vector2i(0, 0),
		"layer": 0, "tile_id": "rock", "author_id": "peer_2", "timestamp": 500
	})
	assert_that(bus.flush_outbound().size()).is_equal(0)

# --- flush_outbound clears queue ---

func test_flush_outbound_clears_queue() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus.request_place_tile(Vector2i(0, 0), 0, "dirt")
	bus.flush_outbound()
	assert_that(bus.flush_outbound().size()).is_equal(0)

func test_multiple_mutations_all_queued() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus.request_place_tile(Vector2i(0, 0), 0, "a")
	bus.request_place_tile(Vector2i(1, 0), 0, "b")
	bus.request_remove_tile(Vector2i(2, 0), 0)
	assert_that(bus.flush_outbound().size()).is_equal(3)
