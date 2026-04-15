## Tests for CharacterAppearance data round-trip.
extends GdUnitTestSuite

const CharacterAppearanceScript := preload("res://player/CharacterAppearance.gd")

func test_default_values() -> void:
	var a = CharacterAppearanceScript.new()
	assert_str(a.base_body_id).is_equal("default")
	assert_str(a.held_item_id).is_equal("")
	assert_str(a.armor_id).is_equal("")
	assert_str(a.head_id).is_equal("")
	assert_str(a.feet_id).is_equal("")
	assert_array(a.active_buff_ids).is_empty()
	assert_that(a.facing).is_equal(Vector2.UP)

func test_to_dict_round_trip() -> void:
	var a = CharacterAppearanceScript.new()
	a.base_body_id = "necromancer"
	a.held_item_id = "bone_wand"
	a.armor_id = "bone_armor"
	a.head_id  = "skull_helm"
	a.feet_id  = "bone_boots"
	a.active_buff_ids.clear()
	a.active_buff_ids.append("blood_harvest")
	a.active_buff_ids.append("undead_resilience")
	a.facing = Vector2.RIGHT

	var b = CharacterAppearanceScript.new()
	b.from_dict(a.to_dict())

	assert_str(b.base_body_id).is_equal("necromancer")
	assert_str(b.held_item_id).is_equal("bone_wand")
	assert_str(b.armor_id).is_equal("bone_armor")
	assert_str(b.head_id).is_equal("skull_helm")
	assert_str(b.feet_id).is_equal("bone_boots")
	assert_array(b.active_buff_ids).contains_exactly(["blood_harvest", "undead_resilience"])
	assert_float(b.facing.x).is_equal(1.0)
	assert_float(b.facing.y).is_equal(0.0)

func test_legacy_body_id_key_in_dict_still_loads() -> void:
	# Backward-compat: old dicts used "body_id" key
	var b = CharacterAppearanceScript.new()
	b.from_dict({"body_id": "necromancer", "held_item_id": "", "active_buff_ids": [], "facing_x": 0.0, "facing_y": -1.0})
	assert_str(b.base_body_id).is_equal("necromancer")

func test_empty_buffs_round_trip() -> void:
	var a = CharacterAppearanceScript.new()
	var b = CharacterAppearanceScript.new()
	b.from_dict(a.to_dict())
	assert_array(b.active_buff_ids).is_empty()

func test_facing_to_row_down() -> void:
	var a = CharacterAppearanceScript.new()
	a.facing = Vector2(0, 1)   # DOWN
	assert_int(a.facing_to_row()).is_equal(0)

func test_facing_to_row_left() -> void:
	var a = CharacterAppearanceScript.new()
	a.facing = Vector2(-1, 0)  # LEFT
	assert_int(a.facing_to_row()).is_equal(1)

func test_facing_to_row_right() -> void:
	var a = CharacterAppearanceScript.new()
	a.facing = Vector2(1, 0)   # RIGHT
	assert_int(a.facing_to_row()).is_equal(2)

func test_facing_to_row_up() -> void:
	var a = CharacterAppearanceScript.new()
	a.facing = Vector2.UP      # UP (default)
	assert_int(a.facing_to_row()).is_equal(3)

func test_facing_to_row_diagonal_prefers_vertical() -> void:
	# Equal x/y magnitude — vertical axis wins (abs(y) >= abs(x))
	var a = CharacterAppearanceScript.new()
	a.facing = Vector2(0.7, 0.7).normalized()
	assert_int(a.facing_to_row()).is_equal(0)  # DOWN (y > 0)
