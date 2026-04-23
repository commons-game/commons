# Commons — High-Level Architecture
_April 2026_

The design held together unusually well because the core mechanics (CRDT world state, shrine territory, loneliness pressure, equal P2P) all pull in the same direction. This document describes how those ideas translate into buildable layers, their interfaces, and the order to build them.

---

## System Map

```
┌─────────────────────────────────────────────────────────────────┐
│                        GAMEPLAY LAYER                           │
│  Player controller · Inventory · Talismans · Reputation         │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                         MOD LAYER                               │
│  Primitive vocabulary · Shrine objects · Territory tracker      │
│  Bundle loader · Effect runtime · In-game editor (early)        │
└──────────────┬──────────────────────────────┬───────────────────┘
               │                              │
┌──────────────▼──────────┐   ┌───────────────▼───────────────────┐
│     NETWORKING LAYER    │   │          WORLD LAYER               │
│  Region authority       │   │  Chunk manager · CRDT tile state   │
│  P2P mesh (WebRTC)      │   │  Chunk weight · Neighborhood bonus  │
│  Merge pressure system  │   │  Procedural gen (FastNoiseLite)    │
│  Session management     │   │  Shrine territory                  │
└──────────────┬──────────┘   └───────────────┬────────────────────┘
               │                              │
┌──────────────▼──────────────────────────────▼───────────────────┐
│                     BACKEND ABSTRACTION LAYER                   │
│          IBackend interface (chunk storage, presence,           │
│          P2P signaling)                                         │
├─────────────────────────┬───────────────────────────────────────┤
│   LocalBackend          │   FreenetBackend                      │
│   (LAN / file-based)    │   (long-term target)                  │
│   Used for dev/testing  │   CRDT contracts, presence subs,      │
│                         │   UDP hole-punching                   │
└─────────────────────────┴───────────────────────────────────────┘
```

---

## Layer 1: Backend Abstraction

**Purpose:** Isolate all storage and network discovery behind one interface. Swap LocalBackend for FreenetBackend without touching any other layer.

### IBackend interface

```gdscript
# Store and retrieve CRDT chunk state
func store_chunk(chunk_coords: Vector2i, crdt_data: PackedByteArray) -> void
func retrieve_chunk(chunk_coords: Vector2i) -> PackedByteArray   # empty = not found

# Presence: tell the network you're at a location; receive callbacks when
# others are nearby (triggers bridge formation evaluation)
func publish_presence(player_id: String, chunk_coords: Vector2i) -> void
func subscribe_area(chunk_coords: Vector2i, radius: int, callback: Callable) -> void
func unsubscribe_area(chunk_coords: Vector2i) -> void

# P2P connection coordination
func request_connection(peer_id: String) -> void   # backend exchanges WebRTC offer/answer
signal peer_connection_ready(peer_id: String, connection_info: Dictionary)

# Mod bundles
func store_mod_bundle(bundle_hash: String, data: PackedByteArray) -> void
func retrieve_mod_bundle(bundle_hash: String) -> PackedByteArray

# Reputation
func submit_report(reporter_id: String, target_id: String, reason: String) -> void
func get_reputation_flags(player_id: String) -> Dictionary
```

### LocalBackend (build first)
- Chunk storage: Dictionary in memory + JSON files on disk
- Presence: local broadcast (all "peers" are on the same LAN or same machine)
- Signaling: direct IP entry (no NAT traversal needed on LAN)
- Mod bundles: local file system
- Reputation: local file

### FreenetBackend (build later, same interface)
- Chunk storage: Freenet CRDT contracts (one per chunk, keyed by coordinates)
- Presence: subscribe to geographic area contracts
- Signaling: Freenet's built-in UDP hole-punching
- Mod bundles: content-addressed Freenet contracts
- Reputation: decentralized Freenet contracts

**The only file that changes when switching backends:** a one-line factory call in the game's bootstrap. Everything else calls `Backend.store_chunk(...)` etc.

---

## Layer 2: World Layer

**Purpose:** Manage the tile world — chunks, procedural generation, CRDT state, chunk weight, shrine territory.

### ChunkManager

The central world object. Owns all loaded `TileMapLayer` nodes, tracks chunk state, handles load/unload as the player moves.

```gdscript
# Core operations
func get_or_load_chunk(coords: Vector2i) -> ChunkData
func unload_chunk(coords: Vector2i) -> void
func place_tile(world_coords: Vector2i, layer: int, tile: TileRef) -> void
func remove_tile(world_coords: Vector2i, layer: int) -> void

# Called by networking layer when a remote tile mutation arrives
func apply_remote_mutation(mutation: TileMutation) -> void

# Chunk weight queries
func get_chunk_weight(coords: Vector2i) -> float
func get_neighborhood_weight(coords: Vector2i) -> float  # sum of neighbors
```

