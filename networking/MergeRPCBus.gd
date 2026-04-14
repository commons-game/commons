## MergeRPCBus — RPC transport for session merge CRDT exchange.
##
## After ENet connects, both peers exchange a "hello" (session_id + chunk) and a
## CRDT snapshot. The host sends first; the client replies with its own snapshot.
## Both sides apply LWW merge and emit merge_applied when done.
##
## chunk_manager must be set by World before any send_ call.
## snapshot_ready/merge_applied signals drive World's HUD and coordinator.
##
## Snapshot format (Array of Dictionaries):
##   [{chunk_x, chunk_y, layer, lx, ly, tile_id, atlas_x, atlas_y, alt_tile,
##     timestamp, author_id}, ...]
extends Node

const MergeHandshakeScript := preload("res://networking/MergeHandshake.gd")

## Emitted on the receiver when a hello arrives. World passes the info to MergeCoordinator.
signal hello_received(remote_session_id: String, remote_chunk: Vector2i)
## Emitted on both sides when the full CRDT exchange is complete.
signal merge_applied

## Set by World.
var chunk_manager: Object = null

var _handshake: MergeHandshakeScript

func _ready() -> void:
	_handshake = MergeHandshakeScript.new()

# ---------------------------------------------------------------------------
# Hello handshake
# ---------------------------------------------------------------------------

## Send our session_id and current chunk to the remote peer.
func send_hello(session_id: String, chunk: Vector2i) -> void:
	if not _can_rpc():
		return
	rpc("_receive_hello", build_hello_payload(session_id, chunk))

@rpc("any_peer", "reliable")
func _receive_hello(payload: Dictionary) -> void:
	var sid: String = payload.get("session_id", "")
	var chunk := Vector2i(int(payload.get("chunk_x", 0)), int(payload.get("chunk_y", 0)))
	hello_received.emit(sid, chunk)

# ---------------------------------------------------------------------------
# CRDT snapshot exchange
# ---------------------------------------------------------------------------

## Serialize and broadcast our full CRDT snapshot to all peers.
func send_snapshot() -> void:
	if not _can_rpc() or chunk_manager == null:
		return
	var records: Array = chunk_manager.get_crdt_snapshot()
	var packed := serialize_snapshot(records)
	rpc("_receive_snapshot", packed)

@rpc("any_peer", "reliable")
func _receive_snapshot(packed: String) -> void:
	if chunk_manager == null:
		return
	var remote_records: Array = deserialize_snapshot(packed)
	var local_records: Array = chunk_manager.get_crdt_snapshot()
	var merged: Array = merge_snapshots(local_records, remote_records)
	chunk_manager.apply_crdt_snapshot(merged)
	merge_applied.emit()

# ---------------------------------------------------------------------------
# Pure helpers — used by tests and internally
# ---------------------------------------------------------------------------

func build_hello_payload(session_id: String, chunk: Vector2i) -> Dictionary:
	return {"session_id": session_id, "chunk_x": chunk.x, "chunk_y": chunk.y}

## Serialise a snapshot Array to a JSON string for RPC transport.
func serialize_snapshot(records: Array) -> String:
	return JSON.stringify(records)

## Deserialise a JSON string back to an Array of tile record Dictionaries.
func deserialize_snapshot(packed: String) -> Array:
	if packed.is_empty():
		return []
	var result = JSON.parse_string(packed)
	if result == null or not result is Array:
		return []
	# Ensure numeric fields are the right types after JSON parse
	var out: Array = []
	for item in result:
		var d: Dictionary = item as Dictionary
		out.append({
			"chunk_x":   int(d.get("chunk_x",  0)),
			"chunk_y":   int(d.get("chunk_y",  0)),
			"layer":     int(d.get("layer",    0)),
			"lx":        int(d.get("lx",       0)),
			"ly":        int(d.get("ly",       0)),
			"tile_id":   int(d.get("tile_id",  0)),
			"atlas_x":   int(d.get("atlas_x",  0)),
			"atlas_y":   int(d.get("atlas_y",  0)),
			"alt_tile":  int(d.get("alt_tile", 0)),
			"timestamp": float(d.get("timestamp", 0.0)),
			"author_id": str(d.get("author_id", "")),
		})
	return out

## LWW merge two flat snapshot Arrays. The unique key is (chunk_x, chunk_y, layer, lx, ly).
## Higher timestamp wins per position.
func merge_snapshots(local_records: Array, remote_records: Array) -> Array:
	# key: "cx,cy,layer,lx,ly" -> record dict
	var index: Dictionary = {}
	for r in local_records:
		var k := _record_key(r)
		index[k] = r
	for r in remote_records:
		var k := _record_key(r)
		if not index.has(k):
			index[k] = r
		elif float(r.get("timestamp", 0.0)) > float(index[k].get("timestamp", 0.0)):
			index[k] = r
	return index.values()

func _record_key(r: Dictionary) -> String:
	return "%d,%d,%d,%d,%d" % [
		int(r.get("chunk_x", 0)), int(r.get("chunk_y", 0)),
		int(r.get("layer", 0)),
		int(r.get("lx", 0)),     int(r.get("ly", 0))
	]

func _can_rpc() -> bool:
	return is_inside_tree() and multiplayer.has_multiplayer_peer()
