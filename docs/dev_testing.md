# Agent-runnable testing

Two systems that together let an agent drive the game without xpra/xdotool
in the loop: the **EventLog** (structured record of what happened) and the
**Puppet harness** (API to drive the player directly from a scenario script).

## EventLog

Autoload. Writes one JSON object per line to `user://logs/events_<unix>.jsonl`
and keeps the last 2000 events in memory.

### API

```gdscript
EventLog.log("event_type", {"key": value, ...})
EventLog.events_of("event_type") -> Array     # in-memory events of that type
EventLog.snapshot() -> Array                  # all events this session
EventLog.get_path() -> String                 # current log file
EventLog.set_enabled(false)                   # tests may disable
```

### Event vocabulary

| Event type | Fields | Emitted by |
|---|---|---|
| `session_start` | `unix_time` | EventLog._ready |
| `tile_place` | `coords, layer, tile_id` | TileMutationBus |
| `tile_remove` | `coords, layer` | TileMutationBus |
| `click` | `tile, button, tool_id, source` (`input`/`puppet`) | TileInteraction._dispatch |
| `tool_select` | `index, id` | Inventory.select_tool |
| `hotbar_select` | `index, id` | Hotbar._set_active |
| `player_died` | `pos` | Player._on_player_died |
| `player_respawned` | `pos, has_home, advanced_to_dawn` | Player._on_player_died (tail) |

Adding a new event type is two lines: call `EventLog.log(...)` at the
chokepoint, add a row to the table above.

### Reading a session

```bash
cat ~/.local/share/godot/app_userdata/Commons/logs/events_*.jsonl | jq .
```

Each line is a complete event — `grep` by type, `jq` for shape, diff two
sessions to see what changed.

## Puppet harness

Not an autoload. Spawned only when `--puppet-scenario=res://path/to/scenario.gd`
is passed via `--` to Godot (user-cmdline-args). Production builds pay zero cost.

### Run a scenario

```bash
godot4 --path . -- --puppet-scenario=res://tests/scenarios/lantern_no_delete.gd
```

Puppet exits with code 0 on pass, 1 on fail. The event log path is printed
on exit so you know where to look for details.

### Scenario contract

```gdscript
extends Node

func _run(p: Node) -> void:
    await p.wait_ready()          # chunks loaded, player exists
    p.select_tool(0)
    p.check(p.active_tool_id() == "lantern", "tool select failed")
    p.click_tile(Vector2i(5, 3), MOUSE_BUTTON_LEFT)
    await p.wait_frames(2)
    p.check(p.has_object_at(Vector2i(5, 3)), "tile was removed unexpectedly")
    p.pass_scenario("lantern is inert")
```

If the scenario returns without calling `pass_scenario` or `fail`, Puppet
treats it as a pass.

### Puppet API

```gdscript
# Lifecycle
wait_ready() -> void
wait_frames(n: int) -> void
wait_for_event(type: String, timeout_sec: float = 5.0) -> Dictionary

# Actions
teleport(tile_pos: Vector2i) -> void
select_tool(slot: int) -> void
click_tile(tile_pos: Vector2i, button: int = MOUSE_BUTTON_LEFT) -> void

# Queries
active_tool_id() -> String
object_atlas_at(tile_pos: Vector2i) -> Vector2i
ground_atlas_at(tile_pos: Vector2i) -> Vector2i
has_object_at(tile_pos: Vector2i) -> bool
snapshot_objects(top_left, bottom_right) -> Dictionary   # "x,y" → atlas

# Outcome
check(cond: bool, msg: String) -> void    # fail() on falsity
pass_scenario(msg: String = "") -> void
fail(msg: String) -> void
screenshot(path: String) -> void
```

### Why this exists

xpra + xdotool input synthesis is unreliable — clicks silently drop, the
agent and the human can't tell whether the fix works or the input dropped.
Puppet bypasses input synthesis entirely by calling dispatch methods directly,
and EventLog provides a deterministic record of what the game processed.

Scenarios are cheap to write, run headless, and gate regressions without
the agent needing to watch a display.
