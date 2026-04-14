## ShrineTerritory — tracks which shrine owns which chunks.
##
## Rules:
##   - A shrine's home chunk belongs to it on registration.
##   - When a chunk is modified and is adjacent (cardinal only) to a shrine's territory,
##     it joins that shrine's territory.
##   - If two shrines both have adjacency to the same modified chunk: CONTESTED.
##   - Contested chunks have no active mod set.
##   - Unregistering a shrine removes all its claimed chunks (and contested chunks it
##     contributed to become wilderness again).
class_name ShrineTerritory

# chunk_coords -> shrine_id String, or "CONTESTED"
var _ownership: Dictionary = {}

# shrine_id -> Array[Vector2i] of all chunks it owns
var _shrine_chunks: Dictionary = {}

# shrine_id -> home chunk Vector2i
var _shrine_home: Dictionary = {}

func register_shrine(shrine_id: String, home_chunk: Vector2i) -> void:
	_shrine_home[shrine_id] = home_chunk
	_shrine_chunks[shrine_id] = [home_chunk]
	_ownership[home_chunk] = shrine_id

func unregister_shrine(shrine_id: String) -> void:
	if not _shrine_home.has(shrine_id):
		return
	# Release all chunks this shrine owned
	var owned: Array = _shrine_chunks.get(shrine_id, [])
	for coords in owned:
		if _ownership.get(coords) == shrine_id:
			_ownership.erase(coords)
	# Release contested chunks this shrine contributed to — mark wilderness
	# (Any contested chunk adjacent to this shrine's territory may have been
	#  contested because of this shrine; clear them all if only one claimant remains.)
	_resolve_contested_after_removal(shrine_id)
	_shrine_chunks.erase(shrine_id)
	_shrine_home.erase(shrine_id)

func on_chunk_modified(coords: Vector2i) -> void:
	# Find all shrines that have adjacency to this chunk
	var claimants := _shrines_adjacent_to(coords)
	if claimants.size() == 0:
		return  # wilderness — no shrine nearby
	if claimants.size() == 1:
		var sid: String = claimants[0]
		_ownership[coords] = sid
		if not _shrine_chunks[sid].has(coords):
			_shrine_chunks[sid].append(coords)
	else:
		# Two or more shrines claim adjacency — contested
		_ownership[coords] = "CONTESTED"

func get_shrine_for_chunk(coords: Vector2i):
	return _ownership.get(coords, null)

## Returns the shrine id if the chunk is owned by exactly one shrine, else null.
func get_active_mod_set(coords: Vector2i):
	var owner = _ownership.get(coords, null)
	if owner == null or owner == "CONTESTED":
		return null
	return owner

# --- Internal helpers ---

func _shrines_adjacent_to(coords: Vector2i) -> Array:
	var cardinal := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var found := {}
	for offset in cardinal:
		var neighbor: Vector2i = coords + (offset as Vector2i)
		var owner = _ownership.get(neighbor, null)
		if owner != null and owner != "CONTESTED":
			found[owner] = true
	return found.keys()

func _resolve_contested_after_removal(removed_shrine_id: String) -> void:
	# After removing a shrine, any CONTESTED chunk that was contested only because
	# of this shrine should be re-evaluated. We scan all contested chunks.
	var to_recheck := []
	for coords in _ownership:
		if _ownership[coords] == "CONTESTED":
			to_recheck.append(coords)
	for coords in to_recheck:
		var claimants := _shrines_adjacent_to(coords)
		# Remove the shrine being unregistered from claimants (its chunks are already
		# erased before this is called — but home chunk may still be in _ownership
		# during iteration; handle gracefully by filtering)
		claimants = claimants.filter(func(s): return s != removed_shrine_id)
		if claimants.size() == 0:
			_ownership.erase(coords)
		elif claimants.size() == 1:
			var sid: String = claimants[0]
			_ownership[coords] = sid
			if not _shrine_chunks[sid].has(coords):
				_shrine_chunks[sid].append(coords)
		# else still contested between remaining shrines — leave as CONTESTED
