## NetworkManager — ENet-based host/join for local and LAN multiplayer.
## Used as an autoload so any scene can call NetworkManager.host() / .join().
##
## For local simulation: both instances run on 127.0.0.1 with the same port.
## For LAN: use the host machine's LAN IP.
## For internet (Phase 6+): swap ENet for WebRTCMultiplayerPeer.
##
## Signals:
##   peer_connected(peer_id: int)
##   peer_disconnected(peer_id: int)
extends Node

const DEFAULT_PORT := 7777
const MAX_PEERS    := 8

const STATE_IDLE    := 0
const STATE_HOSTING := 1
const STATE_JOINING := 2

var _state: int = STATE_IDLE

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Start an ENet server on the given port. Other players call join() to connect.
func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		push_error("NetworkManager: failed to host on port %d — error %d" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	_state = STATE_HOSTING
	print("NetworkManager: hosting on port %d (peer_id=%d)" % [port, multiplayer.get_unique_id()])
	return OK

## Connect to a host as a client.
func join(ip: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("NetworkManager: failed to join %s:%d — error %d" % [ip, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	_state = STATE_JOINING
	print("NetworkManager: joining %s:%d" % [ip, port])
	return OK

## Disconnect from any current session cleanly.
func disconnect_all() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_state = STATE_IDLE

func get_state() -> int:
	return _state

func is_hosting() -> bool:
	return _state == STATE_HOSTING

## True once we have an active multiplayer peer (hosting or joined).
func is_connected_to_session() -> bool:
	return _state != STATE_IDLE and multiplayer.multiplayer_peer != null

func _on_peer_connected(id: int) -> void:
	if _state == STATE_JOINING:
		_state = STATE_HOSTING  # reuse HOSTING to mean "active session"
	print("NetworkManager: peer connected — id=%d" % id)
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: peer disconnected — id=%d" % id)
	peer_disconnected.emit(id)
