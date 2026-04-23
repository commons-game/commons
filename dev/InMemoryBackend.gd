## InMemoryBackend — IBackend implementation backed by a plain dictionary.
##
## Used by PuppetCluster so two Worlds in the same headless process can each
## own isolated chunk storage without fighting over `user://chunks/` on disk.
## Also convenient for unit tests that need a backend round-trip without
## touching the filesystem.
##
## Reputation and equipment follow the same in-memory model.
class_name InMemoryBackend
extends IBackend

var _chunks: Dictionary = {}   # Vector2i → PackedByteArray
var _reputation: Dictionary = {}
var _equipment: Dictionary = {}

func store_chunk(chunk_coords: Vector2i, crdt_data: PackedByteArray) -> void:
	_chunks[chunk_coords] = crdt_data.duplicate()

func retrieve_chunk(chunk_coords: Vector2i) -> PackedByteArray:
	if not _chunks.has(chunk_coords):
		return PackedByteArray()
	return (_chunks[chunk_coords] as PackedByteArray).duplicate()

func delete_chunk(chunk_coords: Vector2i) -> void:
	_chunks.erase(chunk_coords)

func save_reputation(data: Dictionary) -> void:
	_reputation = data.duplicate(true)

func load_reputation() -> Dictionary:
	return _reputation.duplicate(true)

func save_equipment(data: Dictionary) -> void:
	_equipment = data.duplicate(true)

func load_equipment() -> Dictionary:
	return _equipment.duplicate(true)

## Test helper: wipe all stored chunks. Useful between scenarios.
func clear() -> void:
	_chunks.clear()
	_reputation.clear()
	_equipment.clear()

## Test helper: total chunks currently in the store.
func chunk_count() -> int:
	return _chunks.size()
