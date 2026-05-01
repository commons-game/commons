## Cross-peer scenario: two peers begin with their day-clocks at very
## different phases. After a simulated merge they should converge to the
## same total_phase and both be on a deterministically-named "merge:..."
## island.
##
## This exercises the Phase 0d-ii orchestration end-to-end on the in-process
## PuppetCluster harness:
##   - PuppetCluster spawns two Worlds, each with its own MergeCoordinator
##     and IslandRegistry (the registries are autoloads so technically there's
##     ONE instance per process, BUT each peer's MergeCoordinator drives it
##     against that peer's Player/session_id — see "Caveat" below).
##   - We pin each peer's active clock to a known phase via _wall_time_override
##     + _time_offset on the clock owned by the active island.
##   - We trigger the merge via _coordinator.on_peer_connected on each side
##     and inject the cross-peer clock phase via inject_remote_clock_phase
##     (since the in-process harness has only one MultiplayerAPI, the
##     real @rpc round-trip won't reach the other puppet).
##   - We advance wall time with _wall_time_override on each peer's clock
##     and tick the coordinator's _process; the merge should converge and
##     swap each peer's active island to "merge:<sorted-ids>".
##
## Caveat — single-process autoload aliasing:
##   IslandRegistry and DayClock are Godot autoloads, which means there is
##   exactly ONE instance per process. PuppetCluster runs both peers in the
##   same process. So when both peers' MergeCoordinators write to
##   IslandRegistry.set_active_island(), they are writing to the same
##   singleton. The scenario can therefore only verify the convergence on
##   the SHARED active-island state — it cannot show "peer A and peer B each
##   have their own active island". Real two-process play (Tier 4 in
##   docs/multiplayer_testing.md) will not have this aliasing, but the
##   convergence-target arithmetic (max of two phases) and the deterministic
##   id format are still meaningfully exercised here.
##
##   For per-peer assertions of clock-phase isolation, see the unit tests in
##   tests/unit/test_island_registry.gd (each constructs its own registry
##   via _make_registry and is fully isolated).
extends Node

const IslandRegistryScript := preload("res://autoloads/IslandRegistry.gd")

func _run(ps: Array) -> void:
	var a: Node = ps[0]
	var b: Node = ps[1]

	await a.wait_seconds(0.3)

	var coord_a: Node = a.world().get_node_or_null("MergeCoordinator")
	var coord_b: Node = b.world().get_node_or_null("MergeCoordinator")
	a.check(coord_a != null, "peer A has no MergeCoordinator")
	a.check(coord_b != null, "peer B has no MergeCoordinator")
	if coord_a == null or coord_b == null:
		return

	# Short transition so the scenario doesn't hang for 10s — but long enough
	# that the ramp doesn't snap to completion in one frame.
	coord_a.merge_transition_seconds = 0.2
	coord_b.merge_transition_seconds = 0.2

	# Pin the active (shared) clock to a known starting phase (0.3 = mid-day).
	# Both peers see the same singleton; we set it once.
	var clock = IslandRegistry.active_island().clock
	# Use _wall_time_override so the ramp's elapsed-time math is deterministic
	# and unaffected by the wall clock's actual progression.
	clock._wall_time_override = 0.3 * Constants.DAY_CYCLE_SECONDS
	clock._time_offset = 0.0
	clock.resync_phase()
	var local_total_phase: float = float(clock.day_count()) + clock.phase_fraction()

	# Force deterministic session ids so the merged-id string is predictable.
	# (In production these come from SessionManager.session_id; here we
	# overwrite them to remove the random-uuid dependency.)
	coord_a.session_id = "peer-A"
	coord_b.session_id = "peer-B"

	# Step 1: each side learns the other has connected. on_peer_connected on
	# coordinator_a tells it about peer-B, and vice versa.
	coord_a.on_peer_connected("peer-B", Vector2i(0, 0))
	coord_b.on_peer_connected("peer-A", Vector2i(0, 0))

	# Step 2: inject the cross-peer clock phase. Pretend peer-B's clock is at
	# total_phase 0.7 (mid-night) — that's the leader. Coord A is now lagging.
	# Coord B receives our local 0.3 — for B that's behind, so B doesn't
	# accelerate its (shared) clock either way.
	coord_a.inject_remote_clock_phase(0.7)
	coord_b.inject_remote_clock_phase(local_total_phase)

	# At this point the active clock should be accelerating toward 0.7
	# (whichever coordinator's begin_merge picked the larger target wins;
	# both pick 0.7 because max(0.3, 0.7) == max(0.7, 0.3) == 0.7).
	a.check(IslandRegistry.is_merging(),
		"expected IslandRegistry.is_merging() == true after cross-injection (got false)")
	a.check(clock.is_accelerating(),
		"expected active clock to be accelerating (lagging at 0.3 toward 0.7)")

	# Step 3: advance simulated wall time past the transition end.
	clock._wall_time_override = 0.3 * Constants.DAY_CYCLE_SECONDS + 0.5
	# Drive both coordinators a few frames so tick_merge runs and completes.
	for _i in range(5):
		coord_a.tick(0.1)
		coord_b.tick(0.1)
		await a.wait_frames(1)

	# Step 4: assert convergence.
	a.check(not IslandRegistry.is_merging(),
		"expected merge to complete after wall-time past transition end")
	var active_id: String = IslandRegistry.active_island().id
	var expected_id := "merge:peer-A:peer-B"
	a.check(active_id == expected_id,
		"expected active island '%s' got '%s'" % [expected_id, active_id])
	# Final clock phase should be near the leader's (0.7) — both peers' active
	# clocks are now the same merged-island clock, so reading one is enough.
	var final_phase: float = float(IslandRegistry.active_island().clock.day_count()) + IslandRegistry.active_island().clock.phase_fraction()
	a.check(abs(final_phase - 0.7) < 0.05,
		"expected converged total_phase ≈ 0.7, got %.4f" % final_phase)
	# The default island must still exist (never retired).
	a.check(IslandRegistry.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID) != null,
		"default island unexpectedly retired during merge")

	a.pass_scenario("merge converges to deterministic merged-island id with leader phase")
