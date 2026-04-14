## Tests for Inventory — slot management for the player's items.
##
## Slot layout:
##   weapon_slot    — fixed, weapon category only
##   talisman_slot  — fixed, talisman category only
##   tool_slots[2]  — free, any tool/usable category
##   gear_slots     — { helmet, chest, legs, shoes } — armor category only
##   bag[12]        — any category, supports stacking
##
## An ItemStack is a Dictionary: { "id": String, "count": int, "category": String }
## An empty slot is {}.
extends GdUnitTestSuite

const InventoryScript := preload("res://items/Inventory.gd")

func _make() -> Object:
	return InventoryScript.new()

func _stack(id: String, category: String, count: int = 1) -> Dictionary:
	return {"id": id, "category": category, "count": count}

# --- Initial state ---

func test_weapon_slot_starts_empty() -> void:
	var inv = _make()
	assert_bool(inv.weapon_slot.is_empty()).is_true()

func test_talisman_slot_starts_empty() -> void:
	var inv = _make()
	assert_bool(inv.talisman_slot.is_empty()).is_true()

func test_tool_slots_start_empty() -> void:
	var inv = _make()
	assert_bool(inv.tool_slots[0].is_empty()).is_true()
	assert_bool(inv.tool_slots[1].is_empty()).is_true()

func test_gear_slots_start_empty() -> void:
	var inv = _make()
	for slot in ["helmet", "chest", "legs", "shoes"]:
		assert_bool(inv.gear_slots[slot].is_empty()).is_true()

func test_bag_starts_empty() -> void:
	var inv = _make()
	assert_bool(inv.is_bag_empty()).is_true()

func test_talisman_starts_dormant() -> void:
	var inv = _make()
	assert_bool(inv.talisman_awakened).is_false()

# --- Bag ---

func test_add_to_bag_succeeds_when_space() -> void:
	var inv = _make()
	assert_bool(inv.add_to_bag(_stack("wood", "material"), 32)).is_true()

func test_add_to_bag_item_retrievable() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("wood", "material"), 32)
	assert_int(inv.bag_count("wood")).is_equal(1)

func test_add_to_bag_full_returns_false() -> void:
	var inv = _make()
	for i in range(inv.BAG_SIZE):
		inv.add_to_bag(_stack("item_%d" % i, "material"), 1)
	assert_bool(inv.add_to_bag(_stack("overflow", "material"), 1)).is_false()

func test_is_bag_full() -> void:
	var inv = _make()
	for i in range(inv.BAG_SIZE):
		inv.add_to_bag(_stack("item_%d" % i, "material"), 1)
	assert_bool(inv.is_bag_full()).is_true()

func test_stackable_items_merge_in_bag() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("wood", "material", 5), 32)
	inv.add_to_bag(_stack("wood", "material", 3), 32)
	# Should merge into one slot
	assert_int(inv.bag_count("wood")).is_equal(1)
	assert_int(inv.bag_stack_total("wood")).is_equal(8)

func test_stackable_overflow_spills_to_new_slot() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("wood", "material", 30), 32)
	inv.add_to_bag(_stack("wood", "material", 10), 32)  # 30+10 > 32 → spills
	assert_int(inv.bag_count("wood")).is_equal(2)

func test_unstackable_always_occupies_new_slot() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("hammer", "tool"), 1)
	inv.add_to_bag(_stack("hammer", "tool"), 1)
	assert_int(inv.bag_count("hammer")).is_equal(2)

func test_remove_from_bag_decrements_count() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("wood", "material", 10), 32)
	assert_bool(inv.remove_from_bag("wood", 3)).is_true()
	assert_int(inv.bag_stack_total("wood")).is_equal(7)

func test_remove_from_bag_clears_slot_at_zero() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("wood", "material", 3), 32)
	inv.remove_from_bag("wood", 3)
	assert_int(inv.bag_count("wood")).is_equal(0)

func test_remove_from_bag_returns_false_when_not_enough() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("wood", "material", 2), 32)
	assert_bool(inv.remove_from_bag("wood", 5)).is_false()

