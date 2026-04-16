## FreenetBackend — IBackend implementation over Freenet P2P network.
##
## Architecture:
##   GDScript → JSON WebSocket (port 7510) → freeland-proxy (Rust)
##                                          → Freenet node (binary protocol)
##
## Chunk CRDT state is stored as a Freenet contract (one per chunk coord).
## Each store_chunk is a Freenet Put/Update; retrieve_chunk does a local-cache
## lookup, triggering a background Get if the chunk isn't cached yet.
##
## Reputation and equipment are stored in the player delegate (Freenet private
## storage keyed by "rep:local_player" and "equip:local_player").  Reads return
## from an in-memory cache and fire a background delegate load on first access.
## When the load completes, player_data_received is emitted so callers can
## refresh their state.
##
## Usage (Backend.gd):
##   var _backend := FreenetBackend.new()
##   _backend.initialize()
##   # In _process: _backend.poll()
##
## Emits chunk_received(coords, data) when a background chunk Get completes.
## Emits player_data_received(kind, data) when a delegate load completes.
class_name FreenetBackend
extends IBackend

signal chunk_received(coords: Vector2i, data: PackedByteArray)
signal player_data_received(kind: String, data: Dictionary)

const DEFAULT_PROXY_URL := "ws://127.0.0.1:7510"

var _ws := WebSocketPeer.new()
var _proxy_url := DEFAULT_PROXY_URL

## Write-through cache: avoids blocking on every retrieve_chunk call.
var _cache: Dictionary = {}  # Vector2i → PackedByteArray

## Coords whose Get is in-flight (to avoid duplicate requests).
var _pending_gets: Dictionary = {}  # Vector2i → true

var _connected := false

## In-memory cache for player data loaded from the delegate.
var _rep_cache: Dictionary = {}    # "local_player" → Dictionary
var _equip_cache: Dictionary = {}  # "local_player" → Dictionary

## Tracks whether a background load is already in-flight.
var _pending_player_loads: Dictionary = {}  # kind ("reputation"|"equipment") → true

## Pending telemetry callbacks: error_hash → Callable(ok: bool)
var _pending_error_reports: Dictionary = {}  # error_hash → Signal

func initialize(proxy_url: String = DEFAULT_PROXY_URL) -> void:
	_proxy_url = proxy_url
	var err := _ws.connect_to_url(_proxy_url)
	if err != OK:
		push_error("FreenetBackend: failed to initiate WebSocket to %s (err %d)" % [_proxy_url, err])

## Must be called every frame (from Backend._process).
func poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				print("FreenetBackend: connected to proxy at %s" % _proxy_url)
			_drain_responses()
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				push_warning("FreenetBackend: proxy disconnected (code %d)" % _ws.get_close_code())

# ---------------------------------------------------------------------------
# IBackend interface
# ---------------------------------------------------------------------------

func store_chunk(chunk_coords: Vector2i, crdt_data: PackedByteArray) -> void:
	_cache[chunk_coords] = crdt_data
	if not _connected:
		push_warning("FreenetBackend: not connected — chunk %s cached locally only" % str(chunk_coords))
		return
	var req := {
		"op": "Put",
		"chunk_x": chunk_coords.x,
		"chunk_y": chunk_coords.y,
		"state_json": crdt_data.get_string_from_utf8(),
	}
	_ws.send_text(JSON.stringify(req))

func retrieve_chunk(chunk_coords: Vector2i) -> PackedByteArray:
	if _cache.has(chunk_coords):
		return _cache[chunk_coords]
	# Not cached yet — fire a background Get and return empty so the caller
	# falls through to procedural generation. When the Get completes,
	# chunk_received fires and callers can refresh.
	_request_get(chunk_coords)
	return PackedByteArray()

func delete_chunk(chunk_coords: Vector2i) -> void:
	_cache.erase(chunk_coords)
	if not _connected:
		return
	var req := {
		"op": "Delete",
		"chunk_x": chunk_coords.x,
		"chunk_y": chunk_coords.y,
	}
	_ws.send_text(JSON.stringify(req))

func save_reputation(data: Dictionary) -> void:
	_rep_cache["local_player"] = data
	if not _connected:
		return
	var req := {
		"op": "PlayerSave",
		"player_id": "local_player",
		"kind": "reputation",
		"data_json": JSON.stringify(data),
	}
	_ws.send_text(JSON.stringify(req))

