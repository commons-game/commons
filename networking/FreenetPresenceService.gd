## FreenetPresenceService — internet presence via the Freenet lobby contract.
##
## Drop-in replacement for UDPPresenceService. Same public API:
##   publish_presence(player_id, chunk_coords, enet_port)
##   subscribe_area(subscriber_id, center, radius, callback)
##   unsubscribe_area(subscriber_id)
##
## Architecture:
##   GDScript → WebSocket → proxy (ws://127.0.0.1:7510) → Freenet lobby contract
##
## The lobby contract is a LWW-map of session_id → presence entry. All players
## worldwide share the same contract instance (GLOBAL_LOBBY_ID). Freenet handles
## P2P replication — no central server needed.
##
## NAT note: we publish the LAN IP for now. Step 2 (WebRTC) will replace this
## with a STUN-discovered external IP for true internet NAT traversal.
##
## Callback signature (identical to UDPPresenceService):
##   func(session_id: String, chunk: Vector2i, ip: String, enet_port: int)
extends Node

const POLL_INTERVAL   := 10.0     ## seconds between LobbyGet polls
const PRESENCE_TTL    := 300.0    ## ignore entries older than 5 minutes (matches Rust LOBBY_TTL_SECS)
const RECONNECT_DELAY := 5.0      ## seconds to wait before reconnecting after disconnect

var proxy_url: String = "ws://127.0.0.1:7510"

var _local_player_id: String = ""
var _subscriptions: Dictionary = {}  ## subscriber_id → {center, radius, callback}

var _ws: WebSocketPeer = null
var _connected: bool = false
var _poll_timer: float = 0.0
var _reconnect_timer: float = 0.0

## Pending publish: saved if we try to publish before the WebSocket connects.
var _pending_publish: Dictionary = {}

func _ready() -> void:
	_connect_ws()

func _connect_ws() -> void:
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(proxy_url)
	if err != OK:
		push_warning("FreenetPresenceService: failed to start WebSocket connect (err %d)" % err)

func _process(delta: float) -> void:
	if _ws == null:
		return

	_ws.poll()
	var state := _ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_poll_timer = POLL_INTERVAL  # poll immediately on first connect
				# Flush any publish that arrived before connection
				if not _pending_publish.is_empty():
					_send_lobby_put(_pending_publish)
					_pending_publish = {}

			_poll_timer += delta
			if _poll_timer >= POLL_INTERVAL:
				_poll_timer = 0.0
				_send_lobby_get()

			while _ws.get_available_packet_count() > 0:
				var text := _ws.get_packet().get_string_from_utf8()
				_on_message(text)

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				push_warning("FreenetPresenceService: WebSocket closed — reconnecting in %.0fs" \
					% RECONNECT_DELAY)
				_connected = false
			_reconnect_timer += delta
			if _reconnect_timer >= RECONNECT_DELAY:
				_reconnect_timer = 0.0
				_connect_ws()

## Publish this player's presence to the Freenet lobby.
func publish_presence(player_id: String, chunk_coords: Vector2i, enet_port: int = 7777) -> void:
	_local_player_id = player_id
	var entry := {
		"session_id": player_id,
		"chunk_x": chunk_coords.x,
		"chunk_y": chunk_coords.y,
		"ip": _get_local_ip(),
		"enet_port": enet_port,
		"timestamp": Time.get_unix_time_from_system()
	}
	if _connected:
		_send_lobby_put(entry)
	else:
		# Buffer the publish — will be sent on connect
		_pending_publish = entry

## Register a callback for when a remote player appears within radius chunks.
## callback: func(session_id: String, chunk: Vector2i, ip: String, enet_port: int)
func subscribe_area(subscriber_id: String, center: Vector2i,
		radius: int, callback: Callable) -> void:
	_subscriptions[subscriber_id] = {"center": center, "radius": radius, "callback": callback}

func unsubscribe_area(subscriber_id: String) -> void:
	_subscriptions.erase(subscriber_id)

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _send_lobby_put(entry: Dictionary) -> void:
	var req := JSON.stringify({"op": "LobbyPut", "entry": entry})
	_ws.send_text(req)

func _send_lobby_get() -> void:
	_ws.send_text('{"op":"LobbyGet"}')

func _on_message(text: String) -> void:
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		return
	match data.get("op", ""):
		"LobbyGetOk":
			var lobby = JSON.parse_string(data.get("state_json", "{}"))
			if lobby is Dictionary:
				_process_lobby_state(lobby)
		"LobbyPutOk":
			pass  # fire and forget
		"LobbyGetNotFound":
			pass  # no players published yet — normal on first launch
		"Error":
			push_warning("FreenetPresenceService: proxy error — %s" % data.get("message", "?"))

## Testable seam: process a parsed LobbyState and fire matching subscriptions.
func _process_lobby_state(lobby: Dictionary) -> void:
	var now := Time.get_unix_time_from_system()
	var entries: Dictionary = lobby.get("entries", {})
	for sid in entries:
		if sid == _local_player_id:
			continue
		var entry: Dictionary = entries[sid]
		var age: float = now - float(entry.get("timestamp", 0.0))
		if age > PRESENCE_TTL:
			continue  # stale — ignore
		var remote_chunk := Vector2i(int(entry.get("chunk_x", 0)), int(entry.get("chunk_y", 0)))
		var remote_ip: String = entry.get("ip", "")
		var remote_port: int = int(entry.get("enet_port", 7777))
		for sub_id in _subscriptions:
			var sub: Dictionary = _subscriptions[sub_id]
			if _chebyshev(sub["center"] as Vector2i, remote_chunk) <= int(sub["radius"]):
				(sub["callback"] as Callable).call(sid, remote_chunk, remote_ip, remote_port)

## Return this machine's first non-loopback IPv4 address.
## TODO (step 2): replace with STUN-discovered external IP for internet NAT traversal.
func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("127.") or addr.begins_with("::") or addr == "::1":
			continue
		if "." in addr:  # IPv4
			return addr
	return "127.0.0.1"

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
