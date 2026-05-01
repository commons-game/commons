## ProceduralGenerator — stateless procedural world generation.
## Given chunk coords + world seed, produces a deterministic tile layout.
##
## Biomes radiate outward from Constants.SPAWN_CHUNK by Chebyshev distance:
##   Tier 1 (0–3 chunks):  Verdant (Bloom) / Moraine (Still)
##   Tier 2 (4–7 chunks):  Tangle (Bloom)  / Shard   (Still)
##   Tier 3 (8+ chunks):   Mire   (Bloom)  / Hollow  (Still)
##
## Bloom/Still split is determined by a large-scale force noise so regions
## are organic patches rather than hard lines.
class_name ProceduralGenerator

enum Biome {
	VERDANT = 0,  # tier 1 Bloom — soft, living, familiar
	MORAINE = 1,  # tier 1 Still — worn smooth, old stone, glacial
	TANGLE  = 2,  # tier 2 Bloom — dense, hungry, getting strange
	SHARD   = 3,  # tier 2 Still — geometric outcrops, crystal formations
	MIRE    = 4,  # tier 3 Bloom — deep fungal, bioluminescent, wrong
	HOLLOW  = 5,  # tier 3 Still — calcified, petrified, silent
}

const TIER_1_MAX := 3   # Chebyshev chunks from spawn
const TIER_2_MAX := 7

## Returns the biome for a chunk. Deterministic given coords + spawn + seed.
static func get_biome(coords: Vector2i, spawn_chunk: Vector2i, world_seed: int) -> Biome:
	var dx: int = coords.x - spawn_chunk.x
	var dy: int = coords.y - spawn_chunk.y
	var dist: int = max(abs(dx), abs(dy))  # Chebyshev distance

	# Large-scale force noise — determines Bloom vs Still dominance in a region.
	# Low frequency (0.04) creates broad organic patches rather than checkerboard.
	var fn := FastNoiseLite.new()
	fn.seed = world_seed ^ 0x9E3779B9
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.04
	var is_bloom: bool = fn.get_noise_2d(coords.x, coords.y) >= 0.0

	if dist <= TIER_1_MAX:
		return Biome.VERDANT if is_bloom else Biome.MORAINE
	elif dist <= TIER_2_MAX:
		return Biome.TANGLE if is_bloom else Biome.SHARD
	else:
		return Biome.MIRE if is_bloom else Biome.HOLLOW

## Ground tile atlas_x given biome + terrain noise value t ∈ [-1, 1].
## atlas_x: 0=grass, 1=dirt, 2=stone, 3=water
##
## Thresholds are calibrated to the ACTUAL noise distribution, not the theoretical
## uniform distribution. FastNoiseLite/SimplexSmooth clusters heavily near 0 and
## rarely exceeds ±0.65 for the seeds and frequencies used here. All thresholds
## are kept within [-0.55, 0.65] to guarantee every tile type can appear.
static func _ground_atlas(biome: int, t: float) -> int:
	match biome:
		Biome.VERDANT:
			# Lush starting zone. Grass dominant, patches of water, dirt, stone.
			if t < -0.40: return 3  # water  ~30%
			if t < 0.15:  return 0  # grass  ~27%
			if t < 0.50:  return 1  # dirt   ~17%
			return 2                # stone  ~26%
		Biome.MORAINE:
			# Worn plateau. Stone dominant, less water than Verdant.
			if t < -0.50: return 3  # water  ~25%
			if t < 0.30:  return 2  # stone  ~40%  ← centered on 0 = most common
			if t < 0.60:  return 1  # dirt   ~15%
			return 0                # grass  ~20%
		Biome.TANGLE:
			# Dense wetlands. Heavy water, grass where it's dry.
			if t < -0.10: return 3  # water  ~45%
			if t < 0.35:  return 0  # grass  ~22%
			if t < 0.55:  return 1  # dirt   ~10%
			return 2                # stone  ~23%
		Biome.SHARD:
			# Crystalline highlands. Stone very dominant, sparse grass.
			if t < -0.50: return 3  # water  ~25%
			if t < 0.40:  return 2  # stone  ~45%  ← wide middle range
			if t < 0.60:  return 1  # dirt   ~10%
			return 0                # grass  ~20%
		Biome.MIRE:
			# Boggy deep biome. Half water, soft ground.
			if t < 0.00:  return 3  # water  ~50%
			if t < 0.35:  return 1  # dirt   ~17%
			if t < 0.55:  return 0  # grass  ~10%
			return 2                # stone  ~23%
		Biome.HOLLOW:
			# Calcified wasteland. Stone dominant, oppressively empty.
			if t < -0.50: return 3  # water  ~25%
			if t < 0.45:  return 2  # stone  ~47%  ← wide middle range
			if t < 0.60:  return 1  # dirt   ~7%
			return 0                # grass  ~21%
	return 0