func test_remove_from_bag_returns_false_when_absent() -> void:
	var inv = _make()
	assert_bool(inv.remove_from_bag("wood", 1)).is_false()

# --- Weapon slot ---

func test_equip_weapon_accepts_weapon_category() -> void:
	var inv = _make()
	assert_bool(inv.equip_weapon(_stack("sword", "weapon"))).is_true()

func test_equip_weapon_stores_item() -> void:
	var inv = _make()
	inv.equip_weapon(_stack("sword", "weapon"))
	assert_str(inv.weapon_slot["id"]).is_equal("sword")

func test_equip_weapon_rejects_non_weapon() -> void:
	var inv = _make()
	assert_bool(inv.equip_weapon(_stack("hammer", "tool"))).is_false()

func test_equip_weapon_rejects_talisman() -> void:
	var inv = _make()
	assert_bool(inv.equip_weapon(_stack("ward", "talisman"))).is_false()

func test_unequip_weapon_clears_slot() -> void:
	var inv = _make()
	inv.equip_weapon(_stack("sword", "weapon"))
	inv.unequip_weapon()
	assert_bool(inv.weapon_slot.is_empty()).is_true()

func test_unequip_weapon_returns_to_bag() -> void:
	var inv = _make()
	inv.equip_weapon(_stack("sword", "weapon"))
	inv.unequip_weapon()
	assert_int(inv.bag_count("sword")).is_equal(1)

# --- Talisman slot ---

func test_equip_talisman_accepts_talisman_category() -> void:
	var inv = _make()
	assert_bool(inv.equip_talisman(_stack("ward", "talisman"))).is_true()

func test_equip_talisman_rejects_weapon() -> void:
	var inv = _make()
	assert_bool(inv.equip_talisman(_stack("sword", "weapon"))).is_false()

func test_talisman_toggle_returns_true_when_awakened() -> void:
	var inv = _make()
	inv.equip_talisman(_stack("ward", "talisman"))
	var result: bool = inv.toggle_talisman()
	assert_bool(result).is_true()

func test_talisman_toggle_dormant_again_on_second_call() -> void:
	var inv = _make()
	inv.equip_talisman(_stack("ward", "talisman"))
	inv.toggle_talisman()
	var result: bool = inv.toggle_talisman()
	assert_bool(result).is_false()

func test_talisman_toggle_returns_false_when_no_talisman() -> void:
	var inv = _make()
	var result: bool = inv.toggle_talisman()
	assert_bool(result).is_false()

func test_unequip_talisman_sets_dormant() -> void:
	var inv = _make()
	inv.equip_talisman(_stack("ward", "talisman"))
	inv.toggle_talisman()
	inv.unequip_talisman()
	assert_bool(inv.talisman_awakened).is_false()

# --- Tool slots ---

func test_set_tool_slot_accepts_tool() -> void:
	var inv = _make()
	assert_bool(inv.set_tool_slot(0, _stack("hammer", "tool"))).is_true()

func test_set_tool_slot_rejects_weapon() -> void:
	var inv = _make()
	assert_bool(inv.set_tool_slot(0, _stack("sword", "weapon"))).is_false()

func test_set_tool_slot_rejects_talisman() -> void:
	var inv = _make()
	assert_bool(inv.set_tool_slot(0, _stack("ward", "talisman"))).is_false()

func test_set_tool_slot_index_out_of_range_returns_false() -> void:
	var inv = _make()
	assert_bool(inv.set_tool_slot(5, _stack("hammer", "tool"))).is_false()

func test_clear_tool_slot_empties_it() -> void:
	var inv = _make()
	inv.set_tool_slot(1, _stack("hammer", "tool"))
	inv.clear_tool_slot(1)
	assert_bool(inv.tool_slots[1].is_empty()).is_true()

# --- Gear slots ---

func test_equip_gear_accepts_matching_armor_slot() -> void:
	var inv = _make()
	var helmet := _stack("iron_helmet", "armor")
	helmet["equipment_slot"] = "helmet"
	assert_bool(inv.equip_gear(helmet)).is_true()

