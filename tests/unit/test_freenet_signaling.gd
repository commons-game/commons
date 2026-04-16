## Unit tests for FreenetSignaling message parsing logic.
## Tests drive _on_message directly — no WebSocket required.
extends GdUnitTestSuite

const FreenetSignalingScript := preload("res://networking/FreenetSignaling.gd")

var _sig: Object

func before_test() -> void:
	_sig = FreenetSignalingScript.new()
	_sig._connected = true  ## skip WS connect in unit tests

func after_test() -> void:
	if is_instance_valid(_sig):
		_sig.free()

func test_pairing_received_fires_on_get_ok() -> void:
	var received: Array = []
	_sig.pairing_received.connect(func(key, state): received.append({"key": key, "state": state}))

	var state_dict := {
		"pairing_key": "alice:bob",
		"offer": {"sdp": "offer-sdp", "ice_candidates": ["mid:0:cand"], "timestamp": 100.0},
		"answer": null,
		"created_at": 100.0
	}
	_sig._on_message(JSON.stringify({
		"op": "PairingGetOk",
		"pairing_key": "alice:bob",
		"state_json": JSON.stringify(state_dict)
	}))

	assert_int(received.size()).is_equal(1)
	assert_str(received[0]["key"]).is_equal("alice:bob")
	assert_that(received[0]["state"].has("offer")).is_true()

func test_pairing_publish_ok_does_not_emit() -> void:
	var received: Array = []
	_sig.pairing_received.connect(func(k, s): received.append(k))
	_sig._on_message(JSON.stringify({"op": "PairingPublishOk", "pairing_key": "alice:bob"}))
	assert_array(received).is_empty()

func test_pairing_get_not_found_does_not_emit() -> void:
	var received: Array = []
	_sig.pairing_received.connect(func(k, s): received.append(k))
	_sig._on_message(JSON.stringify({"op": "PairingGetNotFound", "pairing_key": "alice:bob"}))
	assert_array(received).is_empty()

func test_invalid_json_does_not_crash() -> void:
	## Should not crash or emit anything
	_sig._on_message("not valid json {{{")
	## Passes if no exception thrown

func test_error_response_does_not_emit() -> void:
	var received: Array = []
	_sig.pairing_received.connect(func(k, s): received.append(k))
	_sig._on_message(JSON.stringify({"op": "Error", "message": "something went wrong"}))
	assert_array(received).is_empty()

func test_pending_requests_buffered_before_connect() -> void:
	_sig._connected = false
	_sig.get_pairing("alice:bob")
	assert_int(_sig._pending.size()).is_equal(1)
	var parsed = JSON.parse_string(_sig._pending[0])
	assert_str(parsed.get("op", "")).is_equal("PairingGet")
	assert_str(parsed.get("pairing_key", "")).is_equal("alice:bob")
