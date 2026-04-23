# Commons — Phase 0 & 1 Implementation Plan
_April 2026_

## Coordinate System (Define Once, Use Everywhere)

Three coordinate spaces exist. Never conflate them.

**World tile coordinates** (`world_coords: Vector2i`)
The flat integer grid of all tiles. Valid range per axis: [-32768, 32767] (16-bit TileMapLayer hard limit). This is what all gameplay code sees.

**Chunk coordinates** (`chunk_coords: Vector2i`)
Identifies a chunk. Derived from world tile coords by floor-division:
```
chunk_coords = Vector2i(floor(world.x / CHUNK_SIZE), floor(world.y / CHUNK_SIZE))
```
With `CHUNK_SIZE = 16`, tile `(1040, -500)` → chunk `(65, -32)`.
**Use true floor division** — GDScript `%` returns negative for negative operands. Use `int(floorf(...))` or the helpers below.

**Local tile coordinates** (`local_coords: Vector2i`)
Position within a chunk. Always `[0, CHUNK_SIZE-1]`.
```
local = Vector2i(((world.x % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE,
                 ((world.y % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE)
```

### CoordUtils autoload (build and test this first)

```gdscript
# res://autoloads/CoordUtils.gd
static func world_to_chunk(w: Vector2i) -> Vector2i:
    return Vector2i(int(floorf(float(w.x) / Constants.CHUNK_SIZE)),
                    int(floorf(float(w.y) / Constants.CHUNK_SIZE)))

static func world_to_local(w: Vector2i) -> Vector2i:
    return Vector2i(((w.x % Constants.CHUNK_SIZE) + Constants.CHUNK_SIZE) % Constants.CHUNK_SIZE,
                    ((w.y % Constants.CHUNK_SIZE) + Constants.CHUNK_SIZE) % Constants.CHUNK_SIZE)

static func chunk_local_to_world(chunk: Vector2i, local: Vector2i) -> Vector2i:
    return Vector2i(chunk.x * Constants.CHUNK_SIZE + local.x,
                    chunk.y * Constants.CHUNK_SIZE + local.y)

static func make_crdt_key(layer: int, lx: int, ly: int) -> int:
    return (layer << 16) | (lx << 8) | ly
```

**Round-trip test:** `chunk_local_to_world(world_to_chunk(p), world_to_local(p)) == p` for all tested points including negative coordinates.

---

## Constants

```gdscript
# res://autoloads/Constants.gd
const CHUNK_SIZE: int = 16       # tiles per chunk side (16×16 = 256 tiles)
const TILE_SIZE: int = 16        # pixels per tile
const LOAD_RADIUS: int = 4       # chunks to keep loaded around player
const UNLOAD_RADIUS: int = 6     # chunks beyond this get unloaded (hysteresis gap prevents thrashing)
const FADE_THRESHOLD: float = 5.0
const WORLD_SEED: int = 12345    # replace with per-world random seed later
```

**Why CHUNK_SIZE=16:** 9×9 load grid = 81 active chunks = 20,736 tiles in memory. Comfortable. With the ±32768 tile limit, you get ±2047 chunks per axis — plenty.

---

## Project Folder Structure

```
res://
├── autoloads/
│   ├── Constants.gd          # All global constants
│   ├── CoordUtils.gd         # Static coordinate conversion helpers
│   └── Backend.gd            # Holds active IBackend instance — the one-line swap point
├── world/
│   ├── chunk/
│   │   ├── Chunk.gd           # ChunkData class (extends Node2D)
│   │   ├── Chunk.tscn         # Node2D + 2 TileMapLayer children
│   │   ├── CRDTTileStore.gd
│   │   └── ChunkManager.gd
│   ├── generation/
│   │   └── ProceduralGenerator.gd
│   └── weight/
│       └── ChunkWeightSystem.gd
├── player/
│   ├── Player.gd
│   ├── Player.tscn
│   └── TileInteraction.gd
├── backend/
│   ├── IBackend.gd
│   └── local/
│       └── LocalBackend.gd
├── tilesets/
│   └── MainTileSet.tres
├── shaders/
│   └── chunk_fade.gdshader    # Phase 1 — optional, modulate.a tween is fine to start
├── tests/
│   ├── unit/
│   │   ├── test_coord_utils.gd
│   │   ├── test_crdt_tile_store.gd
│   │   ├── test_procedural_generator.gd
│   │   └── test_chunk_weight.gd
│   └── integration/
│       ├── test_chunk_manager.gd
│       └── test_persistence.gd
└── project.godot
```

