## Tests for Player._place_structure dispatch via the registries.
##
## Regression target: Player.gd had a hardcoded whitelist
##   if item_id == "campfire" or item_id == "workbench" or ...
## that caused new structures to silently fall through to
## "Player: no structure handler for <id>" when someone added a tile
## entry + StructureRegistry mapping but forgot to update Player.gd.
##
## The dispatch should instead consult TileRegistry + StructureRegistry:
## an item is a placeable structure iff it has a TileRegistry entry AND
## the resolved atlas is registered in StructureRegistry.
extends GdUnitTestSuite

const PlayerScript := preload("res://player/Player.gd")

# ---------------------------------------------------------------------------
# Predicate used by Player._place_structure to decide "this is a structure
# whose placement goes through TileMutationBus → StructureRegistry."
# ---------------------------------------------------------------------------

func test_campfire_dispatched_as_structure() -> void:
	assert_bool(PlayerScript.is_structure_item("campfire")).is_true()

func test_workbench_dispatched_as_structure() -> void:
	assert_bool(PlayerScript.is_structure_item("workbench")).is_true()

func test_bedroll_dispatched_as_structure() -> void:
	assert_bool(PlayerScript.is_structure_item("bedroll")).is_true()

func test_tether_dispatched_as_structure() -> void:
	assert_bool(PlayerScript.is_structure_item("tether")).is_true()

func test_shrine_dispatched_as_structure() -> void:
	assert_bool(PlayerScript.is_structure_item("shrine")).is_true()

# ---------------------------------------------------------------------------
# All currently-registered structures must dispatch — guards against a future
# StructureRegistry entry being added while the dispatch path is forgotten.
# ---------------------------------------------------------------------------

func test_every_registered_structure_dispatches() -> void:
	# Walk every TileRegistry entry whose atlas is in StructureRegistry and
	# assert Player's dispatch predicate accepts it. This is the property
	# version of the per-item tests above.
	var found_any := false
	for tile_name in TileRegistry._entries.keys():
		var entry: Dictionary = TileRegistry.resolve(tile_name)
		if entry.is_empty():
			continue
		var atlas: Vector2i = entry["atlas"]
		if not StructureRegistry.is_structure(atlas):
			continue
		found_any = true
		assert_bool(PlayerScript.is_structure_item(tile_name)).override_failure_message(
			"Structure '%s' (atlas %s) is in both TileRegistry and StructureRegistry " % [tile_name, atlas]
			+ "but Player.is_structure_item() rejects it — placement will fall through "
			+ "to 'no structure handler for %s'." % tile_name
		).is_true()
	assert_bool(found_any).override_failure_message(
		"Sanity: no overlapping TileRegistry+StructureRegistry entries found, " +
		"so this test never asserted anything. Did the registries fail to populate?"
	).is_true()

# ---------------------------------------------------------------------------
# Hypothetical-new-structure: register a brand-new id at runtime and confirm
# Player dispatches it without any code change. THIS is the regression test
# for "added a structure, forgot to update Player.gd's whitelist."
# ---------------------------------------------------------------------------

func test_runtime_registered_structure_dispatches() -> void:
	# A fake atlas slot well outside anything real, in the unused (4,4) area.
	var fake_atlas := Vector2i(7, 7)
	var fake_id := "test_only_structure"

	# Make sure we don't collide with a real entry if the registries grow.
	if TileRegistry.has_tile(fake_id) or StructureRegistry.is_structure(fake_atlas):
		# Skip rather than fail — environment surprise, not the bug we're hunting.
		assert_bool(true).is_true()
		return

	TileRegistry.register(fake_id, 0, fake_atlas, 0)
	StructureRegistry.register(fake_atlas, PlayerScript)  # any GDScript works as a stand-in

	# The whole point: with no edit to Player.gd, this should now be a
	# placeable structure. Pre-refactor (hardcoded whitelist) this would fail.
	assert_bool(PlayerScript.is_structure_item(fake_id)).override_failure_message(
		"A structure registered at runtime in BOTH TileRegistry and StructureRegistry " +
		"was rejected by Player's placement dispatch. The dispatch is not registry-driven " +
		"— next time someone adds a structure they will hit 'no structure handler for X' " +
		"again."
	).is_true()

	# Cleanup: remove fake entries so we don't pollute later tests.
	TileRegistry._entries.erase(fake_id)
	StructureRegistry._scripts.erase(fake_atlas)

# ---------------------------------------------------------------------------
# Non-structure items must NOT dispatch as structures.
# ---------------------------------------------------------------------------

func test_unknown_item_not_a_structure() -> void:
	assert_bool(PlayerScript.is_structure_item("definitely_not_a_real_item_xyz")).is_false()

func test_food_item_not_a_structure() -> void:
	# "berry" is a food item — TileRegistry has no entry for it.
	assert_bool(PlayerScript.is_structure_item("berry")).is_false()

func test_ground_tile_not_a_structure() -> void:
	# "grass" exists in TileRegistry but its atlas (0,0) is not in StructureRegistry.
	assert_bool(PlayerScript.is_structure_item("grass")).is_false()
