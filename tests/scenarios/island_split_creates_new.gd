## Cross-peer scenario: two peers merge, then split. After the split each
## peer's coordinator should call IslandRegistry.split_from_merge with a
## session-scoped id ("solo:<sid>") and the active island should swap to that.
##
## Same single-process autoload caveat as island_merge_clock_converges.gd:
## both peers share one IslandRegistry singleton, so the test verifies the
## split orchestration on the shared state rather than per-peer isolation.
## Per-peer isolation is verified by tests/unit/test_island_registry.gd
## (each test constructs its own IslandRegistry via _make_registry).
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

	coord_a.merge_transition_seconds = 0.2
	coord_b.merge_transition_seconds = 0.2
	coord_a.session_id = "peer-A"
	coord_b.session_id = "peer-B"

	# --- Merge first ---
	var clock = IslandRegistry.active_island().clock
	clock._wall_time_override = 0.3 * Constants.DAY_CYCLE_SECONDS
	clock._time_offset = 0.0
	clock.resync_phase()

	coord_a.on_peer_connected("peer-B", Vector2i(0, 0))
	coord_b.on_peer_connected("peer-A", Vector2i(0, 0))
	# Both peers see the same shared clock, so we use its current total_phase
	# as the "remote" value for both directions — leader/lagger doesn't matter
	# for testing the split path.
	var current_phase: float = float(clock.day_count()) + clock.phase_fraction()
	coord_a.inject_remote_clock_phase(current_phase)
	coord_b.inject_remote_clock_phase(current_phase)

	# Drive to completion.
	clock._wall_time_override = 0.3 * Constants.DAY_CYCLE_SECONDS + 0.5
	for _i in range(5):
		coord_a.tick(0.1)
		coord_b.tick(0.1)
		await a.wait_frames(1)

	# Merged-island invariant before split.
	var merged_id := "merge:peer-A:peer-B"
	a.check(IslandRegistry.active_island().id == merged_id,
		"expected merged-island '%s' before split, got '%s'" % [merged_id, IslandRegistry.active_island().id])

	# Capture phase at the moment of split — we'll assert no rewind.
	var phase_at_split: float = float(IslandRegistry.active_island().clock.day_count()) + IslandRegistry.active_island().clock.phase_fraction()

	# --- Now split (simulate disconnect on peer A's side first) ---
	coord_a.on_peer_disconnected()
	# Peer A's split should have created "solo:peer-A" and made it active.
	# Because the registry is shared in-process, both peers now see this.
	var post_a_id: String = IslandRegistry.active_island().id
	a.check(post_a_id == "solo:peer-A",
		"expected active island 'solo:peer-A' after A's split, got '%s'" % post_a_id)
	# The merged island should have been retired.
	a.check(IslandRegistry.get_island(merged_id) == null,
		"merged island '%s' was not retired on split" % merged_id)
	# Clock state preserved (no rewind): solo island's phase ≈ phase_at_split.
	var post_split_phase: float = float(IslandRegistry.active_island().clock.day_count()) + IslandRegistry.active_island().clock.phase_fraction()
	a.check(abs(post_split_phase - phase_at_split) < 0.01,
		"split rewound the clock — pre %.4f, post %.4f" % [phase_at_split, post_split_phase])

	# --- Now peer B's split fires ---
	# B is currently "merged" from its coord's perspective (we never disconnected
	# it). Trigger its disconnect; it should fork solo:peer-B.
	#
	# In-process autoload aliasing: B's split reads the current active island
	# (which is now solo:peer-A from A's prior split) and treats it as the
	# pre-merge island to retire. In production each process has its own
	# IslandRegistry so this aliasing doesn't happen — A's solo island lives
	# in A's process, B's in B's process. Here we just verify B's solo island
	# exists and is active after its split.
	coord_b.on_peer_disconnected()
	a.check(IslandRegistry.get_island("solo:peer-B") != null,
		"solo:peer-B should exist after B's split")
	a.check(IslandRegistry.active_island().id == "solo:peer-B",
		"expected active island 'solo:peer-B' after B's split, got '%s'" % IslandRegistry.active_island().id)

	a.pass_scenario("split creates per-session solo islands and preserves clock state")
