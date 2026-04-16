## ProceduralGenerator — stateless procedural world generation.
## Given chunk coords + world seed, produces a deterministic tile layout.
## Gotcha: XOR with large primes per-chunk to avoid tiling artifacts.
## Gotcha: never pass world_seed directly to all chunks — identical terrain.
class_name ProceduralGenerator

static func generate_chunk(coords: Vector2i, world_seed: int) -> Dictionary:
	var noise_terrain := FastNoiseLite.new()
	# XOR with large primes per-chunk to avoid tiling artifacts
	noise_terrain.seed = world_seed ^ (coords.x * 73856093) ^ (coords.y * 19349663)
	noise_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_terrain.frequency = 0.08

	var noise_objects := FastNoiseLite.new()
	noise_objects.seed = world_seed ^ (coords.x * 83492791) ^ (coords.y * 17026789)
	# TYPE_SIMPLEX_SMOOTH gives uniform distribution in [-1, 1] so thresholds are
	# predictable: p(x > T) ≈ (1-T)/2. TYPE_CELLULAR was avoided because its
	# RETURN_DISTANCE values cluster heavily near -0.88, making thresholds above
	# ~-0.50 unreachable for >99% of tiles (empirically: only 0-5 objects per chunk).
	noise_objects.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_objects.frequency = 0.15

	var entries := {}
	for ly in range(Constants.CHUNK_SIZE):
		for lx in range(Constants.CHUNK_SIZE):
			var wx := coords.x * Constants.CHUNK_SIZE + lx
			var wy := coords.y * Constants.CHUNK_SIZE + ly
			var t := noise_terrain.get_noise_2d(wx, wy)
			# atlas_x: 3=water (t<-0.2), 0=grass (t<0.2), 1=dirt (t<0.5), 2=stone (else)
			var atlas_x := 3 if t < -0.2 else (0 if t < 0.2 else (1 if t < 0.5 else 2))
			var key := CoordUtils.make_crdt_key(0, lx, ly)
			entries[key] = {"tile_id": 0, "atlas_x": atlas_x, "atlas_y": 0,
			                "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
			var o := noise_objects.get_noise_2d(wx, wy)
			# TYPE_SIMPLEX_SMOOTH distributes uniformly in [-1, 1].
			# p(x > T) ≈ (1-T)/2 — thresholds are directly interpretable as density.
			# 0.3 → ~35% of grass tiles get trees (lush forest feel, easy to find/collide)
			# 0.5 → ~25% of stone tiles get rocks
			if atlas_x == 0 and o > 0.3:
				# Tree on grass
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
				    "tile_id": 0, "atlas_x": 0, "atlas_y": 1, "alt_tile": 0,
				    "timestamp": 0.0, "author_id": ""}
			elif atlas_x == 2 and o > 0.5:
				# Rock on stone
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
				    "tile_id": 0, "atlas_x": 1, "atlas_y": 1, "alt_tile": 0,
				    "timestamp": 0.0, "author_id": ""}
			elif atlas_x == 1 and o > 0.68:
				# Plant on dirt (~8% of dirt tiles: p(x > 0.68) ≈ (1-0.68)/2 = 0.16,
				# but dirt is a subset of ground, so effective density ~8% overall)
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
				    "tile_id": 0, "atlas_x": 2, "atlas_y": 2, "alt_tile": 0,
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
			## Inverted biome: water dominates, stone common, grass rare
			var atlas_x := 3 if t < 0.1 else (2 if t < 0.5 else (1 if t < 0.7 else 0))
			var key := CoordUtils.make_crdt_key(0, lx, ly)
			entries[key] = {"tile_id": 0, "atlas_x": atlas_x, "atlas_y": 0,
			                "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
			var o := noise_objects.get_noise_2d(wx, wy)
			if atlas_x == 2 and o > 0.84:
				## Ether crystal — unique Shifting Lands reward
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
				    "tile_id": 0, "atlas_x": 3, "atlas_y": 2, "alt_tile": 0,
				    "timestamp": 0.0, "author_id": ""}
			elif atlas_x == 2 and o > 0.4:
				## Rock (more common in shifting lands)
				entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
				    "tile_id": 0, "atlas_x": 1, "atlas_y": 1, "alt_tile": 0,
				    "timestamp": 0.0, "author_id": ""}
	return entries
