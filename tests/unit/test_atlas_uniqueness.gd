## Tests that no two distinct logical tiles share an atlas coord.
##
## Regression target: workbench (registered in TileRegistry/StructureRegistry/
## Chunk.gd at atlas (1,2)) collided with marrow_drop (placed by NightSpawner
## and registered in ChunkManager._ensure_tileset_atlas_registered()'s needed[]
## list at the same atlas (1,2)). Whichever set_cell() ran most recently won
## visually; the other tile silently rendered as the wrong sprite. Latent
## footgun — fine until both spawn near each other.
##
## The fix moved marrow_drop to its own atlas slot. This test guards against
## a regression and against any future tile picking an already-used coord.
extends GdUnitTestSuite

const NightSpawnerScript := preload("res://world/NightSpawner.gd")

# Workbench keeps (1,2) — it's the more entrenched reference (TileRegistry,
# StructureRegistry, Chunk.gd collision polys, Player._try_open_workbench).
const WORKBENCH_ATLAS := Vector2i(1, 2)

func test_workbench_atlas_is_1_2() -> void:
	# Documents the canonical workbench slot. If this changes, every
	# co-located reference (Chunk.gd collision, Player._try_open_workbench,
	# test_chunk_collision, the workbench scenario) must change with it.
	var entry: Dictionary = TileRegistry.resolve("workbench")
	assert_that(entry["atlas"]).is_equal(WORKBENCH_ATLAS)
	assert_bool(StructureRegistry.is_structure(WORKBENCH_ATLAS)).is_true()

func test_marrow_drop_atlas_does_not_collide_with_workbench() -> void:
	# The bug: NightSpawner._on_wisp_died placed marrow_drop at the same
	# atlas as workbench. We can't test NightSpawner directly without
	# spinning up a player + chunk_manager, but ChunkManager keeps a
	# parallel `needed[]` list of atlases including marrow_drop's coord.
	# That list must not contain the workbench atlas under marrow_drop's
	# label. Easier: read the constant the spawner uses.
	assert_that(NightSpawnerScript.MARROW_DROP_ATLAS).override_failure_message(
		"marrow_drop atlas (%s) collides with workbench atlas (%s) — " % [NightSpawnerScript.MARROW_DROP_ATLAS, WORKBENCH_ATLAS]
		+ "two logical tiles sharing one cell will overwrite each other visually. "
		+ "Move marrow_drop to a different slot."
	).is_not_equal(WORKBENCH_ATLAS)

func test_no_two_tile_registry_entries_share_an_atlas() -> void:
	# Stronger guard: walk every TileRegistry entry and assert atlas
	# coords are unique. "default" intentionally aliases "grass" — skip it.
	var by_atlas: Dictionary = {}  # Vector2i → first tile_name seen
	for tile_name in TileRegistry._entries.keys():
		if tile_name == "default":
			continue  # documented alias for grass
		var entry: Dictionary = TileRegistry.resolve(tile_name)
		if entry.is_empty():
			continue
		var atlas: Vector2i = entry["atlas"]
		if by_atlas.has(atlas):
			fail("Atlas collision: '%s' and '%s' both register at %s — visual overwrite likely"
				% [by_atlas[atlas], tile_name, atlas])
			return
		by_atlas[atlas] = tile_name
	# Sanity: at least the structures we know about should have shown up.
	assert_int(by_atlas.size()).is_greater(5)

func test_marrow_drop_atlas_is_not_in_tile_registry() -> void:
	# marrow_drop tiles are placed by NightSpawner directly via
	# chunk_manager.place_tile() without a TileRegistry entry — its atlas
	# slot is exclusive to marrow drops. If the slot we picked happens to
	# be a registered tile, the visual will overwrite that tile's icon.
	for tile_name in TileRegistry._entries.keys():
		var entry: Dictionary = TileRegistry.resolve(tile_name)
		if entry.is_empty():
			continue
		assert_that(entry["atlas"]).override_failure_message(
			"marrow_drop's chosen atlas %s is also registered as '%s' — pick a different slot"
				% [NightSpawnerScript.MARROW_DROP_ATLAS, tile_name]
		).is_not_equal(NightSpawnerScript.MARROW_DROP_ATLAS)
