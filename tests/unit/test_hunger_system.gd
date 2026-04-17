## Tests for the food/hunger system on Player.
##
## Strategy: instantiate Player as a bare CharacterBody2D without a full scene.
## @onready vars null-assign but we only exercise the hunger logic, which only
## needs `food`, `max_food`, `_food_timer`, `_starvation_timer`, and `hp`.
## We call _process(delta) directly to simulate time passing.
extends GdUnitTestSuite

const PlayerScript := preload("res://player/Player.gd")
const InventoryScript := preload("res://items/Inventory.gd")

## Minimal stub for chunk_manager (required by _physics_process path).
## Not needed here since we only call _process() directly.

var _player: Node = null

func before_test() -> void:
	_player = PlayerScript.new()
	# Suppress @onready errors — node won't be in a full scene tree.
	# We only test properties and _process logic.
	add_child(_player)
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null

# ---------------------------------------------------------------------------
# Initial state
# ---------------------------------------------------------------------------

func test_player_starts_with_food_100() -> void:
	assert_int(_player.food).is_equal(100)

func test_player_max_food_is_100() -> void:
	assert_int(_player.max_food).is_equal(100)

# ---------------------------------------------------------------------------
# Food depletion over time
# ---------------------------------------------------------------------------

func test_food_decrements_after_drain_interval() -> void:
	# Reset to known state.
	_player.food = 100
	_player._food_timer = 0.0
	# Simulate exactly one drain interval.
	_player._process(float(_player.FOOD_DRAIN_INTERVAL))
	assert_int(_player.food).is_equal(99)

func test_food_decrements_twice_after_two_intervals() -> void:
	_player.food = 100
	_player._food_timer = 0.0
	_player._process(float(_player.FOOD_DRAIN_INTERVAL) * 2.0)
	assert_int(_player.food).is_equal(98)

func test_food_does_not_deplete_before_interval() -> void:
	_player.food = 100
	_player._food_timer = 0.0
	# Just under one interval.
	_player._process(float(_player.FOOD_DRAIN_INTERVAL) - 0.01)
	assert_int(_player.food).is_equal(100)

# ---------------------------------------------------------------------------
# Floor at zero
# ---------------------------------------------------------------------------

func test_food_never_goes_below_zero() -> void:
	_player.food = 1
	_player._food_timer = 0.0
	# Force two drain ticks: food would go to -1 without floor.
	_player._process(float(_player.FOOD_DRAIN_INTERVAL) * 2.0)
	assert_int(_player.food).is_equal(0)

func test_food_stays_at_zero_with_many_ticks() -> void:
	_player.food = 0
	_player._food_timer = 0.0
	for _i in range(10):
		_player._process(float(_player.FOOD_DRAIN_INTERVAL))
	assert_int(_player.food).is_equal(0)

# ---------------------------------------------------------------------------
# Eating restores food
# ---------------------------------------------------------------------------

func test_eating_berry_restores_30_food() -> void:
	_player.food = 50
	# Give the player a berry in the bag.
	var inv = InventoryScript.new()
	inv.add_to_bag({"id": "berry", "category": "food", "count": 1}, 32)
	_player.inventory = inv
	_player._try_eat()
	assert_int(_player.food).is_equal(80)

func test_eating_clamps_food_at_max() -> void:
	_player.food = 90
	var inv = InventoryScript.new()
	inv.add_to_bag({"id": "berry", "category": "food", "count": 1}, 32)
	_player.inventory = inv
	_player._try_eat()
	# 90 + 30 = 120, clamped to 100.
	assert_int(_player.food).is_equal(100)

func test_eating_does_nothing_if_bag_is_empty() -> void:
	_player.food = 50
	var inv = InventoryScript.new()
	_player.inventory = inv
	_player._try_eat()
	assert_int(_player.food).is_equal(50)

func test_eating_removes_berry_from_bag() -> void:
	_player.food = 50
	var inv = InventoryScript.new()
	inv.add_to_bag({"id": "berry", "category": "food", "count": 2}, 32)
	_player.inventory = inv
	_player._try_eat()
	assert_int(inv.bag_stack_total("berry")).is_equal(1)

func test_eating_when_food_full_clamps_at_max() -> void:
	_player.food = 100
	var inv = InventoryScript.new()
	inv.add_to_bag({"id": "berry", "category": "food", "count": 1}, 32)
	_player.inventory = inv
	_player._try_eat()
	assert_int(_player.food).is_equal(100)

# ---------------------------------------------------------------------------
# Starvation: food=0 — damage disabled until food items exist
# ---------------------------------------------------------------------------

func test_starvation_does_not_deal_damage_when_disabled() -> void:
	# Starvation damage is intentionally disabled until consumable food items
	# are added to the game. This test documents the current disabled state.
	# Re-enable (and update this test) when food items are implemented.
	_player.food = 0
	_player._food_timer = 0.0
	_player._starvation_timer = 0.0
	var starting_hp: int = _player.hp
	_player._process(float(_player.STARVATION_INTERVAL))
	assert_int(_player.hp).is_equal(starting_hp)  # no damage — disabled

func test_starvation_does_not_trigger_when_food_above_zero() -> void:
	_player.food = 1
	_player._food_timer = 0.0
	_player._starvation_timer = 0.0
	var starting_hp: int = _player.hp
	_player._process(float(_player.STARVATION_INTERVAL))
	# No starvation damage (food=1 > 0).
	assert_int(_player.hp).is_equal(starting_hp)

func test_starvation_timer_resets_when_food_is_restored() -> void:
	_player.food = 0
	_player._starvation_timer = float(_player.STARVATION_INTERVAL) - 0.1
	_player.food = 10  # eat something — food restored
	_player._process(0.05)
	# Starvation timer should reset to 0 when food > 0.
	assert_float(_player._starvation_timer).is_equal(0.0)
