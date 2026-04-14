## TileMutationBus — single path for all tile changes.
##
## Decouples mutation logic from RPC transport:
##   1. Applies the mutation locally via tile_store.
##   2. Enqueues an outbound mutation record for the transport layer to send.
##
## The transport layer (WebRTC RPC) calls apply_remote_mutation() when it
## receives a mutation from a peer.
##
## tile_store must implement:
##   func set_tile(world_coords: Vector2i, layer: int, tile_id: String, author_id: String)
##   func remove_tile(world_coords: Vector2i, layer: int, author_id: String)
##
## Usage:
##   bus.tile_store = chunk_manager   (or a CRDTTileStore wrapper)
##   bus.local_author_id = player_id
##   bus.request_place_tile(coords, layer, tile_id)
##   var pending := bus.flush_outbound()   # send these to peers via RPC
class_name TileMutationBus

var tile_store: Object = null
var local_author_id: String = "local"

var _outbound: Array = []

func request_place_tile(world_coords: Vector2i, layer: int, tile_id: String) -> void:
	tile_store.set_tile(world_coords, layer, tile_id, local_author_id)
	_outbound.append(_make_record("place", world_coords, layer, tile_id, local_author_id))

func request_remove_tile(world_coords: Vector2i, layer: int) -> void:
	tile_store.remove_tile(world_coords, layer, local_author_id)
	_outbound.append(_make_record("remove", world_coords, layer, "", local_author_id))

## Apply a mutation received from a remote peer.
## Does NOT enqueue an outbound record (we received it, not originated it).
func apply_remote_mutation(record: Dictionary) -> void:
	var coords: Vector2i = record["world_coords"]
	var layer: int = record["layer"]
	var author: String = record.get("author_id", "")
	match record.get("type", ""):
		"place":
			tile_store.set_tile(coords, layer, record.get("tile_id", ""), author)
		"remove":
			tile_store.remove_tile(coords, layer, author)

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
