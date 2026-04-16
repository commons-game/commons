## NetworkManager — WebRTC multiplayer peer wrapper.
##
## ENet has been removed. The only transport is WebRTC, negotiated via the
## Freenet pairing contract. World calls set_webrtc_peer() when WebRTCManager
## establishes a connection; everything else (RPCs, MultiplayerSynchronizer)
## continues to work unchanged through Godot's MultiplayerPeer interface.
##
## Signals:
##   peer_connected(peer_id: int)
##   peer_disconnected(peer_id: int)
extends Node

const DEFAULT_PORT := 7777  # kept for presence broadcast compat; not used for sockets

const STATE_IDLE   := 0
const STATE_ACTIVE := 1

var _state: int = STATE_IDLE

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Called by World when WebRTCManager establishes a connection.
func set_webrtc_peer(mp: WebRTCMultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = mp
	_state = STATE_ACTIVE
	print("NetworkManager: WebRTC peer active")

## Disconnect from any current session cleanly.
func disconnect_all() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_state = STATE_IDLE

func get_state() -> int:
	return _state

func is_hosting() -> bool:
	return _state == STATE_ACTIVE

## True once we have an active WebRTC multiplayer peer.
func is_connected_to_session() -> bool:
	return _state != STATE_IDLE and multiplayer.multiplayer_peer != null

func _on_peer_connected(id: int) -> void:
	_state = STATE_ACTIVE
	print("NetworkManager: peer connected — id=%d" % id)
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: peer disconnected — id=%d" % id)
	peer_disconnected.emit(id)
