## Unit tests for StatusEffectSystem — base-game duration/magnitude effects.
## Distinct from BuffManager (shrine-scoped mod buffs).
extends GdUnitTestSuite

const StatusEffectSystemScript := preload("res://mods/StatusEffectSystem.gd")

var _sys: Object

func before_test() -> void:
	_sys = StatusEffectSystemScript.new()

func after_test() -> void:
	_sys.free()

# --- Basic add / query ---

func test_add_effect_is_active() -> void:
	_sys.add_effect("poison", 5.0, 3.0)
	assert_that(_sys.has_effect("poison")).is_true()

func test_missing_effect_not_active() -> void:
	assert_that(_sys.has_effect("poison")).is_false()

func test_get_magnitude_returns_value() -> void:
	_sys.add_effect("slow", 10.0, 0.5)
	assert_float(_sys.get_effect_magnitude("slow")).is_equal(0.5)

func test_get_magnitude_missing_returns_zero() -> void:
	assert_float(_sys.get_effect_magnitude("slow")).is_equal(0.0)

func test_get_active_effects_contains_added() -> void:
	_sys.add_effect("haste", 3.0, 1.5)
	var effects: Array = _sys.get_active_effects()
	assert_that(effects.size()).is_equal(1)
	assert_that(effects[0]["id"]).is_equal("haste")
	assert_float(effects[0]["magnitude"]).is_equal(1.5)

func test_multiple_effects_tracked_independently() -> void:
	_sys.add_effect("poison", 5.0, 1.0)
	_sys.add_effect("slow",   3.0, 0.5)
	assert_that(_sys.get_active_effects().size()).is_equal(2)
	assert_that(_sys.has_effect("poison")).is_true()
	assert_that(_sys.has_effect("slow")).is_true()

# --- Overwrite ---

func test_add_same_id_overwrites() -> void:
	_sys.add_effect("poison", 5.0, 1.0)
	_sys.add_effect("poison", 10.0, 2.0)
	assert_that(_sys.get_active_effects().size()).is_equal(1)
	assert_float(_sys.get_effect_magnitude("poison")).is_equal(2.0)

# --- Remove ---

func test_remove_effect_clears_it() -> void:
	_sys.add_effect("poison", 5.0, 1.0)
	_sys.remove_effect("poison")
	assert_that(_sys.has_effect("poison")).is_false()

func test_remove_missing_effect_is_no_op() -> void:
	_sys.remove_effect("nonexistent")  # should not throw
	assert_that(_sys.get_active_effects().size()).is_equal(0)

# --- Duration expiry via tick ---

func test_tick_does_not_expire_with_remaining_time() -> void:
	_sys.add_effect("poison", 5.0, 1.0)
	_sys.tick(1.0)
	assert_that(_sys.has_effect("poison")).is_true()

func test_tick_expires_when_duration_elapsed() -> void:
	_sys.add_effect("poison", 2.0, 1.0)
	_sys.tick(2.0)
	assert_that(_sys.has_effect("poison")).is_false()

func test_tick_expires_on_exact_boundary() -> void:
	_sys.add_effect("poison", 1.0, 1.0)
	_sys.tick(1.0)
	assert_that(_sys.has_effect("poison")).is_false()

func test_tick_accumulates_across_calls() -> void:
	_sys.add_effect("poison", 3.0, 1.0)
	_sys.tick(1.5)
	assert_that(_sys.has_effect("poison")).is_true()
	_sys.tick(1.5)
	assert_that(_sys.has_effect("poison")).is_false()

func test_tick_only_expires_elapsed_effects() -> void:
	_sys.add_effect("short", 1.0, 1.0)
	_sys.add_effect("long",  5.0, 1.0)
	_sys.tick(2.0)
	assert_that(_sys.has_effect("short")).is_false()
	assert_that(_sys.has_effect("long")).is_true()

# --- Permanent effects (duration <= 0 = never expire) ---

func test_permanent_effect_never_expires() -> void:
	_sys.add_effect("aura", 0.0, 1.0)  # duration 0 = permanent
	_sys.tick(9999.0)
	assert_that(_sys.has_effect("aura")).is_true()

# --- Signals (verified via manual connect) ---

func test_effect_expired_signal_fires_on_expiry() -> void:
	var fired_ids: Array = []
	_sys.effect_expired.connect(func(id: String) -> void: fired_ids.append(id))
	_sys.add_effect("poison", 1.0, 1.0)
	_sys.tick(1.0)
	assert_that(fired_ids).contains(["poison"])

func test_effects_changed_fires_on_add() -> void:
	# Use Array as reference container — int is value-copied in GDScript lambdas
	var calls := [0]
	_sys.effects_changed.connect(func(_e: Array) -> void: calls[0] += 1)
	_sys.add_effect("poison", 1.0, 1.0)
	assert_that(calls[0]).is_equal(1)

func test_effects_changed_fires_on_remove() -> void:
	_sys.add_effect("poison", 1.0, 1.0)
	var calls := [0]
	_sys.effects_changed.connect(func(_e: Array) -> void: calls[0] += 1)
	_sys.remove_effect("poison")
	assert_that(calls[0]).is_equal(1)

func test_effects_changed_fires_on_expiry() -> void:
	var calls := [0]
	_sys.effects_changed.connect(func(_e: Array) -> void: calls[0] += 1)
	_sys.add_effect("poison", 1.0, 1.0)
	calls[0] = 0  # reset counter after the add emission
	_sys.tick(1.0)
	assert_that(calls[0]).is_equal(1)