## Object tile atlas coords given biome + ground atlas + object noise o ∈ [-1, 1].
## Returns Vector2i(-1,-1) for no object.
##
## Object noise thresholds are also calibrated to actual distribution.
## Original code used o > 0.3 (trees) and o > 0.5 (rocks) — both work reliably.
## All thresholds here stay within that range.
static func _object_atlas(biome: int, ground: int, o: float) -> Vector2i:
	match biome:
		Biome.VERDANT:
			if ground == 0 and o > 0.30:  return Vector2i(0, 1)  # tree  ~35%
			if ground == 2 and o > 0.50:  return Vector2i(1, 1)  # rock  ~25%
			if ground == 1 and o > 0.55:  return Vector2i(2, 2)  # plant ~22%
		Biome.MORAINE:
			if ground == 2 and o > 0.40:  return Vector2i(1, 1)  # rock  ~30%
			if ground == 0 and o > 0.60:  return Vector2i(0, 1)  # tree  ~20%
		Biome.TANGLE:
			# Claustrophobic — trees on almost every grass tile
			if ground == 0 and o > 0.00:  return Vector2i(0, 1)  # tree  ~50%
			if ground == 1 and o > 0.40:  return Vector2i(2, 2)  # plant ~30%
		Biome.SHARD:
			# Ether crystals checked FIRST (higher priority, higher threshold).
			# Rock checked second — conditions don't conflict since crystal fires first.
			if ground == 2 and o > 0.55:  return Vector2i(3, 2)  # ether crystal ~22%
			if ground == 2 and o > 0.25:  return Vector2i(1, 1)  # rock  ~37%
		Biome.MIRE:
			if ground == 0 and o > 0.20:  return Vector2i(0, 1)  # tree   ~40%
			if ground == 1 and o > 0.35:  return Vector2i(2, 2)  # plant  ~32%
		Biome.HOLLOW:
			# Sparse rocks only — oppressive silence. Use reliable threshold.
			if ground == 2 and o > 0.50:  return Vector2i(1, 1)  # rock   ~25%
	return Vector2i(-1, -1)

## Reed atlas — water-adjacent harvestable (Phase 1a of bedroll/reeds).
const REEDS_ATLAS := Vector2i(4, 1)

## Per-biome reed-spawn threshold on the same object noise channel.
## Verdant: scattered patches. Tangle: denser (more of the chunk is wet anyway).
## Other biomes: NaN sentinel meaning "no reeds here".
##
## Thresholds chosen against the calibrated noise distribution and against the
## actual water density per biome (measured empirically — Verdant has ~5% water
## tiles, not the ~30% the comments in _ground_atlas predict). The water-edge
## gate already strongly limits where reeds can land, so we use a permissive
## noise threshold (-0.10 in Verdant) so that water-adjacent walkable cells
## become reed beds at ~50-60% density — readable as a "reed bed" rather than
## a single isolated stalk. Tangle is even more permissive (-0.20) since reeds
## should suit the wetlands palette there.
static func _reeds_threshold(biome: int) -> float:
	match biome:
		Biome.VERDANT: return -0.10
		Biome.TANGLE:  return -0.20
		_:             return INF  # never spawns

## Decide whether the cell at world coords (wx, wy) on `ground` should host a
## reed. Returns the reed atlas or Vector2i(-1, -1).
##
## Constraints: biome must be Verdant or Tangle; ground must be a walkable
## non-water tile (grass=0, dirt=1, stone=2 — water=3 is excluded since reeds
## render on a dry bank, not on the water surface itself); object noise o must
## clear the per-biome threshold; AND at least one of the four cardinal
## neighbours' generated ground tile must be water.
##
## The neighbour check has to use the NEIGHBOUR chunk's biome (not the
## spawning chunk's), because the same noise value classifies to different
## ground tiles across biome boundaries. Without that the spawner can place a
## reed whose actual generated 4-neighbours contain no water — a real
## consistency bug at the seam between Verdant/Tangle and Moraine/Shard.
##
## Stateless: re-derives the neighbour chunk coords + neighbour biome each
## call. The terrain-noise FastNoiseLite is shared across chunks (its seed
## XORs with chunk coords inside generate_chunk so neighbour-chunk noise has a
## different seed) — so we have to construct a noise object for the neighbour
## chunk too. Cheap because it's only invoked on the cells that already
## cleared the much-rarer threshold check.
static func _reeds_atlas(biome: int, ground: int, wx: int, wy: int,
		o: float, world_seed: int, spawn_chunk: Vector2i) -> Vector2i:
	if ground == 3:
		return Vector2i(-1, -1)
	var threshold: float = _reeds_threshold(biome)
	if is_inf(threshold):
		return Vector2i(-1, -1)
	if o <= threshold:
		return Vector2i(-1, -1)
	# Cheap adjacency check — water on any cardinal neighbour is enough.
	# Diagonals deliberately omitted: matches the player's read of "near the
	# water's edge" and keeps reed patches hugging shorelines rather than
	# fanning out into corners.
	for delta in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nwx: int = wx + delta.x
		var nwy: int = wy + delta.y
		# Resolve neighbour's chunk coords + biome. Match generate_chunk's
		# noise seeding so the noise value we sample equals what the neighbour
		# chunk would actually use to classify its ground.
		var ncx: int = int(floor(float(nwx) / float(Constants.CHUNK_SIZE)))
		var ncy: int = int(floor(float(nwy) / float(Constants.CHUNK_SIZE)))
		var ncoords := Vector2i(ncx, ncy)
		var nbiome: int = get_biome(ncoords, spawn_chunk, world_seed)
		var nnoise := FastNoiseLite.new()
		nnoise.seed = world_seed ^ (ncx * 73856093) ^ (ncy * 19349663)
		nnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nnoise.frequency = 0.08
		var nt := nnoise.get_noise_2d(nwx, nwy)
		if _ground_atlas(nbiome, nt) == 3:
			return REEDS_ATLAS
	return Vector2i(-1, -1)

