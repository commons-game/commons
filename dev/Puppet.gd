## Puppet — test harness that drives the game directly from a scenario script.
##
## Purpose: let us write repeatable, headless-friendly interaction tests that
## don't depend on xpra, xdotool, or display forwarding. The agent running the
## scenario has direct, synchronous control over the player and can observe
## state via tile queries and the EventLog.
##
## Lifecycle:
##   1. World.gd checks for `--puppet-scenario=res://path/to/scenario.gd` in
##      OS.get_cmdline_user_args().
##   2. If found, World creates a Puppet instance (via new()), calls attach(),
##      then loads the scenario script and calls scenario._run(puppet).
##   3. Scenario awaits puppet methods to drive the game. When done it calls
##      puppet.pass() or puppet.fail(msg) which quits with exit 0 or 1.
##
## Scenario contract:
##   extends Node
##   func _run(p: Node) -> void:
##       await p.wait_ready()
##       p.select_tool(0)
##       ...
##       p.pass("lantern no-op verified")
##
## Not an autoload — instantiated only when the CLI flag is present so production
## builds pay no cost.
extends Node

var _world: Node = null
var _ready_fired: bool = false
var _scenario_path: String = ""
var _outcome_reported: bool = false

## Attach to the world. Called once by World after its own _ready completes.
func attach(world: Node, scenario_path: String) -> void:
	_world = world
	_scenario_path = scenario_path
	# Defer a frame so World has fully resolved @onready fields.
	call_deferred("_start")

func _start() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_ready_fired = true
	var script = load(_scenario_path)
	if script == null:
		push_error("Puppet: failed to load scenario %s" % _scenario_path)
		fail("scenario load failed: " + _scenario_path)
		return
	var scenario = script.new()
	add_child(scenario)
	if not scenario.has_method("_run"):
		fail("scenario has no _run(puppet) method: " + _scenario_path)
		return
	print("Puppet: running scenario %s" % _scenario_path)
	await scenario._run(self)
	# If the scenario returns without calling pass/fail, treat as pass.
	pass_scenario("scenario returned normally")

# ---------------------------------------------------------------------------
# Lifecycle controls
# ---------------------------------------------------------------------------

func wait_ready() -> void:
	while not _ready_fired:
		await get_tree().process_frame

func wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## Wait real wall-clock seconds. Prefer this over wait_frames when the
## scenario cares about in-game timers (cooldowns, decay windows) because
## frame duration is non-deterministic under headless perf spikes.
func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

## Wait until a specific event type appears in the EventLog, or timeout.
## Returns the event dict, or {} if the timeout elapsed.
func wait_for_event(event_type: String, timeout_sec: float = 5.0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var seen := EventLog.events_of(event_type).size()
	while Time.get_ticks_msec() - t0 < int(timeout_sec * 1000.0):
		var all := EventLog.events_of(event_type)
		if all.size() > seen:
			return all[-1]
		await get_tree().process_frame
	return {}

# ---------------------------------------------------------------------------
# Node accessors
# ---------------------------------------------------------------------------

func world() -> Node:
	return _world

func player() -> Node:
	return _world.get_node_or_null("Player")

func chunk_manager() -> Node:
	return _world.get_node_or_null("ChunkManager")

# ---------------------------------------------------------------------------
# Player actions
# ---------------------------------------------------------------------------

func teleport(tile_pos: Vector2i) -> void:
	var p := player()
	if p == null: return
	p.position = Vector2(
		tile_pos.x * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5,
		tile_pos.y * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5,
	)

func select_tool(tool_slot: int) -> void:
	var p := player()
	if p == null or p.inventory == null: return
	p.inventory.select_tool(tool_slot)

func active_tool_id() -> String:
	var p := player()
	if p == null or p.inventory == null: return ""
	return str(p.inventory.get_active_tool().get("id", ""))

func click_tile(tile_pos: Vector2i, button: int = MOUSE_BUTTON_LEFT) -> void:
	var p := player()
	if p == null: return
	var ti := p.get_node_or_null("TileInteraction")
	if ti == null:
		push_error("Puppet.click_tile: no TileInteraction child on Player")
		return
	ti.puppet_click(tile_pos, button)

# ---------------------------------------------------------------------------
# State queries
# ---------------------------------------------------------------------------

## Returns object-layer atlas at tile_pos. Vector2i(-1,-1) if empty/unloaded.
func object_atlas_at(tile_pos: Vector2i) -> Vector2i:
	var cm := chunk_manager()
	if cm == null: return Vector2i(-1, -1)
	var tile: Dictionary = cm.get_object_tile_at(tile_pos)
	return Vector2i(int(tile.get("atlas_x", -1)), int(tile.get("atlas_y", -1)))

func ground_atlas_at(tile_pos: Vector2i) -> Vector2i:
	var cm := chunk_manager()
	if cm == null: return Vector2i(-1, -1)
	return cm.get_ground_atlas_at(tile_pos)

func has_object_at(tile_pos: Vector2i) -> bool:
	var cm := chunk_manager()
	if cm == null: return false
	return cm.has_tile_at(tile_pos, 1)

## Snapshot object-layer tiles in a [top_left, bottom_right] tile rect.
## Returns Dictionary keyed by "x,y" → Vector2i atlas (or (-1,-1) if empty).
func snapshot_objects(top_left: Vector2i, bottom_right: Vector2i) -> Dictionary:
	var out := {}
	for y in range(top_left.y, bottom_right.y + 1):
		for x in range(top_left.x, bottom_right.x + 1):
			var tp := Vector2i(x, y)
			out["%d,%d" % [x, y]] = object_atlas_at(tp)
	return out

# ---------------------------------------------------------------------------
# Scenario outcome
# ---------------------------------------------------------------------------

func pass_scenario(msg: String = "") -> void:
	if _outcome_reported: return
	_outcome_reported = true
	print("Puppet: PASS — %s" % msg)
	print("Puppet: event log at %s" % EventLog.log_file_path())
	get_tree().quit(0)

func fail(msg: String) -> void:
	if _outcome_reported: return
	_outcome_reported = true
	push_error("Puppet: FAIL — %s" % msg)
	print("Puppet: event log at %s" % EventLog.log_file_path())
	get_tree().quit(1)

## Assertion helper that fails the scenario on falsity.
func check(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)

func screenshot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Puppet: screenshot saved to %s" % path)
