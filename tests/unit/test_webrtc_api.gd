## Verifies that the Godot 4 WebRTC API we depend on exists and has the
## expected constants/methods. Guards against version regressions without
## requiring a live network or second process.
extends GdUnitTestSuite

func test_gathering_state_complete_constant_exists() -> void:
	## GATHERING_STATE_COMPLETE must exist as an enum value on WebRTCPeerConnection
	var val: int = WebRTCPeerConnection.GATHERING_STATE_COMPLETE
	assert_int(val).is_greater_equal(0)

func test_gathering_state_new_constant_exists() -> void:
	var val: int = WebRTCPeerConnection.GATHERING_STATE_NEW
	assert_int(val).is_greater_equal(0)

func test_gathering_state_new_less_than_complete() -> void:
	## Sanity: NEW < COMPLETE in the enum ordering
	assert_int(WebRTCPeerConnection.GATHERING_STATE_NEW).is_less(
		WebRTCPeerConnection.GATHERING_STATE_COMPLETE)

func test_get_gathering_state_method_exists_and_does_not_crash() -> void:
	var conn := WebRTCPeerConnection.new()
	var state := conn.get_gathering_state()
	## Fresh connection starts in NEW state
	assert_int(state).is_equal(WebRTCPeerConnection.GATHERING_STATE_NEW)
	conn.free()

func test_webrtc_peer_connection_initialize_with_stun() -> void:
	var conn := WebRTCPeerConnection.new()
	var err := conn.initialize({
		"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]
	})
	assert_int(err).is_equal(OK)
	conn.free()

func test_webrtc_multiplayer_peer_create_server() -> void:
	var mp := WebRTCMultiplayerPeer.new()
	var err := mp.create_server()
	assert_int(err).is_equal(OK)
	mp.free()

func test_webrtc_multiplayer_peer_create_client() -> void:
	var mp := WebRTCMultiplayerPeer.new()
	var err := mp.create_client(2)
	assert_int(err).is_equal(OK)
	mp.free()
