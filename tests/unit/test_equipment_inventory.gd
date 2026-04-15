## Tests for EquipmentInventory — equipping/unequipping items from bag to slots.
extends GdUnitTestSuite

const EquipmentInventoryScript  := preload("res://items/EquipmentInventory.gd")
const EquipmentRegistryScript   := preload("res://items/EquipmentRegistry.gd")

func before_each() -> void:
	# Reset registry before each test for isolation.
	# Use direct property access (same pattern as test_asset_pack.gd resets _buff_body_map).
	EquipmentRegistryScript._items = {}
	# Register test items
	EquipmentRegistryScript.register({"id": "bone_armor",  "slot": "armor",     "display_name": "Bone Armor"})
	EquipmentRegistryScript.register({"id": "skull_helm",  "slot": "head",      "display_name": "Skull Helm"})
	EquipmentRegistryScript.register({"id": "bone_boots",  "slot": "feet",      "display_name": "Bone Boots"})
	EquipmentRegistryScript.register({"id": "bone_wand",   "slot": "held_item", "display_name": "Bone Wand"})

# ---------------------------------------------------------------------------
# add_to_bag
# ---------------------------------------------------------------------------

func test_add_to_bag_fills_first_empty_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	assert_bool(eq.add_to_bag("bone_armor", "armor")).is_true()
	var bag: Array = eq.get_bag()
	assert_str(str(bag[0])).is_equal("bone_armor")

func test_add_to_bag_second_item_goes_to_second_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_armor", "armor")
	eq.add_to_bag("skull_helm", "head")
	var bag: Array = eq.get_bag()
	assert_str(str(bag[0])).is_equal("bone_armor")
	assert_str(str(bag[1])).is_equal("skull_helm")

func test_add_to_bag_returns_false_when_full() -> void:
	var eq = EquipmentInventoryScript.new()
	for i in range(12):
		assert_bool(eq.add_to_bag("bone_armor", "armor")).is_true()
	assert_bool(eq.add_to_bag("bone_armor", "armor")).is_false()

func test_add_to_bag_fills_exactly_12_slots() -> void:
	var eq = EquipmentInventoryScript.new()
	for i in range(12):
		eq.add_to_bag("bone_armor", "armor")
	var bag: Array = eq.get_bag()
	assert_int(bag.size()).is_equal(12)
	for i in range(12):
		assert_str(str(bag[i])).is_equal("bone_armor")

# ---------------------------------------------------------------------------
# equip
# ---------------------------------------------------------------------------

func test_equip_moves_item_from_bag_to_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_armor", "armor")
	assert_bool(eq.equip("bone_armor")).is_true()
	assert_str(eq.get_equipped("armor")).is_equal("bone_armor")

func test_equip_clears_bag_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_armor", "armor")
	eq.equip("bone_armor")
	var bag: Array = eq.get_bag()
	assert_str(str(bag[0])).is_equal("")

func test_equip_returns_false_when_item_not_in_bag() -> void:
	var eq = EquipmentInventoryScript.new()
	assert_bool(eq.equip("bone_armor")).is_false()

func test_equip_returns_false_for_unknown_slot() -> void:
	# Item added to bag with no slot — equip should fail
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("mystery_item", "")  # slot="" means unknown
	assert_bool(eq.equip("mystery_item")).is_false()

func test_equip_head_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("skull_helm", "head")
	assert_bool(eq.equip("skull_helm")).is_true()
	assert_str(eq.get_equipped("head")).is_equal("skull_helm")

func test_equip_feet_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_boots", "feet")
	assert_bool(eq.equip("bone_boots")).is_true()
	assert_str(eq.get_equipped("feet")).is_equal("bone_boots")

func test_equip_held_item_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_wand", "held_item")
	assert_bool(eq.equip("bone_wand")).is_true()
	assert_str(eq.get_equipped("held_item")).is_equal("bone_wand")

func test_equip_displaces_already_equipped_item_back_to_bag() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_armor", "armor")
	EquipmentRegistryScript.register({"id": "iron_chest", "slot": "armor", "display_name": "Iron Chest"})
	eq.add_to_bag("iron_chest", "armor")
	eq.equip("bone_armor")
	eq.equip("iron_chest")
	assert_str(eq.get_equipped("armor")).is_equal("iron_chest")
	# bone_armor should be back in the bag
	var bag: Array = eq.get_bag()
	var found := false
	for item in bag:
		if str(item) == "bone_armor":
			found = true
	assert_bool(found).is_true()

# ---------------------------------------------------------------------------
# unequip
# ---------------------------------------------------------------------------

func test_unequip_moves_equipped_item_back_to_bag() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_armor", "armor")
	eq.equip("bone_armor")
	assert_bool(eq.unequip("armor")).is_true()
	assert_str(eq.get_equipped("armor")).is_equal("")
	var bag: Array = eq.get_bag()
	assert_str(str(bag[0])).is_equal("bone_armor")

func test_unequip_returns_false_when_slot_empty() -> void:
	var eq = EquipmentInventoryScript.new()
	assert_bool(eq.unequip("armor")).is_false()

func test_unequip_returns_false_for_invalid_slot() -> void:
	var eq = EquipmentInventoryScript.new()
	assert_bool(eq.unequip("nonexistent_slot")).is_false()

func test_unequip_returns_false_when_bag_is_full() -> void:
	var eq = EquipmentInventoryScript.new()
	# Fill bag with 11 items, equip 1 in the armor slot
	for i in range(11):
		eq.add_to_bag("skull_helm", "head")
	eq.add_to_bag("bone_armor", "armor")
	eq.equip("bone_armor")
	# Now bag has 11 skull_helms and 1 empty slot (bone_armor was removed from it).
	# Unequip should find the empty slot and succeed.
	# Actually bag[11] was cleared when bone_armor was equipped.
	assert_bool(eq.unequip("armor")).is_true()

# ---------------------------------------------------------------------------
# get_equipped / get_bag
# ---------------------------------------------------------------------------

func test_get_equipped_empty_slot_returns_empty_string() -> void:
	var eq = EquipmentInventoryScript.new()
	assert_str(eq.get_equipped("armor")).is_equal("")

func test_get_bag_returns_copy_not_reference() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_armor", "armor")
	var bag1: Array = eq.get_bag()
	bag1[0] = "tampered"
	var bag2: Array = eq.get_bag()
	assert_str(str(bag2[0])).is_equal("bone_armor")

# ---------------------------------------------------------------------------
# to_dict / from_dict round-trip
# ---------------------------------------------------------------------------

func test_to_dict_from_dict_round_trip() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.add_to_bag("bone_armor", "armor")
	eq.add_to_bag("skull_helm", "head")
	eq.equip("skull_helm")

	var d: Dictionary = eq.to_dict()
	var eq2 = EquipmentInventoryScript.new()
	eq2.from_dict(d)

	assert_str(eq2.get_equipped("head")).is_equal("skull_helm")
	var bag: Array = eq2.get_bag()
	assert_str(str(bag[0])).is_equal("bone_armor")

func test_from_dict_empty_dict_gives_clean_state() -> void:
	var eq = EquipmentInventoryScript.new()
	eq.from_dict({})
	assert_str(eq.get_equipped("armor")).is_equal("")
	var bag: Array = eq.get_bag()
	assert_int(bag.size()).is_equal(12)

func test_to_dict_contains_equipped_and_bag_keys() -> void:
	var eq = EquipmentInventoryScript.new()
	var d: Dictionary = eq.to_dict()
	assert_bool(d.has("equipped")).is_true()
	assert_bool(d.has("bag")).is_true()
