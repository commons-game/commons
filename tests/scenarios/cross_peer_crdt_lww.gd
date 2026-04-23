## Cross-peer scenario: both peers write the same object-layer tile with
## different tile types. The CRDT's LWW (last-write-wins) merge should
## converge both peers onto whichever write has the higher timestamp,
## regardless of arrival order.
##
## Why this matters: our bridge delivers synchronously in issue order, so the
## "obvious" convergence case is trivial. The interesting assertion is that
## even when a remote write arrives with an OLDER timestamp (a peer that
## lagged), it doesn't clobber the newer local state.
extends Node

const CAMPFIRE_ATLAS := Vector2i(0, 3)
const BEDROLL_ATLAS  := Vector2i(1, 3)

func _run(ps: Array) -> void:
	var a: Node = ps[0]
	var b: Node = ps[1]

	await a.wait_seconds(0.3)

	var tile := Vector2i(6, 2)
	if a.has_object_at(tile):
		a.world().get_node("TileMutationBus").request_remove_tile(tile, 1)
		await a.wait_seconds(0.05)

	# ---- Case 1: simultaneous-but-ordered writes, B's write is later ----
	# A writes campfire first (earlier timestamp), B writes bedroll after.
	a.world().get_node("TileMutationBus").request_place_tile(tile, 1, "campfire")
	await a.wait_seconds(0.05)
	b.world().get_node("TileMutationBus").request_place_tile(tile, 1, "bedroll")
	await a.wait_seconds(0.1)

	# Both peers should converge on bedroll (the later write).
	a.check(a.object_atlas_at(tile) == BEDROLL_ATLAS,
		"peer A expected bedroll (later write), got %s" % a.object_atlas_at(tile))
	a.check(b.object_atlas_at(tile) == BEDROLL_ATLAS,
		"peer B expected bedroll (its own write), got %s" % b.object_atlas_at(tile))

	# ---- Case 2: A attempts to overwrite with a STALE timestamp ----
	# Apply a mutation with a timestamp from the past — it should be rejected
	# by the LWW merge and both peers should still see bedroll.
	var stale_record := {
		"type": "place",
		"world_coords": tile,
		"layer": 1,
		"tile_id": "campfire",
		"author_id": "peer_A_late",
		"timestamp": 1.0,  # far in the past
	}
	a.world().get_node("TileMutationBus").apply_remote_mutation(stale_record.duplicate())
	b.world().get_node("TileMutationBus").apply_remote_mutation(stale_record.duplicate())
	await a.wait_seconds(0.05)

	a.check(a.object_atlas_at(tile) == BEDROLL_ATLAS,
		"stale write clobbered peer A — LWW broken")
	a.check(b.object_atlas_at(tile) == BEDROLL_ATLAS,
		"stale write clobbered peer B — LWW broken")

	a.pass_scenario("LWW: later timestamp wins; stale writes are rejected on both peers")
