# Known Issues

## Chat System

### T key did not open chat (FIXED)
**Status:** Fixed in commit "fix: T key chat".
**Root cause:** Two compounding issues:
1. `Player._unhandled_input` called `chat_input.is_visible_in_tree()` — but `CanvasLayer` extends `Node` directly, NOT `CanvasItem`, so `is_visible_in_tree()` does not exist on it. The call failed silently, the guard always evaluated false, and activate() was never called. The fix is to use `chat_input.visible` (a property CanvasLayer does have).
2. `ChatInput._build_ui()` used `Panel + StyleBoxFlat` which can fail to render in CanvasLayer context. Replaced with `ColorRect` for reliable rendering. Added `mouse_filter = MOUSE_FILTER_IGNORE` and `focus_mode = FOCUS_NONE` on the background rect to prevent it consuming input events.
3. `activate()`/`deactivate()` now use `show()`/`hide()` instead of direct `visible =` assignment for robustness.
**Tests added:** `test_ui_scripts_compile.gd`, `test_chat_input_behavior.gd`, `test_chat_key_routing.gd` (19 total).

### CanvasLayer does not have is_visible_in_tree()
**Status:** Known Godot 4 type hierarchy issue.
**Detail:** `CanvasLayer` extends `Node`, not `CanvasItem`. Methods like `is_visible_in_tree()`, `hide()`, `show()` from `CanvasItem` are NOT available on `CanvasLayer`. Use the `visible` property directly. If you need show()/hide() convenience methods, they DO work on CanvasLayer in Godot 4 (CanvasLayer implements them separately), but `is_visible_in_tree()` does not exist.

## Freenet Backend (Phase 6 spike — open items)

### End-to-end spike complete
**Status:** Done. Chunk Put + Get round-trips through Freenet node verified.
**How to run:**
```bash
# 1. Install Freenet node (once): curl -fsSL https://freenet.org/install.sh | sh
# 2. Start node in local mode:
freenet local --ws-api-address 0.0.0.0
# 3. Build packaged contract:
cd backend/freenet/contracts/chunk-contract
CARGO_TARGET_DIR=../../target fdev build
# 4. Build and run proxy:
cargo build -p freeland-proxy --release
cp contracts/chunk-contract/build/freenet/freeland_chunk_contract .
./target/release/freeland-proxy
# 5. In Backend.gd: use_freenet = true
```
**Known fdev bug:** `fdev build` panics with "Could not find workspace root" unless `CARGO_TARGET_DIR` is set. Workaround: `CARGO_TARGET_DIR=$(pwd)/../../target fdev build`.
**Node binds IPv6 by default:** Must pass `--ws-api-address 0.0.0.0` for IPv4 clients. The proxy URL needs `?encodingProtocol=native` suffix.

### FreenetBackend.gd requires `use_freenet = true` in Backend.gd
**Status:** Manual toggle until we decide when to auto-enable.
**How to enable:** In `autoloads/Backend.gd`, set `use_freenet = true` before `_ready()` runs (or expose as a project setting / command-line arg in a future pass).

### Freenet node auto-updates on startup — no --no-auto-update flag
**Status:** Accepted risk, mitigation planned.
**Detail:** The Freenet node binary checks GitHub on startup and self-updates. It also force-exits if it detects peer version mismatch >6h. There is no CLI flag to disable this. The binary only skips update if it detects a "dirty (locally modified) build" (found via `strings`).
**Mitigation plan:** See `docs/freenet_retrospective.md` — Layer 1 (proxy version assertion in `FREENET_VERSION`), Layer 2 (commit `Cargo.lock`), Layer 3 (commit packaged contract artifact). Do NOT try to suppress auto-update; instead make breakage loud and fast.
**If the proxy fails after a node update:** Run `scripts/update_freenet_backend.sh` (planned) to re-verify the round-trip and update the pinned version.

### No proxy integration smoke test
**Status:** Done — `backend/freenet/proxy/tests/round_trip.rs`.
**Detail:** Test is gated behind `--features integration` so normal `cargo test` stays green.
**Run it:**
```bash
FREENET_NODE_URL=ws://localhost:7509/v1/contract/command?encodingProtocol=native \
FREELAND_CONTRACT_PATH=./freeland_chunk_contract \
  cargo test --features integration -p freeland-proxy -- round_trip --nocapture
```

