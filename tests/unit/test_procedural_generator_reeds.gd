## Tests for reed spawning in ProceduralGenerator.
##
## Reeds (atlas (4,1)) spawn on ground tiles in Verdant + Tangle that are
## adjacent to (or sit on) water. They never spawn in Moraine (low water),
## Mire (tier 3), or Hollow (tier 3). Spawn density is driven by the same
## object-noise channel as trees/rocks; the threshold per-biome is
## documented in ProceduralGenerator._object_atlas.
##
## We test by scanning many chunks (so the chance any one chunk happens to
## have zero reeds doesn't make the test flaky) and asserting at-least / at-
## most invariants. The "adjacent water" property is checked by sampling the
## ground in the four neighbours of every reed tile in a generated chunk.
extends GdUnitTestSuite

const REEDS_ATLAS := Vector2i(4, 1)
const WATER_ATLAS_X := 3

# Pick a seed where Verdant chunks reliably contain water (every Verdant
# chunk has ~30% water under the calibrated threshold so a small scan is
# overwhelmingly likely to see reeds).
const SEED := 12345

# ---------------------------------------------------------------------------
# Spawn presence
# ---------------------------------------------------------------------------

func test_verdant_chunks_can_spawn_reeds() -> void:
	# Scan a 5x5 grid of tier-1 chunks around spawn — biome may be Verdant or
	# Moraine depending on the force-noise patch — assert we see at least one
	# reed somewhere across the sample. Very high probability across 25 chunks.
	var seen: int = _count_reeds_across_chunks(Vector2i(-2, -2), Vector2i(2, 2), SEED)
	assert_int(seen).override_failure_message(
		"expected at least one reed across 25 tier-1 chunks at seed %d, found 0" % SEED
	).is_greater(0)

func test_tangle_chunks_can_spawn_reeds() -> void:
	# Tier 2 = Tangle/Shard. The Bloom/Still split is force-noise driven, so any
	# given quadrant of the ring may be all Shard at one seed. Walk the whole
	# tier-2 ring (Chebyshev 4..7) and only count chunks where the biome is
	# Tangle (the Bloom side of tier 2). Then assert reeds exist somewhere
	# across those Tangle chunks.
	var tangle_reeds := 0
	var tangle_chunks := 0
	for cy in range(-7, 8):
		for cx in range(-7, 8):
			var dist: int = max(abs(cx), abs(cy))
			if dist < 4 or dist > 7:
				continue
			var coords := Vector2i(cx, cy)
			var biome: int = ProceduralGenerator.get_biome(coords, Constants.SPAWN_CHUNK, SEED)
			if biome != ProceduralGenerator.Biome.TANGLE:
				continue
			tangle_chunks += 1
			var entries: Dictionary = ProceduralGenerator.generate_chunk(coords, SEED)
			for key in entries:
				var layer: int = (int(key) >> 16) & 0xFF
				if layer != 1:
					continue
				var entry: Dictionary = entries[key]
				if int(entry["atlas_x"]) == REEDS_ATLAS.x \
						and int(entry["atlas_y"]) == REEDS_ATLAS.y:
					tangle_reeds += 1
	assert_int(tangle_chunks).override_failure_message(
		"no Tangle chunks in the tier-2 ring at seed %d — change SEED" % SEED
	).is_greater(0)
	assert_int(tangle_reeds).override_failure_message(
		"%d Tangle chunks scanned, 0 reeds found at seed %d" % [tangle_chunks, SEED]
	).is_greater(0)

# ---------------------------------------------------------------------------
# Biome exclusion
# ---------------------------------------------------------------------------

func test_no_reeds_outside_verdant_or_tangle() -> void:
	# Walk a wide swath (-15..15 chunks) and for every reed tile we find,
	# assert the chunk's biome is Verdant (0) or Tangle (2). This is the
	# strongest form of the "Moraine/Mire/Shard/Hollow get no reeds" rule
	# — it catches any leak regardless of where the leak's chunk sits.
	for cy in range(-15, 16):
		for cx in range(-15, 16):
			var coords := Vector2i(cx, cy)
			var biome: int = ProceduralGenerator.get_biome(coords, Constants.SPAWN_CHUNK, SEED)
			var entries: Dictionary = ProceduralGenerator.generate_chunk(coords, SEED)
			if not _chunk_has_reeds(entries):
				continue
			assert_bool(biome == ProceduralGenerator.Biome.VERDANT \
					or biome == ProceduralGenerator.Biome.TANGLE
				).override_failure_message(
					"reeds spawned in non-Verdant/Tangle biome %d at chunk %s" % [biome, coords]
				).is_true()

func test_moraine_chunks_have_no_reeds() -> void:
	# Find a confirmed Moraine chunk and assert it's reed-free.
	var found_moraine := false
	for cy in range(-3, 4):
		for cx in range(-3, 4):
			var coords := Vector2i(cx, cy)
			var biome: int = ProceduralGenerator.get_biome(coords, Constants.SPAWN_CHUNK, SEED)
			if biome != ProceduralGenerator.Biome.MORAINE:
				continue
			found_moraine = true
			var entries: Dictionary = ProceduralGenerator.generate_chunk(coords, SEED)
			assert_bool(_chunk_has_reeds(entries)).override_failure_message(
				"reeds found in Moraine chunk %s — must be Verdant/Tangle only" % coords
			).is_false()
	assert_bool(found_moraine).override_failure_message(
		"test seed %d had no Moraine in tier 1; pick a different seed" % SEED
	).is_true()

