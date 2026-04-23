## PuppetCluster — spawn N World instances in the same headless process and
## wire their TileMutationBus instances together so local mutations mirror
## synchronously across peers. Each World gets its own Puppet.
##
## This is the Tier-1 multiplayer test harness. It exercises the same
## apply_remote_mutation code path that real RPC goes through, minus the
## serialization hop — enough to catch cross-peer sync bugs (structures
## ghosting, home-anchor not clearing, CRDT divergence) without any network
## layer, sub-second per scenario.
##
## Scenarios receive an Array of Puppets. Convention: ps[0] is "peer A",
## ps[1] is "peer B", etc.
##
## Lifecycle:
##   1. CLI flag --puppet-cluster-scenario=res://path/to/scenario.gd
##   2. MainMenu dispatches to PuppetCluster.tscn instead of World.tscn
##   3. PuppetCluster._ready spawns N Worlds + Puppets, wires buses
##   4. Calls scenario._run(puppets)
##   5. Scenario calls ps[0].pass_scenario or any puppet's .fail
##
## Storage: Backend is overridden with a shared InMemoryBackend. Both peers
## converge on the same storage — mirrors the Freenet contract model.
extends Node

const WORLD_SCENE := preload("res://world/World.tscn")
const PuppetScript := preload("res://dev/Puppet.gd")
const InMemoryBackendScript := preload("res://dev/InMemoryBackend.gd")

const PEER_COUNT := 2

var _puppets: Array = []
var _outcome_reported: bool = false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario_path := ""
	for a in args:
		if typeof(a) == TYPE_STRING and (a as String).begins_with("--puppet-cluster-scenario="):
			scenario_path = (a as String).trim_prefix("--puppet-cluster-scenario=")
			break
	if scenario_path == "":
		push_error("PuppetCluster: no --puppet-cluster-scenario= flag")
		get_tree().quit(2)
		return

	# Swap to an in-memory backend so peers converge on isolated-but-shared
	# storage rather than fighting over user://chunks/.
	Backend.override(InMemoryBackendScript.new())

	_spawn_peers()
	_wire_buses()
	call_deferred("_start", scenario_path)

func _spawn_peers() -> void:
	for i in range(PEER_COUNT):
		var world: Node = WORLD_SCENE.instantiate()
		world.name = "WorldPeer%d" % i
		add_child(world)
		# Each Puppet attaches to its own World. The Puppet node lives under
		# the World so it can resolve sibling paths ("Player", "ChunkManager")
		# exactly the same way the single-peer harness does.
		var puppet: Node = PuppetScript.new()
		puppet.name = "Puppet"
		world.add_child(puppet)
		puppet.call("attach_cluster", world, self, i)
		_puppets.append(puppet)

## Connect each peer's TileMutationBus to every other peer so a local
## request_place_tile on one World mirrors into the others via their own
## apply_remote_mutation path (the same entry point real RPC uses).
func _wire_buses() -> void:
	var buses: Array = []
	for p in _puppets:
		var world: Node = p.world()
		var bus: Node = world.get_node_or_null("TileMutationBus")
		if bus == null:
			push_error("PuppetCluster: peer %s has no TileMutationBus" % world.name)
			return
		# Give each peer a distinct author id so tie-breaking and log filtering work.
		bus.local_author_id = "peer_%d" % _puppets.find(p)
		buses.append(bus)
	for i in range(buses.size()):
		for j in range(buses.size()):
			if i == j: continue
			buses[i].add_test_peer(buses[j])

func _start(scenario_path: String) -> void:
	# Let each Puppet finish its own startup grace frames first.
	await get_tree().process_frame
	await get_tree().process_frame
	# Wait for every puppet to report ready before dispatching the scenario.
	for p in _puppets:
		await p.wait_ready()

	var script: GDScript = load(scenario_path)
	if script == null:
		fail("scenario load failed: " + scenario_path)
		return
	var scenario = script.new()
	add_child(scenario)
	if not scenario.has_method("_run"):
		fail("scenario has no _run(puppets) method: " + scenario_path)
		return
	print("PuppetCluster: running scenario %s with %d peers" % [scenario_path, _puppets.size()])
	await scenario._run(_puppets)
	pass_scenario("scenario returned normally")

## Reported by any puppet — the first outcome wins and tears down the process.
func pass_scenario(msg: String = "") -> void:
	if _outcome_reported:
		return
	_outcome_reported = true
	print("PuppetCluster: PASS — %s" % msg)
	print("PuppetCluster: peers=%d" % _puppets.size())
	get_tree().quit(0)

func fail(msg: String) -> void:
	if _outcome_reported:
		return
	_outcome_reported = true
	push_error("PuppetCluster: FAIL — %s" % msg)
	get_tree().quit(1)