### fdev upstream bug: CARGO_TARGET_DIR must be set manually
**Status:** Workaround in place, upstream bug to file.
**Detail:** `fdev build` panics "Could not find workspace root" because `env!("CARGO_MANIFEST_DIR")` is baked in from the cargo registry path at fdev's compile time.
**Workaround:** `CARGO_TARGET_DIR=$(pwd)/../../target fdev build` (from the contract directory).
**Action:** File upstream issue on freenet/freenet-core.

### Reputation and equipment not on Freenet
**Status:** Deferred — Freenet delegates not implemented yet.
**Detail:** `save_reputation`, `load_reputation`, `save_equipment`, `load_equipment` fall back to local files in `FreenetBackend`. These need a Freenet delegate (private per-user storage) for true decentralization.

## Performance

### Perf torture baselines (2026-04-15, post physics-batching fix)

**llvmpipe (software renderer)**
| Test | Result | Notes |
|---|---|---|
| chunk_flood | avg=2.5ms, peak=3.9ms, 120 chunks | CPU-bound — GPU makes no difference |
| mob_ramp | ~60fps @ 80 mobs, 30fps @ 200 mobs, final=42fps | |
| tile_flood | 184k mutations/sec, 10.9ms for 2000 | CPU-bound |
| chunk_thrash | peak=96.5ms, avg=20.4ms, 24 load bursts | Physics broadphase bottleneck |

**RTX 3060 (PRIME offload, Xvfb :200, debug build)**
| Test | Result | Notes |
|---|---|---|
| chunk_flood | avg=2.4ms, peak=3.5ms, 120 chunks | Same — chunk load is CPU |
| mob_ramp | 59fps @ 10 mobs → 35fps @ 200 mobs, never drops below 30fps | Vsync-limited; graceful degradation |
| tile_flood | 140k mutations/sec, 14.3ms | Slightly slower — debug overhead |
| chunk_thrash | peak=118.5ms, avg=34ms, 24 load bursts | avg higher due to vsync; peak ≈ same physics cost |

**Key finding:** 200 mobs stays above 30fps on the RTX 3060. Physics broadphase spike (~100ms peak) is the chunk_thrash ceiling on both renderers — it's CPU physics work, not rendering.

**Re-run (CPU/llvmpipe):** `freeland-perf-cpu` alias, or:
```bash
DISPLAY=:200 ~/bin/godot4 --rendering-driver opengl3 --path /home/adam/development/freeland -- --perf-torture
```
**Re-run (GPU/RTX 3060):** `freeland-perf-gpu` alias, or:
```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia DISPLAY=:200 ~/bin/godot4 --rendering-driver opengl3 --path /home/adam/development/freeland -- --perf-torture
```
**Notes:**
- Use `:200` (Xvfb, managed by `xvfb-test.service`) not `:100` (xpra) — xpra adds ~33ms/frame encoding overhead that pollutes all frame-time measurements
- Use `godot4 --path`, NOT `./freeland.x86_64` — the binary has an embedded PCK with old scripts
- chunk_flood and tile_flood are CPU-bound; GPU makes no difference there
- chunk_thrash and mob_ramp reflect physics+AI cost, which IS affected by GPU frame budget
Results saved to `user://perf_baselines/`.

### chunk_thrash peak frames are physics broadphase, not I/O
**Status:** Mitigated — see "initialize before add_child" fix below.
**Root cause:** Each chunk loaded via `_render_all()` adds ~90 ObjectLayer collision shapes to the physics world. The engine rebuilds its broadphase per-frame. 3 chunks × 90 shapes = 270 new collision bodies/frame. On real GPU hardware this is much cheaper than llvmpipe.
**What was fixed (round 1):** Unload path now spreads across frames (MAX_UNLOADS_PER_FRAME=3) and skips `Backend.store_chunk()` for unmodified chunks (eliminates nearly all unload I/O in normal gameplay).
**What was fixed (round 2):** `ChunkManager._load_chunk()` now calls `chunk.initialize()` BEFORE `add_child()`. All `set_cell()` calls happen on a detached node — Godot batches all physics body creation in one pass during `_enter_tree()` instead of one body per `set_cell()`. The `collision_enabled` toggle workaround is NOT needed; the batch happens naturally.