---

## Chunk Scene Tree

```
Node2D  [Chunk.tscn root, Chunk.gd attached]
  ├── TileMapLayer  "GroundLayer"
  │     y_sort_enabled: false
  │     collision_enabled: true (disabled during bulk generation)
  └── TileMapLayer  "ObjectLayer"
        y_sort_enabled: true
        collision_enabled: true
```

Both layers share `MainTileSet.tres`. The root `Node2D` is positioned at pixel offset `chunk_coords * CHUNK_SIZE * TILE_SIZE`. Layer nodes are at local `(0,0)` relative to the root — never offset them.

All chunk instances are children of `ChunkManager` in `World.tscn`:
```
World.tscn
  ├── ChunkManager
  │     ├── Chunk_0_0
  │     ├── Chunk_1_0  ...
  └── Player
```

---

## CRDT Data Format

### In-memory key
```gdscript
key = (layer << 16) | (local_x << 8) | local_y
```
With CHUNK_SIZE=16, local coords fit in 8 bits. Layer 0 = ground, 1 = objects.

### Entry dict
```gdscript
{
    "tile_id": int,        # TileSet source_id; -1 = tombstone
    "atlas_x": int,
    "atlas_y": int,
    "alt_tile": int,       # rotation/mirror alternative
    "timestamp": float,    # Time.get_unix_time_from_system()
    "author_id": String    # player UUID; "" = procedural baseline
}
```

### Tombstone
`tile_id == -1`. Has valid `timestamp` and `author_id`. During merge, higher timestamp wins. During rendering, tombstone → `erase_cell()`.

### On-disk format (LocalBackend)
Path: `user://chunks/<x>_<y>.json` (x/y are signed integers, e.g. `-3_12.json`)

```json
{
    "chunk_x": 5, "chunk_y": -2,
    "world_seed": 12345, "version": 1,
    "entries": [
        {"layer": 0, "lx": 3, "ly": 7,
         "tile_id": 2, "atlas_x": 1, "atlas_y": 0, "alt_tile": 0,
         "timestamp": 1744567890.123, "author_id": "player-uuid"},
        {"layer": 1, "lx": 8, "ly": 2,
         "tile_id": -1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
         "timestamp": 1744567891.0, "author_id": "player-uuid"}
    ]
}
```

Serialized as `JSON.stringify(...).to_utf8_buffer()` for `PackedByteArray` compatibility with `IBackend` interface. Deserialize with `.get_string_from_utf8()` + `JSON.parse_string()`.

Phase 1 stores the full CRDT including procedural tiles. Future optimization: store only player-authored deltas (`author_id != ""`).

---

# Phase 0 — Single-Player Core

**Goal: Walk around a procedurally generated world. Place and remove tiles.**

---

### Task 0.1 — Project Bootstrap

**Create:** `project.godot`, `Constants.gd`, `CoordUtils.gd`, `Backend.gd` (stub), `MainTileSet.tres`

- Godot 4.3+
- Register autoloads in order: Constants → CoordUtils → Backend
- Viewport: 1280×720
- `get_tree().auto_accept_quit = false` in World scene (needed for quit persistence in Phase 1)
- `MainTileSet.tres`: single atlas source with ground tiles (grass, dirt, stone, water) and object tiles (tree, rock). Add collision shapes to solid tiles in the TileSet editor.
- `Backend.gd` stub: all methods no-op, returns empty `PackedByteArray`.

