# Known Issues

## Environment

### Worktree isolation hook broken (WorktreeCreate)
**Status:** Workaround in place.
**Symptom:** `Agent` tool with `isolation: "worktree"` fails with "Failed to create worktree" because the `WorktreeCreate` hook receives a JSON payload that doesn't include a `worktree_path` key in the current Claude Code version.
**Workaround:** Create the worktree manually before spawning the agent:
```bash
git worktree add /home/adam/development/freeland-<branch-name> -b <branch-name>
```
Then point the agent at that directory explicitly in the prompt. Remove with:
```bash
git worktree remove /home/adam/development/freeland-<branch-name>
git branch -d <branch-name>
```

## Environment (continued)

### Godot editor on headless server via xpra
**Setup:**
- Godot 4.3 installed at `~/bin/godot4`
- xpra on port 14600, display `:100`
- Must use `--rendering-driver opengl3` (llvmpipe software renderer — no GPU)
- Must use `--editor` flag or Godot launches the game instead of the editor

**xpra is managed by systemd** (`~/.config/systemd/user/xpra.service`):
- Auto-restarts when Godot windows close (`Restart=always`)
- Exposes web client on port 14600

**Aliases** (in `~/.bashrc`):
- `freeland-xpra` — `systemctl --user start xpra.service`
- `freeland-xpra-stop` — stop the service
- `freeland-xpra-log` — follow service logs
- `freeland-editor` — launch Godot editor in xpra
- `freeland-vt` — shortcut for `scripts/visual_test.sh`

**Connect from laptop:** `http://server:14600`

**Visual testing script:** `scripts/visual_test.sh`
- `start-host [port]` / `start-client [ip] [port]` / `stop-all` / `status`
- `walk <left|right|up|down> <frames>` — prints JS snippet for Playwright `browser_evaluate`
- `key-js <key> [code] [keyCode]` — prints JS for a single keydown+keyup

## Project Code

### GDScript LSP false-positive: "Unexpected < in class body" at line 1
**Status:** Known false positive, no action needed.
**Symptom:** The gdscript LSP plugin reports `Unexpected "<" in class body [-1]` at line 1 of any newly-saved `.gd` file. The error clears on its own once the LSP fully re-indexes the file.
**Root cause:** Transient LSP state during file save; not a real parse error.
**Workaround:** Ignore. If it persists longer than a few seconds, the LSP or Godot editor may need a restart.

### Godot global class_name not resolved for externally-created files
**Status:** Workaround in place.
**Symptom:** If a `.gd` file with `class_name Foo` is created outside the Godot editor (e.g. by an agent writing files directly), Godot's class registry may not know about `Foo` until it rescans the filesystem. Autoloads that reference `Foo.new()` by name will fail with "Identifier not declared in the current scope."
**Workaround:** Use `preload("res://path/to/Foo.gd")` in the calling file instead of relying on the global class name. Example in `Backend.gd`:
```gdscript
const LocalBackendScript := preload("res://backend/local/LocalBackend.gd")
var _backend: IBackend = LocalBackendScript.new()
```

### JSON.parse_string returns floats for integer values
**Status:** Known GDScript behavior, handled in tests.
**Symptom:** `JSON.parse_string('{"x": 5}')["x"]` returns `5.0` (float), not `5` (int). gdUnit4 `is_equal(5)` fails strict type comparison against `5.0`.
**Workaround:** Cast to int before asserting: `int(parsed["x"])`. Runtime deserialization code using `int(item["layer"])` etc. is already correct.

### ChunkManager._player_chunk sentinel bug
**Status:** Fixed.
**Symptom:** `_player_chunk` initialized to `Vector2i.ZERO`. First call to `update_player_position(Vector2i(0,0))` returned immediately (new_chunk == _player_chunk) without loading any chunks.
**Fix:** Initialize to `Vector2i(-9999, -9999)` — a sentinel that can't equal any real chunk in the first call.

### TileInteraction path was one level too shallow
**Status:** Fixed.
**Symptom:** `$"../ChunkManager"` in `TileInteraction.gd` failed because `TileInteraction` is a grandchild of `World` (child of `Player`, which is child of `World`). `..` only reaches `Player`, not `World`.
**Fix:** Changed to `$"../../ChunkManager"`.
**Rule:** When a script is inside an instanced sub-scene (e.g. `Player.tscn`), its `$".."` paths traverse within that sub-scene's hierarchy, not the parent world scene.

