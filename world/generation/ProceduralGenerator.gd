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
## Thresholds chosen so each biome has a distinct feel at a glance.
static func _ground_atlas(biome: int, t: float) -> int:
	match biome:
		Biome.VERDANT:
			# Lush starting zone. Half grass, pockets of water, dirt, stone.
			if t < -0.70: return 3  # water  ~15%
			if t < 0.30:  return 0  # grass  ~50%
			if t < 0.65:  return 1  # dirt   ~17%
			return 2                # stone  ~18%
		Biome.MORAINE:
			# Worn, open plateau. Stone and dirt dominant, sparse grass.
			if t < -0.75: return 3  # water  ~12%
			if t < 0.20:  return 2  # stone  ~47%
			if t < 0.60:  return 1  # dirt   ~20%
			return 0                # grass  ~21%
		Biome.TANGLE:
			# Dense wetlands. Lots of water, grass where it's dry.
			if t < -0.30: return 3  # water  ~35%
			if t < 0.50:  return 0  # grass  ~40%
			if t < 0.80:  return 1  # dirt   ~15%
			return 2                # stone  ~10%
		Biome.SHARD:
			# Crystalline highlands. Stone almost everywhere.
			if t < -0.75: return 3  # water  ~12%
			if t < 0.40:  return 2  # stone  ~57%
			if t < 0.75:  return 1  # dirt   ~17%
			return 0                # grass  ~14%
		Biome.MIRE:
			# Boggy deep biome. Half water, dangerous to navigate.
			if t < -0.30: return 3  # water  ~35%
			if t < 0.20:  return 1  # dirt   ~25%
			if t < 0.60:  return 0  # grass  ~20%
			return 2                # stone  ~20%
		Biome.HOLLOW:
			# Calcified wasteland. Nearly pure stone.
			if t < -0.80: return 3  # water  ~10%
			if t < 0.60:  return 2  # stone  ~70%
			if t < 0.85:  return 1  # dirt   ~12%
			return 0                # grass  ~8%
	return 0

## Object tile atlas coords given biome + ground atlas + object noise o ∈ [-1, 1].
## Returns Vector2i(-1,-1) for no object.
static func _object_atlas(biome: int, ground: int, o: float) -> Vector2i:
	match biome:
		Biome.VERDANT:
			if ground == 0 and o > 0.30:  return Vector2i(0, 1)  # tree  ~35%
			if ground == 2 and o > 0.50:  return Vector2i(1, 1)  # rock  ~25%
			if ground == 1 and o > 0.68:  return Vector2i(2, 2)  # plant ~16%
		Biome.MORAINE:
			if ground == 2 and o > 0.40:  return Vector2i(1, 1)  # rock  ~30%
			if ground == 0 and o > 0.70:  return Vector2i(0, 1)  # tree  ~15%
		Biome.TANGLE:
			# Claustrophobic — trees on almost every grass tile
			if ground == 0 and o > 0.00:  return Vector2i(0, 1)  # tree  ~50%
			if ground == 1 and o > 0.50:  return Vector2i(2, 2)  # plant ~25%
		Biome.SHARD:
			if ground == 2 and o > 0.30:  return Vector2i(1, 1)  # rock   ~35%
			if ground == 2 and o > 0.78:  return Vector2i(3, 2)  # ether crystal ~11%
		Biome.MIRE:
			if ground == 0 and o > 0.20:  return Vector2i(0, 1)  # tree   ~40%
			if ground == 1 and o > 0.40:  return Vector2i(2, 2)  # plant  ~30%
		Biome.HOLLOW:
			# Near-empty. Sparse rocks, nothing else — oppressive silence.
			if ground == 2 and o > 0.70:  return Vector2i(1, 1)  # rock   ~15%
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
			var obj := _object_atlas(biome, atlas_x, o)
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
