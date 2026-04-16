## Unit tests for FreenetPresenceService.
## These tests drive _process_lobby_state directly — no WebSocket required.
## The WS layer is integration-tested separately against a running proxy.
extends GdUnitTestSuite

const FreenetPresenceScript := preload("res://networking/FreenetPresenceService.gd")

var _svc: Object

func before_test() -> void:
	_svc = FreenetPresenceScript.new()
	# Skip WebSocket connect in unit tests
	_svc._connected = true
	_svc._local_player_id = "local-session"

func after_test() -> void:
	if is_instance_valid(_svc):
		_svc.free()

# ---------------------------------------------------------------------------
# _process_lobby_state — core dispatch logic
# ---------------------------------------------------------------------------

func test_callback_fires_for_nearby_player() -> void:
	var fired: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 10,
		func(sid, chunk, ip, port): fired.append(sid))
	var now := Time.get_unix_time_from_system()
	_svc._process_lobby_state({
		"entries": {
			"remote-player": {
				"session_id": "remote-player",
				"chunk_x": 3, "chunk_y": 3,
				"ip": "192.168.1.2", "enet_port": 7777,
				"timestamp": now
			}
		}
	})
	assert_array(fired).contains_exactly(["remote-player"])

func test_callback_not_fired_for_distant_player() -> void:
	var fired: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 5,
		func(sid, _c, _i, _p): fired.append(sid))
	var now := Time.get_unix_time_from_system()
	_svc._process_lobby_state({
		"entries": {
			"far-player": {
				"session_id": "far-player",
				"chunk_x": 100, "chunk_y": 100,
				"ip": "192.168.1.3", "enet_port": 7777,
				"timestamp": now
			}
		}
	})
	assert_array(fired).is_empty()

func test_self_entry_is_ignored() -> void:
	var fired: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 50,
		func(sid, _c, _i, _p): fired.append(sid))
	var now := Time.get_unix_time_from_system()
	_svc._process_lobby_state({
		"entries": {
			"local-session": {
				"session_id": "local-session",
				"chunk_x": 0, "chunk_y": 0,
				"ip": "127.0.0.1", "enet_port": 7777,
				"timestamp": now
			}
		}
	})
	assert_array(fired).is_empty()

func test_stale_entry_is_ignored() -> void:
	var fired: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 50,
		func(sid, _c, _i, _p): fired.append(sid))
	var stale_ts := Time.get_unix_time_from_system() - (_svc.PRESENCE_TTL + 10.0)
	_svc._process_lobby_state({
		"entries": {
			"ghost-player": {
				"session_id": "ghost-player",
				"chunk_x": 1, "chunk_y": 1,
				"ip": "192.168.1.4", "enet_port": 7777,
				"timestamp": stale_ts
			}
		}
	})
	assert_array(fired).is_empty()

func test_callback_receives_correct_ip_and_port() -> void:
	var received: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 20,
		func(_sid, _chunk, ip, port): received.append({"ip": ip, "port": port}))
	var now := Time.get_unix_time_from_system()
	_svc._process_lobby_state({
		"entries": {
			"remote": {
				"session_id": "remote",
				"chunk_x": 0, "chunk_y": 0,
				"ip": "10.0.0.42", "enet_port": 9999,
				"timestamp": now
			}
		}
	})
	assert_int(received.size()).is_equal(1)
	assert_str(received[0]["ip"]).is_equal("10.0.0.42")
	assert_int(received[0]["port"]).is_equal(9999)

func test_multiple_subscriptions_all_fire() -> void:
	var fired_a: Array = []
	var fired_b: Array = []
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 10,
		func(sid, _c, _i, _p): fired_a.append(sid))
	_svc.subscribe_area("sub_b", Vector2i(0, 0), 10,
		func(sid, _c, _i, _p): fired_b.append(sid))
	var now := Time.get_unix_time_from_system()
	_svc._process_lobby_state({
		"entries": {
			"remote": {
				"session_id": "remote", "chunk_x": 2, "chunk_y": 2,
				"ip": "192.168.1.5", "enet_port": 7777, "timestamp": now
			}
		}
	})
	assert_array(fired_a).contains_exactly(["remote"])
	assert_array(fired_b).contains_exactly(["remote"])

func test_unsubscribe_stops_callbacks() -> void:
	var fired: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 50,
		func(sid, _c, _i, _p): fired.append(sid))
	_svc.unsubscribe_area("sub")
	var now := Time.get_unix_time_from_system()
	_svc._process_lobby_state({
		"entries": {
			"remote": {
				"session_id": "remote", "chunk_x": 0, "chunk_y": 0,
				"ip": "192.168.1.6", "enet_port": 7777, "timestamp": now
			}
		}
	})
	assert_array(fired).is_empty()

func test_chebyshev_boundary_exactly_at_radius() -> void:
	## Chebyshev distance = max(|dx|, |dy|). A player at (5,3) from (0,0) = 5.
	## With radius=5 they should trigger; radius=4 they should not.
	var fired: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 5,
		func(sid, _c, _i, _p): fired.append(sid))
	var now := Time.get_unix_time_from_system()
	_svc._process_lobby_state({
		"entries": {
			"edge": {
				"session_id": "edge", "chunk_x": 5, "chunk_y": 3,
				"ip": "192.168.1.7", "enet_port": 7777, "timestamp": now
			}
		}
	})
	assert_array(fired).contains_exactly(["edge"])

func test_empty_lobby_fires_no_callbacks() -> void:
	var fired: Array = []
	_svc.subscribe_area("sub", Vector2i(0, 0), 50,
		func(sid, _c, _i, _p): fired.append(sid))
	_svc._process_lobby_state({"entries": {}})
	assert_array(fired).is_empty()
