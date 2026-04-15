## GravestoneScatter — deterministic gravestone placement around a shrine chunk.
##
## Separated from World.gd so it can be tested without instantiating the full scene.
## Caller is responsible for ensuring chunks in the scatter radius are loaded first.
extends Object

## Place up to `target_count` gravestone tiles (atlas 2,1, object layer) in a
## `chunk_radius`-chunk radius around `shrine_chunk`.
##
## Skips positions that:
##   - Already have an object tile (tree/rock/other — never clobber)
##   - Have a water ground tile (atlas_x == 3)
##   - Are in an unloaded chunk (get_ground_atlas_at returns (-1,-1))
##
## Returns the number of gravestones actually placed.
## Deterministic: seeded from world_seed + shrine_chunk so same world → same layout.
static func scatter(chunk_manager: ChunkManager, shrine_chunk: Vector2i,
                    world_seed: int, target_count: int = 10,
                    chunk_radius: int = 3) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ (shrine_chunk.x * 31337) ^ (shrine_chunk.y * 99991)

	var placed := 0
	var attempts := 0
	var half := Constants.CHUNK_SIZE * chunk_radius

	while placed < target_count and attempts < 50:
		attempts += 1
		var wx := shrine_chunk.x * Constants.CHUNK_SIZE + rng.randi_range(-half, half)
		var wy := shrine_chunk.y * Constants.CHUNK_SIZE + rng.randi_range(-half, half)
		var world_pos := Vector2i(wx, wy)

		# Skip positions already occupied by an object tile
		if chunk_manager.has_tile_at(world_pos, 1):
			continue

		# Skip water ground tiles (atlas_x == 3) and unloaded chunks
		var ground := chunk_manager.get_ground_atlas_at(world_pos)
		if ground.x < 0 or ground.x == 3:
			continue

		chunk_manager.place_tile(world_pos, 1, 0, Vector2i(2, 1), 0, "necromancer_shrine")
		placed += 1

	return placed
