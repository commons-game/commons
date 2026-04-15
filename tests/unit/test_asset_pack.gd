## Tests for AssetPack resolution logic.
extends GdUnitTestSuite

const AssetPackScript := preload("res://player/AssetPack.gd")

func before_each() -> void:
	# Reset to debug pack before each test
	AssetPackScript.current_pack = "debug"
	AssetPackScript._registered = {}

func test_debug_pack_returns_null() -> void:
	var result = AssetPackScript.resolve("body", "default")
	assert_object(result).is_null()

func test_debug_pack_always_null_regardless_of_slot() -> void:
	assert_object(AssetPackScript.resolve("body", "necromancer")).is_null()
	assert_object(AssetPackScript.resolve("held_item", "bone_wand")).is_null()
	assert_object(AssetPackScript.resolve("status_effect", "blood_harvest")).is_null()

func test_register_pack_stores_mapping() -> void:
	AssetPackScript.register_pack("test_pack", {
		"body": {"warrior": "res://fake/warrior.png"}
	})
	assert_bool(AssetPackScript._registered.has("test_pack")).is_true()

func test_registered_pack_lookup_no_crash() -> void:
	# Path doesn't exist — ResourceLoader.exists returns false, so resolve returns null.
	# Verify no crash when pack is active and variant is unmapped.
	AssetPackScript.register_pack("my_pack", {
		"body": {"hero": "res://nonexistent/hero.png"}
	})
	AssetPackScript.current_pack = "my_pack"
	# Resolving an unmapped slot returns null — no crash
	var result = AssetPackScript.resolve("body", "nonexistent_variant")
	assert_object(result).is_null()