### GDScript parse() pattern — no static from_dict()
**Status:** Established pattern, use everywhere.
**Symptom:** `static func from_dict() -> MyClass` fails when `class_name` isn't registered — `MyClass.new()` in a static context throws "Identifier not declared."
**Pattern:** Use an instance method instead:
```gdscript
var obj = MyScript.new()
obj.parse(data_dict)
```
Never use static factory methods on data classes that use `class_name`.

### MultiplayerSpawner auto_spawn_list is silently ignored at runtime
**Status:** Fixed.
**Symptom:** The `auto_spawn_list` property written into a `.tscn` file for `MultiplayerSpawner` is not a valid runtime property — it is silently ignored, so the spawner never knows which scenes to replicate. Connected clients never receive spawned nodes.
**Fix:** Register spawnable scenes programmatically in `_ready()`:
```gdscript
$MultiplayerSpawner.add_spawnable_scene("res://player/RemotePlayer.tscn")
```

### MultiplayerSpawner does not preserve set_multiplayer_authority on replicated nodes
**Status:** Fixed.
**Symptom:** Host calls `node.set_multiplayer_authority(peer_id)` before `add_child(node)`. When the spawner replicates the node to clients, the authority defaults back to 1 on the client side — the client never sends sync updates because it doesn't think it's authoritative.
**Fix:** In `RemotePlayer._ready()`, re-derive authority from the node name convention `RemotePlayer_<peer_id>`:
```gdscript
var parts := name.split("_")
if parts.size() == 2 and parts[1].is_valid_int():
    set_multiplayer_authority(int(parts[1]))
```

### RemotePlayer must be Node2D, not CharacterBody2D
**Status:** Fixed.
**Symptom:** RemotePlayer shared a CollisionShape2D with the local Player (both at the same world position on the client). Physics blocked the Player from moving — `move_and_slide()` treated the RemotePlayer as a solid obstacle.
**Fix:** RemotePlayer extends `Node2D` (no physics), CollisionShape2D removed. It is purely visual.

### Injecting keyboard input to Godot via xdotool does not work through xpra
**Status:** Workaround documented.
**Symptom:** `xdotool windowfocus --sync <id>; xdotool keydown Right` sends X11 key events but Godot never receives them when running behind xpra.
**Workaround:** Dispatch keyboard events via JavaScript in xpra's browser client instead:
```javascript
document.dispatchEvent(new KeyboardEvent('keydown', {
    key:'ArrowRight', code:'ArrowRight', keyCode:39, bubbles:true
}));
```
Use via Playwright's `browser_evaluate` tool or the browser console.

### Array element type inference in GDScript
**Status:** Known GDScript limitation, handled with explicit casts.
**Symptom:** Iterating over `Array` of `Vector2i` values and using `:=` on the result fails type inference: "Cannot infer the type of 'x' variable."
**Workaround:** Explicit cast: `var v: Vector2i = item as Vector2i` or `(item as Vector2i)`.

### SceneReplicationConfig boolean parse errors in .tscn
**Status:** Fixed.
**Symptom:** Hand-writing `spawn = true` / `sync = true` inside a `SceneReplicationConfig` sub-resource in a `.tscn` file causes non-fatal errors at startup:
```
ERROR: Condition "p_value.get_type() != Variant::BOOL" is true. Returning: false
   at: _set (modules/multiplayer/scene_replication_config.cpp:59)
```
Godot 4.3's deserializer passes these values with the wrong type, so `spawn` and `sync` silently default to false (i.e., position sync does NOT work despite no crash).
**Fix:** Remove the `SceneReplicationConfig` sub-resource from the `.tscn` entirely and build it programmatically in `_ready()`:
```gdscript
func _ready() -> void:
    var config := SceneReplicationConfig.new()
    config.add_property(NodePath(".:position"))
    config.property_set_spawn(NodePath(".:position"), true)
    config.property_set_sync(NodePath(".:position"), true)
    $MultiplayerSynchronizer.replication_config = config
```
Applied in `player/Player.gd` and `player/RemotePlayer.gd`.