func load_reputation() -> Dictionary:
	if _rep_cache.has("local_player"):
		return _rep_cache["local_player"]
	_request_player_load("reputation")
	return {}

func save_equipment(data: Dictionary) -> void:
	_equip_cache["local_player"] = data
	if not _connected:
		return
	var req := {
		"op": "PlayerSave",
		"player_id": "local_player",
		"kind": "equipment",
		"data_json": JSON.stringify(data),
	}
	_ws.send_text(JSON.stringify(req))

func load_equipment() -> Dictionary:
	if _equip_cache.has("local_player"):
		return _equip_cache["local_player"]
	_request_player_load("equipment")
	return {}

## Send a telemetry report and await acknowledgement.
## Returns true on ReportErrorOk, false on error or no connection.
func report_error(entry: Dictionary) -> bool:
	if not _connected:
		return false
	var req := {
		"op":           "ReportError",
		"session_id":   entry.get("session_id", ""),
		"error_hash":   entry.get("error_hash", ""),
		"error_type":   entry.get("error_type", ""),
		"file":         entry.get("file", ""),
		"line":         int(entry.get("line", 0)),
		"phase":        entry.get("phase", ""),
		"game_version": entry.get("game_version", ""),
		"platform":     entry.get("platform", ""),
		"godot_version":entry.get("godot_version", ""),
		"ts":           float(entry.get("ts", 0.0)),
	}
	_ws.send_text(JSON.stringify(req))
	# Fire-and-forget for telemetry — we don't block on the response.
	# The response is handled in _handle_response and silently discarded.
	return true

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _request_get(coords: Vector2i) -> void:
	if _pending_gets.has(coords):
		return  # already in-flight
	if not _connected:
		return  # will retry on next retrieve_chunk call once connected
	_pending_gets[coords] = true
	var req := {
		"op": "Get",
		"chunk_x": coords.x,
		"chunk_y": coords.y,
	}
	_ws.send_text(JSON.stringify(req))

func _request_player_load(kind: String) -> void:
	if _pending_player_loads.has(kind):
		return  # already in-flight
	if not _connected:
		return  # will retry on next load_* call once connected
	_pending_player_loads[kind] = true
	var req := {
		"op": "PlayerLoad",
		"player_id": "local_player",
		"kind": kind,
	}
	_ws.send_text(JSON.stringify(req))

func _drain_responses() -> void:
	while _ws.get_available_packet_count() > 0:
		var packet := _ws.get_packet()
		var text := packet.get_string_from_utf8()
		var resp = JSON.parse_string(text)
		if resp == null or not resp is Dictionary:
			push_warning("FreenetBackend: invalid response payload: %s" % text)
			continue
		_handle_response(resp as Dictionary)

func _handle_response(resp: Dictionary) -> void:
	var op: String = resp.get("op", "")
	match op:
		"PutOk":
			pass  # local cache already up-to-date; no further action needed
		"GetOk":
			var coords := Vector2i(int(resp["chunk_x"]), int(resp["chunk_y"]))
			var data: PackedByteArray = (resp["state_json"] as String).to_utf8_buffer()
			_cache[coords] = data
			_pending_gets.erase(coords)
			chunk_received.emit(coords, data)
		"GetNotFound":
			var coords := Vector2i(int(resp["chunk_x"]), int(resp["chunk_y"]))
			_pending_gets.erase(coords)
			# No action — caller already fell through to procedural generation.
		"DeleteOk":
			pass
		"PlayerSaveOk":
			pass  # in-memory cache already updated; no further action needed
		"PlayerLoadOk":
			var kind: String = resp.get("kind", "")
			var data_json: String = resp.get("data_json", "{}")
			var parsed = JSON.parse_string(data_json)
			var data: Dictionary = parsed if parsed is Dictionary else {}
			_pending_player_loads.erase(kind)
			match kind:
				"reputation":
					_rep_cache["local_player"] = data
				"equipment":
					_equip_cache["local_player"] = data
			player_data_received.emit(kind, data)
		"PlayerLoadNotFound":
			var kind: String = resp.get("kind", "")
			_pending_player_loads.erase(kind)
			# No data stored yet — caller already returned {} from load_*.
		"ReportErrorOk":
			pass  # telemetry acknowledged; nothing further needed
		"Error":
			push_error("FreenetBackend proxy error: %s" % resp.get("message", "(no message)"))
		_:
			push_warning("FreenetBackend: unknown response op: %s" % op)
