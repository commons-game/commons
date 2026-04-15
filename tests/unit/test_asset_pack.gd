## Tests for AssetPack resolution and buff→body mapping.
extends GdUnitTestSuite

const AssetPackScript := preload("res://player/AssetPack.gd")

func before_each() -> void:
	# Reset static state before each test
	AssetPackScript.current_pack = "debug"
	AssetPackScript._registered = {}
	AssetPackScript._buff_body_map = {}
	AssetPackScript._buff_item_map = {}

func test_registered_pack_found_regardless_of_current_pack() -> void:
	# Registered pack assets are resolved even when current_pack != pack_name.
	# Path doesn't exist → returns null cleanly (ResourceLoader.exists=false).
	AssetPackScript.current_pack = "debug"
	AssetPackScript.register_pack("my_mod", {
		"body": {"hero": "res://nonexistent/hero.png"}
	})
	var result: Texture2D = AssetPackScript.resolve("body", "hero")
	assert_object(result).is_null()  # nonexistent path → null, but no crash

func test_unregistered_variant_returns_null() -> void:
	AssetPackScript.register_pack("my_mod", {
		"body": {"warrior": "res://nonexistent/warrior.png"}
	})
	var result: Texture2D = AssetPackScript.resolve("body", "nonexistent_variant")
	assert_object(result).is_null()

func test_unknown_slot_returns_null() -> void:
	var result: Texture2D = AssetPackScript.resolve("unknown_slot", "default")
	assert_object(result).is_null()

func test_register_pack_stores_mapping() -> void:
	AssetPackScript.register_pack("test_pack", {
		"body": {"warrior": "res://fake/warrior.png"}
	})
	assert_bool(AssetPackScript._registered.has("test_pack")).is_true()

func test_buff_body_map_resolves_registered_buff() -> void:
	AssetPackScript.register_buff_body_map({
		"blood_harvest": "necromancer",
		"undead_resilience": "necromancer",
	})
	assert_str(AssetPackScript.resolve_body_for_buffs(["blood_harvest"])).is_equal("necromancer")

func test_buff_body_map_first_match_wins() -> void:
	AssetPackScript.register_buff_body_map({
		"buff_a": "body_a",
		"buff_b": "body_b",
	})
	# First buff in the list with a mapping wins
	var result: String = AssetPackScript.resolve_body_for_buffs(["buff_a", "buff_b"])
	assert_str(result).is_equal("body_a")

func test_buff_body_map_no_match_returns_default() -> void:
	assert_str(AssetPackScript.resolve_body_for_buffs(["unknown_buff"])).is_equal("default")

func test_buff_body_map_empty_list_returns_default() -> void:
	assert_str(AssetPackScript.resolve_body_for_buffs([])).is_equal("default")

func test_buff_item_map_resolves_registered_buff() -> void:
	AssetPackScript.register_buff_item_map({"blood_harvest": "bone_wand"})
	assert_str(AssetPackScript.resolve_item_for_buffs(["blood_harvest"])).is_equal("bone_wand")

func test_buff_item_map_no_match_returns_empty() -> void:
	assert_str(AssetPackScript.resolve_item_for_buffs(["unknown_buff"])).is_equal("")

func test_buff_item_map_empty_list_returns_empty() -> void:
	assert_str(AssetPackScript.resolve_item_for_buffs([])).is_equal("")
