## Tests for VibeBus — two-axis ambient state machine.
##
## Rules:
##   - push(source_id, tension_delta, tone_delta, decay_seconds) adds a contribution.
##   - get_tension() / get_tone() return the summed, clamped [0,1] values.
##   - Each contribution decays to zero over its decay_seconds.
##   - Multiple sources sum independently.
##   - Pushing the same source_id replaces the previous contribution for that source.
##   - Values are always clamped to [0, 1].
##   - vibe_shifted(tension, tone) signal fires when summed state changes noticeably.
extends GdUnitTestSuite

const VibeBusScript := preload("res://world/VibeBus.gd")

func _make_bus() -> Object:
	return VibeBusScript.new()

# --- Initial state ---

func test_initial_tension_is_zero() -> void:
	var b = _make_bus()
	assert_float(b.get_tension()).is_equal(0.0)

func test_initial_tone_is_zero() -> void:
	var b = _make_bus()
	assert_float(b.get_tone()).is_equal(0.0)

# --- push adds contribution ---

func test_push_sets_tension() -> void:
	var b = _make_bus()
	b.push("combat", 0.6, 0.0, 10.0)
	assert_float(b.get_tension()).is_equal_approx(0.6, 0.001)

func test_push_sets_tone() -> void:
	var b = _make_bus()
	b.push("forest", 0.0, 0.4, 10.0)
	assert_float(b.get_tone()).is_equal_approx(0.4, 0.001)

func test_push_sets_both_axes() -> void:
	var b = _make_bus()
	b.push("event", 0.3, 0.7, 10.0)
	assert_float(b.get_tension()).is_equal_approx(0.3, 0.001)
	assert_float(b.get_tone()).is_equal_approx(0.7, 0.001)

# --- Multiple sources sum ---

func test_two_sources_sum_tension() -> void:
	var b = _make_bus()
	b.push("src_a", 0.2, 0.0, 10.0)
	b.push("src_b", 0.3, 0.0, 10.0)
	assert_float(b.get_tension()).is_equal_approx(0.5, 0.001)

func test_two_sources_sum_tone() -> void:
	var b = _make_bus()
	b.push("src_a", 0.0, 0.1, 10.0)
	b.push("src_b", 0.0, 0.2, 10.0)
	assert_float(b.get_tone()).is_equal_approx(0.3, 0.001)

# --- Same source_id replaces previous ---

func test_same_source_replaces_contribution() -> void:
	var b = _make_bus()
	b.push("src_a", 0.8, 0.0, 10.0)
	b.push("src_a", 0.2, 0.0, 10.0)
	assert_float(b.get_tension()).is_equal_approx(0.2, 0.001)

# --- Clamping ---

func test_tension_clamped_at_1() -> void:
	var b = _make_bus()
	b.push("a", 0.7, 0.0, 10.0)
	b.push("b", 0.7, 0.0, 10.0)
	assert_float(b.get_tension()).is_equal_approx(1.0, 0.001)

func test_tone_clamped_at_1() -> void:
	var b = _make_bus()
	b.push("a", 0.0, 0.9, 10.0)
	b.push("b", 0.0, 0.9, 10.0)
	assert_float(b.get_tone()).is_equal_approx(1.0, 0.001)

func test_values_never_below_zero() -> void:
	var b = _make_bus()
	assert_float(b.get_tension()).is_greater_equal(0.0)
	assert_float(b.get_tone()).is_greater_equal(0.0)

# --- Decay ---

func test_contribution_decays_to_zero_after_decay_seconds() -> void:
	var b = _make_bus()
	b.push("src", 0.8, 0.0, 2.0)
	b.tick(2.0)  # full decay period
	assert_float(b.get_tension()).is_equal_approx(0.0, 0.001)

func test_contribution_partially_decays() -> void:
	var b = _make_bus()
	b.push("src", 1.0, 0.0, 4.0)
	b.tick(2.0)  # half the decay period
	# Should be somewhere between 0 and 1 (still decaying)
	assert_float(b.get_tension()).is_greater(0.0)
	assert_float(b.get_tension()).is_less(1.0)

func test_separate_sources_decay_independently() -> void:
	var b = _make_bus()
	b.push("fast", 0.5, 0.0, 1.0)
	b.push("slow", 0.5, 0.0, 100.0)
	b.tick(1.0)  # fast source fully decayed, slow barely changed
	assert_float(b.get_tension()).is_greater(0.4)  # slow still contributing
	assert_float(b.get_tension()).is_less(0.6)     # fast gone

# --- vibe_shifted signal ---

func test_vibe_shifted_fires_after_push() -> void:
	var b = _make_bus()
	add_child(b)
	var fired: Array = [false]
	b.vibe_shifted.connect(func(_t, _n): fired[0] = true)
	b.push("src", 0.5, 0.3, 10.0)
	b.tick(0.0)  # trigger signal flush
	assert_bool(fired[0]).is_true()
	remove_child(b)

func test_vibe_shifted_passes_current_values() -> void:
	var b = _make_bus()
	add_child(b)
	var t_val: Array = [0.0]
	var n_val: Array = [0.0]
	b.vibe_shifted.connect(func(t, n):
		t_val[0] = t
		n_val[0] = n)
	b.push("src", 0.4, 0.6, 10.0)
	b.tick(0.0)
	assert_float(t_val[0]).is_equal_approx(0.4, 0.01)
	assert_float(n_val[0]).is_equal_approx(0.6, 0.01)
	remove_child(b)
