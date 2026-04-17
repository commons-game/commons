## Tests for ItemRegistry icon data — every item must have a non-trivial icon.
##
## Catches the regression where items displayed raw "_"-separated id text in
## the hotbar instead of a visual icon. The fix added icon_color and icon_atlas
## fields to ItemDefinition and wired them in ItemRegistry.
##
## Three guarantees tested:
##   1. Every item has a non-zero, non-transparent icon_color.
##   2. Items with world-tile art (wood, stone, ether_crystal) use their
##      corresponding atlas coords so the hotbar shows the same sprite
##      the player sees in the game world.
##   3. Key milestone items (campfire, tether, flint_tool) have visually
##      distinct colours rather than the neutral grey fallback.
extends GdUnitTestSuite

# Full item ID list — update when items are added to ItemRegistry.
const ALL_ITEM_IDS: Array = [
	"lantern", "hammer", "shovel", "wooden_axe", "wooden_pickaxe",
	"iron_sword",
	"talisman_of_chaos", "ward_of_solitude", "compass_of_lost",
	"leather_helmet", "leather_chest", "leather_legs", "leather_shoes",
	"wood", "stone", "ether_crystal", "marrow", "sinter", "berry",
	"campfire", "workbench", "bedroll", "tether", "shrine",
	"flint_tool", "stone_axe", "stone_pickaxe",
	"mass_core", "form_crystal", "ichor", "cipher",
]

# ---------------------------------------------------------------------------
# Every item must resolve and have a non-transparent icon color
# ---------------------------------------------------------------------------

func test_all_items_resolve_in_registry() -> void:
	for item_id in ALL_ITEM_IDS:
		var def = ItemRegistry.resolve(item_id)
		assert_object(def).override_failure_message(
			"ItemRegistry.resolve('%s') returned null" % item_id
		).is_not_null()

func test_all_items_have_non_transparent_icon_color() -> void:
	for item_id in ALL_ITEM_IDS:
		var def = ItemRegistry.resolve(item_id)
		if def == null:
			continue
		assert_float(def.icon_color.a).override_failure_message(
			"%s icon_color is transparent (alpha = 0)" % item_id
		).is_greater(0.0)

func test_no_item_uses_pure_black_icon() -> void:
	# Black (0,0,0) is invisible against the dark slot background — a sign
	# the color was never set.
	for item_id in ALL_ITEM_IDS:
		var def = ItemRegistry.resolve(item_id)
		if def == null:
			continue
		var is_black: bool = (def.icon_color.r < 0.05 and
		                      def.icon_color.g < 0.05 and
		                      def.icon_color.b < 0.05)
		assert_bool(is_black).override_failure_message(
			"%s icon_color is near-black — likely unset" % item_id
		).is_false()

# ---------------------------------------------------------------------------
# World-tile items use atlas icons (free art from the tileset)
# ---------------------------------------------------------------------------

func test_wood_has_atlas_icon() -> void:
	var def = ItemRegistry.resolve("wood")
	assert_bool(def.icon_atlas != Vector2i(-1, -1)).is_true()

func test_stone_has_atlas_icon() -> void:
	var def = ItemRegistry.resolve("stone")
	assert_bool(def.icon_atlas != Vector2i(-1, -1)).is_true()

func test_ether_crystal_has_atlas_icon() -> void:
	var def = ItemRegistry.resolve("ether_crystal")
	assert_bool(def.icon_atlas != Vector2i(-1, -1)).is_true()

func test_wood_atlas_is_tree_tile() -> void:
	# Wood comes from trees — the hotbar should show the tree sprite (0,1).
	var def = ItemRegistry.resolve("wood")
	assert_bool(def.icon_atlas == Vector2i(0, 1)).is_true()

func test_stone_atlas_is_rock_tile() -> void:
	# Stone comes from rocks — the hotbar should show the rock sprite (1,1).
	var def = ItemRegistry.resolve("stone")
	assert_bool(def.icon_atlas == Vector2i(1, 1)).is_true()

func test_ether_crystal_atlas_is_crystal_tile() -> void:
	var def = ItemRegistry.resolve("ether_crystal")
	assert_bool(def.icon_atlas == Vector2i(3, 2)).is_true()

# ---------------------------------------------------------------------------
# Items without world tiles must NOT have an atlas icon set
# ---------------------------------------------------------------------------

func test_campfire_has_no_atlas_icon() -> void:
	# Campfire has no world-tile sprite yet — must use color fallback.
	var def = ItemRegistry.resolve("campfire")
	assert_bool(def.icon_atlas == Vector2i(-1, -1)).is_true()

func test_flint_tool_has_no_atlas_icon() -> void:
	var def = ItemRegistry.resolve("flint_tool")
	assert_bool(def.icon_atlas == Vector2i(-1, -1)).is_true()

# ---------------------------------------------------------------------------
# Milestone items have visually distinct colours
# ---------------------------------------------------------------------------

func test_campfire_icon_is_orange() -> void:
	# Campfire is the step-3 milestone — its icon should be warm orange,
	# not the neutral grey fallback Color(0.35, 0.35, 0.35).
	var def = ItemRegistry.resolve("campfire")
	assert_float(def.icon_color.r).is_greater(0.7)  # high red
	assert_float(def.icon_color.b).is_less(0.3)     # low blue → orange

func test_tether_icon_has_blue_component() -> void:
	# Tether is Still-aligned (blue/ice) — distinct from warm-toned structures.
	var def = ItemRegistry.resolve("tether")
	assert_float(def.icon_color.b).is_greater(0.5)

func test_shrine_icon_is_purple() -> void:
	# Shrine blends Bloom + Still — should read as purple, not orange or blue.
	var def = ItemRegistry.resolve("shrine")
	assert_float(def.icon_color.r).is_greater(0.3)
	assert_float(def.icon_color.b).is_greater(0.3)

func test_ichor_icon_is_green() -> void:
	# Ichor = pure Bloom — vivid green, distinct from earthy material colours.
	var def = ItemRegistry.resolve("ichor")
	assert_float(def.icon_color.g).is_greater(0.6)
