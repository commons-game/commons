## ChatSystem — friend list, block list, command parsing, and chat routing.
##
## Autoload: ChatSystem
## Handles proximity chat and DM routing for Phase A+B.
## Phase C: Freenet-backed DM delivery via FreenetDMQueue.
extends Node

const FRIENDS_PATH := "user://friends.json"
const BLOCKED_PATH := "user://blocked.json"

## {player_id: {id, name, pubkey: ""}}  — pubkey empty until Phase C
var _friends: Dictionary = {}
## {player_id: true}
var _blocked: Dictionary = {}

## Last 20 messages for history panel
var _history: Array = []  # [{sender, text, dm: bool, timestamp}]
const HISTORY_MAX := 20

signal message_received(sender_name: String, text: String, is_dm: bool, sender_id: String)
signal history_updated

func _ready() -> void:
	_load_friends()
	_load_blocked()

# ---------------------------------------------------------------------------
# Friend list
# ---------------------------------------------------------------------------

func add_friend(player_id: String, player_name: String) -> void:
	if player_id.is_empty():
		return
	_friends[player_id] = {"id": player_id, "name": player_name, "pubkey": ""}
	_save_friends()

func remove_friend(player_id: String) -> void:
	if _friends.has(player_id):
		_friends.erase(player_id)
		_save_friends()

func is_friend(player_id: String) -> bool:
	return _friends.has(player_id)

## Returns Array of dicts [{id, name, pubkey}].
func get_friends() -> Array:
	var result: Array = []
	for k in _friends:
		result.append(_friends[k])
	return result

# ---------------------------------------------------------------------------
# Block list
# ---------------------------------------------------------------------------

func block(player_id: String) -> void:
	if player_id.is_empty():
		return
	_blocked[player_id] = true
	_save_blocked()

func unblock(player_id: String) -> void:
	if _blocked.has(player_id):
		_blocked.erase(player_id)
		_save_blocked()

func is_blocked(player_id: String) -> bool:
	return _blocked.has(player_id)

# ---------------------------------------------------------------------------
# Message routing
# ---------------------------------------------------------------------------

## Called by ChatInput after the player submits text.
func handle_input(raw_text: String, local_player_id: String, local_player_name: String) -> void:
	var trimmed := raw_text.strip_edges()
	if trimmed.is_empty():
		return
	if trimmed.begins_with("/"):
		if not _parse_command(trimmed, local_player_id, local_player_name):
			pass  # _parse_command handles unknown command feedback internally
	else:
		send_proximity(local_player_id, local_player_name, trimmed)

func send_proximity(sender_id: String, sender_name: String, text: String) -> void:
	# Emit locally — own bubble + history
	_push_history(sender_name, text, false, sender_id)
	emit_signal("message_received", sender_name, text, false, sender_id)
	# Broadcast to peers if in multiplayer
	if Engine.has_singleton("ChatRPC"):
		Engine.get_singleton("ChatRPC").broadcast_proximity(sender_id, sender_name, text)
	elif get_node_or_null("/root/ChatRPC") != null:
		get_node("/root/ChatRPC").broadcast_proximity(sender_id, sender_name, text)

func send_dm(sender_id: String, sender_name: String, target_name: String, text: String) -> void:
	# Check if target is in local session
	var chat_rpc: Node = get_node_or_null("/root/ChatRPC")
	var target_peer_id_str: String = ""
	if chat_rpc != null:
		target_peer_id_str = str(chat_rpc.call("find_local_player", target_name))

	if target_peer_id_str != "" and target_peer_id_str.is_valid_int():
		# Target is online in local session
		var target_peer_id := int(target_peer_id_str)
		if chat_rpc != null:
			chat_rpc.send_dm_local(target_peer_id, sender_id, sender_name, text)
	else:
		# Offline — queue for Freenet delivery
		var dm_queue := get_node_or_null("/root/FreenetDMQueue")
		if dm_queue != null:
			dm_queue.enqueue(target_name, text)
		else:
			_push_system_message("Could not send DM to '%s': not online and no DM queue available." % target_name)

## Called by ChatRPC when a remote proximity message arrives.
func receive_proximity(sender_id: String, sender_name: String, text: String) -> void:
	if is_blocked(sender_id):
		return
	_push_history(sender_name, text, false, sender_id)
	emit_signal("message_received", sender_name, text, false, sender_id)

