## Backend.gd — Phase 0 stub.
## All methods are no-ops or return empty data.
## Phase 1: swap to LocalBackend. Phase 6: swap to FreenetBackend.
## The swap point is a single line in _ready().
extends Node

func retrieve_chunk(_coords: Vector2i) -> PackedByteArray:
	## Phase 0: always returns empty (triggers procedural generation).
	return PackedByteArray()

func store_chunk(_coords: Vector2i, _data: PackedByteArray) -> void:
	## Phase 0: no-op.
	pass

func delete_chunk(_coords: Vector2i) -> void:
	## Phase 0: no-op.
	pass
