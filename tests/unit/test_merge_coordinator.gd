## Unit tests for MergeCoordinator.
## Drives _on_peer_discovered directly — no UDP or ENet required.
extends GdUnitTestSuite

const MergeCoordinatorScript := preload("res://networking/MergeCoordinator.gd")

var _coord: Object
var _to_free: Array = []

func before_test() -> void:
	_coord = MergeCoordinatorScript.new()
	_coord.session_id = "aaa_local"   # lower than "bbb_remote" → I host
	_to_free.append(_coord)

func after_test() -> void:
	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()

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

# --- Host/client role ---

func test_lower_session_id_is_host() -> void:
	_coord.dev_instant_merge = true
	var emitted: Array = []
	_coord.connection_needed.connect(func(ip, port, i_am_host): emitted.append(i_am_host))
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 7777)
	assert_that(emitted.size()).is_equal(1)
	assert_bool(emitted[0]).is_true()   # aaa < bbb → I host

func test_higher_session_id_is_client() -> void:
	_coord.session_id = "zzz_local"   # higher than "aaa_remote"
	_coord.dev_instant_merge = true
	var emitted: Array = []
	_coord.connection_needed.connect(func(ip, port, i_am_host): emitted.append(i_am_host))
	_coord._on_peer_discovered("aaa_remote", Vector2i(1, 0), "192.168.1.2", 7777)
	assert_bool(emitted[0]).is_false()  # zzz > aaa → I join

# --- Bridge gate ---

func test_zero_pressure_does_not_emit_connection_needed() -> void:
	# At pressure=0 the randf() < pressure gate always fails
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	# Tick zero delta — pressure stays 0
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_false()

func test_full_pressure_always_emits_connection_needed() -> void:
	_coord.dev_instant_merge = true  # sets pressure to 1.0
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_true()

func test_duplicate_discovery_ignored_while_merging() -> void:
	_coord.dev_instant_merge = true
	var emitted: Array = [0]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] += 1)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
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
	## If ENet never connects after connection_needed, _merging must reset
	## after MERGING_TIMEOUT so the coordinator can retry the next broadcast.
	_coord.dev_instant_merge = true
	## Trigger _merging = true by discovering a peer
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 7777)
	assert_bool(_coord._merging).is_true()
	## Tick past timeout
	_coord.tick(_coord.MERGING_TIMEOUT + 0.1)
	assert_bool(_coord._merging).is_false()

func test_merging_flag_not_reset_before_timeout() -> void:
	## _merging must stay true until the timeout elapses — not cleared prematurely.
	_coord.dev_instant_merge = true
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 7777)
	assert_bool(_coord._merging).is_true()
	## Tick to just before timeout
	_coord.tick(_coord.MERGING_TIMEOUT - 0.5)
	assert_bool(_coord._merging).is_true()

func test_reconnect_possible_after_timeout() -> void:
	## After timeout resets _merging, a new peer discovery must re-arm the bridge.
	_coord.dev_instant_merge = true
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 7777)
	_coord.tick(_coord.MERGING_TIMEOUT + 0.1)
	## Now _merging is false — a second discovery should re-emit connection_needed
	var emitted: Array = [0]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] += 1)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 7777)
	assert_int(emitted[0]).is_equal(1)

func test_successful_connect_clears_merging_timer() -> void:
	## on_peer_connected must clear _merging so the timeout branch never fires late.
	_coord.dev_instant_merge = true
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.2", 7777)
	_coord.on_peer_connected("bbb_remote", Vector2i(1, 0))
	assert_bool(_coord._merging).is_false()
	assert_bool(_coord.is_merged()).is_true()
	## Ticking past what would have been the timeout must not clear merged state
	_coord.tick(_coord.MERGING_TIMEOUT + 1.0)
	assert_bool(_coord.is_merged()).is_true()
