## IBackend — abstract base class for all backend implementations.
## Phase 1: LocalBackend. Phase 6: FreenetBackend.
## ONLY instantiated in Backend.gd autoload. Everything else calls Backend.*.
class_name IBackend
extends RefCounted

func store_chunk(_chunk_coords: Vector2i, _crdt_data: PackedByteArray) -> void:
	push_error("IBackend.store_chunk not implemented")

func retrieve_chunk(_chunk_coords: Vector2i) -> PackedByteArray:
	push_error("IBackend.retrieve_chunk not implemented")
	return PackedByteArray()

func delete_chunk(_chunk_coords: Vector2i) -> void:
	pass  # optional — not all backends need explicit delete

# Presence and signaling — stubs for now, implemented in Phase 4+
func publish_presence(_player_id: String, _chunk_coords: Vector2i) -> void:
	pass

func subscribe_area(_chunk_coords: Vector2i, _radius: int, _callback: Callable) -> void:
	pass

func unsubscribe_area(_chunk_coords: Vector2i) -> void:
	pass
