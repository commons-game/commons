## Tests for TileInteraction harvest loop — fist hits, tile HP tracking, and drops.
##
## Strategy: stub _bus and _chunk_mgr so tests run without a full scene.
## The stub bus records request_remove_tile calls rather than routing them.
## The stub chunk manager returns a preset tile entry for any coords queried.
## After add_child() fires _ready() (which tries @onready paths and null-assigns),
## we override _bus and _chunk_mgr directly before each test.
##
## What is covered:
##   - HARVESTABLE_TILES constant has correct HP and drop specs
##   - Tree (max_hp=3): survives N-1 hits, dies on Nth, drops wood
##   - Rock (max_hp=5): survives N-1 hits, dies on Nth, drops stone
##   - Ephemeral damage resets when tile not hit within DAMAGE_RESET_S
##   - Non-harvestable tiles (gravestone) are never removed
##   - Empty/missing tile is a no-op
##   - Two adjacent tiles track HP independently
extends GdUnitTestSuite

const TileInteractionScript := preload("res://player/TileInteraction.gd")
const InventoryScript       := preload("res://items/Inventory.gd")

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

## Records request_remove_tile() calls; never actually mutates the world.
class StubBus extends Node:
	var remove_calls: Array = []
	func request_remove_tile(coords: Vector2i, _layer: int) -> void:
		remove_calls.append(coords)
	func request_place_tile(_coords: Vector2i, _layer: int, _id: String) -> void:
		pass

## Returns a single preset tile entry for any coords.
class StubChunkManager extends Node:
	var _preset: Dictionary = {}
	func set_tile(t: Dictionary) -> void:
		_preset = t
	func get_object_tile_at(_coords: Vector2i) -> Dictionary:
		return _preset

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

var _ti: Node        = null
var _bus: StubBus    = null
var _cm: StubChunkManager = null
var _inv: Object     = null

func before_test() -> void:
	_bus = StubBus.new()
	add_child(_bus)
	_cm = StubChunkManager.new()
	add_child(_cm)
	_ti = TileInteractionScript.new()
	# @onready vars will null-assign (paths don't exist in test tree).
	# We override them once _ready() has run.
	add_child(_ti)
	await get_tree().process_frame
	_ti._bus       = _bus
	_ti._chunk_mgr = _cm
	_inv = InventoryScript.new()

func after_test() -> void:
	if is_instance_valid(_ti):  _ti.queue_free()
	if is_instance_valid(_bus): _bus.queue_free()
	if is_instance_valid(_cm):  _cm.queue_free()
	_ti = null; _bus = null; _cm = null; _inv = null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _tree() -> Dictionary:
	return {"tile_id": 0, "atlas_x": 0, "atlas_y": 1, "alt_tile": 0}

func _rock() -> Dictionary:
	return {"tile_id": 0, "atlas_x": 1, "atlas_y": 1, "alt_tile": 0}

func _hit(pos: Vector2i, times: int = 1) -> void:
	for _i in range(times):
		_ti._swing_tile(pos, _inv)

# ---------------------------------------------------------------------------
# HARVESTABLE_TILES constant
# ---------------------------------------------------------------------------

func test_tree_atlas_is_in_harvestable_tiles() -> void:
	assert_bool(TileInteractionScript.HARVESTABLE_TILES.has(Vector2i(0, 1))).is_true()

func test_rock_atlas_is_in_harvestable_tiles() -> void:
	assert_bool(TileInteractionScript.HARVESTABLE_TILES.has(Vector2i(1, 1))).is_true()

func test_tree_max_hp_is_3() -> void:
	var spec: Dictionary = TileInteractionScript.HARVESTABLE_TILES[Vector2i(0, 1)]
	assert_int(int(spec["max_hp"])).is_equal(3)

func test_rock_max_hp_is_5() -> void:
	var spec: Dictionary = TileInteractionScript.HARVESTABLE_TILES[Vector2i(1, 1)]
	assert_int(int(spec["max_hp"])).is_equal(5)

func test_tree_drops_wood() -> void:
	var spec: Dictionary = TileInteractionScript.HARVESTABLE_TILES[Vector2i(0, 1)]
	var drops: Array = spec.get("drops", [])
	assert_int(drops.size()).is_greater(0)
	assert_str(str(drops[0]["id"])).is_equal("wood")

func test_rock_drops_stone() -> void:
	var spec: Dictionary = TileInteractionScript.HARVESTABLE_TILES[Vector2i(1, 1)]
	var drops: Array = spec.get("drops", [])
	assert_int(drops.size()).is_greater(0)
	assert_str(str(drops[0]["id"])).is_equal("stone")

# ---------------------------------------------------------------------------
# Tree HP: max_hp = 3
# ---------------------------------------------------------------------------

func test_tree_survives_first_hit() -> void:
	_cm.set_tile(_tree())
	_hit(Vector2i(1, 1))
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_tree_survives_second_hit() -> void:
	_cm.set_tile(_tree())
	_hit(Vector2i(2, 2), 2)
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_tree_dies_on_third_hit() -> void:
	_cm.set_tile(_tree())
	_hit(Vector2i(3, 3), 3)
	assert_int(_bus.remove_calls.size()).is_equal(1)