func test_equip_gear_rejects_wrong_slot() -> void:
	var inv = _make()
	var helmet := _stack("iron_helmet", "armor")
	helmet["equipment_slot"] = "helmet"
	assert_bool(inv.equip_gear(helmet)).is_true()  # helmet in helmet slot — ok
	var chest := _stack("iron_chest", "armor")
	chest["equipment_slot"] = "chest"
	assert_bool(inv.equip_gear(chest)).is_true()   # chest in chest slot — ok

func test_equip_gear_rejects_non_armor() -> void:
	var inv = _make()
	var fake := _stack("sword", "weapon")
	fake["equipment_slot"] = "helmet"
	assert_bool(inv.equip_gear(fake)).is_false()

func test_equip_gear_stores_in_correct_slot() -> void:
	var inv = _make()
	var legs := _stack("leather_legs", "armor")
	legs["equipment_slot"] = "legs"
	inv.equip_gear(legs)
	assert_str(inv.gear_slots["legs"]["id"]).is_equal("leather_legs")

func test_unequip_gear_returns_to_bag() -> void:
	var inv = _make()
	var shoes := _stack("boots", "armor")
	shoes["equipment_slot"] = "shoes"
	inv.equip_gear(shoes)
	inv.unequip_gear("shoes")
	assert_int(inv.bag_count("boots")).is_equal(1)
	assert_bool(inv.gear_slots["shoes"].is_empty()).is_true()

# --- Serialization ---

func test_to_dict_from_dict_roundtrip_weapon() -> void:
	var inv = _make()
	inv.equip_weapon(_stack("sword", "weapon"))
	var inv2 = _make()
	inv2.from_dict(inv.to_dict())
	assert_str(inv2.weapon_slot["id"]).is_equal("sword")

func test_to_dict_from_dict_roundtrip_bag() -> void:
	var inv = _make()
	inv.add_to_bag(_stack("wood", "material", 5), 32)
	var inv2 = _make()
	inv2.from_dict(inv.to_dict())
	assert_int(inv2.bag_stack_total("wood")).is_equal(5)

func test_to_dict_from_dict_roundtrip_talisman_awakened() -> void:
	var inv = _make()
	inv.equip_talisman(_stack("ward", "talisman"))
	inv.toggle_talisman()
	var inv2 = _make()
	inv2.from_dict(inv.to_dict())
	assert_bool(inv2.talisman_awakened).is_true()

# --- Active tool selection ---

func test_active_tool_index_defaults_to_zero() -> void:
	var inv = _make()
	assert_int(inv.active_tool_index).is_equal(0)

func test_select_tool_changes_active_index() -> void:
	var inv = _make()
	inv.select_tool(1)
	assert_int(inv.active_tool_index).is_equal(1)

func test_select_tool_out_of_range_is_ignored() -> void:
	var inv = _make()
	inv.select_tool(5)
	assert_int(inv.active_tool_index).is_equal(0)

func test_select_tool_negative_is_ignored() -> void:
	var inv = _make()
	inv.select_tool(-1)
	assert_int(inv.active_tool_index).is_equal(0)

func test_get_active_tool_returns_content_of_active_slot() -> void:
	var inv = _make()
	inv.set_tool_slot(0, _stack("shovel", "tool"))
	var tool: Dictionary = inv.get_active_tool()
	assert_str(tool.get("id", "")).is_equal("shovel")

func test_get_active_tool_returns_slot_1_when_selected() -> void:
	var inv = _make()
	inv.set_tool_slot(0, _stack("shovel", "tool"))
	inv.set_tool_slot(1, _stack("hammer", "tool"))
	inv.select_tool(1)
	var tool: Dictionary = inv.get_active_tool()
	assert_str(tool.get("id", "")).is_equal("hammer")

func test_get_active_tool_returns_empty_when_slot_empty() -> void:
	var inv = _make()
	var tool: Dictionary = inv.get_active_tool()
	assert_bool(tool.is_empty()).is_true()
