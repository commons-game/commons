## Tests for EquipmentRegistry — static item registration.
extends GdUnitTestSuite

const EquipmentRegistryScript := preload("res://items/EquipmentRegistry.gd")

func before_each() -> void:
	EquipmentRegistryScript._items = {}

# ---------------------------------------------------------------------------
# register + get_item
# ---------------------------------------------------------------------------

func test_register_and_get_item_round_trip() -> void:
	EquipmentRegistryScript.register({
		"id": "bone_armor", "slot": "armor", "display_name": "Bone Armor",
		"stats": {"defense_modifier": 1.3}
	})
	var d: Dictionary = EquipmentRegistryScript.get_item("bone_armor")
	assert_str(str(d.get("id", ""))).is_equal("bone_armor")
	assert_str(str(d.get("slot", ""))).is_equal("armor")
	assert_str(str(d.get("display_name", ""))).is_equal("Bone Armor")

func test_get_item_returns_empty_dict_for_unknown_id() -> void:
	var d: Dictionary = EquipmentRegistryScript.get_item("nonexistent")
	assert_bool(d.is_empty()).is_true()

func test_register_overwrites_existing_entry() -> void:
	EquipmentRegistryScript.register({"id": "bone_armor", "slot": "armor", "display_name": "v1"})
	EquipmentRegistryScript.register({"id": "bone_armor", "slot": "armor", "display_name": "v2"})
	var d: Dictionary = EquipmentRegistryScript.get_item("bone_armor")
	assert_str(str(d.get("display_name", ""))).is_equal("v2")

func test_get_item_returns_copy_not_reference() -> void:
	EquipmentRegistryScript.register({"id": "bone_armor", "slot": "armor", "display_name": "Bone Armor"})
	var d1: Dictionary = EquipmentRegistryScript.get_item("bone_armor")
	d1["display_name"] = "tampered"
	var d2: Dictionary = EquipmentRegistryScript.get_item("bone_armor")
	assert_str(str(d2.get("display_name", ""))).is_equal("Bone Armor")

# ---------------------------------------------------------------------------
# get_slot
# ---------------------------------------------------------------------------

func test_get_slot_returns_correct_slot() -> void:
	EquipmentRegistryScript.register({"id": "skull_helm", "slot": "head", "display_name": "Skull Helm"})
	assert_str(EquipmentRegistryScript.get_slot("skull_helm")).is_equal("head")

func test_get_slot_returns_empty_for_unknown_id() -> void:
	assert_str(EquipmentRegistryScript.get_slot("nonexistent")).is_equal("")

func test_get_slot_for_all_valid_slot_types() -> void:
	EquipmentRegistryScript.register({"id": "test_armor",     "slot": "armor",     "display_name": "A"})
	EquipmentRegistryScript.register({"id": "test_head",      "slot": "head",      "display_name": "H"})
	EquipmentRegistryScript.register({"id": "test_feet",      "slot": "feet",      "display_name": "F"})
	EquipmentRegistryScript.register({"id": "test_held_item", "slot": "held_item", "display_name": "W"})
	assert_str(EquipmentRegistryScript.get_slot("test_armor")).is_equal("armor")
	assert_str(EquipmentRegistryScript.get_slot("test_head")).is_equal("head")
	assert_str(EquipmentRegistryScript.get_slot("test_feet")).is_equal("feet")
	assert_str(EquipmentRegistryScript.get_slot("test_held_item")).is_equal("held_item")

# ---------------------------------------------------------------------------
# register edge cases
# ---------------------------------------------------------------------------

func test_register_item_without_id_is_ignored() -> void:
	# Should push_error but not crash; registry stays empty
	EquipmentRegistryScript.register({"slot": "armor", "display_name": "No ID"})
	var d: Dictionary = EquipmentRegistryScript.get_item("")
	assert_bool(d.is_empty()).is_true()

# ---------------------------------------------------------------------------
# reset
# ---------------------------------------------------------------------------

func test_reset_clears_all_entries() -> void:
	EquipmentRegistryScript.register({"id": "bone_armor", "slot": "armor", "display_name": "Bone Armor"})
	EquipmentRegistryScript._items = {}
	var d: Dictionary = EquipmentRegistryScript.get_item("bone_armor")
	assert_bool(d.is_empty()).is_true()
