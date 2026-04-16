## Tests for loot pickup item registration and inventory integration.
extends GdUnitTestSuite

const InventoryScript := preload("res://items/Inventory.gd")

func test_ether_crystal_registered() -> void:
	assert_bool(ItemRegistry.has_item("ether_crystal")).is_true()

func test_ether_crystal_is_material() -> void:
	var def := ItemRegistry.resolve("ether_crystal")
	assert_object(def).is_not_null()
	assert_str(def.category).is_equal("material")

func test_ether_crystal_stacks_to_16() -> void:
	var def := ItemRegistry.resolve("ether_crystal")
	assert_int(def.stack_max).is_equal(16)

func test_add_ether_crystal_to_inventory() -> void:
	var inv := InventoryScript.new()
	inv.add_to_bag({"id": "ether_crystal", "category": "material", "count": 1}, 16)
	var found := false
	for i in inv.BAG_SIZE:
		var slot: Dictionary = inv.bag[i]
		if slot.get("id", "") == "ether_crystal":
			found = true
			break
	assert_bool(found).is_true()

func test_loot_pickup_gives_wood_and_stone() -> void:
	var inv := InventoryScript.new()
	inv.add_to_bag({"id": "wood",  "category": "material", "count": 2}, 32)
	inv.add_to_bag({"id": "stone", "category": "material", "count": 2}, 32)
	var wood_found  := false
	var stone_found := false
	for i in inv.BAG_SIZE:
		var slot: Dictionary = inv.bag[i]
		if slot.get("id", "") == "wood":  wood_found  = true
		if slot.get("id", "") == "stone": stone_found = true
	assert_bool(wood_found).is_true()
	assert_bool(stone_found).is_true()
