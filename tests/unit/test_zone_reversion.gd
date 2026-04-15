## Tests for zone reversion — when a player leaves a shrine zone,
## _on_buffs_changed([]) must revert appearance to "use world/default body" (base_body_id == "").
extends GdUnitTestSuite

const AssetPackScript          := preload("res://player/AssetPack.gd")
const CharacterAppearanceScript := preload("res://player/CharacterAppearance.gd")
const PlayerScript             := preload("res://player/Player.gd")

func before_each() -> void:
	# Reset static state before each test
	AssetPackScript._registered = {}
	AssetPackScript._buff_slot_maps = {}

# ---------------------------------------------------------------------------
# Task 1a: AssetPack.resolve_slot_for_buffs("body", []) returns "" not "default"
# ---------------------------------------------------------------------------

func test_resolve_slot_for_buffs_body_with_registered_buff_returns_variant() -> void:
	## Register a buff → body mapping and verify it resolves correctly.
	AssetPackScript.register_buff_slot_map("body", {"necro": "necromancer_body"})
	assert_str(AssetPackScript.resolve_slot_for_buffs("body", ["necro"])).is_equal("necromancer_body")

func test_resolve_slot_for_buffs_body_empty_buffs_returns_empty_string() -> void:
	## No active buffs → no override → empty string (signals "use world/default body").
	## register a map so the slot exists, then call with no buffs.
	AssetPackScript.register_buff_slot_map("body", {"necro": "necromancer_body"})
	assert_str(AssetPackScript.resolve_slot_for_buffs("body", [])).is_equal("")

func test_resolve_slot_for_buffs_body_empty_no_map_returns_empty_string() -> void:
	## With no registered buff→body map and no active buffs, should still return "".
	assert_str(AssetPackScript.resolve_slot_for_buffs("body", [])).is_equal("")

func test_resolve_slot_for_buffs_unknown_buff_returns_empty_string() -> void:
	## A buff that isn't in the map returns "" for body (no override).
	AssetPackScript.register_buff_slot_map("body", {"necro": "necromancer_body"})
	assert_str(AssetPackScript.resolve_slot_for_buffs("body", ["unknown_buff"])).is_equal("")

# ---------------------------------------------------------------------------
# Task 1b: Player._on_buffs_changed([]) results in appearance.base_body_id == ""
# ---------------------------------------------------------------------------

func test_player_on_buffs_changed_empty_sets_base_body_id_empty() -> void:
	## Simulate what Player._on_buffs_changed([]) does:
	## appearance.base_body_id should be "" when no buffs are active.
	## We create a bare CharacterAppearance to simulate the Player's appearance field.
	var appearance = CharacterAppearanceScript.new()
	appearance.base_body_id = "necromancer_body"  # was previously set by shrine entry
	appearance.active_buff_ids.clear()
	# Simulate the Player._on_buffs_changed([]) logic:
	var buffs: Array = []
	for b in buffs:
		appearance.active_buff_ids.append(str(b.get("buff_id", "")))
	appearance.base_body_id = AssetPackScript.resolve_slot_for_buffs("body", appearance.active_buff_ids)
	assert_str(appearance.base_body_id).is_equal("")

func test_player_on_buffs_changed_with_buff_sets_body_id() -> void:
	## When buffs are active, _on_buffs_changed sets the correct body variant.
	AssetPackScript.register_buff_slot_map("body", {"necro": "necromancer_body"})
	var appearance = CharacterAppearanceScript.new()
	appearance.base_body_id = "default"
	appearance.active_buff_ids.clear()
	var buffs: Array = [{"buff_id": "necro"}]
	for b in buffs:
		appearance.active_buff_ids.append(str(b.get("buff_id", "")))
	appearance.base_body_id = AssetPackScript.resolve_slot_for_buffs("body", appearance.active_buff_ids)
	assert_str(appearance.base_body_id).is_equal("necromancer_body")
