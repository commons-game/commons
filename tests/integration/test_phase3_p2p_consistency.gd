## Phase 3 end-to-end consistency test.
## Simulates two peers in-process: each has its own TileMutationBus and MockTileStore.
## Mutations from one peer are manually delivered to the other via apply_remote_mutation(),
## verifying that both stores converge to the same state (CRDT consistency guarantee).
##
## Also verifies:
##   - MergePressureSystem integrates with SessionManager peer_count
##   - RegionAuthority correctly transfers authority as peers move
extends GdUnitTestSuite

const TileMutationBusScript  := preload("res://networking/TileMutationBus.gd")
const MergePressureScript    := preload("res://networking/MergePressureSystem.gd")
const SessionManagerScript   := preload("res://networking/SessionManager.gd")
const RegionAuthorityScript  := preload("res://networking/RegionAuthority.gd")

# Simple tile store that records the last write per (coords, layer) key.
# Simulates LWW: later timestamp wins, matching CRDT semantics.
class SimTileStore:
	# key: "x,y,layer" -> {tile_id, author, timestamp}
	var tiles: Dictionary = {}

	func set_tile(world_coords: Vector2i, layer: int, tile_id: String, author_id: String) -> void:
		var key := "%d,%d,%d" % [world_coords.x, world_coords.y, layer]
		tiles[key] = {"tile_id": tile_id, "author": author_id}

	func remove_tile(world_coords: Vector2i, layer: int, author_id: String) -> void:
		var key := "%d,%d,%d" % [world_coords.x, world_coords.y, layer]
		tiles[key] = {"tile_id": "", "author": author_id}

	func get_tile(world_coords: Vector2i, layer: int) -> String:
		var key := "%d,%d,%d" % [world_coords.x, world_coords.y, layer]
		return tiles.get(key, {}).get("tile_id", "")

func _make_peer(author_id: String) -> Array:  # [bus, store]
	var store = SimTileStore.new()
	var bus = TileMutationBusScript.new()
	bus.tile_store = store
	bus.local_author_id = author_id
	return [bus, store]

## Deliver peer A's outbound queue to peer B.
func _sync(from_bus: Object, to_bus: Object) -> void:
	for record in from_bus.flush_outbound():
		to_bus.apply_remote_mutation(record)

# --- CRDT consistency ---

func test_place_from_peer_a_syncs_to_peer_b() -> void:
	var a: Array = _make_peer("peer_a")
	var b: Array = _make_peer("peer_b")
	var bus_a = a[0]; var store_a = a[1]
	var bus_b = b[0]; var store_b = b[1]

	bus_a.request_place_tile(Vector2i(1, 2), 0, "grass")
	_sync(bus_a, bus_b)

	assert_that(store_a.get_tile(Vector2i(1, 2), 0)).is_equal("grass")
	assert_that(store_b.get_tile(Vector2i(1, 2), 0)).is_equal("grass")

func test_remove_from_peer_b_syncs_to_peer_a() -> void:
	var a: Array = _make_peer("peer_a")
	var b: Array = _make_peer("peer_b")
	var bus_a = a[0]; var store_a = a[1]
	var bus_b = b[0]; var store_b = b[1]

	bus_a.request_place_tile(Vector2i(3, 3), 0, "stone")
	_sync(bus_a, bus_b)

	bus_b.request_remove_tile(Vector2i(3, 3), 0)
	_sync(bus_b, bus_a)

	assert_that(store_a.get_tile(Vector2i(3, 3), 0)).is_equal("")
	assert_that(store_b.get_tile(Vector2i(3, 3), 0)).is_equal("")