## Combat / Mob Polish (next pass)

### No visual feedback on pickup or combat
**Status:** Deferred.
**Symptom:** Walking over a loot tile and attacking mobs are silent — no flash, sound, or HUD update. Only console prints.
**Next pass:** Brief pickup flash on item tile removal, HP bar above mobs, player HP shown in HUD.

### Mobs spawn on top of the player
**Status:** Deferred.
**Symptom:** Spawn radius 8 tiles with chase range 6 — mobs enter aggro immediately on spawn, attacking before the player can orient.
**Next pass:** Increase spawn radius to 12–15 tiles, or add a 2s aggro-grace period after spawning.

### No combat audio or death effects
**Status:** Deferred.
**Next pass:** Screen shake on hit, red flash on player damage, mob death particle/fade.

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

### --dev-health-check requires -- separator and cannot use --headless
**Status:** Pattern established.
**Symptom:** Running `./freeland.x86_64 --dev-health-check` hangs silently (arg not seen). Running with `--headless` segfaults in `get_viewport().get_texture().get_image()`.
**Root cause:** `OS.get_cmdline_user_args()` only returns args after `--`. Without `--`, `--dev-health-check` is treated as an engine arg and ignored. `--headless` uses a dummy renderer with no texture, so viewport image capture segfaults.
**Correct invocation:**
```bash
DISPLAY=:100 ./freeland.x86_64 --rendering-driver opengl3 -- --dev-health-check
```
**Applies to:** All `--dev-*` args (health-check, screenshot-cycle, frame-log).

### gdUnit4 headless test invocation
**Status:** Established pattern.
**Correct invocation:**
```bash
DISPLAY=:100 ~/bin/godot4 --rendering-driver opengl3 \
  --path /home/adam/development/freeland \
  --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/ -c --ignoreHeadlessMode
```
**Notes:**
- Use `-a res://tests/` **before** any `--` separator — gdUnit4 reads `OS.get_cmdline_args()`, not `OS.get_cmdline_user_args()`
- `--ignoreHeadlessMode` is required; without it the runner exits with code 103
- `--run-tests --exit` (the Godot built-in flags) do NOT invoke gdUnit4 — they're unrelated

### Chunks fade to gray after ~5 seconds (ChunkWeightSystem weight formula)
**Status:** Fixed.
**Symptom:** World looks correct for ~5 seconds, then gradually fades to gray over 3–5 seconds. Repeats.
**Root cause:** `ChunkWeightSystem.FADE_THRESHOLD = 5.0` but the weight formula only counted `modification_count`. Unmodified chunks always scored `weight = 0`, so every unmodified chunk failed the threshold on the first 5-second tick and started fading (alpha tween to 0, revealing the gray viewport background).
**Fix:** Added `VISIT_BASE_SCORE = 10.0` to the weight formula. Recently-visited chunks now get `visit_score = VISIT_BASE_SCORE * decay` which decays on the same `RECENCY_HALF_LIFE`. A chunk visited within the last hour scores above `FADE_THRESHOLD` and won't fade. Only genuinely abandoned chunks eventually fade out.

### xpra periodic gray screen flash
**Status:** Not xpra — was the chunk fade bug above. `--encoding=rgb --video=no` left in xpra config as it doesn't hurt.

### Godot editor on headless server via xpra
**Setup:**
- Godot 4.3 installed at `~/bin/godot4`
- xpra on port 14600, display `:100`
- Must use `--rendering-driver opengl3` (llvmpipe software renderer — no GPU)
- Must use `--editor` flag or Godot launches the game instead of the editor

**xpra runs in DESKTOP mode** (`~/.config/systemd/user/xpra.service`):
- `xpra start-desktop :100` with `xfwm4` as window manager
- Browser shows a single canvas rendering the full 1920x1080 virtual desktop
- Avoids seamless-mode reconnect bug: in seamless mode, switching JS focus between window canvases triggered an X11 focus event that caused xpra to drop and reconnect the browser session
- Auto-restarts (`Restart=always`); exposes web client on port 14600

