## WebRTCManager — manages the WebRTC connection lifecycle for one pairing.
##
## Uses non-trickle ICE: gathers all ICE candidates locally first, then
## publishes offer/answer + all candidates in a single write to the Freenet
## pairing contract. This trades a few seconds of setup latency for much
## simpler signaling logic (no trickle ICE state machine).
##
## STUN server: stun.l.google.com:19302 (free, no account needed).
## TURN: not implemented — symmetric NAT connections (~20% of cases) will fail.
## TODO (step 2.5): add TURN for full coverage.
##
## Usage (World.gd):
##   var mgr = WebRTCManager.new()
##   add_child(mgr)
##   mgr.signaling = _signaling_node
##   # Offerer (lower session ID):
##   mgr.start_as_offerer(pairing_key, my_peer_id=1)
##   # Answerer:
##   mgr.start_as_answerer(pairing_key, remote_peer_id=1)
##
## Emits:
##   peer_established(mp: WebRTCMultiplayerPeer, i_am_host: bool)
##     — fires when connection is fully set up; World sets multiplayer.multiplayer_peer = mp
##   connection_failed — fires after CONNECT_TIMEOUT with no connection
extends Node

signal peer_established(mp: WebRTCMultiplayerPeer, i_am_host: bool)
signal connection_failed

const STUN_SERVERS := [{"urls": ["stun:stun.l.google.com:19302"]}]
const GATHER_TIMEOUT  := 8.0    ## max seconds to wait for ICE gathering
const POLL_INTERVAL   := 2.0    ## seconds between PairingGet polls
const CONNECT_TIMEOUT := 30.0   ## give up after this many seconds total

## Set by World before starting.
var signaling: Node = null

## State machine
enum State { IDLE, GATHERING, POLLING_OFFER, PUBLISHING_OFFER,
             POLLING_ANSWER, PUBLISHING_ANSWER, CONNECTING, DONE, FAILED }
var _state: State = State.IDLE

var _pairing_key: String = ""
var _i_am_offerer: bool = false
var _my_multiplayer_id: int = 0
var _remote_multiplayer_id: int = 0

var _mp: WebRTCMultiplayerPeer = null
var _conn: WebRTCPeerConnection = null

var _local_sdp: String = ""
var _local_sdp_type: String = ""
var _ice_candidates: Array = []   ## Array of {mid, index, name}

var _poll_timer: float = 0.0
var _gather_timer: float = 0.0
var _total_timer: float = 0.0

## Start as the offerer (lower session ID alphabetically).
## `my_peer_id` should be 1 (host in Godot's multiplayer model).
func start_as_offerer(pairing_key: String, my_peer_id: int = 1) -> void:
	_pairing_key = pairing_key
	_i_am_offerer = true
	_my_multiplayer_id = my_peer_id
	_remote_multiplayer_id = 2 if my_peer_id == 1 else 1
	_setup_multiplayer_peer(true)
	_conn.create_offer()
	_state = State.GATHERING
	print("WebRTCManager: offerer — gathering ICE for key=%s" % pairing_key)

## Start as the answerer (higher session ID alphabetically).
## Polls the pairing contract until the offer appears.
func start_as_answerer(pairing_key: String, my_peer_id: int = 2) -> void:
	_pairing_key = pairing_key
	_i_am_offerer = false
	_my_multiplayer_id = my_peer_id
	_remote_multiplayer_id = 1 if my_peer_id == 2 else 2
	_setup_multiplayer_peer(false)
	_state = State.POLLING_OFFER
	_poll_timer = POLL_INTERVAL  # poll immediately
	print("WebRTCManager: answerer — polling for offer, key=%s" % pairing_key)

func _process(delta: float) -> void:
	if _state == State.IDLE or _state == State.DONE or _state == State.FAILED:
		return

	# Poll the WebRTC connection
	if _mp != null:
		_mp.poll()

	_total_timer += delta

	if _total_timer >= CONNECT_TIMEOUT:
		_fail("timed out after %.0fs" % CONNECT_TIMEOUT)
		return

	match _state:
		State.GATHERING:
			_gather_timer += delta
			_try_complete_gathering()

		State.POLLING_OFFER:
			_poll_timer += delta
			if _poll_timer >= POLL_INTERVAL:
				_poll_timer = 0.0
				signaling.get_pairing(_pairing_key)

		State.POLLING_ANSWER:
			_poll_timer += delta
			if _poll_timer >= POLL_INTERVAL:
				_poll_timer = 0.0
				signaling.get_pairing(_pairing_key)

		State.CONNECTING:
			# Check if the WebRTCMultiplayerPeer is connected
			if _mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				_state = State.DONE
				print("WebRTCManager: connected!")
				peer_established.emit(_mp, _i_am_offerer)

# ---------------------------------------------------------------------------
# Called by World when FreenetSignaling emits pairing_received
# ---------------------------------------------------------------------------

func on_pairing_received(pairing_key: String, state: Dictionary) -> void:
	if pairing_key != _pairing_key:
		return

	match _state:
		State.POLLING_OFFER:
			var offer = state.get("offer", null)
			if offer == null or not offer is Dictionary:
				return  # no offer yet — keep polling
			_apply_remote_offer(offer)

		State.POLLING_ANSWER:
			var answer = state.get("answer", null)
			if answer == null or not answer is Dictionary:
				return  # answer not yet written — keep polling
			_apply_remote_answer(answer)

# ---------------------------------------------------------------------------
# WebRTC peer connection setup
# ---------------------------------------------------------------------------

