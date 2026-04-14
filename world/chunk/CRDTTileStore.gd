## CRDTTileStore — Last-Write-Wins Map for tile state.
## Key invariants (must stay green for Phase 3 multiplayer):
##   1. set_tile then get_tile returns the entry
##   2. remove_tile writes a tombstone (tile_id == -1)
##   3. Older placement does not overwrite newer tombstone
##   4. Merge commutativity: A.merge(B) result == B.merge(A) result
##   5. Merge idempotency: A.merge(A) leaves A unchanged
##   6. Merge associativity: (A.merge(B)).merge(C) == A.merge(B.merge(C))
class_name CRDTTileStore

var _data: Dictionary = {}

func set_tile(layer: int, local: Vector2i, tile_id: int,
              atlas: Vector2i, alt: int, author: String) -> void:
	var key := CoordUtils.make_crdt_key(layer, local.x, local.y)
	var ts := Time.get_unix_time_from_system()
	var existing = _data.get(key, null)
	if existing == null or ts > existing["timestamp"]:
		_data[key] = {"tile_id": tile_id, "atlas_x": atlas.x, "atlas_y": atlas.y,
		              "alt_tile": alt, "timestamp": ts, "author_id": author}

func remove_tile(layer: int, local: Vector2i, author: String) -> void:
	## Tombstone: tile_id = -1. Higher timestamp wins on merge.
	var key := CoordUtils.make_crdt_key(layer, local.x, local.y)
	var ts := Time.get_unix_time_from_system()
	var existing = _data.get(key, null)
	if existing == null or ts > existing["timestamp"]:
		_data[key] = {"tile_id": -1, "atlas_x": 0, "atlas_y": 0,
		              "alt_tile": 0, "timestamp": ts, "author_id": author}

func get_tile(layer: int, local: Vector2i) -> Dictionary:
	return _data.get(CoordUtils.make_crdt_key(layer, local.x, local.y), {})

func merge(other: CRDTTileStore) -> void:
	## In-place merge. For each key, keep the entry with the higher timestamp.
	for key in other._data:
		var other_entry: Dictionary = other._data[key]
		var self_entry = _data.get(key, null)
		if self_entry == null or other_entry["timestamp"] > self_entry["timestamp"]:
			_data[key] = other_entry.duplicate()

func load_from_entries(entries: Dictionary) -> void:
	_data = entries.duplicate(true)

func get_all_entries() -> Dictionary:
	return _data
