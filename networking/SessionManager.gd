## SessionManager — equal-peer P2P session state machine.
##
## No host. All peers are equal. Last peer standing keeps the session alive —
## a player going solo after others disconnect is still in their own session.
## The actual WebRTC transport is handled separately; this class manages
## the logical peer set and session identity.
##
## Usage:
##   session.start_session()
##   session.add_peer("peer_abc")
##   session.remove_peer("peer_abc")
##   var count := session.peer_count()
class_name SessionManager

var session_id: String = ""
var _peers: Dictionary = {}   # peer_id -> true
var _active: bool = false

func start_session() -> void:
	session_id = _generate_id()
	_peers.clear()
	_active = true

func is_active() -> bool:
	return _active

## Add a connected peer. Idempotent — adding the same peer twice is safe.
func add_peer(peer_id: String) -> void:
	_peers[peer_id] = true

## Remove a peer. Safe to call with an unknown peer_id.
## Session stays active even when the peer set drops to zero.
func remove_peer(peer_id: String) -> void:
	_peers.erase(peer_id)

## Returns a copy of the current peer id set as an Array.
func get_peers() -> Array:
	return _peers.keys()

## Number of currently connected peers (not counting self).
func peer_count() -> int:
	return _peers.size()

func _generate_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), randi()]