**Aliases** (in `~/.bashrc`):
- `freeland-xpra` — `systemctl --user start xpra.service`
- `freeland-xpra-stop` — stop the service
- `freeland-xpra-log` — follow service logs
- `freeland-editor` — launch Godot editor in xpra
- `freeland-vt` — shortcut for `scripts/visual_test.sh`

**Connect from laptop:** `http://server:14600`

**Visual testing script:** `scripts/visual_test.sh`
- `start-host [port]` / `start-client [ip] [port]` — launches with `--position` for side-by-side layout (host left, client right at 960px each)
- `stop-all` / `status`
- `walk <left|right|up|down> <frames>` — prints JS snippet for Playwright `browser_evaluate`
- `key-js <key> [code] [keyCode]` — prints JS for a single keydown+keyup
- In desktop mode, keyboard events go to the X11-focused window. Click the desired window area in the browser canvas first, then dispatch keys to `document`.

## Layer 4 — Food/Hunger, Berry Plant, Eat with F (2026-04-15)

### Food drain uses a while-loop to handle large deltas
**Status:** Implemented correctly.
**Detail:** `_process` accumulates `_food_timer` and uses `while _food_timer >= FOOD_DRAIN_INTERVAL` (not `if`) so that a single large delta (e.g. test calling `_process(16.0)`) drains the correct number of ticks. The `if` variant was the initial bug — caught by `test_food_decrements_twice_after_two_intervals` going red.

### Plant tile at atlas (2,2) is walkable (no collision)
**Status:** By design.
**Detail:** Plant at atlas (2,2) has no entry in `_ensure_tileset_collision`'s tile_polys, so no collision polygon is generated. Player walks through plants. If blocking plants are ever wanted, add `Vector2i(2,2): bottom_poly` to the tile_polys dict in `Chunk._ensure_tileset_collision()`.

### Starvation timer test requires assert_float not assert_int
**Status:** Fixed in test.
**Detail:** `_starvation_timer` is a float. `assert_int(_starvation_timer).is_equal(0)` throws "unexpected type <float>". Use `assert_float(_player._starvation_timer).is_equal(0.0)` when testing timer state.

## Layer 3 — Campfire, Workbench, Stone Tools (2026-04-15)

### Inventory.set_tool_slot() now accepts "structure" category
**Status:** Intentional change.
**Detail:** Structures (campfire, workbench) can now live in tool slots so TileInteraction can detect them via get_active_tool(). The category gate now allows "tool" OR "structure". Test_inventory tests still pass because they only set tools; no regression expected.

### CampfireSystem uses polling (not signals) for light sync
**Status:** Acceptable for current scope.
**Detail:** CampfireSystem scans loaded chunks every 2s. Lights may lag up to 2s after campfire placement/removal. If real-time sync is needed, wire to TileMutationBus's tile_store events in a future pass.

## Project Code

### Player renders under ObjectLayer / collision unusable in dense forest
**Status:** Fixed.
**Symptom 1 (visual):** Player circle drawn under tree/rock tiles — player appears "between layers."
**Symptom 2 (collision):** Player either stuck on spawn (started on a tree tile) or nearly impassable world due to full-tile 16×16 collision boxes on every tree/rock.
**Root cause 1:** No explicit `z_index` set on GroundLayer, ObjectLayer, or Player. Godot 4 renders CanvasItems depth-first by z_index; ties broken by tree order. Dynamically-added chunks (added as children of ChunkManager after Player is in the tree) can end up with a higher implicit draw order than Player.
**Root cause 2:** `_ensure_tileset_collision` used a full-tile polygon (`-h,-h` to `h,h`) for all collidable tiles including trees. ~25% of grass tiles generate trees (ProceduralGenerator `o > 0.5`), creating near-impassable terrain. Full-tile collision also means the player can spawn inside a tree at origin.
**Fix:**
- `Chunk._ready()`: `ground_layer.z_index = 0`, `object_layer.z_index = 1`
- `Player._ready()`: `z_index = 2`
- `_ensure_tileset_collision()`: trees and rocks now use a bottom-half polygon (`y: 0→h, x: ±0.7h`) — player can walk near the crown, only blocked at the trunk/base.
**How we could have caught this:**
1. Integration test: place player + tree on ObjectLayer → assert `move_and_slide()` stopped, then assert movement on open ground succeeded.
2. Startup assertion: `assert(player.z_index > object_layer.z_index)`.
3. Health check screenshot analysis: verify player sprite pixel is visible (not occluded by tile color) at player world position.