---

### Task 0.2 — ProceduralGenerator

**Create:** `res://world/generation/ProceduralGenerator.gd`

`class_name ProceduralGenerator` — no `extends Node`. Stateless.

```gdscript
static func generate_chunk(coords: Vector2i, world_seed: int) -> Dictionary:
    var noise_terrain := FastNoiseLite.new()
    # XOR with large primes per-chunk to avoid tiling artifacts
    noise_terrain.seed = world_seed ^ (coords.x * 73856093) ^ (coords.y * 19349663)
    noise_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise_terrain.frequency = 0.08

    var noise_objects := FastNoiseLite.new()
    noise_objects.seed = world_seed ^ (coords.x * 83492791) ^ (coords.y * 17026789)
    noise_objects.noise_type = FastNoiseLite.TYPE_CELLULAR
    noise_objects.frequency = 0.15

    var entries := {}
    for ly in range(Constants.CHUNK_SIZE):
        for lx in range(Constants.CHUNK_SIZE):
            var wx := coords.x * Constants.CHUNK_SIZE + lx
            var wy := coords.y * Constants.CHUNK_SIZE + ly
            var t := noise_terrain.get_noise_2d(wx, wy)
            var atlas_x := 3 if t < -0.2 else (0 if t < 0.2 else (1 if t < 0.5 else 2))
            var key := CoordUtils.make_crdt_key(0, lx, ly)
            entries[key] = {"tile_id": 0, "atlas_x": atlas_x, "atlas_y": 0,
                            "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
            var o := noise_objects.get_noise_2d(wx, wy)
            if atlas_x == 0 and o > 0.5:
                entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
                    "tile_id": 0, "atlas_x": 0, "atlas_y": 1, "alt_tile": 0,
                    "timestamp": 0.0, "author_id": ""}
            elif atlas_x == 2 and o > 0.6:
                entries[CoordUtils.make_crdt_key(1, lx, ly)] = {
                    "tile_id": 0, "atlas_x": 1, "atlas_y": 1, "alt_tile": 0,
                    "timestamp": 0.0, "author_id": ""}
    return entries
```

**Gotcha — noise seed XOR:** Never pass `world_seed` directly to `FastNoiseLite.seed` for all chunks. Chunks sharing a seed produce identical terrain — use the XOR-with-primes pattern above.

**Gotcha — GDScript speed:** 256 tiles per chunk is fast enough (~1–2ms). Don't optimize prematurely. If chunk generation ever shows up in profiling, move to a Thread.

**Tests:**
- Same coords + same seed → identical output (determinism)
- Different chunk coords → different output (no tiling)
- Ground tiles present for all 256 local positions (layer 0 entries == 256)
- Adjacent chunks share no identical row patterns

---

### Task 0.3 — CRDTTileStore

**Create:** `res://world/chunk/CRDTTileStore.gd`

`class_name CRDTTileStore` — plain GDScript, no Node.

```gdscript
var _data: Dictionary = {}

func set_tile(layer: int, local: Vector2i, tile_id: int,
              atlas: Vector2i, alt: int, author: String) -> void:
    var key := CoordUtils.make_crdt_key(layer, local.x, local.y)
    var ts := Time.get_unix_time_from_system()
    var existing = _data.get(key, null)
    if existing == null or ts > existing["timestamp"]:
        _data[key] = {"tile_id": tile_id, "atlas_x": atlas.x, "atlas_y": atlas.y,
                      "alt_tile": alt, "timestamp": ts, "author_id": author}

func remove_tile(layer: int, local: Vector2i, author: String) -> void:
    var key := CoordUtils.make_crdt_key(layer, local.x, local.y)
    var ts := Time.get_unix_time_from_system()
    var existing = _data.get(key, null)
    if existing == null or ts > existing["timestamp"]:
        _data[key] = {"tile_id": -1, "atlas_x": 0, "atlas_y": 0,
                      "alt_tile": 0, "timestamp": ts, "author_id": author}

func get_tile(layer: int, local: Vector2i) -> Dictionary:
    return _data.get(CoordUtils.make_crdt_key(layer, local.x, local.y), {})

func merge(other: CRDTTileStore) -> void:
    for key in other._data:
        var other_entry: Dictionary = other._data[key]
        var self_entry = _data.get(key, null)
        if self_entry == null or other_entry["timestamp"] > self_entry["timestamp"]:
            _data[key] = other_entry.duplicate()

func load_from_entries(entries: Dictionary) -> void:
    _data = entries.duplicate(true)

func get_all_entries() -> Dictionary:
    return _data
```

