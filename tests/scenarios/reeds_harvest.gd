## Scenario: place a reed tile next to the player, bare-handed left-click,
## verify the tile is removed AND the inventory contains the reeds item.
##
## We don't trust the world generator to drop a reed within sight at any
## given seed — wave the magic wand: directly request_place_tile a reed via
## the bus, then exercise the click path the player would actually take.
## The harvest pipeline (TileInteraction → bus → CRDT → drop into bag) is
## what's being verified, not procgen.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/reeds_harvest.gd
extends Node

const REEDS_ATLAS := Vector2i(4, 1)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	p.check(bus != null, "World has no TileMutationBus")

	# Pick a tile one east of the player. If something already occupies it
	# (tree, rock from procgen) clear the slot first so the place lands.
	var player_pos: Vector2 = p.player().position
	var origin := Vector2i(
		int(floor(player_pos.x / Constants.TILE_SIZE)),
		int(floor(player_pos.y / Constants.TILE_SIZE)),
	)
	var reed_tile := origin + Vector2i(1, 0)
	if p.has_object_at(reed_tile):
		bus.request_remove_tile(reed_tile, 1)
		await p.wait_frames(2)

	bus.request_place_tile(reed_tile, 1, "reeds")
	await p.wait_frames(3)

	p.check(p.object_atlas_at(reed_tile) == REEDS_ATLAS,
		"reed tile failed to place (got atlas %s)" % p.object_atlas_at(reed_tile))

	# Bare-hand the click — make sure the active tool isn't lantern/shovel
	# from the starter loadout. Selecting an empty tool slot leaves the
	# wielded id empty, which TileInteraction treats as a fist swing.
	var inv: Object = p.player().inventory
	# Clear both default tool slots so wielded_item_id() returns "".
	inv.clear_tool_slot(0)
	inv.clear_tool_slot(1)
	inv.select_tool(0)

	var reeds_before: int = inv.bag_stack_total("reeds")

	p.click_tile(reed_tile, MOUSE_BUTTON_LEFT)
	# One swing kills max_hp=1 reeds; wait long enough for the bus and
	# render-side erase to settle.
	await p.wait_seconds(0.6)

	p.check(p.object_atlas_at(reed_tile) == Vector2i(-1, -1),
		"reed tile not removed after one bare-handed click (still %s)"
			% p.object_atlas_at(reed_tile))

	var reeds_after: int = inv.bag_stack_total("reeds")
	p.check(reeds_after - reeds_before >= 1,
		"expected at least 1 reeds in bag after harvest, got delta %d (before=%d, after=%d)"
			% [reeds_after - reeds_before, reeds_before, reeds_after])

	p.pass_scenario("bare-handed harvest of reed tile yields reeds item")