### ProceduralGenerator: FastNoiseLite TYPE_CELLULAR range is [-0.88, -0.19], not [0, 1]
**Status:** Fixed.
**Symptom:** Zero trees or rocks ever generated in the world. Player could walk everywhere without collision despite collision code being correct.
**Root cause:** `FastNoiseLite.TYPE_CELLULAR` with default settings returns values in approximately `[-0.88, -0.19]`. The original thresholds `o > 0.5` (trees) and `o > 0.6` (rocks) are entirely outside this range — they can never be true. No object tiles were ever placed since the project was created.
**Fix:** Changed thresholds to values within the actual cellular noise range:
```gdscript
# -0.30 ≈ top 16% → ~16% tree density on grass tiles
if atlas_x == 0 and o > -0.30:
# -0.22 ≈ top 5%  → ~5% rock density on stone tiles
elif atlas_x == 2 and o > -0.22:
```
**How we could have caught this:** A unit test for `ProceduralGenerator.generate_chunk()` that asserts the returned entries contain at least one layer-1 tile across a large sample (e.g., 10 chunks). This would have failed immediately on the first run. Test added to catch regressions.
**Note:** `TYPE_SIMPLEX_SMOOTH` returns values in `[-1, 1]` as expected. Only cellular noise has this compressed range.

### CanvasLayer does not support _draw() / draw_rect() / queue_redraw()
**Status:** Pattern established — use Control/ColorRect nodes instead.
**Symptom:** Calling `draw_rect()` or `queue_redraw()` inside a `CanvasLayer` script produces `Function "draw_rect()" not found in base self` errors. `_draw()` is silently never called.
**Root cause:** `_draw()` is a `Node2D` / `Control` virtual method. `CanvasLayer` inherits from neither — it has no drawing API.
**Fix:** For UI elements on a CanvasLayer, use `ColorRect`, `Panel`, `Label`, and other `Control` nodes as children. Store references and update their `.color`, `.size`, `.modulate` properties directly in `_process()`. This is also how the rest of the HUD is built.

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
This also applies to:
- **Type annotations on vars**: `var x: Foo = null` → use `var x = null  # Foo` or the preloaded const type
- **Function parameter types**: `func f(a: Foo)` → use `func f(a: Object)` with a comment
- **`:=` inference from Object**: `var d := obj.some_method()` fails when `obj` is typed `Object`; use explicit type `var d: Dictionary = obj.call("some_method")`

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

### MultiplayerSynchronizer replication fails when authority set in _ready()
**Status:** Fixed.
**Symptom:** `ERROR: Condition "!node || !sync->get_replication_config_ptr()" is true. Returning: ERR_UNCONFIGURED` on client when a RemotePlayer is spawned. The synchronizer has no network ID because `set_multiplayer_authority()` and the replication config setup were called in `_ready()`, which fires after the spawner's `on_replication_start`.
**Fix:** Move both `set_multiplayer_authority()` AND `$MultiplayerSynchronizer.replication_config = config` into `_enter_tree()` instead of `_ready()`. By the time `_enter_tree()` fires, the node is entering the tree but the spawner hasn't processed replication yet.
```gdscript
func _enter_tree() -> void:
    var parts := name.split("_")
    if parts.size() == 2 and parts[1].is_valid_int():
        set_multiplayer_authority(int(parts[1]))
    var config := SceneReplicationConfig.new()
    config.add_property(NodePath(".:position"))
    config.property_set_spawn(NodePath(".:position"), true)
    config.property_set_sync(NodePath(".:position"), true)
    $MultiplayerSynchronizer.replication_config = config
```
**Rule:** Any setup that must be in place before the MultiplayerSpawner processes a newly-spawned node belongs in `_enter_tree()`, not `_ready()`.

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

