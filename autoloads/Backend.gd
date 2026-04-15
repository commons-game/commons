## Backend.gd — autoload singleton. The sole IBackend access point.
## Phase 1: LocalBackend. Phase 6: swap LocalBackend to FreenetBackend.
## Nothing outside this file instantiates IBackend.
extends Node

const LocalBackendScript := preload("res://backend/local/LocalBackend.gd")
const FreenetBackendScript := preload("res://backend/freenet/FreenetBackend.gd")

## Set to true to use FreenetBackend instead of LocalBackend.
## In production this will be driven by a project setting or command-line flag.
var use_freenet: bool = false

var _backend: IBackend

func _ready() -> void:
	if use_freenet:
		_backend = FreenetBackendScript.new()
	else:
		_backend = LocalBackendScript.new()
	_backend.initialize()

func _process(_delta: float) -> void:
	_backend.poll()

func store_chunk(coords: Vector2i, data: PackedByteArray) -> void:
	_backend.store_chunk(coords, data)

func retrieve_chunk(coords: Vector2i) -> PackedByteArray:
	return _backend.retrieve_chunk(coords)

func delete_chunk(coords: Vector2i) -> void:
	_backend.delete_chunk(coords)

func save_reputation(data: Dictionary) -> void:
	_backend.save_reputation(data)

func load_reputation() -> Dictionary:
	return _backend.load_reputation()

func save_equipment(data: Dictionary) -> void:
	_backend.save_equipment(data)

func load_equipment() -> Dictionary:
	return _backend.load_equipment()
