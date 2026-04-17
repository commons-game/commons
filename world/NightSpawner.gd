## NightSpawner — spawns Sprout waves at night and clears them at dawn.
##
## Not an autoload. Instantiated by World._setup_day_night_system().
## Set `player` and `chunk_manager` before add_child.
##
## Spawn rules:
##   - 4-6 Sprouts per night wave, 8-16 tile radius around the player.
##   - Skips water tiles (atlas x=3) and unloaded chunks (atlas x<0).
##   - Grace period: no spawning in the first 30 seconds of a session.
##
## Dawn rules:
##   - Sprouts NOT currently in chase state call flee() and self-destruct after 2s.
##   - Sprouts in chase state are left to play out normally (die or lose player).
extends Node

const SproutScene := preload("res://world/mobs/Sprout.tscn")
const WispScript  := preload("res://world/mobs/Wisp.gd")
const PaleScript  := preload("res://world/mobs/Pale.gd")

## Set by World before add_child.
var player: Node = null
var chunk_manager: ChunkManager = null

## How long after session start before spawning is allowed (seconds).
const GRACE_PERIOD := 30.0

## Radius range (tiles) for spawn scatter.
const SPAWN_RADIUS_MIN := 8
const SPAWN_RADIUS_MAX := 16

## Wave size range.
const WAVE_MIN := 4
const WAVE_MAX := 6

var _session_timer: float = 0.0
var _grace_elapsed: bool = false

## All Sprouts currently alive and tracked by this spawner.
var _active_sprouts: Array = []

func _ready() -> void:
	DayClock.phase_changed.connect(_on_phase_changed)

func _process(delta: float) -> void:
	if not _grace_elapsed:
		_session_timer += delta
		if _session_timer >= GRACE_PERIOD:
			_grace_elapsed = true
			print("NightSpawner: grace period over — night spawning enabled")

func _on_phase_changed(is_day: bool) -> void:
	# Purge freed nodes from tracking list first.
	_active_sprouts = _active_sprouts.filter(func(s): return is_instance_valid(s))

	if is_day:
		_on_dawn()
	else:
		_on_dusk()

func _on_dusk() -> void:
	if not _grace_elapsed:
		print("NightSpawner: grace period active — skipping night wave")
		return
	if player == null or chunk_manager == null:
		push_warning("NightSpawner: missing player or chunk_manager — cannot spawn")
		return

	var origin := Vector2i(int(floorf(player.position.x / Constants.TILE_SIZE)),
	                       int(floorf(player.position.y / Constants.TILE_SIZE)))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec())
	var count := rng.randi_range(WAVE_MIN, WAVE_MAX)
	var placed := 0
	var attempts := 0
	var max_attempts := count * 20

	while placed < count and attempts < max_attempts:
		attempts += 1
		# Random angle and distance in tile space.
		var dist := rng.randi_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
		var angle := rng.randf_range(0.0, TAU)
		var tx := origin.x + int(round(cos(angle) * dist))
		var ty := origin.y + int(round(sin(angle) * dist))
		var ground: Vector2i = chunk_manager.get_ground_atlas_at(Vector2i(tx, ty))
		# Skip water (atlas x=3) and unloaded chunks (atlas x<0).
		if ground.x < 0 or ground.x == 3:
			continue
		# Skip tiles too close to an active campfire.
		var candidate_pos := Vector2i(tx, ty)
		var near_campfire: bool = false
		for cf_pos in CampfireRegistry.get_campfire_positions():
			if (cf_pos - candidate_pos).length() <= 6.0:
				near_campfire = true
				break
		if near_campfire:
			continue

		var sprout = SproutScene.instantiate()
		sprout.position = Vector2(tx * Constants.TILE_SIZE + Constants.TILE_SIZE / 2.0,
		                         ty * Constants.TILE_SIZE + Constants.TILE_SIZE / 2.0)
		sprout.chunk_manager = chunk_manager
		sprout.player = player
		get_parent().add_child(sprout)
		sprout.mob_died.connect(_on_sprout_died.bind(sprout))
		_active_sprouts.append(sprout)
		placed += 1

	print("NightSpawner: spawned %d/%d Sprouts near %s (%d attempts)" % [placed, count, origin, attempts])
	_spawn_night_mobs(origin, rng)

