## MobSpawner — spawns Mob instances around a world position.
## Not parallel-safe: do not call spawn() concurrently from multiple agents.
extends Node

const MobScene := preload("res://world/mobs/Mob.tscn")

## Spawn `count` mobs within `radius` tiles of `origin_world_pos`.
## chunk_manager and player must be passed in.
## Returns Array of spawned Mob nodes.
func spawn(origin_world_pos: Vector2i, count: int, radius: int,
           chunk_manager: ChunkManager, player: Node, parent: Node) -> Array:
	var mobs: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(origin_world_pos.x * 31337 + origin_world_pos.y * 99991)
	var attempts := 0
	var max_attempts := count * 20  # retry generously to avoid bad luck on water
	while mobs.size() < count and attempts < max_attempts:
		attempts += 1
		var wx := origin_world_pos.x + rng.randi_range(-radius, radius)
		var wy := origin_world_pos.y + rng.randi_range(-radius, radius)
		# Skip water tiles (atlas x=3) and unloaded chunks (atlas x<0)
		var ground: Vector2i = chunk_manager.get_ground_atlas_at(Vector2i(wx, wy))
		if ground.x < 0 or ground.x == 3:
			continue
		var mob = MobScene.instantiate()
		mob.position = Vector2(wx * Constants.TILE_SIZE + Constants.TILE_SIZE / 2.0,
		                       wy * Constants.TILE_SIZE + Constants.TILE_SIZE / 2.0)
		mob.chunk_manager = chunk_manager
		mob.player = player
		parent.add_child(mob)
		mob.mob_died.connect(_on_mob_died.bind(chunk_manager))
		mobs.append(mob)
	print("MobSpawner: placed %d/%d mobs near %s (%d attempts)" % [mobs.size(), count, origin_world_pos, attempts])
	return mobs

func _on_mob_died(tile_pos: Vector2i, chunk_manager: ChunkManager) -> void:
	# Place a loot pickup tile (atlas 3,1) at the mob's death position
	chunk_manager.place_tile(tile_pos, 1, 0, Vector2i(3, 1), 0, "mob_drop")