static func generate_chunk(coords: Vector2i, world_seed: int) -> Dictionary:
	var biome := get_biome(coords, Constants.SPAWN_CHUNK, world_seed)

	var noise_terrain := FastNoiseLite.new()
	noise_terrain.seed = world_seed ^ (coords.x * 73856093) ^ (coords.y * 19349663)
	noise_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_terrain.frequency = 0.08

	var noise_objects := FastNoiseLite.new()
	noise_objects.seed = world_seed ^ (coords.x * 83492791) ^ (coords.y * 17026789)
	noise_objects.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_objects.frequency = 0.15

	var entries := {}
	for ly in range(Constants.CHUNK_SIZE):
		for lx in range(Constants.CHUNK_SIZE):
			var wx := coords.x * Constants.CHUNK_SIZE + lx
			var wy := coords.y * Constants.CHUNK_SIZE + ly
			var t := noise_terrain.get_noise_2d(wx, wy)
			var o := noise_objects.get_noise_2d(wx, wy)
			var atlas_x := _ground_atlas(biome, t)
			entries[CoordUtils.make_crdt_key(0, lx, ly)] = {
				"tile_id": 0, "atlas_x": atlas_x, "atlas_y": 0,
				"alt_tile": 0, "timestamp": 0.0, "author_id": ""}
			# Reeds get FIRST claim on water-adjacent walkable cells — trees
			# and rocks shouldn't grow in waterlogged soil, so reeds out-prioritise
			# them along shorelines. Falls through to _object_atlas for any cell
			# that isn't a reed candidate.
			var obj := _reeds_atlas(biome, atlas_x, wx, wy, o,
				world_seed, Constants.SPAWN_CHUNK)
			if obj == Vector2i(-1, -1):
				obj = _object_atlas(biome, atlas_x, o)
			if obj != Vector2i(-1, -1):
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
					"tile_id": 0, "atlas_x": obj.x, "atlas_y": obj.y, "alt_tile": 0,
					"timestamp": 0.0, "author_id": ""}
	return entries

## Generate an alien "shifting lands" chunk using an alternate seed.
## Inverted biome: water/stone dominant, ether crystals as rare unique reward.
static func generate_shifted_chunk(coords: Vector2i, world_seed: int, shift_seed: int) -> Dictionary:
	var noise_terrain := FastNoiseLite.new()
	noise_terrain.seed = (world_seed ^ shift_seed) ^ (coords.x * 73856093) ^ (coords.y * 19349663)
	noise_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_terrain.frequency = 0.10

	var noise_objects := FastNoiseLite.new()
	noise_objects.seed = (world_seed ^ shift_seed) ^ (coords.x * 83492791) ^ (coords.y * 17026789)
	noise_objects.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_objects.frequency = 0.18

	var entries := {}
	for ly in range(Constants.CHUNK_SIZE):
		for lx in range(Constants.CHUNK_SIZE):
			var wx := coords.x * Constants.CHUNK_SIZE + lx
			var wy := coords.y * Constants.CHUNK_SIZE + ly
			var t := noise_terrain.get_noise_2d(wx, wy)
			var atlas_x := 3 if t < 0.1 else (2 if t < 0.5 else (1 if t < 0.7 else 0))
			entries[CoordUtils.make_crdt_key(0, lx, ly)] = {
				"tile_id": 0, "atlas_x": atlas_x, "atlas_y": 0,
				"alt_tile": 0, "timestamp": 0.0, "author_id": ""}
			var o := noise_objects.get_noise_2d(wx, wy)
			if atlas_x == 2 and o > 0.84:
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
					"tile_id": 0, "atlas_x": 3, "atlas_y": 2, "alt_tile": 0,
					"timestamp": 0.0, "author_id": ""}
			elif atlas_x == 2 and o > 0.4:
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
					"tile_id": 0, "atlas_x": 1, "atlas_y": 1, "alt_tile": 0,
					"timestamp": 0.0, "author_id": ""}
	return entries
