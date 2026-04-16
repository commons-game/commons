## Phase 4 end-to-end merge lifecycle test.
## Exercises the full chain:
##   - Two solo sessions accumulate merge pressure
##   - Presence service notifies each other when in range
##   - BridgeFormation decides to form a bridge (pressure=1.0)
##   - Bridge chunks are calculated
##   - MergeHandshake exchanges and merges CRDT stores
##   - TalismanItem modifies pressure ramp rate
##   - Sessions drift apart → SplitDetector triggers dissolution
##   - Pressure resets after split
extends GdUnitTestSuite

const MergePressureScript    := preload("res://networking/MergePressureSystem.gd")
const SessionManagerScript   := preload("res://networking/SessionManager.gd")
const LocalPresenceScript    := preload("res://networking/LocalPresenceService.gd")
const BridgeFormationScript  := preload("res://networking/BridgeFormation.gd")
const MergeHandshakeScript   := preload("res://networking/MergeHandshake.gd")
const TalismanItemScript     := preload("res://networking/TalismanItem.gd")
const SplitDetectorScript    := preload("res://networking/SplitDetector.gd")

func test_full_merge_and_split_lifecycle() -> void:
	# --- Setup: two solo sessions ---
	var session_a = SessionManagerScript.new()
	var session_b = SessionManagerScript.new()
	session_a.start_session()
	session_b.start_session()

	var pressure_a = MergePressureScript.new()
	var pressure_b = MergePressureScript.new()
	pressure_a.peer_count = 1
	pressure_b.peer_count = 1

	# Both accumulate pressure over time
	pressure_a.tick(500.0)
	pressure_b.tick(500.0)
	assert_that(pressure_a.pressure).is_greater(0.0)
	assert_that(pressure_b.pressure).is_greater(0.0)

	# --- Presence: sessions detect each other ---
	var presence = LocalPresenceScript.new()
	var discovered: Array = []
	presence.subscribe_area(session_a.session_id, Vector2i(0, 0), 10,
		func(pid, coords): discovered.append({"pid": pid, "coords": coords}))
	presence.publish_presence(session_b.session_id, Vector2i(5, 0))
	assert_that(discovered.size()).is_equal(1)
	assert_that(discovered[0]["pid"]).is_equal(session_b.session_id)

	# --- Bridge formation: pressure=1.0 always bridges ---
	pressure_a.pressure = 1.0
	pressure_b.pressure = 1.0
	var bridge = BridgeFormationScript.new()
	assert_bool(bridge.should_form_bridge(
		Vector2i(0, 0), Vector2i(5, 0), 1.0, 1.0)).is_true()

	var bridge_chunks: Array = bridge.get_bridge_chunks(Vector2i(0, 0), Vector2i(5, 0))
	assert_that(bridge_chunks.size()).is_equal(4)  # intermediates between 0 and 5

	# --- Merge handshake: exchange and merge CRDT stores ---
	var crdt_a := {
		"tile_0_0": {"tile_id": 0, "atlas_x": 0, "atlas_y": 1, "alt_tile": 0,
		             "timestamp": 100.0, "author_id": "session_a"}
	}
	var crdt_b := {
		"tile_5_0": {"tile_id": 0, "atlas_x": 2, "atlas_y": 0, "alt_tile": 0,
		             "timestamp": 200.0, "author_id": "session_b"}
	}
	var handshake = MergeHandshakeScript.new()

	var proposal_b: Dictionary = handshake.propose_merge(
		session_b.session_id, crdt_b, session_b.get_peers()) as Dictionary
	var merged: Dictionary = handshake.accept_merge(proposal_b, crdt_a) as Dictionary

	# Both sessions' tiles are present after merge
	assert_bool(merged.has("tile_0_0")).is_true()
	assert_bool(merged.has("tile_5_0")).is_true()

	# Combined peer list
	session_a.add_peer(session_b.session_id)
	var all_peers: Array = handshake.get_combined_peers(
		session_a.get_peers(), session_b.get_peers()) as Array
	assert_bool(all_peers.has(session_b.session_id)).is_true()

	# Pressure stops ticking once merged (peer_count > 1 total)
	pressure_a.peer_count = 2
	var pressure_before: float = pressure_a.pressure
	pressure_a.tick(100.0)
	assert_that(pressure_a.pressure).is_equal(pressure_before)

	# --- Sessions drift apart → split ---
	var split = SplitDetectorScript.new()
	assert_bool(split.should_dissolve(Vector2i(0, 0), Vector2i(5, 0))).is_false()
	assert_bool(split.should_dissolve(Vector2i(0, 0), Vector2i(30, 0))).is_true()

	# Dissolve: reset pressure
	split.on_dissolve(pressure_a)
	assert_that(pressure_a.pressure).is_equal(pressure_a.reset_value)

func test_talisman_accelerates_bridge_finding() -> void:
	var pressure = MergePressureScript.new()
	var base_rate: float = pressure.ramp_rate

	var compass = TalismanItemScript.new()
	compass.id = "compass_of_the_lost"
	compass.modifier = 5.0
	compass.apply_to(pressure)

	assert_that(pressure.ramp_rate).is_equal(base_rate * 5.0)

	# With higher ramp_rate, pressure reaches threshold sooner
	pressure.peer_count = 1
	pressure.tick(100.0)
	var fast_pressure: float = pressure.pressure

	var slow = MergePressureScript.new()
	slow.peer_count = 1
	slow.tick(100.0)

	assert_that(fast_pressure).is_greater(slow.pressure)

func test_ward_of_solitude_slows_bridge_finding() -> void:
	var pressure = MergePressureScript.new()
	var ward = TalismanItemScript.new()
	ward.id = "ward_of_solitude"
	ward.modifier = 0.1   # 10x slower accumulation
	ward.apply_to(pressure)

	pressure.peer_count = 1
	pressure.tick(100.0)
	var slow_pressure: float = pressure.pressure

	var normal = MergePressureScript.new()
	normal.peer_count = 1
	normal.tick(100.0)

	assert_that(slow_pressure).is_less(normal.pressure)

func test_presence_out_of_range_does_not_trigger_bridge_evaluation() -> void:
	var presence = LocalPresenceScript.new()
	var triggered: Array = []
	presence.subscribe_area("session_a", Vector2i(0, 0), 3,
		func(pid, _c): triggered.append(pid))

	# Publish far away — no callback
	presence.publish_presence("session_b", Vector2i(50, 50))
	assert_that(triggered.size()).is_equal(0)

func test_lww_merge_conflict_resolved_correctly() -> void:
	# Conflict: both sessions modified the same tile; remote is newer — remote must win.
	var handshake = MergeHandshakeScript.new()
	var local  := {"chunk_0_0": {"tile_id": 0, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
	                              "timestamp": 100.0, "author_id": "stale_author"}}
	var remote := {"chunk_0_0": {"tile_id": 0, "atlas_x": 2, "atlas_y": 0, "alt_tile": 0,
	                              "timestamp": 999.0, "author_id": "fresh_author"}}
	var proposal: Dictionary = handshake.propose_merge("session_b", remote, []) as Dictionary
	var merged: Dictionary = handshake.accept_merge(proposal, local) as Dictionary
	assert_that(merged["chunk_0_0"]["author_id"]).is_equal("fresh_author")
