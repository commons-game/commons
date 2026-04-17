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
	# Remove from tracking list.
	_active_sprouts = _active_sprouts.filter(func(s): return s != sprout)
	# Drop Pulp loot tile at death position.
	if chunk_manager != null:
		chunk_manager.place_tile(tile_pos, 1, 0, Vector2i(3, 1), 0, "pulp_drop")
