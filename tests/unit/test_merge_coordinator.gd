## Unit tests for MergeCoordinator.
## Drives _on_peer_discovered directly — no network required.
extends GdUnitTestSuite

const MergeCoordinatorScript := preload("res://networking/MergeCoordinator.gd")
const IslandRegistryScript := preload("res://autoloads/IslandRegistry.gd")

var _coord: Object
var _to_free: Array = []
## Phase 0d-ii: track island ids registered as side effects (e.g. by _do_split
## creating a solo: island, or completing a merge creating a merge: island)
## so we can scrub them after each test and not poison subsequent ones.
var _registered_island_ids_before: Dictionary = {}

func before_test() -> void:
	_coord = MergeCoordinatorScript.new()
	_coord.session_id = "aaa_local"   # lower than "bbb_remote" → I am offerer
	_to_free.append(_coord)
	# Snapshot which islands existed before this test so we can drop any new
	# ones the test creates as a side effect (split / merge wiring).
	_registered_island_ids_before.clear()
	for island in IslandRegistry.all_islands():
		_registered_island_ids_before[island.id] = true

func after_test() -> void:
	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()
	# Restore default as active so the next test starts clean. Do this BEFORE
	# unregistering side-effect islands so we don't try to set_active to a
	# stale id while it's still in the dictionary.
	IslandRegistry.set_active_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	# Drop any islands the test created as side effects.
	for island in IslandRegistry.all_islands():
		if not _registered_island_ids_before.has(island.id):
			IslandRegistry.unregister_island(island.id)
	# Clear any in-progress merge transition state on the registry singleton
	# so the next test's is_merging() reads false.
	IslandRegistry._merge_target_total_phase = -1.0
	IslandRegistry._merge_island_id = ""
	IslandRegistry._merge_pre_island_id = ""
	# Reset the default island's clock so we don't poison time-dependent tests.
	var default_clock = IslandRegistry.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID).clock
	default_clock._time_override = -1.0
	default_clock._wall_time_override = -1.0
	default_clock._time_offset = 0.0
	# Also clear any leftover acceleration ramp state.
	default_clock._accel_duration_seconds = 0.0
	default_clock._accel_extra_offset = 0.0
	default_clock._accel_start_wall_time = -1.0
	default_clock._accel_base_offset = 0.0
	default_clock.resync_phase()

# --- Pressure ticking ---

func test_pressure_ticks_when_solo() -> void:
	_coord.tick(10.0)
	assert_float(_coord.get_pressure()).is_greater(0.0)

func test_pressure_does_not_tick_when_merged() -> void:
	_coord.dev_instant_merge = true
	_coord.tick(10.0)  # tick to build pressure
	_coord.on_peer_connected("bbb_remote", Vector2i(5, 0))
	var p_before: float = _coord.get_pressure()
	_coord.tick(100.0)
	assert_float(_coord.get_pressure()).is_equal(p_before)

func test_pressure_caps_at_one() -> void:
	_coord.tick(999999.0)
	assert_float(_coord.get_pressure()).is_equal(1.0)

# --- Dev instant merge mode ---

func test_dev_instant_merge_starts_at_full_pressure() -> void:
	var dev = MergeCoordinatorScript.new()
	dev.session_id = "aaa_local"
	dev.dev_instant_merge = true
	_to_free.append(dev)
	assert_float(dev.get_pressure()).is_equal(1.0)

func test_dev_mode_uses_fast_broadcast_interval() -> void:
	var dev = MergeCoordinatorScript.new()
	dev.session_id = "aaa_local"
	dev.dev_instant_merge = true
	_to_free.append(dev)
	assert_float(dev.broadcast_interval).is_less_equal(2.0)

# --- Offerer/answerer role (formerly host/client) ---

func test_lower_session_id_is_offerer() -> void:
	_coord.dev_instant_merge = true
	var emitted: Array = []
	_coord.webrtc_pairing_needed.connect(func(_key, i_am_offerer): emitted.append(i_am_offerer))
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 0)
	assert_that(emitted.size()).is_equal(1)
	assert_bool(emitted[0]).is_true()   # aaa < bbb → I am offerer

func test_higher_session_id_is_answerer() -> void:
	_coord.session_id = "zzz_local"   # higher than "aaa_remote"
	_coord.dev_instant_merge = true
	var emitted: Array = []
	_coord.webrtc_pairing_needed.connect(func(_key, i_am_offerer): emitted.append(i_am_offerer))
	_coord._on_peer_discovered("aaa_remote", Vector2i(1, 0), "192.168.1.2", 0)
	assert_bool(emitted[0]).is_false()  # zzz > aaa → I am answerer

