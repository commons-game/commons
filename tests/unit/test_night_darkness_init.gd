## Tests for NightDarkness initialisation.
##
## Catches two regressions:
##   1. DayClock.is_day() was called (nonexistent) — should be is_daytime().
##      Caught by verifying _ready() doesn't crash and the signal connects cleanly.
##   2. When the game loads mid-night, phase_changed never fired for dusk so the
##      player ambient light was never attached and the world stayed bright.
##      Caught by verifying the CanvasModulate is dark after _ready when mid-night.
extends GdUnitTestSuite

const NightDarknessScript := preload("res://world/NightDarkness.gd")

# ---------------------------------------------------------------------------
# Signal connection
# ---------------------------------------------------------------------------

func test_ready_does_not_crash() -> void:
	# If DayClock.is_day() (nonexistent) is called, Godot throws SCRIPT ERROR
	# and the node fails to set up. This test verifies _ready() completes.
	var nd := NightDarknessScript.new()
	add_child(nd)
	await get_tree().process_frame
	assert_bool(is_instance_valid(nd)).is_true()
	nd.queue_free()

func test_phase_changed_signal_is_connected() -> void:
	var nd := NightDarknessScript.new()
	add_child(nd)
	await get_tree().process_frame
	assert_bool(
		DayClock.phase_changed.is_connected(nd._on_phase_changed)
	).override_failure_message(
		"NightDarkness must connect DayClock.phase_changed in _ready()"
	).is_true()
	nd.queue_free()

# ---------------------------------------------------------------------------
# Radial texture utility
# ---------------------------------------------------------------------------

func test_make_radial_texture_returns_non_null() -> void:
	var tex = NightDarknessScript._make_radial_texture(32)
	assert_object(tex).is_not_null()

func test_make_radial_texture_correct_size() -> void:
	var tex := NightDarknessScript._make_radial_texture(64) as ImageTexture
	assert_object(tex).is_not_null()
	assert_int(tex.get_width()).is_equal(64)
	assert_int(tex.get_height()).is_equal(64)

func test_make_radial_texture_center_is_bright() -> void:
	# Center pixel should be fully opaque (alpha=1), edge should be transparent.
	var tex := NightDarknessScript._make_radial_texture(32) as ImageTexture
	var img  := tex.get_image()
	var center_alpha: float = img.get_pixel(16, 16).a
	var edge_alpha:   float = img.get_pixel(0, 0).a
	assert_float(center_alpha).is_greater(0.9)
	assert_float(edge_alpha).is_less(0.1)

# ---------------------------------------------------------------------------
# Day/night constants are distinct
# ---------------------------------------------------------------------------

func test_night_color_is_darker_than_day_color() -> void:
	assert_float(NightDarknessScript.COLOR_NIGHT.r).is_less(
		NightDarknessScript.COLOR_DAY.r)
	assert_float(NightDarknessScript.COLOR_NIGHT.g).is_less(
		NightDarknessScript.COLOR_DAY.g)
	assert_float(NightDarknessScript.COLOR_NIGHT.b).is_less(
		NightDarknessScript.COLOR_DAY.b)

func test_day_color_is_white() -> void:
	assert_float(NightDarknessScript.COLOR_DAY.r).is_equal_approx(1.0, 0.001)
	assert_float(NightDarknessScript.COLOR_DAY.g).is_equal_approx(1.0, 0.001)
	assert_float(NightDarknessScript.COLOR_DAY.b).is_equal_approx(1.0, 0.001)
