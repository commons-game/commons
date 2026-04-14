## Unit tests for MergeRPCBus snapshot serialization logic.
## RPC delivery itself is not tested here (requires live multiplayer peer).
extends GdUnitTestSuite

const MergeRPCBusScript := preload("res://networking/MergeRPCBus.gd")

var _bus: Object

func before_test() -> void:
	_bus = MergeRPCBusScript.new()

func after_test() -> void:
	_bus.free()

# --- Snapshot serialization ---

func test_build_snapshot_from_records_roundtrip() -> void:
	var records: Array = [
		{"chunk_x": 0, "chunk_y": 0, "layer": 0, "lx": 3, "ly": 5,
		 "tile_id": 1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 1000.0, "author_id": "alice"},
		{"chunk_x": 1, "chunk_y": 0, "layer": 0, "lx": 7, "ly": 2,
		 "tile_id": 2, "atlas_x": 1, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 2000.0, "author_id": "bob"},
	]
	# Serialise then deserialise
	var packed: String = _bus.serialize_snapshot(records)
	var parsed: Array = _bus.deserialize_snapshot(packed)
	assert_that(parsed.size()).is_equal(2)
	assert_that(int(parsed[0]["tile_id"])).is_equal(1)
	assert_that(int(parsed[1]["tile_id"])).is_equal(2)
	assert_that(int(parsed[0]["lx"])).is_equal(3)
	assert_that(parsed[0]["author_id"]).is_equal("alice")

func test_empty_snapshot_roundtrips_cleanly() -> void:
	var packed: String = _bus.serialize_snapshot([])
	var parsed: Array = _bus.deserialize_snapshot(packed)
	assert_that(parsed.size()).is_equal(0)

func test_lww_merge_keeps_higher_timestamp() -> void:
	# local has older tile, remote has newer — remote should win
	var local_records: Array = [
		{"chunk_x": 0, "chunk_y": 0, "layer": 0, "lx": 0, "ly": 0,
		 "tile_id": 1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 100.0, "author_id": "alice"},
	]
	var remote_records: Array = [
		{"chunk_x": 0, "chunk_y": 0, "layer": 0, "lx": 0, "ly": 0,
		 "tile_id": 2, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 999.0, "author_id": "bob"},
	]
	var merged: Array = _bus.merge_snapshots(local_records, remote_records)
	# One unique position — winner has tile_id 2 (higher timestamp)
	assert_that(merged.size()).is_equal(1)
	assert_that(int(merged[0]["tile_id"])).is_equal(2)

func test_lww_merge_keeps_local_when_newer() -> void:
	var local_records: Array = [
		{"chunk_x": 0, "chunk_y": 0, "layer": 0, "lx": 0, "ly": 0,
		 "tile_id": 99, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 5000.0, "author_id": "alice"},
	]
	var remote_records: Array = [
		{"chunk_x": 0, "chunk_y": 0, "layer": 0, "lx": 0, "ly": 0,
		 "tile_id": 1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 100.0, "author_id": "bob"},
	]
	var merged: Array = _bus.merge_snapshots(local_records, remote_records)
	assert_that(int(merged[0]["tile_id"])).is_equal(99)

func test_merge_combines_non_conflicting_tiles() -> void:
	var local_records: Array = [
		{"chunk_x": 0, "chunk_y": 0, "layer": 0, "lx": 0, "ly": 0,
		 "tile_id": 1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 100.0, "author_id": "alice"},
	]
	var remote_records: Array = [
		{"chunk_x": 1, "chunk_y": 0, "layer": 0, "lx": 0, "ly": 0,
		 "tile_id": 2, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 200.0, "author_id": "bob"},
	]
	var merged: Array = _bus.merge_snapshots(local_records, remote_records)
	assert_that(merged.size()).is_equal(2)

func test_session_hello_payload_roundtrip() -> void:
	var payload: Dictionary = _bus.build_hello_payload("my_session", Vector2i(3, -7))
	assert_that(payload["session_id"]).is_equal("my_session")
	assert_that(int(payload["chunk_x"])).is_equal(3)
	assert_that(int(payload["chunk_y"])).is_equal(-7)