# --- Bridge gate ---

func test_zero_pressure_does_not_emit_pairing_needed() -> void:
	var emitted: Array = [false]
	_coord.webrtc_pairing_needed.connect(func(_k, _o): emitted[0] = true)
	# Tick zero delta — pressure stays 0
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 0)
	assert_bool(emitted[0]).is_false()

func test_full_pressure_always_emits_pairing_needed() -> void:
	_coord.dev_instant_merge = true  # sets pressure to 1.0
	var emitted: Array = [false]
	_coord.webrtc_pairing_needed.connect(func(_k, _o): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 0)
	assert_bool(emitted[0]).is_true()

func test_duplicate_discovery_ignored_while_merging() -> void:
	_coord.dev_instant_merge = true
	var emitted: Array = [0]
	_coord.webrtc_pairing_needed.connect(func(_k, _o): emitted[0] += 1)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 0)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 0)
	assert_that(emitted[0]).is_equal(1)

# --- Split detection ---

func test_split_resets_pressure_and_emits_signal() -> void:
	_coord.dev_instant_merge = true
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	var split_fired: Array = [false]
	_coord.split_occurred.connect(func(_sid): split_fired[0] = true)
	# Move remote chunk far away (> SPLIT_DISTANCE = 25)
	_coord.update_remote_chunk(Vector2i(50, 0))
	_coord.tick(0.1)  # triggers split check
	assert_bool(split_fired[0]).is_true()
	assert_float(_coord.get_pressure()).is_equal(_coord.reset_value())

func test_no_split_when_close() -> void:
	_coord.dev_instant_merge = true
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	var split_fired: Array = [false]
	_coord.split_occurred.connect(func(_sid): split_fired[0] = true)
	_coord.update_remote_chunk(Vector2i(3, 0))
	_coord.tick(0.1)
	assert_bool(split_fired[0]).is_false()

func test_peer_disconnected_clears_merged_state() -> void:
	_coord.dev_instant_merge = true
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	assert_bool(_coord.is_merged()).is_true()
	_coord.on_peer_disconnected()
	assert_bool(_coord.is_merged()).is_false()

# --- Reconnect robustness ---

func test_merging_flag_resets_after_timeout() -> void:
	## If WebRTC never connects after webrtc_pairing_needed, _merging must reset
	## after MERGING_TIMEOUT so the coordinator can retry the next broadcast.
	_coord.dev_instant_merge = true
	## Trigger _merging = true by discovering a peer
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 0)
	assert_bool(_coord._merging).is_true()
	## Tick past timeout
	_coord.tick(_coord.MERGING_TIMEOUT + 0.1)
	assert_bool(_coord._merging).is_false()

func test_merging_flag_not_reset_before_timeout() -> void:
	_coord.dev_instant_merge = true
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 0)
	assert_bool(_coord._merging).is_true()
	_coord.tick(_coord.MERGING_TIMEOUT - 0.5)
	assert_bool(_coord._merging).is_true()

func test_reconnect_possible_after_timeout() -> void:
	## After timeout resets _merging, a new peer discovery must re-arm the bridge.
	_coord.dev_instant_merge = true
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 0)
	_coord.tick(_coord.MERGING_TIMEOUT + 0.1)
	## Now _merging is false — a second discovery should re-emit webrtc_pairing_needed
	var emitted: Array = [0]
	_coord.webrtc_pairing_needed.connect(func(_k, _o): emitted[0] += 1)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 0)
	assert_int(emitted[0]).is_equal(1)

func test_successful_connect_clears_merging_timer() -> void:
	## on_peer_connected must clear _merging so the timeout branch never fires late.
	_coord.dev_instant_merge = true
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 0)
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	assert_bool(_coord._merging).is_false()
	assert_bool(_coord.is_merged()).is_true()
	## Ticking past what would have been the timeout must not clear merged state
	_coord.tick(_coord.MERGING_TIMEOUT + 1.0)
	assert_bool(_coord.is_merged()).is_true()

