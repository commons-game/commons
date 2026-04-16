## Loopback WebRTC integration test.
##
## Runs two WebRTCManager instances in the same Godot process using a
## MockSignaling node that relays publish/get calls instantly (no Freenet).
## Verifies the full offer→answer→connect state machine without a real network.
##
## Expected duration: ~8–15s (ICE gather + DTLS handshake on loopback).
## If this times out, check that GdUnit4 timeout is set ≥ 30s in settings
## (GdUnit4 → Settings → Test Timeout).
##
## NOTE: WebRTC requires at least one data channel, which WebRTCMultiplayerPeer
## creates automatically via add_peer(). Both sides must call poll() each frame,
## which happens automatically because we add them to the scene tree.
extends GdUnitTestSuite

const WebRTCManagerScript := preload("res://networking/WebRTCManager.gd")

## -----------------------------------------------------------------------
## MockSignaling — same surface API as FreenetSignaling, no WebSocket.
## When either side publishes, pairing_received fires immediately so both
## managers see the update on the same frame.
## -----------------------------------------------------------------------
class MockSignaling extends Node:
	signal pairing_received(pairing_key: String, state: Dictionary)
	var _store: Dictionary = {}  ## pairing_key → {"offer": …, "answer": …}

	func publish_offer(key: String, sdp: String, ice: Array) -> void:
		if not _store.has(key):
			_store[key] = {"offer": null, "answer": null}
		_store[key]["offer"] = {
			"sdp": sdp,
			"ice_candidates": ice,
			"timestamp": Time.get_unix_time_from_system()
		}
		pairing_received.emit(key, _store[key].duplicate(true))

	func publish_answer(key: String, sdp: String, ice: Array) -> void:
		if not _store.has(key):
			_store[key] = {"offer": null, "answer": null}
		_store[key]["answer"] = {
			"sdp": sdp,
			"ice_candidates": ice,
			"timestamp": Time.get_unix_time_from_system()
		}
		pairing_received.emit(key, _store[key].duplicate(true))

	func get_pairing(key: String) -> void:
		if _store.has(key):
			pairing_received.emit(key, _store[key].duplicate(true))
		## else: no state yet — caller will retry on next POLL_INTERVAL tick

## -----------------------------------------------------------------------
## Helpers
## -----------------------------------------------------------------------

func _make_loopback_pair() -> Array:
	## Returns [offerer_mgr, answerer_mgr, mock_signaling]
	var sig = MockSignaling.new()
	add_child(sig)

	var offerer = WebRTCManagerScript.new()
	offerer.signaling = sig
	add_child(offerer)
	sig.pairing_received.connect(offerer.on_pairing_received)

	var answerer = WebRTCManagerScript.new()
	answerer.signaling = sig
	add_child(answerer)
	sig.pairing_received.connect(answerer.on_pairing_received)

	return [offerer, answerer, sig]

func _cleanup_loopback(trio: Array) -> void:
	for node in trio:
		if is_instance_valid(node):
			node.queue_free()

## -----------------------------------------------------------------------
## Tests
## -----------------------------------------------------------------------

func test_loopback_connects() -> void:
	## Full offer→ICE-gather→publish→answer→ICE-gather→publish→DTLS→connected.
	## Both peer_established signals must fire within 25 seconds.
	var trio := _make_loopback_pair()
	var offerer = trio[0] as Node
	var answerer = trio[1] as Node

	## Use a Dictionary for shared state — GDScript lambdas capture primitive
	## values (bool) by value, not by reference. Dictionaries are reference types.
	var st := {"offerer_established": false, "answerer_established": false,
			   "offerer_failed": false, "answerer_failed": false}

	offerer.peer_established.connect(func(_mp, _host): st["offerer_established"] = true)
	answerer.peer_established.connect(func(_mp, _host): st["answerer_established"] = true)
	offerer.connection_failed.connect(func(): st["offerer_failed"] = true)
	answerer.connection_failed.connect(func(): st["answerer_failed"] = true)

	var key := "loopback:test"
	offerer.start_as_offerer(key)
	answerer.start_as_answerer(key)

	## Poll every 100ms for up to 25 seconds
	var elapsed := 0.0
	const TIMEOUT := 25.0
	const TICK := 0.1
	while elapsed < TIMEOUT:
		await get_tree().create_timer(TICK).timeout
		elapsed += TICK
		if st["offerer_established"] and st["answerer_established"]:
			break
		if st["offerer_failed"] or st["answerer_failed"]:
			break

	_cleanup_loopback(trio)

	if st["offerer_failed"] or st["answerer_failed"]:
		assert_bool(false).override_failure_message(
			"WebRTC loopback failed — offerer_failed=%s answerer_failed=%s" \
			% [st["offerer_failed"], st["answerer_failed"]]).is_true()
		return

	assert_bool(st["offerer_established"]).override_failure_message(
		"Offerer never received peer_established within %.0fs" % TIMEOUT).is_true()
	assert_bool(st["answerer_established"]).override_failure_message(
		"Answerer never received peer_established within %.0fs" % TIMEOUT).is_true()

func test_loopback_wrong_key_ignored() -> void:
	## If answerer uses a different pairing key, no connection forms.
	## Both should end in FAILED after CONNECT_TIMEOUT — but for test speed
	## we just verify that cross-key pairing_received calls don't crash or
	## accidentally advance state.
	var trio := _make_loopback_pair()
	var offerer = trio[0] as Node
	var answerer = trio[1] as Node

	var st := {"established": false}
	offerer.peer_established.connect(func(_mp, _h): st["established"] = true)

	offerer.start_as_offerer("alice:bob")
	answerer.start_as_answerer("carol:dave")   ## different key

	## Wait 3 seconds — not enough to time out, but enough to confirm no
	## spurious peer_established fires for mismatched keys.
	await get_tree().create_timer(3.0).timeout

	_cleanup_loopback(trio)

	assert_bool(st["established"]).override_failure_message(
		"Offerer should NOT connect when answerer uses a different key").is_false()