## Spawn Wisps (Bloom night mob) and Pales (Still night mob) further out.
## Mob type is chosen per-tile based on the biome at that position:
##   Bloom biomes (Verdant/Tangle/Mire) → Wisp
##   Still biomes (Moraine/Shard/Hollow) → Pale
##   Tier 1 biomes → no night mobs (only Sprouts at tier 1)
func _spawn_night_mobs(origin: Vector2i, rng: RandomNumberGenerator) -> void:
	var spawned_wisps := 0
	var spawned_pales := 0
	var target := rng.randi_range(2, 4)  # total night mobs per wave
	var attempts := 0

	while (spawned_wisps + spawned_pales) < target and attempts < target * 15:
		attempts += 1
		var dist := rng.randi_range(14, 24)
		var angle := rng.randf_range(0.0, TAU)
		var tx := origin.x + int(round(cos(angle) * dist))
		var ty := origin.y + int(round(sin(angle) * dist))
		if chunk_manager == null:
			continue
		var ground: Vector2i = chunk_manager.get_ground_atlas_at(Vector2i(tx, ty))
		if ground.x < 0 or ground.x == 3:
			continue
		var chunk_coords := CoordUtils.world_to_chunk(Vector2i(tx, ty))
		var biome := ProceduralGenerator.get_biome(chunk_coords, Constants.SPAWN_CHUNK, Constants.WORLD_SEED)
		# Tier 1 biomes: no Wisps or Pales — Sprouts only
		if biome == ProceduralGenerator.Biome.VERDANT or biome == ProceduralGenerator.Biome.MORAINE:
			continue
		var is_bloom_biome := (biome == ProceduralGenerator.Biome.TANGLE or
		                       biome == ProceduralGenerator.Biome.MIRE)
		var mob: CharacterBody2D
		if is_bloom_biome:
			mob = WispScript.new()
		else:
			mob = PaleScript.new()
		mob.position = Vector2(tx * Constants.TILE_SIZE + Constants.TILE_SIZE / 2.0,
		                       ty * Constants.TILE_SIZE + Constants.TILE_SIZE / 2.0)
		mob.chunk_manager = chunk_manager
		mob.player = player
		get_parent().add_child(mob)
		if is_bloom_biome:
			mob.mob_died.connect(_on_wisp_died.bind(mob))
			spawned_wisps += 1
		else:
			spawned_pales += 1
	print("NightSpawner: spawned %d Wisps + %d Pales (%d attempts)" % [spawned_wisps, spawned_pales, attempts])

func _on_dawn() -> void:
	var chased := 0
	var fled := 0
	for sprout in _active_sprouts:
		if not is_instance_valid(sprout):
			continue
		# Sprouts already in chase state keep fighting; others flee.
		if sprout._state == sprout.State.CHASE:
			chased += 1
		else:
			sprout.flee()
			fled += 1
	print("NightSpawner: dawn — %d Sprouts fleeing, %d still chasing" % [fled, chased])

func _on_sprout_died(tile_pos: Vector2i, sprout: Node) -> void:
	_active_sprouts = _active_sprouts.filter(func(s): return s != sprout)
	if chunk_manager != null:
		chunk_manager.place_tile(tile_pos, 1, 0, Vector2i(3, 1), 0, "pulp_drop")

func _on_wisp_died(tile_pos: Vector2i, _wisp: Node) -> void:
	# Drop a Marrow tile — the night-gated Tether ingredient.
	if chunk_manager != null:
		chunk_manager.place_tile(tile_pos, 1, 0, Vector2i(1, 2), 0, "marrow_drop")
