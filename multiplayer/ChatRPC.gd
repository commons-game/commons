## ChatRPC — thin RPC wrapper for chat messages over ENet.
## No-op in single-player (no multiplayer peer).
##
## Added to the scene tree by World._setup_chat_system().
extends Node

## Find a remote player node by display name.
## Walks RemotePlayer_* siblings, checks display_name property or node name.
## Returns the peer id as a String, or "" if not found.
func find_local_player(player_name: String) -> String:
	var parent := get_parent()
	if parent == null:
		return ""
	for child in parent.get_children():
		var cname: String = child.name
		if not cname.begins_with("RemotePlayer_"):
			continue
		# Check display_name property if it exists
		if child.get("display_name") == player_name:
			var peer_part := cname.substr("RemotePlayer_".length())
			return peer_part
		# Fallback: check peer id portion of node name
		var peer_part := cname.substr("RemotePlayer_".length())
		if peer_part == player_name:
			return peer_part
	return ""

## Broadcast proximity chat to all peers. Server fans out to clients.
@rpc("any_peer", "call_local", "reliable")
func rpc_proximity(sender_id: String, sender_name: String, text: String) -> void:
	ChatSystem.receive_proximity(sender_id, sender_name, text)

func broadcast_proximity(sender_id: String, sender_name: String, text: String) -> void:
	if not multiplayer.has_multiplayer_peer():
		# Single-player: already delivered locally by ChatSystem.send_proximity
		return
	rpc("rpc_proximity", sender_id, sender_name, text)

## Send DM to a specific peer id.
@rpc("any_peer", "call_local", "reliable")
func rpc_dm(sender_id: String, sender_name: String, text: String) -> void:
	ChatSystem.receive_dm(sender_id, sender_name, text)

func send_dm_local(target_peer_id: int, sender_id: String, sender_name: String, text: String) -> void:
	rpc_id(target_peer_id, "rpc_dm", sender_id, sender_name, text)