## Called by ChatRPC when a remote DM arrives.
func receive_dm(sender_id: String, sender_name: String, text: String) -> void:
	if is_blocked(sender_id):
		return
	_push_history("[DM] " + sender_name, text, true, sender_id)
	emit_signal("message_received", sender_name, text, true, sender_id)

# ---------------------------------------------------------------------------
# Command parser
# ---------------------------------------------------------------------------

## Parse and execute a slash command. Returns true if handled (even if unknown).
func _parse_command(text: String, local_player_id: String, local_player_name: String) -> bool:
	# Strip leading slash and split on spaces
	var without_slash := text.substr(1)  # remove leading "/"
	var parts := without_slash.split(" ", false)
	if parts.is_empty():
		return true
	var cmd := parts[0].to_lower()

	match cmd:
		"addfriend":
			if parts.size() < 2:
				_push_system_message("Usage: /addfriend <name>")
			else:
				var name_arg := parts[1]
				# Phase C: look up real id via session; for now use name as id
				var id_arg := _resolve_player_id(name_arg)
				add_friend(id_arg, name_arg)
				_push_system_message("Added %s to friends." % name_arg)
		"removefriend":
			if parts.size() < 2:
				_push_system_message("Usage: /removefriend <name>")
			else:
				var name_arg := parts[1]
				var id_arg := _resolve_player_id(name_arg)
				remove_friend(id_arg)
				_push_system_message("Removed %s from friends." % name_arg)
		"block":
			if parts.size() < 2:
				_push_system_message("Usage: /block <name>")
			else:
				var name_arg := parts[1]
				var id_arg := _resolve_player_id(name_arg)
				block(id_arg)
				_push_system_message("Blocked %s." % name_arg)
		"unblock":
			if parts.size() < 2:
				_push_system_message("Usage: /unblock <name>")
			else:
				var name_arg := parts[1]
				var id_arg := _resolve_player_id(name_arg)
				unblock(id_arg)
				_push_system_message("Unblocked %s." % name_arg)
		"dm":
			if parts.size() < 3:
				_push_system_message("Usage: /dm <name> <message>")
			else:
				var target := parts[1]
				# Everything after the target name is the message (supports multi-word)
				var msg_parts := parts.slice(2)
				var msg := " ".join(msg_parts)
				send_dm(local_player_id, local_player_name, target, msg)
		_:
			_push_system_message("Unknown command: /%s" % cmd)

	return true

## Push a system/status message into history and emit signal.
func _push_system_message(text: String) -> void:
	_push_history("[System]", text, false, "")
	emit_signal("message_received", "[System]", text, false, "")

## Resolve a display name to a player id.
## Phase A/B: tries to find matching RemotePlayer node; falls back to name-as-id.
func _resolve_player_id(player_name: String) -> String:
	var chat_rpc: Node = get_node_or_null("/root/ChatRPC")
	if chat_rpc != null:
		var found: String = str(chat_rpc.call("find_local_player", player_name))
		if found != "":
			return found
	return player_name  # Phase C will do pubkey exchange

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------

func _push_history(sender: String, text: String, is_dm: bool, sender_id: String) -> void:
	_history.append({
		"sender": sender,
		"text": text,
		"dm": is_dm,
		"sender_id": sender_id,
		"timestamp": Time.get_unix_time_from_system(),
	})
	while _history.size() > HISTORY_MAX:
		_history.pop_front()
	emit_signal("history_updated")

func get_history() -> Array:
	return _history.duplicate()

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _load_friends() -> void:
	if not FileAccess.file_exists(FRIENDS_PATH):
		return
	var f := FileAccess.open(FRIENDS_PATH, FileAccess.READ)
	if f == null:
		return
	var json_str := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(json_str)
	if parsed is Dictionary:
		_friends = parsed

func _save_friends() -> void:
	var f := FileAccess.open(FRIENDS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("ChatSystem: cannot write " + FRIENDS_PATH)
		return
	f.store_string(JSON.stringify(_friends))
	f.close()

func _load_blocked() -> void:
	if not FileAccess.file_exists(BLOCKED_PATH):
		return
	var f := FileAccess.open(BLOCKED_PATH, FileAccess.READ)
	if f == null:
		return
	var json_str := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(json_str)
	if parsed is Dictionary:
		_blocked = parsed

func _save_blocked() -> void:
	var f := FileAccess.open(BLOCKED_PATH, FileAccess.WRITE)
	if f == null:
		push_error("ChatSystem: cannot write " + BLOCKED_PATH)
		return
	f.store_string(JSON.stringify(_blocked))
	f.close()