**Clock precision note:** `Time.get_unix_time_from_system()` gives millisecond precision. Two writes in the same millisecond will tie. Add a monotonic counter tiebreaker in Phase 3 when multiple peers write simultaneously. Not needed for Phase 0.

**Tests (must all pass before Phase 3):**
- `set_tile` then `get_tile` returns the entry
- `remove_tile` writes a tombstone (`tile_id == -1`)
- Older placement does not overwrite newer tombstone
- Merge commutativity: `A.merge(B)` ≡ `B.merge(A)` (compare resulting `_data`)
- Merge idempotency: `A.merge(A)` leaves A unchanged
- Merge associativity: `(A.merge(B)).merge(C)` ≡ `A.merge(B.merge(C))`

---

### Task 0.4 — Chunk Scene and ChunkData

**Create:** `Chunk.tscn`, `Chunk.gd`

```gdscript
class_name ChunkData
extends Node2D

var chunk_coords: Vector2i
var crdt: CRDTTileStore
var ground_layer: TileMapLayer
var object_layer: TileMapLayer

# Phase 1 fields — declare now, use in Phase 1
var modification_count: int = 0
var last_visited: float = 0.0
var weight: float = 0.0
var is_fading: bool = false

func _ready() -> void:
    ground_layer = $GroundLayer
    object_layer = $ObjectLayer
    crdt = CRDTTileStore.new()

func initialize(coords: Vector2i, entries: Dictionary) -> void:
    chunk_coords = coords
    position = Vector2(coords.x * Constants.CHUNK_SIZE * Constants.TILE_SIZE,
                       coords.y * Constants.CHUNK_SIZE * Constants.TILE_SIZE)
    crdt.load_from_entries(entries)
    _render_all()

func _render_all() -> void:
    # Disable collision during bulk set to avoid per-cell physics rebuild
    ground_layer.collision_enabled = false
    object_layer.collision_enabled = false
    ground_layer.clear()
    object_layer.clear()
    for key in crdt.get_all_entries():
        var entry: Dictionary = crdt.get_all_entries()[key]
        if entry["tile_id"] == -1:
            continue  # tombstone
        var layer_idx: int = (key >> 16) & 0xFF
        var lx: int = (key >> 8) & 0xFF
        var ly: int = key & 0xFF
        var tl := ground_layer if layer_idx == 0 else object_layer
        tl.set_cell(Vector2i(lx, ly), entry["tile_id"],
                    Vector2i(entry["atlas_x"], entry["atlas_y"]), entry["alt_tile"])
    ground_layer.collision_enabled = true
    object_layer.collision_enabled = true

func apply_mutation(layer: int, local: Vector2i, entry: Dictionary) -> void:
    var tl := ground_layer if layer == 0 else object_layer
    if entry.get("tile_id", -1) == -1:
        tl.erase_cell(local)
    else:
        tl.set_cell(local, entry["tile_id"],
                    Vector2i(entry["atlas_x"], entry["atlas_y"]), entry["alt_tile"])
```

---

### Task 0.5 — ChunkManager

**Create:** `res://world/chunk/ChunkManager.gd`

