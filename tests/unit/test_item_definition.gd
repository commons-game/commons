## Tests for ItemDefinition — describes a type of item.
extends GdUnitTestSuite

const ItemDefinitionScript := preload("res://items/ItemDefinition.gd")

func _make(id: String, category: String) -> Object:
	var d = ItemDefinitionScript.new()
	d.id = id
	d.category = category
	return d

# --- Basic fields ---

func test_id_stored() -> void:
	var d = _make("hammer", "tool")
	assert_str(d.id).is_equal("hammer")

func test_category_stored() -> void:
	var d = _make("hammer", "tool")
	assert_str(d.category).is_equal("tool")

func test_display_name_defaults_to_id() -> void:
	var d = _make("hammer", "tool")
	assert_str(d.display_name).is_equal("hammer")

func test_display_name_can_be_set() -> void:
	var d = _make("hammer", "tool")
	d.display_name = "Iron Hammer"
	assert_str(d.display_name).is_equal("Iron Hammer")

func test_stack_max_defaults_to_1() -> void:
	var d = _make("hammer", "tool")
	assert_int(d.stack_max).is_equal(1)

func test_stack_max_can_be_set_higher_for_materials() -> void:
	var d = _make("wood", "material")
	d.stack_max = 32
	assert_int(d.stack_max).is_equal(32)

func test_equipment_slot_defaults_empty() -> void:
	var d = _make("hammer", "tool")
	assert_str(d.equipment_slot).is_equal("")

func test_equipment_slot_set_for_armor() -> void:
	var d = _make("iron_helmet", "armor")
	d.equipment_slot = "helmet"
	assert_str(d.equipment_slot).is_equal("helmet")

# --- Category validation ---

func test_is_weapon() -> void:
	var d = _make("sword", "weapon")
	assert_bool(d.is_weapon()).is_true()
	assert_bool(d.is_talisman()).is_false()
	assert_bool(d.is_tool()).is_false()

func test_is_talisman() -> void:
	var d = _make("ward", "talisman")
	assert_bool(d.is_talisman()).is_true()
	assert_bool(d.is_weapon()).is_false()

func test_is_tool() -> void:
	var d = _make("hammer", "tool")
	assert_bool(d.is_tool()).is_true()

func test_is_armor() -> void:
	var d = _make("iron_helmet", "armor")
	assert_bool(d.is_armor()).is_true()

func test_is_material() -> void:
	var d = _make("wood", "material")
	assert_bool(d.is_material()).is_true()

# --- to_dict / from_dict roundtrip ---

func test_to_dict_contains_id() -> void:
	var d = _make("hammer", "tool")
	var dict: Dictionary = d.to_dict()
	assert_str(dict["id"]).is_equal("hammer")

func test_to_dict_contains_category() -> void:
	var d = _make("hammer", "tool")
	var dict: Dictionary = d.to_dict()
	assert_str(dict["category"]).is_equal("tool")

func test_from_dict_roundtrip() -> void:
	var d = _make("iron_sword", "weapon")
	d.display_name = "Iron Sword"
	d.stack_max = 1
	var d2 = ItemDefinitionScript.new()
	d2.from_dict(d.to_dict())
	assert_str(d2.id).is_equal("iron_sword")
	assert_str(d2.category).is_equal("weapon")
	assert_str(d2.display_name).is_equal("Iron Sword")
