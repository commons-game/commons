## TileMutationBus — single path for all tile changes.
##
## Extends Node so it can live in the scene tree and use @rpc for peer broadcast.
## Pure logic is still fully unit-testable: when not in the scene tree,
## broadcast_mutation() is a no-op (is_inside_tree() returns false).
##
## tile_store must implement:
##   func set_tile(world_coords: Vector2i, layer: int, tile_id: String, author_id: String)
##   func remove_tile(world_coords: Vector2i, layer: int, author_id: String)
##
## RPC serialization: Vector2i is sent as [x, y] Array because Godot's RPC layer
## does not guarantee Vector2i passes cleanly across the network boundary.
## _rpc_receive_mutation() converts it back before calling apply_remote_mutation().
class_name TileMutationBus
extends Node

## Fired after a tile is placed — whether by local request or remote RPC.
## Systems that care about specific tile coords (e.g. Player's home-anchor
## tracker) can listen here instead of polling.
signal tile_placed(world_coords: Vector2i, layer: int, tile_id: String)
signal tile_removed(world_coords: Vector2i, layer: int)

var tile_store: Object = null
var local_author_id: String = "local"

var _outbound: Array = []

## Test-only: in-process mirrors for PuppetCluster. When a local request fires,
## every bus in this list also receives apply_remote_mutation synchronously.
## Production always leaves this empty.
var _test_peer_buses: Array = []

func add_test_peer(bus: Object) -> void:
	_test_peer_buses.append(bus)

func request_place_tile(world_coords: Vector2i, layer: int, tile_id: String) -> void:
	tile_store.set_tile(world_coords, layer, tile_id, local_author_id)
	var record := _make_record("place", world_coords, layer, tile_id, local_author_id)
	_outbound.append(record)
	broadcast_mutation(record)
	_log_event("tile_place", {"coords": world_coords, "layer": layer, "tile_id": tile_id})
	tile_placed.emit(world_coords, layer, tile_id)

func request_remove_tile(world_coords: Vector2i, layer: int) -> void:
	tile_store.remove_tile(world_coords, layer, local_author_id)
	var record := _make_record("remove", world_coords, layer, "", local_author_id)
	_outbound.append(record)
	broadcast_mutation(record)
	_log_event("tile_remove", {"coords": world_coords, "layer": layer})
	tile_removed.emit(world_coords, layer)

## EventLog is an autoload and is always in scope, but in unit tests the
## node may not be fully ready when this bus fires. Guard with a validity check.
func _log_event(event_type: String, data: Dictionary) -> void:
	if is_instance_valid(EventLog):
		EventLog.record(event_type, data)

## Apply a mutation received from a remote peer.
## Does NOT enqueue an outbound record (we received it, not originated it).
func apply_remote_mutation(record: Dictionary) -> void:
	var coords: Vector2i = record["world_coords"]
	var layer: int = record["layer"]
	var author: String = record.get("author_id", "")
	match record.get("type", ""):
		"place":
			var tile_id_str: String = record.get("tile_id", "")
			tile_store.set_tile(coords, layer, tile_id_str, author)
			tile_placed.emit(coords, layer, tile_id_str)
		"remove":
			tile_store.remove_tile(coords, layer, author)
			tile_removed.emit(coords, layer)

## Broadcast a mutation to all connected peers via RPC.
## No-op when not in the scene tree (unit tests) or no multiplayer peer is active.
func broadcast_mutation(record: Dictionary) -> void:
	# Test-harness mirror: in-process direct delivery to sibling Worlds.
	# Each mirrored bus sees the mutation through its normal apply_remote_mutation
	# path — same code the RPC receiver uses — so scenarios exercise the real
	# code path without needing a network layer. Production leaves this empty.
	for peer_bus in _test_peer_buses:
		peer_bus.apply_remote_mutation(record.duplicate())
	if not is_inside_tree():
		return
	if not multiplayer.has_multiplayer_peer():
		return
	var serializable := record.duplicate()
	var coords: Vector2i = serializable["world_coords"]
	serializable["world_coords"] = [coords.x, coords.y]
	rpc("_rpc_receive_mutation", serializable)

## RPC receive — called on all peers when a mutation is broadcast.
## Converts the Array-encoded world_coords back to Vector2i before applying.
@rpc("any_peer", "reliable")
func _rpc_receive_mutation(record: Dictionary) -> void:
	if record.has("world_coords"):
		var arr: Array = record["world_coords"] as Array
		record["world_coords"] = Vector2i(int(arr[0]), int(arr[1]))
	apply_remote_mutation(record)

## Returns the pending outbound queue and clears it.
func flush_outbound() -> Array:
	var pending := _outbound.duplicate()
	_outbound.clear()
	return pending

func _make_record(type: String, coords: Vector2i, layer: int,
		tile_id: String, author: String) -> Dictionary:
	return {
		"type": type,
		"world_coords": coords,
		"layer": layer,
		"tile_id": tile_id,
		"author_id": author,
		"timestamp": Time.get_unix_time_from_system()
	}
