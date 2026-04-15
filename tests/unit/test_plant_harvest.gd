## Tests for plant tile harvesting and berry drops.
##
## Reuses the same stub pattern as test_harvest_loop.gd.
## Plant atlas = Vector2i(2, 2), max_hp = 2.
extends GdUnitTestSuite

const TileInteractionScript := preload("res://player/TileInteraction.gd")
const InventoryScript       := preload("res://items/Inventory.gd")

# ---------------------------------------------------------------------------
# Stubs (identical pattern to test_harvest_loop.gd)
# ---------------------------------------------------------------------------

class StubBus extends Node:
	var remove_calls: Array = []
	func request_remove_tile(coords: Vector2i, _layer: int) -> void:
		remove_calls.append(coords)
	func request_place_tile(_coords: Vector2i, _layer: int, _id: String) -> void:
		pass

class StubChunkManager extends Node:
	var _preset: Dictionary = {}
	func set_tile(t: Dictionary) -> void:
		_preset = t
	func get_object_tile_at(_coords: Vector2i) -> Dictionary:
		return _preset

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

var _ti: Node             = null
var _bus: StubBus         = null
var _cm: StubChunkManager = null
var _inv: Object          = null

func before_test() -> void:
	_bus = StubBus.new()
	add_child(_bus)
	_cm = StubChunkManager.new()
	add_child(_cm)
	_ti = TileInteractionScript.new()
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

func _plant() -> Dictionary:
	return {"tile_id": 0, "atlas_x": 2, "atlas_y": 2, "alt_tile": 0}

func _hit(pos: Vector2i, times: int = 1) -> void:
	for _i in range(times):
		_ti._swing_tile(pos, _inv)

# ---------------------------------------------------------------------------
# HARVESTABLE_TILES presence
# ---------------------------------------------------------------------------

func test_plant_atlas_is_in_harvestable_tiles() -> void:
	assert_bool(TileInteractionScript.HARVESTABLE_TILES.has(Vector2i(2, 2))).is_true()

func test_plant_max_hp_is_2() -> void:
	var spec: Dictionary = TileInteractionScript.HARVESTABLE_TILES[Vector2i(2, 2)]
	assert_int(int(spec["max_hp"])).is_equal(2)

func test_plant_drops_berry() -> void:
	var spec: Dictionary = TileInteractionScript.HARVESTABLE_TILES[Vector2i(2, 2)]
	var drops: Array = spec.get("drops", [])
	assert_int(drops.size()).is_greater(0)
	assert_str(str(drops[0]["id"])).is_equal("berry")

func test_berry_is_food_category_in_drops() -> void:
	var spec: Dictionary = TileInteractionScript.HARVESTABLE_TILES[Vector2i(2, 2)]
	var drops: Array = spec.get("drops", [])
	assert_int(drops.size()).is_greater(0)
	assert_str(str(drops[0]["category"])).is_equal("food")

# ---------------------------------------------------------------------------
# Plant HP: max_hp = 2
# ---------------------------------------------------------------------------

func test_plant_survives_first_hit() -> void:
	_cm.set_tile(_plant())
	_hit(Vector2i(50, 50))
	assert_int(_bus.remove_calls.size()).is_equal(0)

func test_plant_dies_on_second_hit() -> void:
	_cm.set_tile(_plant())
	_hit(Vector2i(51, 51), 2)
	assert_int(_bus.remove_calls.size()).is_equal(1)

func test_plant_remove_targets_correct_coords() -> void:
	_cm.set_tile(_plant())
	var pos := Vector2i(52, 52)
	_hit(pos, 2)
	assert_bool(_bus.remove_calls.has(pos)).is_true()

# ---------------------------------------------------------------------------
# Drops
# ---------------------------------------------------------------------------

func test_plant_drops_berry_on_death() -> void:
	_cm.set_tile(_plant())
	_hit(Vector2i(53, 53), 2)
	assert_int(_inv.bag_stack_total("berry")).is_greater_equal(1)

func test_plant_drops_at_least_1_berry() -> void:
	_cm.set_tile(_plant())
	_hit(Vector2i(54, 54), 2)
	assert_int(_inv.bag_stack_total("berry")).is_greater_equal(1)

func test_plant_drops_at_most_2_berries() -> void:
	_cm.set_tile(_plant())
	_hit(Vector2i(55, 55), 2)
	assert_int(_inv.bag_stack_total("berry")).is_less_equal(2)

func test_plant_no_drops_before_death() -> void:
	_cm.set_tile(_plant())
	_hit(Vector2i(56, 56), 1)  # only 1 hit, still alive
	assert_int(_inv.bag_stack_total("berry")).is_equal(0)
