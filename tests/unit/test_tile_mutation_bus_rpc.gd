## Tests for TileMutationBus RPC receive path.
## The send path (rpc() call) requires a live multiplayer peer and is verified
## by running two instances. The receive path is pure logic and fully testable.
##
## RPC serialization rule: Vector2i is transmitted as [x, y] Array because
## Godot's RPC layer may not reliably pass Vector2i across the network boundary.
## _rpc_receive_mutation() converts it back before calling apply_remote_mutation().
extends GdUnitTestSuite

const TileMutationBusScript := preload("res://networking/TileMutationBus.gd")

var _to_free: Array = []

func after_test() -> void:
	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()

class MockTileStore:
	var placed: Array = []
	var removed: Array = []
	func set_tile(world_coords: Vector2i, layer: int, tile_id: String, author_id: String) -> void:
		placed.append({"coords": world_coords, "layer": layer, "tile_id": tile_id, "author": author_id})
	func remove_tile(world_coords: Vector2i, layer: int, author_id: String) -> void:
		removed.append({"coords": world_coords, "layer": layer, "author": author_id})

func _make_bus() -> Array:
	var store = MockTileStore.new()
	var bus = TileMutationBusScript.new()
	bus.tile_store = store
	bus.local_author_id = "player_local"
	_to_free.append(bus)
	return [bus, store]

# --- _rpc_receive_mutation: place ---

func test_rpc_receive_place_applies_to_store() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus._rpc_receive_mutation({
		"type": "place",
		"world_coords": [3, 7],   # Array form for RPC transport
		"layer": 0,
		"tile_id": "grass",
		"author_id": "peer_2",
		"timestamp": 1000
	})
	assert_that(store.placed.size()).is_equal(1)
	assert_that(store.placed[0]["tile_id"]).is_equal("grass")
	assert_that(store.placed[0]["coords"]).is_equal(Vector2i(3, 7))

func test_rpc_receive_place_does_not_enqueue_outbound() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus._rpc_receive_mutation({
		"type": "place", "world_coords": [0, 0],
		"layer": 0, "tile_id": "stone", "author_id": "peer_2", "timestamp": 1
	})
	assert_that(bus.flush_outbound().size()).is_equal(0)

# --- _rpc_receive_mutation: remove ---

func test_rpc_receive_remove_applies_to_store() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus._rpc_receive_mutation({
		"type": "remove",
		"world_coords": [5, 5],
		"layer": 1,
		"tile_id": "",
		"author_id": "peer_3",
		"timestamp": 2000
	})
	assert_that(store.removed.size()).is_equal(1)
	assert_that(store.removed[0]["coords"]).is_equal(Vector2i(5, 5))

# --- Vector2i serialization roundtrip ---

func test_vector2i_roundtrip_positive() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus._rpc_receive_mutation({
		"type": "place", "world_coords": [100, 200],
		"layer": 0, "tile_id": "x", "author_id": "p", "timestamp": 1
	})
	assert_that(store.placed[0]["coords"]).is_equal(Vector2i(100, 200))

func test_vector2i_roundtrip_negative() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]; var store = pair[1]
	bus._rpc_receive_mutation({
		"type": "place", "world_coords": [-32, -16],
		"layer": 0, "tile_id": "x", "author_id": "p", "timestamp": 1
	})
	assert_that(store.placed[0]["coords"]).is_equal(Vector2i(-32, -16))

# --- Local request still enqueues outbound (existing behaviour preserved) ---

func test_local_place_still_enqueues_outbound() -> void:
	var pair: Array = _make_bus()
	var bus = pair[0]
	bus.request_place_tile(Vector2i(1, 1), 0, "dirt")
	assert_that(bus.flush_outbound().size()).is_equal(1)
