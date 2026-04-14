## Tests for TalismanItem — item carrying a merge_pressure_modifier.
##
## Rules:
##   - TalismanItem has an id and a merge_pressure_modifier (float, default 1.0).
##   - apply_to(pressure_system) calls pressure_system.apply_talisman_modifier().
##   - Multiple talismans stack multiplicatively (each calls apply_talisman_modifier
##     in sequence, which multiplies ramp_rate each time).
##   - modifier=1.0 (identity) has no effect on pressure.
extends GdUnitTestSuite

const TalismanItemScript      := preload("res://networking/TalismanItem.gd")
const MergePressureScript     := preload("res://networking/MergePressureSystem.gd")

func _make_talisman(modifier: float) -> Object:
	var t = TalismanItemScript.new()
	t.modifier = modifier
	return t

func _make_pressure() -> Object:
	return MergePressureScript.new()

# --- apply_to scales ramp_rate ---

func test_modifier_two_doubles_ramp_rate() -> void:
	var pressure = _make_pressure()
	var base: float = pressure.ramp_rate
	_make_talisman(2.0).apply_to(pressure)
	assert_that(pressure.ramp_rate).is_equal(base * 2.0)

func test_modifier_half_halves_ramp_rate() -> void:
	var pressure = _make_pressure()
	var base: float = pressure.ramp_rate
	_make_talisman(0.5).apply_to(pressure)
	assert_that(pressure.ramp_rate).is_equal(base * 0.5)

func test_modifier_identity_has_no_effect() -> void:
	var pressure = _make_pressure()
	var base: float = pressure.ramp_rate
	_make_talisman(1.0).apply_to(pressure)
	assert_that(pressure.ramp_rate).is_equal(base)

func test_multiple_talismans_stack_multiplicatively() -> void:
	var pressure = _make_pressure()
	var base: float = pressure.ramp_rate
	_make_talisman(2.0).apply_to(pressure)
	_make_talisman(3.0).apply_to(pressure)
	assert_that(pressure.ramp_rate).is_equal(base * 6.0)

# --- metadata ---

func test_talisman_stores_id() -> void:
	var t = TalismanItemScript.new()
	t.id = "compass_of_the_lost"
	assert_that(t.id).is_equal("compass_of_the_lost")

func test_talisman_default_modifier_is_one() -> void:
	var t = TalismanItemScript.new()
	assert_that(t.modifier).is_equal(1.0)