### ChunkManager.update_player_position skips reload after eviction
**Status:** Fixed.
**Symptom:** When ChunkWeightSystem evicts all chunks under the player, the world goes blank and never regenerates. Player can move but no terrain reappears.
**Root cause:** `update_player_position` short-circuits with `if new_chunk == _player_chunk: return`. After eviction the player's chunk address hasn't changed, so the early return fires and `_load_chunks_in_radius` is never called.
**Fix:** Also check that the current chunk is actually loaded:
```gdscript
if new_chunk == _player_chunk and _loaded_chunks.has(new_chunk):
    return
```
This triggers a full reload on the next `_physics_process` tick after any eviction that removes the player's chunk.

### Godot debug mode treats "redundant assert" as a fatal error
**Status:** Pattern established — use push_error instead.
**Symptom:** An `assert(expr, msg)` where Godot's static analyzer can prove `expr` is always true causes `ERROR: 'Assert statement is redundant because the expression is always true.'` and halts script execution in debug mode. This most commonly hits validation functions that check invariants right after setting them in the same scope (e.g., asserting `source.has_tile(x)` right after calling `source.create_tile(x)`).
**Fix:** Use `push_error` + early return for invariant checks. Reserve `assert()` only for things Godot cannot statically prove — e.g., results from cross-scope method calls or runtime values.
```gdscript
# Bad — Godot can prove this is always true: fatal in debug
assert(source.has_tile(coords), "tile not registered")

# Good — non-fatal, always runs, captures the same mistake
if not source.has_tile(coords):
    push_error("tile %s not registered" % coords)
```

### TileSet tile_size defaults to (0,0) when omitted from .tres — tiles silently invisible
**Status:** Fixed.
**Symptom:** TileMapLayer tiles are set (source_id and atlas_coords readable back via `get_cell_*`) and the TileSetAtlasSource has a valid texture and registered tiles, but the TileMapLayer renders as a solid gray background with no tile art.
**Root cause:** `TileSet.tile_size` defaults to `Vector2i(0, 0)` when the property is absent from the `.tres` file. With zero tile size the renderer cannot calculate tile UV regions and silently produces no output.
**Fix:** Either add `tile_size = Vector2i(16, 16)` to the `[resource]` block in `MainTileSet.tres`, OR (belt-and-suspenders) set it programmatically in `Chunk._ready()`:
```gdscript
ground_layer.tile_set.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
```
Both are now in place. The `.tres` fix covers the editor; the code fix covers any deep-copy of the resource at scene instantiation time.

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

### GDScript type inference fails on method calls through untyped objects
**Status:** Pattern established — use explicit type annotations.
**Symptom:** `var x := obj.some_method()` where `obj` is untyped (created externally, no `class_name` registered) causes `"Cannot infer the type of 'x' variable because the value doesn't have a set type."` parse error. Similarly, declaring `var node: Node = $"../MyNode"` and calling a script-defined method on it gives a runtime `"Invalid call. Nonexistent function ... in base 'Node'"` error because GDScript resolves against the declared type, not the runtime type.
**Fix:**
1. For untyped `obj`: use explicit type annotation instead of `:=`: `var x: String = obj.some_method()`
2. For `@onready` variables pointing at externally-scripted nodes: drop the type annotation entirely: `@onready var shrine_manager = $"../ShrineManager"` (untyped → dynamic dispatch works)
**Rule:** Use `const Script := preload(...)` + `var x: Script` for all externally-created scripts. This gives full type safety without the class registry. Only fall back to untyped vars when the preloaded script itself has circular dependencies.

### UDPPresenceService port conflict on single-machine testing
**Status:** Known limitation, workaround in place.
**Symptom:** When two Godot instances run on the same machine, the second instance logs `UDPPresenceService: could not bind port 7778 (err 2) — running without UDP`. The second instance never receives UDP presence broadcasts from the first, so auto-discovery never triggers.
**Root cause:** Both instances try to bind the same broadcast port (7778). Only the first one succeeds.
**Workaround:** For same-machine testing, use `--host`/`--join` ENet flags to force the direct connection. The `start-host-dev`/`start-client-dev` commands in `scripts/visual_test.sh` include these flags automatically. The CRDT merge lifecycle (hello handshake → snapshot exchange) still runs fully over the ENet connection.
**Note:** Auto-discovery works correctly on a real LAN with two separate machines where both instances can bind their local port.