func test_mire_chunks_have_no_reeds() -> void:
	# Tier 3 — Mire/Hollow. Pick a Mire chunk far enough from spawn.
	var found_mire := false
	for cy in range(-15, 16):
		for cx in range(-15, 16):
			var coords := Vector2i(cx, cy)
			var biome: int = ProceduralGenerator.get_biome(coords, Constants.SPAWN_CHUNK, SEED)
			if biome != ProceduralGenerator.Biome.MIRE:
				continue
			found_mire = true
			var entries: Dictionary = ProceduralGenerator.generate_chunk(coords, SEED)
			assert_bool(_chunk_has_reeds(entries)).override_failure_message(
				"reeds found in Mire chunk %s — tier-3 biomes get no reeds" % coords
			).is_false()
			# One Mire is enough — biome rule, not chunk-specific.
			return
	assert_bool(found_mire).override_failure_message(
		"test seed %d found no Mire in scan — widen scan or change seed" % SEED
	).is_true()

# ---------------------------------------------------------------------------
# Adjacency rule
# ---------------------------------------------------------------------------

func test_every_reed_has_water_neighbour_or_is_on_water() -> void:
	# For every reed in a Verdant or Tangle chunk, assert at least one of the
	# 4-cardinal neighbouring ground tiles (or the cell itself) is water.
	# This is the load-bearing "near water" invariant — without it the
	# placement helper would scatter reeds anywhere.
	var reeds_checked := 0
	for cy in range(-7, 8):
		for cx in range(-7, 8):
			var coords := Vector2i(cx, cy)
			var biome: int = ProceduralGenerator.get_biome(coords, Constants.SPAWN_CHUNK, SEED)
			if biome != ProceduralGenerator.Biome.VERDANT \
					and biome != ProceduralGenerator.Biome.TANGLE:
				continue
			var entries: Dictionary = ProceduralGenerator.generate_chunk(coords, SEED)
			for key in entries:
				var layer: int = (int(key) >> 16) & 0xFF
				if layer != 1:
					continue
				var entry: Dictionary = entries[key]
				if int(entry["atlas_x"]) != REEDS_ATLAS.x \
						or int(entry["atlas_y"]) != REEDS_ATLAS.y:
					continue
				reeds_checked += 1
				var lx: int = (int(key) >> 8) & 0xFF
				var ly: int = int(key) & 0xFF
				assert_bool(_reed_position_is_water_adjacent(coords, lx, ly, SEED)
				).override_failure_message(
					"reed at chunk %s local (%d,%d) has no water neighbour" % [coords, lx, ly]
				).is_true()
	assert_int(reeds_checked).override_failure_message(
		"scanned 0 reeds across the sample area — the spawn rule may be broken"
	).is_greater(0)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _count_reeds_across_chunks(top_left: Vector2i, bottom_right: Vector2i,
		world_seed: int) -> int:
	var total := 0
	for cy in range(top_left.y, bottom_right.y + 1):
		for cx in range(top_left.x, bottom_right.x + 1):
			var entries: Dictionary = ProceduralGenerator.generate_chunk(
				Vector2i(cx, cy), world_seed)
			for key in entries:
				var layer: int = (int(key) >> 16) & 0xFF
				if layer != 1:
					continue
				var entry: Dictionary = entries[key]
				if int(entry["atlas_x"]) == REEDS_ATLAS.x \
						and int(entry["atlas_y"]) == REEDS_ATLAS.y:
					total += 1
	return total

func _chunk_has_reeds(entries: Dictionary) -> bool:
	for key in entries:
		var layer: int = (int(key) >> 16) & 0xFF
		if layer != 1:
			continue
		var entry: Dictionary = entries[key]
		if int(entry["atlas_x"]) == REEDS_ATLAS.x \
				and int(entry["atlas_y"]) == REEDS_ATLAS.y:
			return true
	return false

## Returns true if the cell at (lx, ly) inside chunk `coords` is water OR any
## of its 4-cardinal neighbours (looked up through the entries of whatever
## chunk owns them) is water. Re-generates chunk entries on demand.
func _reed_position_is_water_adjacent(coords: Vector2i, lx: int, ly: int,
		world_seed: int) -> bool:
	var local_entries: Dictionary = ProceduralGenerator.generate_chunk(coords, world_seed)
	if _ground_is_water(local_entries, lx, ly):
		return true
	var neighbours := [
		Vector2i(lx - 1, ly), Vector2i(lx + 1, ly),
		Vector2i(lx, ly - 1), Vector2i(lx, ly + 1),
	]
	# Cache cross-chunk lookups by chunk coord so we don't re-generate the same
	# neighbour chunk four times.
	var neighbour_chunk_cache: Dictionary = {}
	neighbour_chunk_cache[coords] = local_entries
	for n in neighbours:
		var nlx: int = n.x
		var nly: int = n.y
		var ncoords := coords
		if nlx < 0:
			nlx += Constants.CHUNK_SIZE
			ncoords.x -= 1
		elif nlx >= Constants.CHUNK_SIZE:
			nlx -= Constants.CHUNK_SIZE
			ncoords.x += 1
		if nly < 0:
			nly += Constants.CHUNK_SIZE
			ncoords.y -= 1
		elif nly >= Constants.CHUNK_SIZE:
			nly -= Constants.CHUNK_SIZE
			ncoords.y += 1
		if not neighbour_chunk_cache.has(ncoords):
			neighbour_chunk_cache[ncoords] = ProceduralGenerator.generate_chunk(
				ncoords, world_seed)
		if _ground_is_water(neighbour_chunk_cache[ncoords], nlx, nly):
			return true
	return false

func _ground_is_water(entries: Dictionary, lx: int, ly: int) -> bool:
	var key: int = CoordUtils.make_crdt_key(0, lx, ly)
	if not entries.has(key):
		return false
	return int((entries[key] as Dictionary)["atlas_x"]) == WATER_ATLAS_X
