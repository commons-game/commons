## FreenetSignaling — reads and writes the Freenet pairing contract for WebRTC signaling.
##
## Used by WebRTCManager to exchange SDP offer/answer and ICE candidates
## between two players. Each pairing gets its own Freenet contract instance
## keyed by "{min_sid}:{max_sid}".
##
## Uses a separate WebSocket connection from FreenetPresenceService so the
## presence polling and signaling don't interfere with each other.
##
## Emits:
##   pairing_received(pairing_key: String, state: Dictionary)
##     — fired when PairingGetOk arrives; state has keys "offer" and/or "answer"
##       each with {"sdp", "ice_candidates", "timestamp"}
extends Node

signal pairing_received(pairing_key: String, state: Dictionary)

const RECONNECT_DELAY := 3.0

var proxy_url: String = "ws://127.0.0.1:7510"

var _ws: WebSocketPeer = null
var _connected: bool = false
var _reconnect_timer: float = 0.0
var _pending: Array = []  ## requests queued before WS connects

func _ready() -> void:
	_connect_ws()

func _connect_ws() -> void:
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(proxy_url)

func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				for msg in _pending:
					_ws.send_text(msg)
				_pending.clear()
			while _ws.get_available_packet_count() > 0:
				_on_message(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				push_warning("FreenetSignaling: WS closed — reconnecting")
				_connected = false
			_reconnect_timer += delta
			if _reconnect_timer >= RECONNECT_DELAY:
				_reconnect_timer = 0.0
				_connect_ws()

## Publish this player's SDP offer and ICE candidates to the pairing contract.
func publish_offer(pairing_key: String, sdp: String, ice_candidates: Array) -> void:
	_send({
		"op": "PairingPublishOffer",
		"pairing_key": pairing_key,
		"sdp": sdp,
		"ice_candidates": ice_candidates,
		"timestamp": Time.get_unix_time_from_system()
	})

## Publish this player's SDP answer and ICE candidates to the pairing contract.
func publish_answer(pairing_key: String, sdp: String, ice_candidates: Array) -> void:
	_send({
		"op": "PairingPublishAnswer",
		"pairing_key": pairing_key,
		"sdp": sdp,
		"ice_candidates": ice_candidates,
		"timestamp": Time.get_unix_time_from_system()
	})

## Request the current pairing state. Result arrives via pairing_received signal.
func get_pairing(pairing_key: String) -> void:
	_send({"op": "PairingGet", "pairing_key": pairing_key})

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _send(data: Dictionary) -> void:
	var text := JSON.stringify(data)
	if _connected:
		_ws.send_text(text)
	else:
		_pending.append(text)

func _on_message(text: String) -> void:
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		return
	match data.get("op", ""):
		"PairingGetOk":
			var key: String = data.get("pairing_key", "")
			var state = JSON.parse_string(data.get("state_json", "{}"))
			if state is Dictionary:
				pairing_received.emit(key, state)
		"PairingPublishOk":
			pass  # fire and forget
		"PairingGetNotFound":
			pass  # no offer yet — caller will retry
		"Error":
			push_warning("FreenetSignaling: proxy error — %s" % data.get("message", "?"))