### GDScript lambda int capture is by value — use Array as reference container
**Status:** Pattern established.
**Symptom:** In a gdUnit4 test (or any GDScript lambda), `var count := 0; signal.connect(func(): count += 1)` — the outer `count` is never incremented. GDScript lambdas copy primitive values (int, float, bool) at capture time.
**Fix:** Wrap in an Array: `var calls := [0]; signal.connect(func(): calls[0] += 1)`. Arrays are reference types and the lambda sees the same object.
**Applies to:** Any signal callback or lambda that needs to mutate an integer counter.

### GDScript type inference fails on Dictionary value arithmetic
**Status:** Pattern established.
**Symptom:** `var x := float_val - (dict["key1"] / dict["key2"])` — "Cannot infer the type of 'x' variable because the value doesn't have a set type." Dictionary values return `Variant`, and arithmetic on `Variant` stays `Variant`.
**Fix:** Cast dictionary lookups explicitly: `var x: float = float_val - (float(dict["key1"]) / float(dict["key2"]))`.
**Applies to:** Any arithmetic on values retrieved from an untyped `Dictionary`.

### GDScript typed Array cannot be assigned from untyped Array literal
**Status:** Pattern established.
**Symptom:** `my_obj.active_buff_ids = ["a", "b"]` where `active_buff_ids: Array[String]` causes runtime error: "Invalid assignment of property ... with value of type 'Array'." The literal `["a", "b"]` is an untyped `Array`, and GDScript cannot implicitly coerce it into a typed `Array[String]` at runtime.
**Fix:** Use `append()` to build typed arrays, or `append_array()` from another typed source:
```gdscript
a.active_buff_ids.clear()
a.active_buff_ids.append("blood_harvest")
a.active_buff_ids.append("undead_resilience")
```
**Applies to:** Any `Array[T]` property on an object accessed through an untyped variable (e.g. from `preload().new()` in tests). Direct `:=` assignment from `[]` literals works only when the variable is declared with a known typed type at parse time.

### GDScript static var not shared across preload() calls in different scripts (GDScript 4.3)
**Status:** Workaround in place.
**Symptom:** Two files each do `const FooScript := preload("res://Foo.gd")`. Assigning to `FooScript._static_var` in one file does NOT affect what `FooScript._static_var` reads in the other file, even though the path is identical. `static var _items = {}` in `EquipmentRegistry.gd` registered from test `before_each()` was invisible inside `EquipmentInventory.gd` when calling `get_slot()`.
**Root cause:** In GDScript 4.3, `preload()` may return different Script resource objects for the same path when scripts are loaded in different compilation units (test runner vs game scripts). The `static var` is stored per-Script-resource-object, so two different objects → two independent static dictionaries.
**Workaround:** Design data classes so they do NOT depend on static var lookups from other scripts at call time. Instead, pass any required data (e.g. slot name) at the time items enter the inventory (`add_to_bag(item_id, slot)`), and store it alongside the item. This way the lookup happens once at the caller's site (where the registry IS visible) rather than deep inside the method.
**Alternative workaround (for tests only):** Use direct property assignment in `before_each()`: `FooScript._items = {}` rather than calling a `reset()` static method — the direct assignment pattern matches what `test_asset_pack.gd` does for `_buff_body_map`.
**Note:** The direct assignment workaround alone does NOT fix the inverse problem (test sets state, method reads different state). The architectural fix (no cross-script static dependency) is the correct solution.

### Godot upstream bug: TileMapLayer collision_enabled toggle breaks physics after set_cell()
**Status:** Unreported upstream (no account yet). Recorded here to file when ready. Workaround found — see "initialize before add_child" fix.
**Godot version:** 4.3
**Reproduction:**
1. Create a TileMapLayer with a TileSet that has a physics layer and tile collision shapes
2. Set `collision_enabled = false`
3. Call `set_cell()` to place several tiles
4. Set `collision_enabled = true`
5. Observe: tiles render correctly but CharacterBody2D passes through them — no physics bodies generated

