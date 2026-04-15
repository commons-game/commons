## Tests for Health component.
extends GdUnitTestSuite

const HealthScript := preload("res://world/mobs/Health.gd")

func test_take_damage_reduces_hp() -> void:
	var h = HealthScript.new()
	h._init(100)
	h.take_damage(30)
	assert_int(h.current_hp).is_equal(70)

func test_death_signal_fires_at_zero() -> void:
	var h = HealthScript.new()
	h._init(10)
	var calls := [0]
	h.died.connect(func(): calls[0] += 1)
	h.take_damage(10)
	assert_int(calls[0]).is_equal(1)

func test_cannot_go_below_zero() -> void:
	var h = HealthScript.new()
	h._init(10)
	h.take_damage(999)
	assert_int(h.current_hp).is_equal(0)

func test_heal_clamps_to_max() -> void:
	var h = HealthScript.new()
	h._init(100)
	h.take_damage(40)
	h.heal(999)
	assert_int(h.current_hp).is_equal(100)

func test_is_alive_returns_false_after_death() -> void:
	var h = HealthScript.new()
	h._init(10)
	h.take_damage(10)
	assert_bool(h.is_alive()).is_false()
