## ChunkWeightSystem — tracks chunk durability and triggers fade+eviction.
## Runs on a 5s tick. Chunks below FADE_THRESHOLD fade out, get deleted,
## and regenerate procedurally on next visit.
class_name ChunkWeightSystem
extends Node

const TICK_INTERVAL := 5.0
const MODIFICATION_WEIGHT := 2.0
const RECENCY_HALF_LIFE := 3600.0    # seconds; set to 30.0 in tests to verify quickly
const VISIT_BASE_SCORE := 10.0       # weight granted to recently-visited unmodified chunks
const NEIGHBORHOOD_BONUS_CAP := 50.0
const FADE_DURATION := 10.0          # seconds for visual alpha tween

var _timer: float = 0.0
@onready var chunk_manager: ChunkManager = $"../ChunkManager"

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= TICK_INTERVAL:
		_timer = 0.0
		_recalculate_all()

func _recalculate_all() -> void:
	var now := Time.get_unix_time_from_system()
	for coords in chunk_manager.get_loaded_chunk_coords():
		var chunk := chunk_manager.get_chunk(coords)
		if chunk == null or chunk.is_fading:
			continue
		var mod_score := float(chunk.modification_count) * MODIFICATION_WEIGHT
		var age := maxf(now - chunk.last_visited, 0.0)
		var decay := pow(0.5, age / RECENCY_HALF_LIFE)
		var recency := mod_score * decay
		# Unmodified but recently-visited chunks still get weight so they don't fade
		# while the player is nearby. VISIT_BASE_SCORE decays on the same half-life.
		var visit_score := VISIT_BASE_SCORE * decay if chunk.last_visited > 0.0 else 0.0
		var neighbor_sum := 0.0
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := chunk_manager.get_chunk(coords + offset)
			if n:
				neighbor_sum += n.weight
		chunk.weight = recency + visit_score + minf(neighbor_sum * 0.1, NEIGHBORHOOD_BONUS_CAP)
		if chunk.weight < Constants.FADE_THRESHOLD:
			chunk.is_fading = true
			_start_fade(chunk)

func _start_fade(chunk: ChunkData) -> void:
	var tween := get_tree().create_tween()
	tween.tween_property(chunk, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(_evict.bind(chunk.chunk_coords))

func _evict(coords: Vector2i) -> void:
	Backend.delete_chunk(coords)
	chunk_manager.force_unload_chunk_no_persist(coords)
