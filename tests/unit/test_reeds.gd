## Unit tests for the reeds resource (Phase 1a of the bedroll/reeds feature).
##
## Reeds are a water-adjacent harvestable. The tile is registered in
## TileRegistry at atlas (4, 1); the matching item lives in ItemRegistry as a
## stackable material; harvesting it yields the "reeds" item bare-handed.
##
## What this file guards:
##   - The tile is registered AND lands on the atlas slot we picked.
##   - The item exists, is a "material", and stacks like wood/stone (32).
##   - The item icon reuses the world-tile atlas slot (free icon art).
##   - The harvestable spec exists in TileInteraction.HARVESTABLE_TILES with
##     bare-hand-killable max_hp (1) and a reeds drop. Without this entry the
##     harvest path silently no-ops on the tile.
##
## See also tests/unit/test_atlas_uniqueness.gd — once reeds register at (4,1)
## the existing "no two TileRegistry entries share an atlas" guard covers the
## collision dimension.
extends GdUnitTestSuite

const TileInteractionScript := preload("res://player/TileInteraction.gd")

const REEDS_ATLAS := Vector2i(4, 1)

# ---------------------------------------------------------------------------
# TileRegistry
# ---------------------------------------------------------------------------

func test_reeds_registered_in_tile_registry() -> void:
	assert_bool(TileRegistry.has_tile("reeds")).is_true()

func test_reeds_atlas_is_4_1() -> void:
	var entry: Dictionary = TileRegistry.resolve("reeds")
	assert_bool(entry.is_empty()).is_false()
	assert_that(entry["atlas"]).is_equal(REEDS_ATLAS)

# ---------------------------------------------------------------------------
# ItemRegistry
# ---------------------------------------------------------------------------

func test_reeds_registered_in_item_registry() -> void:
	assert_bool(ItemRegistry.has_item("reeds")).is_true()

func test_reeds_is_material_category() -> void:
	var def := ItemRegistry.resolve("reeds")
	assert_object(def).is_not_null()
	assert_str(def.category).is_equal("material")

func test_reeds_stack_max_is_32() -> void:
	# Matches wood/stone — common gathering material.
	var def := ItemRegistry.resolve("reeds")
	assert_int(def.stack_max).is_equal(32)

func test_reeds_icon_atlas_matches_tile_atlas() -> void:
	# Reuses the world-tile sprite as the inventory icon, like wood/stone do.
	var def := ItemRegistry.resolve("reeds")
	assert_that(def.icon_atlas).is_equal(REEDS_ATLAS)

# ---------------------------------------------------------------------------
# Harvest spec — TileInteraction.HARVESTABLE_TILES
# ---------------------------------------------------------------------------

func test_reeds_atlas_is_in_harvestable_tiles() -> void:
	# Without this entry the swing path silently no-ops on reeds.
	assert_bool(TileInteractionScript.HARVESTABLE_TILES.has(REEDS_ATLAS)).is_true()

func test_reeds_max_hp_is_1_bare_hand_killable() -> void:
	# Bare-hand fist damage is 1 (TileInteraction._tool_damage default).
	# max_hp=1 means a single bare-handed click harvests reeds.
	# Runtime lookup via .get() — direct [] indexing on a const dict whose
	# literal definition lacks the key is a parse-time error in Godot 4.3.
	var table: Dictionary = TileInteractionScript.HARVESTABLE_TILES
	var spec: Dictionary = table.get(REEDS_ATLAS, {})
	assert_int(int(spec.get("max_hp", -1))).is_equal(1)

func test_reeds_drops_reeds_item() -> void:
	var table: Dictionary = TileInteractionScript.HARVESTABLE_TILES
	var spec: Dictionary = table.get(REEDS_ATLAS, {})
	var drops: Array = spec.get("drops", [])
	assert_int(drops.size()).is_greater(0)
	assert_str(str(drops[0]["id"])).is_equal("reeds")

func test_reeds_drop_category_is_material() -> void:
	var table: Dictionary = TileInteractionScript.HARVESTABLE_TILES
	var spec: Dictionary = table.get(REEDS_ATLAS, {})
	var drops: Array = spec.get("drops", [])
	assert_int(drops.size()).is_greater(0)
	assert_str(str(drops[0]["category"])).is_equal("material")
