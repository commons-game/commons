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

**Start xpra session:**
```bash
xpra start :100 --daemon=yes --exit-with-children=no --html=on --bind-tcp=0.0.0.0:14600 --dpi=96 --xvfb="Xvfb +extension Composite -screen 0 1920x1080x24+32 -nolisten tcp -noreset -dpi 96"
```

**Launch editor:**
```bash
DISPLAY=:100 ~/bin/godot4 --editor --rendering-driver opengl3 --path /home/adam/development/freeland/ &
```

**Aliases** (in `~/.bashrc`): `freeland-xpra` and `freeland-editor`

**Connect from laptop:** `http://server:14600`

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

### Array element type inference in GDScript
**Status:** Known GDScript limitation, handled with explicit casts.
**Symptom:** Iterating over `Array` of `Vector2i` values and using `:=` on the result fails type inference: "Cannot infer the type of 'x' variable."
**Workaround:** Explicit cast: `var v: Vector2i = item as Vector2i` or `(item as Vector2i)`.
