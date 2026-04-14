## UDPPresenceService — LAN presence publish/subscribe via UDP broadcast.
##
## Each player broadcasts their session_id + chunk position to the LAN.
## Subscribers receive callbacks when a remote player enters their radius.
##
## The _on_packet_received(text, sender_ip) method is the testable seam:
## tests call it directly; _process feeds it from the real UDP socket.
##
## Callback signature: func(session_id: String, chunk: Vector2i, ip: String, enet_port: int)
extends Node

const PRESENCE_PORT  := 7778
const BROADCAST_ADDR := "255.255.255.255"

## Override in tests to use a loopback address.
var broadcast_address: String = BROADCAST_ADDR
## Override in tests to use a non-conflicting port.
var listen_port: int = PRESENCE_PORT
## The local player's session_id — packets matching this are ignored (no self-notify).
var _local_player_id: String = ""

# subscriber_id -> {center: Vector2i, radius: int, callback: Callable}
var _subscriptions: Dictionary = {}

var _socket: PacketPeerUDP = null
var _bound: bool = false

func _ready() -> void:
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	var err := _socket.bind(listen_port)
	if err != OK:
		push_warning("UDPPresenceService: could not bind port %d (err %d) — running without UDP" \
			% [listen_port, err])
		return
	_bound = true

func _process(_delta: float) -> void:
	if not _bound or _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var sender_ip := _socket.get_packet_ip()
		_on_packet_received(packet.get_string_from_utf8(), sender_ip)

## Broadcast this player's presence to the LAN.
func publish_presence(player_id: String, chunk_coords: Vector2i, enet_port: int = 7777) -> void:
	_local_player_id = player_id
	if not _bound or _socket == null:
		return
	var payload := JSON.stringify({
		"session_id": player_id,
		"x": chunk_coords.x,
		"y": chunk_coords.y,
		"enet_port": enet_port
	})
	_socket.set_dest_address(broadcast_address, listen_port)
	_socket.put_packet(payload.to_utf8_buffer())

## Register a callback for when a remote player appears within radius chunks.
func subscribe_area(subscriber_id: String, center: Vector2i,
		radius: int, callback: Callable) -> void:
	_subscriptions[subscriber_id] = {"center": center, "radius": radius, "callback": callback}

func unsubscribe_area(subscriber_id: String) -> void:
	_subscriptions.erase(subscriber_id)

## Testable seam: parse one raw UDP payload and fire matching subscriptions.
func _on_packet_received(text: String, sender_ip: String) -> void:
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		return
	var sid: String = data.get("session_id", "")
	if sid.is_empty() or sid == _local_player_id:
		return
	var coords := Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
	var enet_port: int = int(data.get("enet_port", 7777))
	for sub_id in _subscriptions:
		var sub: Dictionary = _subscriptions[sub_id]
		if _chebyshev(sub["center"] as Vector2i, coords) <= int(sub["radius"]):
			(sub["callback"] as Callable).call(sid, coords, sender_ip, enet_port)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