```gdscript
class_name ChunkManager
extends Node

const CHUNK_SCENE := preload("res://world/chunk/Chunk.tscn")

var _loaded_chunks: Dictionary = {}  # Vector2i → ChunkData
var _player_chunk: Vector2i = Vector2i.ZERO

func update_player_position(world_tile_pos: Vector2i) -> void:
    var new_chunk := CoordUtils.world_to_chunk(world_tile_pos)
    if new_chunk == _player_chunk:
        return
    _player_chunk = new_chunk
    _load_chunks_in_radius(new_chunk, Constants.LOAD_RADIUS)
    _unload_chunks_outside_radius(new_chunk, Constants.UNLOAD_RADIUS)

func update_player_last_visited(world_tile_pos: Vector2i) -> void:
    # Phase 1: update last_visited on player-adjacent chunks
    var now := Time.get_unix_time_from_system()
    var pc := CoordUtils.world_to_chunk(world_tile_pos)
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            var chunk := get_chunk(pc + Vector2i(dx, dy))
            if chunk:
                chunk.last_visited = now

func place_tile(world_coords: Vector2i, layer: int, tile_id: int,
                atlas: Vector2i, alt: int, author: String) -> void:
    var cc := CoordUtils.world_to_chunk(world_coords)
    var local := CoordUtils.world_to_local(world_coords)
    var chunk := get_chunk(cc)
    if chunk == null:
        push_warning("place_tile on unloaded chunk %s" % cc)
        return
    chunk.crdt.set_tile(layer, local, tile_id, atlas, alt, author)
    chunk.apply_mutation(layer, local, chunk.crdt.get_tile(layer, local))
    chunk.modification_count += 1

func remove_tile(world_coords: Vector2i, layer: int, author: String) -> void:
    var cc := CoordUtils.world_to_chunk(world_coords)
    var local := CoordUtils.world_to_local(world_coords)
    var chunk := get_chunk(cc)
    if chunk == null:
        return
    chunk.crdt.remove_tile(layer, local, author)
    chunk.apply_mutation(layer, local, {"tile_id": -1})
    chunk.modification_count += 1

func get_chunk(coords: Vector2i) -> ChunkData:
    return _loaded_chunks.get(coords, null)

func get_loaded_chunk_coords() -> Array:
    return _loaded_chunks.keys()

func force_unload_chunk_no_persist(coords: Vector2i) -> void:
    var chunk := _loaded_chunks.get(coords) as ChunkData
    if chunk:
        chunk.queue_free()
    _loaded_chunks.erase(coords)

func _load_chunks_in_radius(center: Vector2i, radius: int) -> void:
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            var coords := center + Vector2i(dx, dy)
            if not _loaded_chunks.has(coords):
                _load_chunk(coords)

func _load_chunk(coords: Vector2i) -> void:
    assert(abs(coords.x) <= 2047 and abs(coords.y) <= 2047,
           "Chunk coords %s would exceed 16-bit TileMapLayer limit" % coords)
    var raw := Backend.retrieve_chunk(coords)
    var entries := _deserialize_entries(raw) if not raw.is_empty() \
                   else ProceduralGenerator.generate_chunk(coords, Constants.WORLD_SEED)
    var chunk := CHUNK_SCENE.instantiate() as ChunkData
    add_child(chunk)
    chunk.initialize(coords, entries)
    chunk.last_visited = Time.get_unix_time_from_system()
    _loaded_chunks[coords] = chunk

func _unload_chunks_outside_radius(center: Vector2i, radius: int) -> void:
    var to_unload: Array[Vector2i] = []
    for coords in _loaded_chunks:
        if abs(coords.x - center.x) > radius or abs(coords.y - center.y) > radius:
            to_unload.append(coords)
    for coords in to_unload:
        _unload_chunk(coords)

func _unload_chunk(coords: Vector2i) -> void:
    var chunk := get_chunk(coords)
    if chunk:
        Backend.store_chunk(coords, _serialize_chunk(chunk))
        chunk.queue_free()
    _loaded_chunks.erase(coords)

func _serialize_chunk(chunk: ChunkData) -> PackedByteArray:
    var list := []
    for key in chunk.crdt.get_all_entries():
        var e: Dictionary = chunk.crdt.get_all_entries()[key]
        list.append({"layer": (key >> 16) & 0xFF, "lx": (key >> 8) & 0xFF, "ly": key & 0xFF,
                     "tile_id": e["tile_id"], "atlas_x": e["atlas_x"], "atlas_y": e["atlas_y"],
                     "alt_tile": e["alt_tile"], "timestamp": e["timestamp"],
                     "author_id": e["author_id"]})
    return JSON.stringify({"chunk_x": chunk.chunk_coords.x, "chunk_y": chunk.chunk_coords.y,
                           "world_seed": Constants.WORLD_SEED, "version": 1,
                           "entries": list}).to_utf8_buffer()

func _deserialize_entries(data: PackedByteArray) -> Dictionary:
    var payload: Dictionary = JSON.parse_string(data.get_string_from_utf8())
    if payload == null:
        return {}
    var entries := {}
    for item in payload.get("entries", []):
        entries[CoordUtils.make_crdt_key(item["layer"], item["lx"], item["ly"])] = {
            "tile_id": item["tile_id"], "atlas_x": item["atlas_x"], "atlas_y": item["atlas_y"],
            "alt_tile": item["alt_tile"], "timestamp": item["timestamp"],
            "author_id": item["author_id"]}
    return entries
```