**Expected:** Re-enabling collision should cause the layer to generate physics bodies for all existing tiles.
**Workaround (implemented):** Call `initialize()` before `add_child()` in ChunkManager. All `set_cell()` calls happen on a detached node. When the node enters the scene tree via `add_child()`, `_enter_tree()` batches all physics body creation at once — no collision toggle needed. `notify_runtime_tile_data_update()` and `update_internals()` were investigated but neither forces a rebuild for this specific bug (they only handle runtime tile data overrides and pending-dirty-quadrant flushes respectively).
**Note for upstream ticket:** `collision_enabled` toggled false→true after `set_cell()` leaves dirty quadrant markers processed-with-no-bodies. The layer doesn't re-mark those quadrants dirty on re-enable, so `update_internals()` finds nothing to do. Expected behavior: re-enabling collision should mark all existing cells dirty.

## MainMenu / Startup

### MainMenu bypass for tests, CI, and dev CLI args
**Status:** Implemented in `ui/MainMenu.gd`.
**Detail:** `MainMenu._ready()` checks for bypass conditions before calling `_build_ui()`:
- `--host` → `GameConfig.mode = "host"`, jump to World
- `--join <ip>` → `GameConfig.mode = "join"`, `GameConfig.host_ip = <ip>`, jump to World
- `--skip-menu` → jump to World as solo (`GameConfig.mode` stays `""`)
- `DisplayServer.get_name() == "headless"` → jump to World immediately (test runner / CI)
- All bypass paths use `change_scene_to_file.call_deferred(...)` and `return` before `_build_ui()`.

**All bypass paths also honour `--port <n>`** via `_parse_port(args)`.

**Invariant to test for:** `_name_edit` is `null` after `_ready()` in headless mode — proof that `_build_ui()` was never called. See `tests/unit/test_main_menu_bypass.gd`.

**CLI invocation pattern** (args must follow `--` separator for `OS.get_cmdline_user_args()`):
```bash
# Host
~/bin/godot4 --path /home/adam/development/freeland -- --host --port 7778
# Join
~/bin/godot4 --path /home/adam/development/freeland -- --join 192.168.1.5 --port 7778
# Skip menu (solo, dev)
~/bin/godot4 --path /home/adam/development/freeland -- --skip-menu
```

## Shifting Lands

### Mechanic implemented — no known issues
**Status:** Implemented in commit "feat: Shifting Lands — alien biome drift on player split".
**What it does:** When two players split (disconnect), unloaded chunks stochastically drift to an
alien biome: water/stone dominant, ether crystals as unique reward (atlas 3,2). Observed chunks
stay stable (quantum observer rule). On merge, CRDT reconciliation restores shared truth.
Visual: pulsing purple border during split state (ShiftingLandsHUD, layer 18).

**Quantum observer rule:** Only chunks NOT currently loaded can drift. `ShiftingLandsSystem.is_chunk_shifted()`
is called from `ChunkManager._load_chunk()` for freshly-generated (not on-disk) chunks only. A loaded
chunk is immune — you can stand in grass and watch the world shift around you.

**How to trigger a split manually for testing:**
```bash
# Run two instances — they will auto-discover via UDP and merge:
~/bin/godot4 --rendering-driver opengl3 --path /home/adam/development/freeland -- --dev-instant-merge
# Second instance in another terminal:
~/bin/godot4 --rendering-driver opengl3 --path /home/adam/development/freeland -- --dev-instant-merge
# Walk them apart to trigger split, then watch unloaded chunks shift.
# --dev-instant-merge collapses merge pressure to 1.0 so discovery is near-instant.
```

**Drift parameters** (in `ShiftingLandsSystem.gd`):
- `DRIFT_START_DELAY = 5.0` — seconds after split before any drift begins (grace period).
- `DRIFT_RATE = 0.12` — probability per second of drifting once delay passes. Caps at 95%.

**Alien biome layout** (inverted from normal):
- Water dominates (t < 0.1), stone common (t < 0.5), dirt sparse (t < 0.7), grass rare (else).
- Ether crystals spawn on stone at object-noise > 0.84 (very rare).
- Rocks spawn on stone at object-noise > 0.4 (more common than normal world).

**Pre-existing test failures (unrelated to Shifting Lands):**
- `test_chunk_manager.gd > test_chunks_loaded_in_radius_after_player_move` — **FIXED**: test only awaited 1 frame; LOAD_RADIUS=4 requires ~27 frames to drain queue at MAX_LOADS_PER_FRAME=3. Fixed by awaiting 30 frames.
- `test_gravestone_scatter.gd > test_scatter_places_at_least_one_gravestone` — density edge case, still open.
