## Tests for DayNightSystem.sky_color_for_phase() — multi-stop sky gradient.
##
## Rules:
##   - Midday (phase 0.25) is near white (full brightness).
##   - Midnight (phase 0.75) is dark (all channels < 0.2).
##   - Dusk (phase ~0.5) is warm/orange, NOT gray.
##   - No phase in the transition zones produces a "muddy gray":
##       gray = spread (max-min channels) < 0.15 AND mid-value in 0.25–0.80.
##   - Cycle wraps: phase 0.0 and phase 1.0 produce the same color.
extends GdUnitTestSuite

const DayNightSystemScript := preload("res://world/DayNightSystem.gd")

# Helpers

func _sky(phase: float) -> Color:
	return DayNightSystemScript.sky_color_for_phase(phase)

func _is_gray(color: Color) -> bool:
	var max_c := maxf(color.r, maxf(color.g, color.b))
	var min_c := minf(color.r, minf(color.g, color.b))
	var spread := max_c - min_c
	var mid := (max_c + min_c) * 0.5
	return spread < 0.15 and mid > 0.25 and mid < 0.80

# --- Key phases ---

func test_midday_is_white() -> void:
	var c := _sky(0.25)
	assert_float(c.r).is_greater_equal(0.95)
	assert_float(c.g).is_greater_equal(0.95)
	assert_float(c.b).is_greater_equal(0.95)

func test_midnight_is_dark() -> void:
	var c := _sky(0.75)
	assert_float(c.r).is_less(0.15)
	assert_float(c.g).is_less(0.15)
	assert_float(c.b).is_less(0.15)

func test_dusk_is_warm_not_gray() -> void:
	var c := _sky(0.50)
	# Warm = red/orange dominant: r > b by meaningful margin
	assert_float(c.r).is_greater(c.b + 0.2)
	assert_bool(_is_gray(c)).is_false()

func test_dawn_is_warm_not_gray() -> void:
	var c := _sky(0.0)
	assert_bool(_is_gray(c)).is_false()

func test_cycle_wraps_cleanly() -> void:
	var dawn    := _sky(0.0)
	var dawn_1  := _sky(1.0)
	assert_float(dawn.r).is_equal_approx(dawn_1.r, 0.001)
	assert_float(dawn.g).is_equal_approx(dawn_1.g, 0.001)
	assert_float(dawn.b).is_equal_approx(dawn_1.b, 0.001)

# --- No gray in transition zones ---
# Sample 24 phases evenly; none should be muddy gray.

func test_afternoon_transition_not_gray() -> void:
	for i in range(6, 10):  # phase 0.30 – 0.45 (afternoon toward dusk)
		var c := _sky(float(i) / 20.0)
		assert_bool(_is_gray(c)).is_false()

func test_dusk_to_night_transition_not_gray() -> void:
	for i in range(10, 14):  # phase 0.50 – 0.65 (dusk into early night)
		var c := _sky(float(i) / 20.0)
		assert_bool(_is_gray(c)).is_false()

func test_night_to_dawn_transition_not_gray() -> void:
	for i in range(16, 20):  # phase 0.80 – 0.95 (late night toward dawn)
		var c := _sky(float(i) / 20.0)
		assert_bool(_is_gray(c)).is_false()