**Tests:**
- After `update_player_position`, chunks within `LOAD_RADIUS` are in `_loaded_chunks`
- Moving player far causes original chunks to unload
- `place_tile` at a negative world coordinate resolves correctly (test `(-1,-1)`, `(-16,-16)`)
- `place_tile` at a chunk boundary world coordinate hits the correct chunk

---

### Task 0.6 — Player Controller

**Create:** `Player.tscn`, `Player.gd`, `TileInteraction.gd`

`Player.tscn` structure:
```
CharacterBody2D  (Player.gd)
  ├── CollisionShape2D  (RectangleShape2D, 12×12px)
  ├── Sprite2D          (placeholder)
  └── Camera2D          (zoom: Vector2(2,2), position_smoothing_enabled: true)
```

```gdscript
# Player.gd
extends CharacterBody2D
const SPEED := 80.0
@onready var chunk_manager: ChunkManager = $"../ChunkManager"

func _physics_process(_delta: float) -> void:
    velocity = Vector2(Input.get_axis("ui_left", "ui_right"),
                       Input.get_axis("ui_up", "ui_down")).normalized() * SPEED
    move_and_slide()
    var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
                             int(floorf(position.y / Constants.TILE_SIZE)))
    chunk_manager.update_player_position(tile_pos)
    chunk_manager.update_player_last_visited(tile_pos)
```

```gdscript
# TileInteraction.gd — attach to Player or World
extends Node
@onready var chunk_manager: ChunkManager = $"../ChunkManager"

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.pressed):
        return
    var world_px := get_viewport().get_canvas_transform().affine_inverse() \
                    * get_viewport().get_mouse_position()
    var tile_pos := Vector2i(int(floorf(world_px.x / Constants.TILE_SIZE)),
                             int(floorf(world_px.y / Constants.TILE_SIZE)))
    if event.button_index == MOUSE_BUTTON_LEFT:
        chunk_manager.place_tile(tile_pos, 1, 0, Vector2i(0, 0), 0, "local-player")
    elif event.button_index == MOUSE_BUTTON_RIGHT:
        chunk_manager.remove_tile(tile_pos, 1, "local-player")
```

**Y-sort note:** Defer y-sort setup to Phase 2. For now the player draws on top of everything.

---

### Task 0.7 — Test Suite and CI

