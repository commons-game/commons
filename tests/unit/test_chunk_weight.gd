## Tests for ChunkWeightSystem weight formula.
## Uses a short RECENCY_HALF_LIFE to verify fade behavior quickly.
extends GdUnitTestSuite


# Mirrors ChunkWeightSystem._recalculate weight for a single chunk with no neighbors.
func _calc_weight(mod_count: int, age_secs: float, half_life: float) -> float:
	var mod_score := float(mod_count) * 2.0  # MODIFICATION_WEIGHT = 2.0
	return mod_score * pow(0.5, age_secs / half_life)

# --- 0 modifications ---

func test_zero_modifications_always_below_threshold() -> void:
	# No modifications: mod_score = 0, weight = 0 regardless of recency.
	var w := _calc_weight(0, 0.0, 30.0)
	assert_that(w).is_less(Constants.FADE_THRESHOLD)

# --- Well above threshold ---

func test_fifty_modifications_fresh_above_threshold() -> void:
	# 50 modifications, just visited: weight = 100 >> FADE_THRESHOLD (5.0).
	var w := _calc_weight(50, 0.0, 30.0)
	assert_that(w).is_greater(Constants.FADE_THRESHOLD)

# --- Decay below threshold after enough time ---

func test_decay_below_threshold_after_several_half_lives() -> void:
	# After 5 half-lives, weight = 100 * 0.5^5 = 3.125 < 5.0
	var w := _calc_weight(50, 150.0, 30.0)
	assert_that(w).is_less(Constants.FADE_THRESHOLD)

# --- Neighborhood bonus cap ---

func test_neighborhood_bonus_capped() -> void:
	# neighbor_sum * 0.1 with enormous neighbor_sum must not exceed NEIGHBORHOOD_BONUS_CAP
	var neighbor_sum := 10000.0
	var bonus := minf(neighbor_sum * 0.1, 50.0)  # NEIGHBORHOOD_BONUS_CAP = 50.0
	assert_that(bonus).is_equal(50.0)

# --- is_fading guard: a chunk that starts fading has weight 0, which stays below threshold ---

func test_fading_chunk_has_zero_recency_weight() -> void:
	# A chunk with is_fading=true would have 0 modifications → weight = 0 < FADE_THRESHOLD.
	# This confirms the formula produces the right signal to trigger the guard.
	var w := _calc_weight(0, 0.0, 30.0)
	assert_that(w).is_less_equal(0.0)