### ChunkData

Each chunk holds:
- Two `TileMapLayer` node references (ground + objects)
- A `CRDTTileStore` — the authoritative tile state
- Modification count and last-visited timestamp (for weight calculation)
- Shrine reference (null if wilderness)
- Generation seed (for deterministic procedural regen)

### CRDTTileStore

Last-Write-Wins Map keyed by `(layer, tile_coords)`. Value is `{tile_ref, timestamp, author_id}`. Merge operation: for each key, keep the entry with the higher timestamp.

```gdscript
func set_tile(layer: int, coords: Vector2i, tile: TileRef, author: String) -> void
func remove_tile(layer: int, coords: Vector2i, author: String) -> void
func merge(other: CRDTTileStore) -> void   # in-place merge, keeps higher timestamps
func serialize() -> PackedByteArray
func deserialize(data: PackedByteArray) -> void
func get_tile(layer: int, coords: Vector2i) -> TileRef   # null = empty
```

### ChunkWeightSystem

Runs on a slow timer (every few seconds, not every frame). For each loaded chunk, recalculates weight:

```
weight = base_modification_score
       + recency_bonus(last_visited)
       + neighborhood_bonus(sum of adjacent chunk weights, capped)
       
if weight < FADE_THRESHOLD:
    schedule_chunk_for_fade(chunk)
```

Chunks in shrine territory get a multiplier on the neighborhood bonus. Fading is gradual — the chunk's tiles decay visually before the chunk data is dropped.

### ProceduralGenerator

Stateless. Given a chunk coordinate and a world seed, produces a deterministic tile layout using `FastNoiseLite`. Multiple noise passes: terrain type, elevation, object scatter, biome.

```gdscript
func generate_chunk(coords: Vector2i, world_seed: int) -> CRDTTileStore
```

When a chunk is loaded and `backend.retrieve_chunk()` returns empty, `ProceduralGenerator.generate_chunk()` produces the baseline. Player modifications layer on top via CRDT merges.

### ShrineTerritory

Tracks which chunks belong to which shrine. Evaluated when chunks are loaded or modified.

```gdscript
func get_shrine_for_chunk(coords: Vector2i) -> ShrineData   # null = wilderness
func register_shrine(shrine: ShrineData) -> void
func on_chunk_modified(coords: Vector2i) -> void  # re-evaluates territory adjacency
func get_active_mod_set(coords: Vector2i) -> ModSet  # null = vanilla
```

Territory rule: a chunk joins shrine S's territory if it is modified AND adjacent to at least one chunk already in S's territory (or is the shrine chunk itself). Two shrine territories meeting: boundary chunks go to a `CONTESTED` state — no mod set, vanilla rules.

---

## Layer 3: Networking Layer

**Purpose:** Manage real-time peer synchronization, session lifecycle, and the merge pressure system.

### SessionManager

Tracks the current P2P session. Equal peers — no host. Uses Godot's `WebRTCMultiplayerPeer`.

```gdscript
# Session lifecycle
func start_session() -> void
func add_peer(peer_id: String, connection_info: Dictionary) -> void
func remove_peer(peer_id: String) -> void   # graceful — last peer keeps session alive

# Merge pressure
func get_merge_pressure() -> float  # 0.0–1.0, increases over unmerged time
func reset_merge_pressure() -> void  # called on merge/split
func tick_merge_pressure(delta: float) -> void  # called every frame

# Session merge handshake
func propose_merge(remote_session_id: String) -> void
func accept_merge(proposal: MergeProposal) -> void
signal merge_ready(combined_peers: Array, combined_crdt_data: Dictionary)
```

### RegionAuthority

Wraps Godot's `set_multiplayer_authority()`. Determines which peer holds authority for each loaded region (chunk group). Authority is the peer closest to the region center by world coordinates. Transfers automatically as peers move.

```gdscript
func get_authority_for_chunk(coords: Vector2i) -> int   # peer_id
func on_peer_moved(peer_id: int, new_chunk: Vector2i) -> void  # may trigger transfer
func on_peer_left(peer_id: int) -> void  # redistributes authority
```

### TileMutationBus

The single path for all tile changes. Ensures mutations travel through CRDT and RPC correctly.

```gdscript
# Called by gameplay layer
func request_place_tile(world_coords: Vector2i, layer: int, tile: TileRef) -> void
func request_remove_tile(world_coords: Vector2i, layer: int) -> void

# Internals:
# 1. Applies locally to CRDTTileStore
# 2. Sends RPC to all peers in range (reliable, ordered)
# 3. Peers apply to their CRDTTileStore via ChunkManager.apply_remote_mutation()
```

### MergePressureSystem

Simple accumulator. Linear ramp.