gdUnit4 as the test framework. Install via Godot Asset Library (Asset #4390).

**CI (`.github/workflows/test.yml`):**
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: godot-gdunit-labs/gdUnit4-action@v1
        with:
          godot-version: '4.3'
          paths: 'res://tests'
          timeout: 300
```

**Phase 0 milestone:** Player spawns, WASD moves, chunks load around movement, left-click places a tile, right-click removes it, no crashes at negative coordinates or chunk boundaries.

---

# Phase 1 — World Persistence

**Goal: Placed tiles survive restart. Abandoned chunks fade and regenerate.**

---

### Task 1.1 — IBackend Interface

**Create:** `res://backend/IBackend.gd`

```gdscript
class_name IBackend
extends RefCounted

func store_chunk(chunk_coords: Vector2i, crdt_data: PackedByteArray) -> void:
    push_error("IBackend.store_chunk not implemented")

func retrieve_chunk(chunk_coords: Vector2i) -> PackedByteArray:
    push_error("IBackend.retrieve_chunk not implemented")
    return PackedByteArray()

func delete_chunk(chunk_coords: Vector2i) -> void:
    pass  # optional — not all backends need explicit delete

# Presence and signaling — stubs for now, implemented in Phase 4+
func publish_presence(player_id: String, chunk_coords: Vector2i) -> void: pass
func subscribe_area(chunk_coords: Vector2i, radius: int, callback: Callable) -> void: pass
func unsubscribe_area(chunk_coords: Vector2i) -> void: pass
```

Update `Backend.gd` autoload:
```gdscript
extends Node
var _backend: IBackend

func _ready() -> void:
    _backend = LocalBackend.new()
    _backend.initialize()

func store_chunk(coords: Vector2i, data: PackedByteArray) -> void:
    _backend.store_chunk(coords, data)

func retrieve_chunk(coords: Vector2i) -> PackedByteArray:
    return _backend.retrieve_chunk(coords)

func delete_chunk(coords: Vector2i) -> void:
    _backend.delete_chunk(coords)
```

**The swap point:** Change `LocalBackend.new()` to `FreenetBackend.new()` in Phase 6. Nothing else changes.

---

### Task 1.2 — LocalBackend

**Create:** `res://backend/local/LocalBackend.gd`

```gdscript
class_name LocalBackend
extends IBackend

const CHUNK_DIR := "user://chunks/"

func initialize() -> void:
    DirAccess.make_dir_recursive_absolute(CHUNK_DIR)

func store_chunk(chunk_coords: Vector2i, crdt_data: PackedByteArray) -> void:
    var file := FileAccess.open(_path(chunk_coords), FileAccess.WRITE)
    if file:
        file.store_buffer(crdt_data)
        file.close()
    else:
        push_error("LocalBackend: write failed for %s: %d" % [_path(chunk_coords), FileAccess.get_open_error()])

func retrieve_chunk(chunk_coords: Vector2i) -> PackedByteArray:
    if not FileAccess.file_exists(_path(chunk_coords)):
        return PackedByteArray()
    var file := FileAccess.open(_path(chunk_coords), FileAccess.READ)
    if file == null:
        return PackedByteArray()
    var data := file.get_buffer(file.get_length())
    file.close()
    return data

func delete_chunk(chunk_coords: Vector2i) -> void:
    if FileAccess.file_exists(_path(chunk_coords)):
        DirAccess.remove_absolute(_path(chunk_coords))

func _path(coords: Vector2i) -> String:
    return CHUNK_DIR + "%d_%d.json" % [coords.x, coords.y]
```

**Wire quit-persistence in World.gd:**
```gdscript
func _ready() -> void:
    get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        $ChunkManager._persist_all_loaded_chunks()
        get_tree().quit()
```

Add to ChunkManager:
```gdscript
func _persist_all_loaded_chunks() -> void:
    for coords in _loaded_chunks:
        var chunk := _loaded_chunks[coords] as ChunkData
        Backend.store_chunk(coords, _serialize_chunk(chunk))
```

---

### Task 1.3 — ChunkWeightSystem

**Create:** `res://world/weight/ChunkWeightSystem.gd`

```gdscript
class_name ChunkWeightSystem
extends Node

const TICK_INTERVAL := 5.0
const MODIFICATION_WEIGHT := 2.0
const RECENCY_HALF_LIFE := 3600.0    # seconds (tune from data)
const NEIGHBORHOOD_BONUS_CAP := 50.0
const FADE_DURATION := 10.0          # seconds for visual fade

var _timer: float = 0.0
@onready var chunk_manager: ChunkManager = $"../ChunkManager"

func _process(delta: float) -> void:
    _timer += delta
    if _timer >= TICK_INTERVAL:
        _timer = 0.0
        _recalculate_all()

func _recalculate_all() -> void:
    var now := Time.get_unix_time_from_system()
    for coords in chunk_manager.get_loaded_chunk_coords():
        var chunk := chunk_manager.get_chunk(coords)
        if chunk == null or chunk.is_fading:
            continue
        var mod_score := float(chunk.modification_count) * MODIFICATION_WEIGHT
        var age := now - chunk.last_visited
        var recency := mod_score * pow(0.5, age / RECENCY_HALF_LIFE)
        var neighbor_sum := 0.0
        for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
            var n := chunk_manager.get_chunk(coords + offset)
            if n:
                neighbor_sum += n.weight
        chunk.weight = recency + minf(neighbor_sum * 0.1, NEIGHBORHOOD_BONUS_CAP)
        if chunk.weight < Constants.FADE_THRESHOLD:
            chunk.is_fading = true
            _start_fade(chunk)

func _start_fade(chunk: ChunkData) -> void:
    var tween := get_tree().create_tween()
    tween.tween_property(chunk, "modulate:a", 0.0, FADE_DURATION)
    tween.tween_callback(_evict.bind(chunk.chunk_coords))

func _evict(coords: Vector2i) -> void:
    Backend.delete_chunk(coords)
    chunk_manager.force_unload_chunk_no_persist(coords)
```

**Weight formula notes:**
- `mod_score` is linear in modification count (as decided — shape from data later)
- Exponential recency decay: a chunk with 50 modifications hits FADE_THRESHOLD after ~1hr unvisited
- Set `RECENCY_HALF_LIFE = 30.0` in tests to verify fade behavior quickly
- Neighborhood bonus: surrounded chunks are more durable; isolated edge chunks fade first

**Tests (`test_chunk_weight.gd`):**
- 0 modifications, last_visited = 1hr ago → weight below FADE_THRESHOLD
- 50 modifications, last_visited = now → weight well above threshold
- Neighbor bonus capped at NEIGHBORHOOD_BONUS_CAP
- `is_fading = true` chunk is not re-scheduled on subsequent ticks

---

### Phase 1 Milestone Verification

1. Play and place several tiles in multiple chunks.
2. Close the game window (triggers persist-on-quit).
3. Confirm `user://chunks/` has `.json` files.
4. Relaunch. Walk to placed tiles — they're present.
5. For testing: set `RECENCY_HALF_LIFE = 30.0`. Place no tiles. Wait. Observe chunks fade visually then regenerate procedurally on re-approach.

---

## Key Invariants — Never Break These

1. **All tile mutations go through `ChunkManager.place_tile()` / `remove_tile()`.** Never call `set_cell()` directly from gameplay code.
2. **`CoordUtils` is the sole coordinate conversion authority.** No inline arithmetic elsewhere.
3. **`IBackend` is only instantiated in `Backend.gd`.** Everything else calls `Backend.*`.
4. **The 16-bit chunk coordinate guard assertion stays in `_load_chunk` forever.**
5. **CRDT merge tests must stay green** — Phase 3 multiplayer depends entirely on correctness here.
6. **Session peers are always equal** — no peer has elevated code privilege.

## What Is Not In Phases 0–1

Shrine/mod system, WebRTC, SessionManager, TileMutationBus RPC, MergePressureSystem, reputation, FreenetBackend, witness quorum, delta-only CRDT persistence, y-sort tuning. All deferred to their respective phases.
