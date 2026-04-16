## Unit tests for WebRTCManager utility logic.
## The actual WebRTC connection requires a live STUN server + network,
## so we test: pairing key derivation, ICE encoding/decoding, and the
## on_pairing_received dispatch logic in isolation.
extends GdUnitTestSuite

const WebRTCManagerScript := preload("res://networking/WebRTCManager.gd")

# ---------------------------------------------------------------------------
# Pairing key derivation
# ---------------------------------------------------------------------------

func test_pairing_key_is_alphabetically_ordered() -> void:
	var key := WebRTCManagerScript.make_pairing_key("zzz_session", "aaa_session")
	assert_str(key).is_equal("aaa_session:zzz_session")

func test_pairing_key_same_regardless_of_arg_order() -> void:
	var k1 := WebRTCManagerScript.make_pairing_key("alice", "bob")
	var k2 := WebRTCManagerScript.make_pairing_key("bob", "alice")
	assert_str(k1).is_equal(k2)

func test_pairing_key_equal_sessions_still_works() -> void:
	## Edge case: same session ID on both sides (shouldn't happen in practice,
	## but must not crash).
	var key := WebRTCManagerScript.make_pairing_key("same", "same")
	assert_str(key).is_equal("same:same")

# ---------------------------------------------------------------------------
# ICE candidate encode/decode round-trip
# ---------------------------------------------------------------------------

func _make_manager() -> Object:
	var mgr = WebRTCManagerScript.new()
	## No add_child — testing pure logic only
	return mgr

func test_ice_encode_decode_roundtrip() -> void:
	var mgr = _make_manager()
	var candidates := [
		{"mid": "audio", "index": 0, "name": "candidate:1 1 UDP 12345 192.168.1.1 55234 typ host"},
		{"mid": "video", "index": 1, "name": "candidate:2 1 UDP 12344 192.168.1.1 55235 typ host"},
	]
	var encoded: Array = mgr._encode_ice_candidates(candidates)
	assert_int(encoded.size()).is_equal(2)

	var decoded0 = mgr._decode_ice_candidate(encoded[0])
	assert_that(decoded0 != null).is_true()
	assert_str(decoded0["mid"]).is_equal("audio")
	assert_int(decoded0["index"]).is_equal(0)
	assert_str(decoded0["name"]).is_equal(candidates[0]["name"])

	var decoded1 = mgr._decode_ice_candidate(encoded[1])
	assert_str(decoded1["mid"]).is_equal("video")
	assert_int(decoded1["index"]).is_equal(1)

func test_ice_decode_invalid_returns_null() -> void:
	var mgr = _make_manager()
	assert_that(mgr._decode_ice_candidate("no-colon-here") == null).is_true()
	assert_that(mgr._decode_ice_candidate("one:only") == null).is_true()

func test_ice_encode_empty_list() -> void:
	var mgr = _make_manager()
	var result: Array = mgr._encode_ice_candidates([])
	assert_array(result).is_empty()

# ---------------------------------------------------------------------------
# on_pairing_received ignores wrong pairing key
# ---------------------------------------------------------------------------

func test_on_pairing_received_ignores_different_key() -> void:
	var mgr = _make_manager()
	mgr._pairing_key = "alice:bob"
	mgr._state = mgr.State.POLLING_OFFER
	## Different key — should not change state
	mgr.on_pairing_received("carol:dave", {"offer": {"sdp": "x", "ice_candidates": [], "timestamp": 1.0}})
	assert_int(mgr._state).is_equal(mgr.State.POLLING_OFFER)

func test_on_pairing_received_ignores_empty_offer() -> void:
	var mgr = _make_manager()
	mgr._pairing_key = "alice:bob"
	mgr._state = mgr.State.POLLING_OFFER
	## Correct key but no offer yet
	mgr.on_pairing_received("alice:bob", {"offer": null})
	assert_int(mgr._state).is_equal(mgr.State.POLLING_OFFER)

func test_on_pairing_received_ignores_empty_answer() -> void:
	var mgr = _make_manager()
	mgr._pairing_key = "alice:bob"
	mgr._state = mgr.State.POLLING_ANSWER
	## Correct key but answer not yet written
	mgr.on_pairing_received("alice:bob", {"offer": {"sdp": "o", "ice_candidates": [], "timestamp": 1.0}})
	## Still POLLING_ANSWER because no "answer" key
	assert_int(mgr._state).is_equal(mgr.State.POLLING_ANSWER)