```gdscript
var pressure: float = 0.0        # 0.0–1.0
var ramp_rate: float = 0.001     # per second — tune from data
var reset_value: float = 0.05    # small positive value after split (not zero)

func tick(delta: float) -> void:
    if SessionManager.peer_count == 1:   # solo or effectively alone
        pressure = min(1.0, pressure + ramp_rate * delta)

func apply_talisman_modifier(modifier: float) -> void:
    ramp_rate *= modifier   # talismans adjust rate, not pressure directly

func try_merge_event() -> void:
    # Called on a slow timer by backend presence callbacks
    if randf() < pressure:
        Backend.publish_presence_with_merge_intent(player_chunk)
```

---

## Layer 4: Mod Layer

**Purpose:** Load, interpret, and apply mod bundles. Manage shrine objects and territory.

### ModRuntime

Interprets mod bundle data against the primitive vocabulary. Stateless — evaluates triggers and returns effect lists.

```gdscript
func load_bundle(bundle_hash: String) -> ModBundle
func get_effect_list(trigger: TriggerContext, mod_set: ModSet) -> Array[Effect]
func apply_effects(effects: Array[Effect], context: EffectContext) -> void
```

### ModBundle

Parsed representation of a mod's YAML-compiled binary. Contains:
- Tile definitions: `Dictionary[String, TileDef]`
- Entity definitions: `Dictionary[String, EntityDef]`
- Item definitions: `Dictionary[String, ItemDef]`
- Buff definitions: `Dictionary[String, BuffDef]`
- Biome definitions: `Dictionary[String, BiomeDef]`

### ShrineObject (in-game entity)

A special tile/entity that anchors a mod set to the world. Stored in the chunk's CRDT like any tile, but carries extra metadata:
- `mod_bundle_hash: String` — content-addressed reference to the mod bundle on the backend
- `mod_bundle_version: String` — the pinned version hash
- `owner_id: String` — the player who placed it (for reputation/reporting purposes only — no game-enforced privilege)

When a shrine is loaded, `ShrineTerritory.register_shrine()` is called. When destroyed (tile removed), territory dissolves.

### BoundaryEnforcer

Runs on entity position updates. For each non-player entity, checks if it is within or near a shrine boundary.

```gdscript
func on_entity_moved(entity: Node2D, new_chunk: Vector2i) -> void:
    var shrine = ShrineTerritory.get_shrine_for_chunk(new_chunk)
    if entity.origin_shrine != shrine:
        entity.apply_boundary_damage(delta)   # "vampire in sunlight"
        if entity.health <= 0:
            entity.die_at_boundary()
```

For player items: `ItemInstance.active = ShrineTerritory.get_shrine_for_chunk(player_chunk) == item.origin_shrine`. Dormant items skip all `on_use` and `passive_effects` evaluation.

For buffs: `BuffManager.on_chunk_changed(new_chunk)` removes any buffs whose `origin_shrine` doesn't match the new chunk's shrine.

---

## Layer 5: Gameplay Layer

**Purpose:** Player controller, tile interaction, inventory, talismans, and reputation UI. Calls down into all other layers; nothing calls up into it.

```
PlayerController → TileMutationBus (place/remove)
PlayerController → MergePressureSystem (talisman modifiers)
PlayerController → SessionManager (report, reputation query)
InventorySystem  → ModRuntime (evaluate item on_use effects)
BuffManager      → ModRuntime (evaluate passive_effect ticks)
```

---

## Build Order

Each phase produces something runnable and testable before the next phase begins.

### Phase 0 — Single-player core
_Goal: You can walk around, see procedurally generated tiles, place and remove tiles._

1. Godot project setup, TileMapLayer scene structure (2 layers)
2. `ProceduralGenerator` — `FastNoiseLite` → tiles
3. `ChunkManager` — load/unload chunks around player, 16-bit coordinate budget respected
4. Basic player controller — top-down WASD movement, camera follow
5. Tile placement/removal (mouse click → `set_cell` / `erase_cell`)
6. Basic tile set — ground types, a few object tiles
7. gdUnit4 test suite scaffolding — chunk load/unload, tile set/get, procedural determinism

_Milestone: Solo infinite-world exploration with tile editing._

### Phase 1 — World persistence (local)
_Goal: Tiles you place survive a restart. Chunk weight system works._

1. `CRDTTileStore` — LWW-Map, serialize/deserialize
2. `LocalBackend` — disk-backed chunk storage
3. `IBackend` interface extracted (LocalBackend is first impl)
4. `ChunkWeightSystem` — modification count, recency, fade scheduling
5. Visual fade for decaying chunks (shader or color modulation)
6. Tests: CRDT merge correctness, weight decay curve

_Milestone: Modified chunks persist. Unmodified wilderness fades and regenerates identically from seed._

### Phase 2 — Mod system (pre-multiplayer)
_Goal: You can define a custom tile in YAML, place a shrine, and walk into the mod area._