func _setup_multiplayer_peer(i_am_host: bool) -> void:
	_mp = WebRTCMultiplayerPeer.new()
	if i_am_host:
		_mp.create_server()
	else:
		_mp.create_client(_my_multiplayer_id)

	_conn = WebRTCPeerConnection.new()
	var err := _conn.initialize({"iceServers": STUN_SERVERS})
	if err != OK:
		push_error("WebRTCManager: failed to initialize peer connection (err %d)" % err)
		return

	_conn.session_description_created.connect(_on_sdp_created)
	_conn.ice_candidate_created.connect(_on_ice_candidate)

	_mp.add_peer(_conn, _remote_multiplayer_id)

# ---------------------------------------------------------------------------
# Signal handlers from WebRTCPeerConnection
# ---------------------------------------------------------------------------

func _on_sdp_created(type: String, sdp: String) -> void:
	_conn.set_local_description(type, sdp)
	_local_sdp = sdp
	_local_sdp_type = type
	print("WebRTCManager: local description set (type=%s)" % type)

func _on_ice_candidate(mid: String, index: int, name: String) -> void:
	_ice_candidates.append({"mid": mid, "index": index, "name": name})

# ---------------------------------------------------------------------------
# ICE gathering completion detection (polled — no signal in Godot 4)
# ---------------------------------------------------------------------------

func _try_complete_gathering() -> void:
	if _conn == null:
		return
	var gathering_state := _conn.get_gathering_state()
	var timed_out := _gather_timer >= GATHER_TIMEOUT

	if gathering_state == WebRTCPeerConnection.GATHERING_STATE_COMPLETE or timed_out:
		if timed_out and gathering_state != WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			push_warning("WebRTCManager: ICE gather timeout — publishing with %d candidates" \
				% _ice_candidates.size())

		if _local_sdp.is_empty():
			_fail("no SDP after ICE gathering completed")
			return

		var ice_strings := _encode_ice_candidates(_ice_candidates)
		if _i_am_offerer:
			_state = State.PUBLISHING_OFFER
			signaling.publish_offer(_pairing_key, _local_sdp, ice_strings)
			_state = State.POLLING_ANSWER
			_poll_timer = POLL_INTERVAL  # poll immediately
			print("WebRTCManager: offer published, polling for answer")
		else:
			_state = State.PUBLISHING_ANSWER
			signaling.publish_answer(_pairing_key, _local_sdp, ice_strings)
			_state = State.CONNECTING
			print("WebRTCManager: answer published, waiting for connection")

# ---------------------------------------------------------------------------
# Applying remote descriptions
# ---------------------------------------------------------------------------

func _apply_remote_offer(offer: Dictionary) -> void:
	var sdp: String = offer.get("sdp", "")
	var ice_strings: Array = offer.get("ice_candidates", [])
	if sdp.is_empty():
		return

	print("WebRTCManager: received offer, creating answer")
	_conn.set_remote_description("offer", sdp)
	# set_remote_description triggers session_description_created with "answer"
	# which calls _on_sdp_created → sets _local_sdp

	# Apply offerer's ICE candidates
	for encoded in ice_strings:
		var parts = _decode_ice_candidate(encoded)
		if parts != null:
			_conn.add_ice_candidate(parts.mid, parts.index, parts.name)

	# Now wait for ICE gathering of our answer
	_state = State.GATHERING
	_gather_timer = 0.0
	_ice_candidates = []
	print("WebRTCManager: gathering ICE for answer")

func _apply_remote_answer(answer: Dictionary) -> void:
	var sdp: String = answer.get("sdp", "")
	var ice_strings: Array = answer.get("ice_candidates", [])
	if sdp.is_empty():
		return

	print("WebRTCManager: received answer, applying")
	_conn.set_remote_description("answer", sdp)

	# Apply answerer's ICE candidates
	for encoded in ice_strings:
		var parts = _decode_ice_candidate(encoded)
		if parts != null:
			_conn.add_ice_candidate(parts.mid, parts.index, parts.name)

	_state = State.CONNECTING
	print("WebRTCManager: answer applied, waiting for connection")

# ---------------------------------------------------------------------------
# ICE candidate encoding/decoding  ("mid:index:sdp" format)
# ---------------------------------------------------------------------------

func _encode_ice_candidates(candidates: Array) -> Array:
	var result := []
	for c in candidates:
		result.append("%s:%d:%s" % [c.mid, c.index, c.name])
	return result

func _decode_ice_candidate(encoded: String):
	## Returns {mid, index, name} or null on parse failure.
	var colon1 := encoded.find(":")
	if colon1 < 0:
		return null
	var colon2 := encoded.find(":", colon1 + 1)
	if colon2 < 0:
		return null
	return {
		"mid":   encoded.left(colon1),
		"index": int(encoded.substr(colon1 + 1, colon2 - colon1 - 1)),
		"name":  encoded.substr(colon2 + 1)
	}

# ---------------------------------------------------------------------------
# Failure
# ---------------------------------------------------------------------------

func _fail(reason: String) -> void:
	push_error("WebRTCManager: failed — %s" % reason)
	_state = State.FAILED
	connection_failed.emit()

## Compute the pairing key for two session IDs deterministically.
## Both sides get the same key regardless of who calls it.
static func make_pairing_key(sid_a: String, sid_b: String) -> String:
	if sid_a < sid_b:
		return sid_a + ":" + sid_b
	return sid_b + ":" + sid_a
