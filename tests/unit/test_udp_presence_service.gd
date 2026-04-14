## Unit tests for UDPPresenceService.
## Tests drive _on_packet_received directly — no real UDP sockets needed.
extends GdUnitTestSuite

const UDPPresenceScript := preload("res://networking/UDPPresenceService.gd")

var _svc: Object

func before_test() -> void:
	_svc = UDPPresenceScript.new()

func after_test() -> void:
	_svc.free()

# --- Subscription / callback dispatch ---

func test_in_range_presence_fires_callback() -> void:
	var received: Array = []
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 10,
		func(sid, chunk, ip, port): received.append({"sid": sid, "chunk": chunk}))
	_svc._local_player_id = "player_a"  # so we don't self-filter
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":3,"y":0,"enet_port":7777}', "192.168.1.2")
	assert_that(received.size()).is_equal(1)
	assert_that(received[0]["sid"]).is_equal("remote_b")
	assert_that(received[0]["chunk"]).is_equal(Vector2i(3, 0))

func test_out_of_range_presence_does_not_fire() -> void:
	var received: Array = []
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 5,
		func(_s, _c, _i, _p): received.append(true))
	_svc._local_player_id = "player_a"
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":50,"y":50,"enet_port":7777}', "192.168.1.2")
	assert_that(received.size()).is_equal(0)

func test_own_session_id_filtered_out() -> void:
	var received: Array = []
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("player_a", Vector2i(0, 0), 100,
		func(_s, _c, _i, _p): received.append(true))
	_svc._on_packet_received(
		'{"session_id":"player_a","x":1,"y":0,"enet_port":7777}', "127.0.0.1")
	assert_that(received.size()).is_equal(0)

func test_enet_port_passed_to_callback() -> void:
	var got_port: Array = [0]
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 20,
		func(_s, _c, _i, p): got_port[0] = p)
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":2,"y":0,"enet_port":9999}', "10.0.0.5")
	assert_that(got_port[0]).is_equal(9999)

func test_sender_ip_passed_to_callback() -> void:
	var got_ip: Array = [""]
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 20,
		func(_s, _c, ip, _p): got_ip[0] = ip)
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":0,"y":0,"enet_port":7777}', "10.0.0.5")
	assert_that(got_ip[0]).is_equal("10.0.0.5")

func test_malformed_packet_is_no_op() -> void:
	var fired: Array = [false]
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 100,
		func(_s, _c, _i, _p): fired[0] = true)
	_svc._on_packet_received("not json at all }{", "1.2.3.4")
	assert_bool(fired[0]).is_false()

func test_multiple_subscribers_in_range_all_fire() -> void:
	var calls: Array = [0]
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("sub_1", Vector2i(0, 0), 10,
		func(_s, _c, _i, _p): calls[0] += 1)
	_svc.subscribe_area("sub_2", Vector2i(0, 0), 10,
		func(_s, _c, _i, _p): calls[0] += 1)
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":1,"y":0,"enet_port":7777}', "1.2.3.4")
	assert_that(calls[0]).is_equal(2)

func test_unsubscribe_stops_callbacks() -> void:
	var calls: Array = [0]
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 100,
		func(_s, _c, _i, _p): calls[0] += 1)
	_svc.unsubscribe_area("sub_a")
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":0,"y":0,"enet_port":7777}', "1.2.3.4")
	assert_that(calls[0]).is_equal(0)

func test_chebyshev_boundary_exact_radius_fires() -> void:
	var fired: Array = [false]
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 5,
		func(_s, _c, _i, _p): fired[0] = true)
	# Chebyshev dist from (0,0) to (5,3) = max(5,3) = 5 — exactly on boundary
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":5,"y":3,"enet_port":7777}', "1.2.3.4")
	assert_bool(fired[0]).is_true()

func test_chebyshev_one_past_boundary_does_not_fire() -> void:
	var fired: Array = [false]
	_svc._local_player_id = "player_a"
	_svc.subscribe_area("sub_a", Vector2i(0, 0), 5,
		func(_s, _c, _i, _p): fired[0] = true)
	# Chebyshev dist from (0,0) to (6,0) = 6 — one past boundary
	_svc._on_packet_received(
		'{"session_id":"remote_b","x":6,"y":0,"enet_port":7777}', "1.2.3.4")
	assert_bool(fired[0]).is_false()
