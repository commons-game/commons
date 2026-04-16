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

## Maximum bytes per RPC message (WebRTC data channel limit ~65535; leave headroom).
const MAX_MSG_BYTES := 50000

## Set by World.
var chunk_manager: Object = null

var _handshake: MergeHandshakeScript

## Reassembly buffer: sender_id → {chunks: {index: PackedByteArray}, total: int}
var _snapshot_buf: Dictionary = {}

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

## Serialize, compress, and broadcast our CRDT snapshot to all peers.
## Large snapshots are split into ≤MAX_MSG_BYTES chunks.
func send_snapshot() -> void:
	if not _can_rpc() or chunk_manager == null:
		return
	var records: Array = chunk_manager.get_crdt_snapshot()
	var json_str := JSON.stringify(records)
	var compressed := json_str.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	var total := compressed.size()
	var num_chunks := maxi(1, ceili(float(total) / MAX_MSG_BYTES))
	for i in range(num_chunks):
		var start := i * MAX_MSG_BYTES
		var slice: PackedByteArray = compressed.slice(start, min(start + MAX_MSG_BYTES, total))
		rpc("_receive_snapshot_chunk", i, num_chunks, slice)

@rpc("any_peer", "reliable")
func _receive_snapshot_chunk(index: int, total_chunks: int, data: PackedByteArray) -> void:
	if chunk_manager == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _snapshot_buf.has(sender):
		_snapshot_buf[sender] = {"chunks": {}, "total": total_chunks}
	_snapshot_buf[sender]["chunks"][index] = data
	if _snapshot_buf[sender]["chunks"].size() < total_chunks:
		return  # still waiting for more chunks
	# All chunks received — reassemble and merge
	var full := PackedByteArray()
	for i in range(total_chunks):
		full.append_array(_snapshot_buf[sender]["chunks"][i])
	_snapshot_buf.erase(sender)
	var json_str := full.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()
	var remote_records: Array = deserialize_snapshot(json_str)
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
