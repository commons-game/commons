## Integration test: FreenetPresenceService + FreenetSignaling → freeland-dev-proxy.
##
## Starts the dev proxy as a subprocess, then drives real WebSocket connections
## through it to verify:
##   1. Lobby round-trip  (LobbyPut → LobbyGet → callback fires)
##   2. Pairing round-trip (PairingPublishOffer + PairingPublishAnswer → pairing_received)
##
## Prerequisites: build the dev proxy once before running:
##   cd backend/freenet && ~/.cargo/bin/cargo build --bin freeland-dev-proxy
##
## The proxy binary path is inferred from the project root.
extends GdUnitTestSuite

const FreenetPresenceServiceScript := preload("res://networking/FreenetPresenceService.gd")
const FreenetSignalingScript        := preload("res://networking/FreenetSignaling.gd")

## PID of the dev proxy subprocess — killed in after_test().
var _proxy_pid: int = -1
## Nodes to free after each test.
var _nodes: Array = []

const PROXY_BINARY := "backend/freenet/target/debug/freeland-dev-proxy"
const PROXY_PORT   := 7511   ## Use 7511 so we don't collide with a real proxy on 7510
const WS_URL       := "ws://127.0.0.1:7511"
const CONNECT_WAIT := 1.5    ## seconds to wait for proxy to start accepting connections

## -----------------------------------------------------------------------
## Suite setup / teardown
## -----------------------------------------------------------------------

func before_test() -> void:
	## Start the dev proxy on a test port.
	var project_root := ProjectSettings.globalize_path("res://")
	var binary := project_root + PROXY_BINARY
	if not FileAccess.file_exists(binary):
		push_error("Dev proxy not built. Run: cd backend/freenet && ~/.cargo/bin/cargo build --bin freeland-dev-proxy")
		return

	## Pass listen address as first arg so we don't collide with a running real proxy.
	_proxy_pid = OS.create_process(binary, ["127.0.0.1:%d" % PROXY_PORT], false)
	if _proxy_pid < 0:
		push_error("Failed to start dev proxy (PID=%d)" % _proxy_pid)

func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	if _proxy_pid > 0:
		OS.kill(_proxy_pid)
		_proxy_pid = -1

func _make_presence() -> Node:
	var svc = FreenetPresenceServiceScript.new()
	svc.proxy_url = WS_URL
	add_child(svc)
	_nodes.append(svc)
	return svc

func _make_signaling() -> Node:
	var sig = FreenetSignalingScript.new()
	sig.proxy_url = WS_URL
	add_child(sig)
	_nodes.append(sig)
	return sig

## -----------------------------------------------------------------------
## Helper: wait until a condition is true, polling every 100ms.
## -----------------------------------------------------------------------
func _wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
		if condition.call():
			return true
	return false

## -----------------------------------------------------------------------
## Test 1 — Pairing round-trip (offer + answer)
## -----------------------------------------------------------------------

func test_pairing_roundtrip() -> void:
	if _proxy_pid < 0:
		assert_bool(false).override_failure_message("Dev proxy not running — skipping test").is_true()
		return

	await get_tree().create_timer(CONNECT_WAIT).timeout

	var sig_a = _make_signaling()
	var sig_b = _make_signaling()

	## Wait for both to connect.
	var both_connected := await _wait_until(
		func(): return sig_a._connected and sig_b._connected, 5.0)
	if not both_connected:
		assert_bool(false).override_failure_message("Signaling WS never connected within 5s").is_true()
		return

	var key := "alpha:beta"

	## sig_b listens for pairing updates.
	var b_received: Array = []
	sig_b.pairing_received.connect(
		func(k, state): if k == key: b_received.append(state))

	## Publish offer from sig_a.
	sig_a.publish_offer(key, "v=0\r\no=- offer-sdp", ["mid0:0:candidate1"])
	await get_tree().create_timer(0.3).timeout

	## sig_b polls.
	sig_b.get_pairing(key)
	var got_offer := await _wait_until(func(): return not b_received.is_empty(), 5.0)
	assert_bool(got_offer).override_failure_message(
		"sig_b never received offer via PairingGetOk").is_true()

	if not b_received.is_empty():
		var state: Dictionary = b_received[0]
		assert_bool(state.has("offer")).override_failure_message(
			"PairingGetOk state missing 'offer' key").is_true()

	## Now publish answer from sig_b.
	var a_received: Array = []
	sig_a.pairing_received.connect(
		func(k, state): if k == key: a_received.append(state))

	sig_b.publish_answer(key, "v=0\r\no=- answer-sdp", ["mid0:0:candidate2"])
	await get_tree().create_timer(0.3).timeout

	sig_a.get_pairing(key)
	var got_answer := await _wait_until(func(): return not a_received.is_empty(), 5.0)
	assert_bool(got_answer).override_failure_message(
		"sig_a never received answer via PairingGetOk").is_true()

	if not a_received.is_empty():
		var state: Dictionary = a_received[0]
		assert_bool(state.has("answer")).override_failure_message(
			"PairingGetOk state missing 'answer' key").is_true()

## -----------------------------------------------------------------------
## Test 3 — Two presence nodes discover each other
## -----------------------------------------------------------------------

func test_two_players_discover_each_other() -> void:
	if _proxy_pid < 0:
		assert_bool(false).override_failure_message("Dev proxy not running — skipping test").is_true()
		return

	await get_tree().create_timer(CONNECT_WAIT).timeout

	var svc_a = _make_presence()
	var svc_b = _make_presence()
	svc_a._local_player_id = "player-alpha"
	svc_b._local_player_id = "player-beta"

	var both_connected := await _wait_until(
		func(): return svc_a._connected and svc_b._connected, 5.0)
	if not both_connected:
		assert_bool(false).override_failure_message("Presence WS never connected within 5s").is_true()
		return

	## Both publish near the same chunk.
	svc_a.publish_presence("player-alpha", Vector2i(0, 0))
	svc_b.publish_presence("player-beta",  Vector2i(1, 0))

	## Both subscribe to a large area.
	var a_sees: Array = []
	var b_sees: Array = []
	svc_a.subscribe_area("sub", Vector2i(0, 0), 20,
		func(sid, _c, _i, _p): a_sees.append(sid))
	svc_b.subscribe_area("sub", Vector2i(0, 0), 20,
		func(sid, _c, _i, _p): b_sees.append(sid))

	## Force immediate poll.
	svc_a._poll_timer = svc_a.POLL_INTERVAL
	svc_b._poll_timer = svc_b.POLL_INTERVAL

	## Wait for discovery.
	var a_found_b := await _wait_until(func(): return "player-beta" in a_sees, 8.0)
	var b_found_a := await _wait_until(func(): return "player-alpha" in b_sees, 8.0)

	assert_bool(a_found_b).override_failure_message(
		"player-alpha never discovered player-beta within 8s").is_true()
	assert_bool(b_found_a).override_failure_message(
		"player-beta never discovered player-alpha within 8s").is_true()
