## Backend.gd — autoload singleton. The sole IBackend access point.
## Phase 1: LocalBackend. Phase 6: swap LocalBackend to FreenetBackend.
## Nothing outside this file instantiates IBackend.
extends Node

const LocalBackendScript := preload("res://backend/local/LocalBackend.gd")

var _backend: IBackend

func _ready() -> void:
	_backend = LocalBackendScript.new()
	_backend.initialize()

func store_chunk(coords: Vector2i, data: PackedByteArray) -> void:
	_backend.store_chunk(coords, data)

func retrieve_chunk(coords: Vector2i) -> PackedByteArray:
	return _backend.retrieve_chunk(coords)

func delete_chunk(coords: Vector2i) -> void:
	_backend.delete_chunk(coords)