func test_tree_remove_targets_correct_coords() -> void:
	_cm.set_tile(_tree())
	var pos := Vector2i(4, 4)
	_hit(pos, 3)
	assert_bool(_bus.remove_calls.has(pos)).is_true()

func test_tree_drops_wood_on_death() -> void:
	_cm.set_tile(_tree())
	_hit(Vector2i(5, 5), 3)
	assert_int(_inv.bag_stack_total("wood")).is_greater_equal(1)

func test_tree_drops_at_least_1_wood() -> void:
	_cm.set_tile(_tree())
	_hit(Vector2i(6, 6), 3)
	assert_int(_inv.bag_stack_total("wood")).is_greater_equal(1)

func test_tree_drops_at_most_3_wood() -> void:
	_cm.set_tile(_tree())
	_hit(Vector2i(7, 7), 3)
	assert_int(_inv.bag_stack_total("wood")).is_less_equal(3)

# ---------------------------------------------------------------------------
# Rock HP: max_hp = 5
# ---------------------------------------------------------------------------

func test_rock_survives_four_hits() -> void:
	_cm.set_tile(_rock())
	_hit(Vector2i(10, 10), 4)
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_rock_dies_on_fifth_hit() -> void:
	_cm.set_tile(_rock())
	_hit(Vector2i(11, 11), 5)
	assert_int(_bus.remove_calls.size()).is_equal(1)

func test_rock_drops_stone_on_death() -> void:
	_cm.set_tile(_rock())
	_hit(Vector2i(12, 12), 5)
	assert_int(_inv.bag_stack_total("stone")).is_greater_equal(1)

func test_rock_drops_at_most_2_stone() -> void:
	_cm.set_tile(_rock())
	_hit(Vector2i(13, 13), 5)
	assert_int(_inv.bag_stack_total("stone")).is_less_equal(2)

# ---------------------------------------------------------------------------
# Ephemeral HP reset
# ---------------------------------------------------------------------------

func test_hp_resets_after_damage_reset_window() -> void:
	# Hit tree twice (hp_remaining = 1). Then fake inactivity by backdating
	# last_hit_usec beyond DAMAGE_RESET_S. Third hit should reset → hp = 2,
	# not kill the tile.
	_cm.set_tile(_tree())
	var pos := Vector2i(20, 20)
	_hit(pos, 2)
	assert_int(_bus.remove_calls.size()).is_equal(0)
	# Backdate the hit timestamp past the reset window.
	var stale_usec := Time.get_ticks_usec() \
		- int(TileInteractionScript.DAMAGE_RESET_S * 1_000_000) - 1
	_ti._tile_damage[pos]["last_hit_usec"] = stale_usec
	# One more hit — resets then deals 1 damage. hp_remaining = 2. No kill.
	_hit(pos)
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_hp_does_not_reset_within_window() -> void:
	# Verify damage accumulates when hits are fast (no reset).
	_cm.set_tile(_tree())
	var pos := Vector2i(21, 21)
	_hit(pos, 2)
	# Immediately hit again — should use accumulated damage (hp_remaining=1 → 0)
	_hit(pos)
	assert_int(_bus.remove_calls.size()).is_equal(1)

# ---------------------------------------------------------------------------
# Non-harvestable and empty tiles
# ---------------------------------------------------------------------------

func test_gravestone_not_harvestable() -> void:
	# atlas (2,1) = gravestone — not in HARVESTABLE_TILES
	_cm.set_tile({"tile_id": 0, "atlas_x": 2, "atlas_y": 1, "alt_tile": 0})
	_hit(Vector2i(30, 30), 10)
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_loot_pickup_not_harvestable() -> void:
	# atlas (3,1) = loot_pickup — not in HARVESTABLE_TILES
	_cm.set_tile({"tile_id": 0, "atlas_x": 3, "atlas_y": 1, "alt_tile": 0})
	_hit(Vector2i(31, 31), 10)
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_empty_tile_is_noop() -> void:
	_cm.set_tile({})
	_hit(Vector2i(32, 32))
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_empty_tile_gives_no_drops() -> void:
	_cm.set_tile({})
	_hit(Vector2i(33, 33), 5)
	assert_bool(_inv.is_bag_empty()).is_true()

# ---------------------------------------------------------------------------
# Independent HP tracking per tile position
# ---------------------------------------------------------------------------

func test_two_tiles_track_hp_independently() -> void:
	_cm.set_tile(_tree())
	var pos_a := Vector2i(40, 40)
	var pos_b := Vector2i(41, 41)
	# Hit A twice, B once — neither dies (A needs 3, B needs 3)
	_hit(pos_a, 2)
	_hit(pos_b, 1)
	assert_int(_bus.remove_calls.size()).is_equal(0)
	# Third hit on A kills it; B is untouched
	_hit(pos_a)
	assert_int(_bus.remove_calls.size()).is_equal(1)
	assert_bool(_bus.remove_calls.has(pos_a)).is_true()
	assert_bool(_bus.remove_calls.has(pos_b)).is_false()

func test_killing_one_tile_does_not_affect_other() -> void:
	_cm.set_tile(_tree())
	var pos_a := Vector2i(42, 42)
	var pos_b := Vector2i(43, 43)
	_hit(pos_a, 3)  # kill A
	_hit(pos_b, 2)  # B at 1 hp remaining — should still be alive
	assert_int(_bus.remove_calls.size()).is_equal(1)  # only A removed