1. Primitive vocabulary spec — tile, entity, item, buff definitions
2. YAML → binary compiler (`commons-mod-compiler`, standalone tool)
3. `ModBundle` parser
4. `ModRuntime` — trigger evaluation, effect application
5. `ShrineObject` entity — place in world, registers with `ShrineTerritory`
6. `ShrineTerritory` — territory tracking, no-man's land detection
7. `BoundaryEnforcer` — vampire rule for entities, dormant items, buff removal
8. Basic in-game editor — field forms for tile/entity/item defs, "publish to shrine" action
9. Tests: shrine territory expansion, boundary behavior, mod bundle load/unload

_Milestone: Place a shrine, author a custom tile in the editor, walk in and see it work, walk out and see it deactivate._

### Phase 3 — Local multiplayer (LAN)
_Goal: Two players on the same LAN can see each other and build together._

1. WebRTC peer setup — `WebRTCMultiplayerPeer`, direct IP connection
2. `SessionManager` — equal P2P, last-survivor lifecycle
3. `RegionAuthority` — `set_multiplayer_authority()` wiring
4. `TileMutationBus` — RPC tile placement/removal, CRDT merge on receive
5. Player presence sync — positions, animations
6. `MultiplayerSpawner` for chunk nodes
7. Tests: two-simulation in-process harness (drives both peers, verifies CRDT consistency)

_Milestone: Two players on LAN, both see the same world state, tile placements sync correctly._

### Phase 4 — Merge system
_Goal: Two solo sessions can merge when wandering._

1. `MergePressureSystem` — linear ramp, per-session timer
2. `LocalBackend` presence subscription (simulated on LAN — second machine publishes presence)
3. Bridge chunk formation — materialization of connecting chunks
4. Session merge handshake — exchange CRDT stores, form new joint session
5. Talisman items — `merge_pressure_modifier` field wired up
6. Post-merge split — pressure reset, bridge dissolution trigger

_Milestone: Two solo players wandering eventually find each other. Bridge appears. They can walk into each other's space. Bridge dissolves if they wander apart._

### Phase 5 — Reputation system
_Goal: Report mechanism exists; reported players route to chaos pool._

1. `LocalBackend` reputation storage
2. Report UI — accessible from player interaction menu
3. Merge routing — check reputation flags before proposing merge; chaos pool logic
4. "Talisman of Chaos" item — sets player's routing flag to opt into chaos pool

_Milestone: Reported player only merges with other chaos-pool players._

### Phase 6 — Freenet integration
_Goal: World state and mods live on Freenet. Sessions find each other via Freenet presence._

1. `FreenetBackend` — implement `IBackend` against Freenet contracts
2. Chunk contracts — one Freenet CRDT contract per chunk
3. Mod bundle contracts — content-addressed, pinned
4. Presence contracts — geographic area subscription
5. NAT traversal — replace hardcoded STUN with Freenet's hole-punching
6. Reputation contracts — decentralized, tamper-resistant
7. Tests: backend compatibility (run full test suite against FreenetBackend)

_Milestone: Sessions on different machines find each other via Freenet, world state persists on the network._

### Phase 7 — Hardening and scale
_Goal: It actually works under load and adversarial conditions._

1. Multi-witness tile placement (GDScript implementation — quorum confirmation before CRDT commit)
2. Chunk weight formula tuning from real session data
3. Performance profiling — chunk load times, trigger evaluation budget, CRDT merge cost
4. Shrine territory stress testing — many shrines, contested boundaries
5. Player count testing — how far can you push before region authority struggles

---

## Key Invariants (don't break these)

1. **No tile mutation bypasses TileMutationBus.** Everything goes through CRDT → RPC → peers. Never call `set_cell()` directly from gameplay code.
2. **No mod code executes.** Mods are data. `ModRuntime` interprets them. No `load()`, no `call()` on mod-provided scripts.
3. **Backend is always called through IBackend.** Never instantiate `FreenetBackend` or `LocalBackend` directly outside the bootstrap.
4. **Chunk world coordinates always fit in 16-bit signed integers per axis.** The `ChunkManager` is responsible for this contract. Gameplay code uses world coordinates; the chunk manager translates.
5. **CRDT merges are always correct.** A merge must be the same regardless of order. Tests enforce this.
6. **Session peers are always equal.** No peer has elevated privilege in code. Authority is temporary and functional, not ranked.

---

## What Stays Simple (resist overengineering)

- **Chunk weight formula** — linear for now. Shape from data.
- **Merge pressure** — linear ramp, one float. Tune the constant.
- **CRDT conflict resolution** — last-write-wins by timestamp. Don't build a vector clock unless LWW proves insufficient.
- **Region authority election** — nearest peer to region center. Don't build a Raft consensus protocol.
- **Witness quorum** — defer until Phase 7. Optimistic placement is fine to ship.