# ---------------------------------------------------------------------------
# Phase 0d-ii: island lifecycle wiring
# ---------------------------------------------------------------------------
#
# The clock-phase exchange runs on top of the existing on_peer_connected /
# _do_split path. These tests use inject_remote_clock_phase() to simulate the
# inbound RPC (real RPC requires a MultiplayerAPI; the unit suite has none).
# IslandRegistry is the live autoload, so each test scrubs side-effect islands
# in after_test().

func test_merged_island_id_is_deterministic_and_sorted() -> void:
	# Both peers must compute the same merged_id by sorting the two session ids.
	_coord.session_id = "zzz_local"
	_coord._remote_session_id = "aaa_remote"
	# Internal helper: sorted alphabetically → aaa_remote < zzz_local
	assert_str(_coord._merged_island_id()).is_equal("merge:aaa_remote:zzz_local")
	# Other ordering, same result
	_coord.session_id = "aaa_remote"
	_coord._remote_session_id = "zzz_local"
	assert_str(_coord._merged_island_id()).is_equal("merge:aaa_remote:zzz_local")

func test_split_island_id_is_session_scoped() -> void:
	_coord.session_id = "peer-X"
	assert_str(_coord._split_island_id()).is_equal("solo:peer-X")

func test_on_peer_connected_alone_does_not_begin_island_merge() -> void:
	# merge_ready arrives but the remote-phase RPC hasn't yet — no transition.
	_coord.dev_instant_merge = true
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	assert_bool(IslandRegistry.is_merging()).is_false()

func test_on_peer_connected_then_remote_phase_begins_island_merge() -> void:
	# Pin local clock to total_phase 0.0; remote sends 0.5 → local is lagging
	# → IslandRegistry should start a transition with the active clock
	# accelerating.
	_coord.dev_instant_merge = true
	var clock = IslandRegistry.active_island().clock
	clock._wall_time_override = 0.0
	clock._time_offset = 0.0
	clock.resync_phase()
	# Make the transition short so subsequent tests don't have to wait.
	_coord.merge_transition_seconds = 1.0
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	_coord.inject_remote_clock_phase(0.5)
	assert_bool(IslandRegistry.is_merging()).is_true()
	assert_bool(clock.is_accelerating()).is_true()

func test_remote_phase_before_merge_ready_waits_for_handshake() -> void:
	# RPC arrives before merge_ready (race) — must NOT begin the transition.
	# Once on_peer_connected fires, the deferred phase is consumed.
	_coord.dev_instant_merge = true
	_coord.merge_transition_seconds = 1.0
	_coord.inject_remote_clock_phase(0.5)
	assert_bool(IslandRegistry.is_merging()).is_false()
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	assert_bool(IslandRegistry.is_merging()).is_true()

func test_process_drives_island_tick_merge_during_transition() -> void:
	# After begin_merge, _process should call IslandRegistry.tick_merge so the
	# accelerating clock advances. We verify by driving wall time forward and
	# observing the active clock's phase advance.
	_coord.dev_instant_merge = true
	var clock = IslandRegistry.active_island().clock
	clock._wall_time_override = 0.0
	clock._time_offset = 0.0
	clock.resync_phase()
	_coord.merge_transition_seconds = 1.0
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	_coord.inject_remote_clock_phase(0.5)
	# Halfway through wall time → halfway through ramp → phase 0.25
	clock._wall_time_override = 0.5
	_coord.tick(0.5)
	assert_float(clock.phase_fraction()).is_equal_approx(0.25, 0.01)
	# Past the ramp end → completion → swapped to merged island
	clock._wall_time_override = 1.5
	_coord.tick(0.1)
	assert_bool(IslandRegistry.is_merging()).is_false()
	assert_str(IslandRegistry.active_island().id).starts_with("merge:")

func test_split_calls_island_registry_split_from_merge() -> void:
	# After a clean merge + completed transition, _do_split (via
	# on_peer_disconnected) must fork a fresh solo: island and swap to it.
	_coord.dev_instant_merge = true
	var clock = IslandRegistry.active_island().clock
	clock._wall_time_override = 0.0
	clock._time_offset = 0.0
	clock.resync_phase()
	_coord.merge_transition_seconds = 1.0
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	_coord.inject_remote_clock_phase(0.5)
	clock._wall_time_override = 1.5
	_coord.tick(0.1)
	assert_str(IslandRegistry.active_island().id).starts_with("merge:")
	# Now disconnect — must swap to solo:aaa_local.
	_coord.on_peer_disconnected()
	assert_str(IslandRegistry.active_island().id).is_equal("solo:aaa_local")