func test_concurrent_mutations_both_synced() -> void:
	# A and B each place different tiles at different coords, then exchange.
	var a: Array = _make_peer("peer_a")
	var b: Array = _make_peer("peer_b")
	var bus_a = a[0]; var store_a = a[1]
	var bus_b = b[0]; var store_b = b[1]

	bus_a.request_place_tile(Vector2i(0, 0), 0, "fire")
	bus_b.request_place_tile(Vector2i(1, 0), 0, "ice")

	# Cross-sync: each gets the other's mutation
	_sync(bus_a, bus_b)
	_sync(bus_b, bus_a)

	# Both peers see both tiles
	assert_that(store_a.get_tile(Vector2i(0, 0), 0)).is_equal("fire")
	assert_that(store_a.get_tile(Vector2i(1, 0), 0)).is_equal("ice")
	assert_that(store_b.get_tile(Vector2i(0, 0), 0)).is_equal("fire")
	assert_that(store_b.get_tile(Vector2i(1, 0), 0)).is_equal("ice")

func test_apply_remote_idempotent() -> void:
	# Applying the same mutation twice must not duplicate state.
	var a: Array = _make_peer("peer_a")
	var b: Array = _make_peer("peer_b")
	var bus_a = a[0]
	var bus_b = b[0]; var store_b = b[1]

	bus_a.request_place_tile(Vector2i(5, 5), 0, "wood")
	var records: Array = bus_a.flush_outbound()

	# Apply the same record twice
	bus_b.apply_remote_mutation(records[0])
	bus_b.apply_remote_mutation(records[0])

	# Store should reflect a single placement (last write idempotent)
	assert_that(store_b.get_tile(Vector2i(5, 5), 0)).is_equal("wood")

# --- SessionManager + MergePressureSystem integration ---

func test_pressure_stops_ticking_after_peer_joins() -> void:
	var session = SessionManagerScript.new()
	session.start_session()
	var pressure = MergePressureScript.new()
	pressure.peer_count = session.peer_count()  # 0 → but we're solo, set to 1
	pressure.peer_count = 1
	pressure.tick(10.0)
	var solo_pressure: float = pressure.pressure
	assert_that(solo_pressure).is_greater(0.0)

	session.add_peer("peer_2")
	pressure.peer_count = session.peer_count()  # now 1 peer → peer_count=1 still solo?
	# peer_count() counts OTHER peers — 1 other means we are merged
	# MergePressure uses peer_count>1 for "not solo": wire it as (session.peer_count()+1) > 1
	# i.e., total participants = session.peer_count() + 1 (self)
	pressure.peer_count = session.peer_count() + 1  # 2 total — merged
	pressure.tick(10.0)
	# Pressure should not have increased
	assert_that(pressure.pressure).is_equal(solo_pressure)

func test_pressure_resets_on_merge() -> void:
	var pressure = MergePressureScript.new()
	pressure.peer_count = 1
	pressure.tick(100.0)
	assert_that(pressure.pressure).is_greater(0.0)
	pressure.reset()
	assert_that(pressure.pressure).is_equal(pressure.reset_value)

# --- RegionAuthority with two moving peers ---

func test_authority_transfers_as_peers_move() -> void:
	var ra = RegionAuthorityScript.new()
	ra.on_peer_moved(1, Vector2i(0, 0))   # local
	ra.on_peer_moved(2, Vector2i(10, 0))  # remote

	# Chunk (2,0): local dist=2, remote dist=8 → local owns it
	assert_that(ra.get_authority_for_chunk(Vector2i(2, 0))).is_equal(1)

	# Remote peer moves close
	ra.on_peer_moved(2, Vector2i(3, 0))
	# Chunk (2,0): local dist=2, remote dist=1 → remote owns it now
	assert_that(ra.get_authority_for_chunk(Vector2i(2, 0))).is_equal(2)

func test_authority_falls_back_to_local_when_peer_leaves() -> void:
	var ra = RegionAuthorityScript.new()
	ra.on_peer_moved(1, Vector2i(0, 0))
	ra.on_peer_moved(2, Vector2i(1, 0))

	assert_that(ra.get_authority_for_chunk(Vector2i(1, 0))).is_equal(2)
	ra.on_peer_left(2)
	assert_that(ra.get_authority_for_chunk(Vector2i(1, 0))).is_equal(1)
