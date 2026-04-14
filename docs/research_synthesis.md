# Freeland — Research Synthesis
_April 2026_

## Stack Under Evaluation

| Component | Tool | Status |
|---|---|---|
| Game engine | Godot 4 | Mature, stable |
| Tilemap / world | TileMapLayer (Godot 4.3+) | First-class, some limits |
| Real-time multiplayer | Region authority + CRDT + witness layer (see §5) | To be built |
| Testing harness | gdUnit4 or GUT | Both mature |
| Decentralized backend | Freenet | Public alpha (March 2026) |

---

## 1. Godot 4 — Capabilities Assessment

### Verdict: Solid foundation, known custom work items

**TileMapLayer (2-layer setup):**
- `TileMap` is deprecated. Use two `TileMapLayer` nodes (ground + objects), sharing one `TileSet`. Clean for this use case.
- `set_cell()` / `erase_cell()` are first-class runtime tile modification APIs. No cost beyond quadrant collision rebuild.
- **Hard limit: coordinates are 16-bit signed (-32768 to 32767).** Infinite worlds require chunking from day one. There is no escape hatch.
- Disable `collision_enabled` during bulk chunk generation, then re-enable — avoids per-cell physics rebuild.

**Procedural generation:**
- `FastNoiseLite` is built in (SimplexSmooth, Perlin, Cellular, etc.). Sample `get_noise_2d(x, y)` → tile type. No plugins needed.

**Chunk system (infinite/large worlds):**
- **Not provided.** Must build: chunk Dictionary keyed by coords, load/unload `TileMapLayer` nodes as player moves, serialize modified tiles as deltas from procedural baseline.
- Estimated: 300–500 lines GDScript for a solid chunk manager.
- Consider C# or GDExtension for noise sampling over large areas — GDScript is slow for bulk operations.

**Multiplayer world sync:**
- `MultiplayerSynchronizer` on tile data is impractical at world scale.
- Correct pattern: RPC-based tile mutations. Server is authority. Client sends `tile_placed(layer, coords, ...)` RPC → server validates and applies → broadcasts to all relevant clients. `reliable` transfer mode required.
- `MultiplayerSpawner` handles chunk node replication (spawns chunk scene on all peers). Tile data still needs separate RPC.
- `set_visibility_for(peer_id)` limits which peers get which updates — important at scale.

**Known gotchas:**
- Y-sort needs deliberate scene structure when mixing dynamically spawned chunk nodes with player sprites.
- Navigation mesh rebuilds on tile change — manageable for sparse edits, potential CPU concern near busy areas.

---

## 2. Testing Harness

### Verdict: Mature frameworks exist; multiplayer simulation testing requires custom build

**Framework recommendation:**
- **gdUnit4** — best CI story (official `gdUnit4-action`, JUnit XML output, embedded editor inspector). Supports GDScript + C# (via `gdUnit4Net`).
- **GUT** — simpler, most docs/tutorials, large community. GDScript only.
- Either works. gdUnit4 has the edge for CI automation.

**Deterministic physics — critical:**
- Godot's built-in `PhysicsServer2D` is **NOT deterministic** across machines. This breaks rollback netcode.
- Solution: **SG Physics 2D** (by Snopek Games) — fixed-point 2D physics designed for rollback. Required for any deterministic simulation.

**What exists out of the box:**
- `simulate(obj, ticks, delta)` (GUT) / `SceneRunner.simulate_frames()` (gdUnit4) — tick-level simulation in tests.
- `OfflineMultiplayerPeer` — fake peer for testing RPC dispatch in a single process.
- `TileMapLayer` is a plain Node — fully testable. `get_cell_tile_data(pos)` for assertions.

**What must be built:**
- **In-process two-client harness**: Two simulation instances driven with same inputs, state compared per tick. No framework provides this.
- **Record/replay**: Custom input log format (array of `{tick, peer_inputs}`). Golden-hash files for regression testing.
- **Multiplayer desync detection**: Rollback addon's Log Inspector handles this during live sessions; integrate with `_save_state()` hash verification.
- **Key prerequisite**: Simulation logic must be isolated into a pure GDScript class (no SceneTree dependencies) to be independently testable.

**CI setup (GitHub Actions):**
```yaml
- uses: godot-gdunit-labs/gdUnit4-action@v1
  with:
    godot-version: '4.3'
    paths: 'res://tests'
```
Handles Godot download, import warm-up, headless execution. JUnit XML output included.

---

## 3. Snopek Rollback Netcode — Feasibility Assessment

### Verdict: Right tool for real-time player sync; wrong tool for mutable worlds and session merging

**What it is:**
- `godot-rollback-netcode` on GitLab by David Snopek. Godot Asset Library (asset #2450).
- Status: v1.0.0-alpha10 (May 2024). Godot 4.2+ compatible. Active development. Still alpha.
- Core: `SyncManager` singleton, tick-rate-fixed `_network_process(input)`, per-node `_save_state()` / `_load_state()`.

**How rollback works:**
Every peer predicts remote inputs (default: repeat last known). When real remote input arrives and differs, the engine rolls back to last good tick, re-simulates forward. Corrections are fast enough to be invisible under normal latency. Requires O(n) state snapshots per rollback, re-simulation of up to 15 frames.

**CRITICAL — Mutable world state conflict:**
Rollback requires saving and restoring every piece of simulation state. Including a large tilemap in the rollback loop is prohibitive (8MB state copy ≈ 1ms; a world with thousands of tiles makes this unworkable). Three options:

- **Option A (include in rollback):** Not viable at any interesting world scale.
- **Option B (exclude world from rollback):** World mutations are never rolled back. Tile placements are permanent the moment executed. Requires its own sync discipline (confirmed-tick-only commits or separate authoritative channel). **This is the practical path.**
- **Option C (hybrid):** Tile mutations travel outside the rollback loop entirely as reliable ordered RPCs, applied as side-effects. Only player position/physics/fast state goes through rollback. Standard pattern for Minecraft-style real-time multiplayer. **Library doesn't provide tooling for this — must architect yourself.**

**CRITICAL — Session merging NOT supported:**
- No late-join. All peers must connect and `SyncManager.add_peer()` before `SyncManager.start()`.
- No `add_peer_mid_game()`. No session snapshot/transfer built in.
- Merging two independent sessions with diverged world states is entirely outside the library's scope.
- Custom merge process would require: stop both sessions → merge world states (conflict resolution strategy needed) → serialize merged state → distribute to all peers → start new joint session from tick 0.

**Determinism requirements (constraints on all game code):**
- No `randf()` / `randi()` — use `NetworkRandomNumberGenerator`
- No wall-clock time in simulation — use `SyncManager.current_tick`
- No floats in networked state (cross-platform FPU drift) — use SG Physics 2D (integer/fixed-point)
- No async ops in tick logic
- Scene-tree insertion order matters
- No per-Node references in state dictionaries

**Practical player count ceiling:** 2–8 players well-supported. 4–6 is the sweet spot. 10+ requires significant optimization work. Full-mesh P2P topology scales as O(n²) in bandwidth.

**Overall:** The Snopek library is excellent for real-time player movement/interaction within a stable session. It is architecturally in tension with two of this game's core mechanics: (1) mutable persistent world, (2) session merging. The library can still be used, but both of these features require building substantial custom infrastructure on top of it. The question is whether the benefits of rollback prediction (smooth player movement under latency) justify that cost over a simpler client-server authoritative model that naturally supports late-join and world mutation.

---

## 4. Freenet — Feasibility Assessment

### Verdict: Architecturally well-suited; too early to rely on; plan a fallback

**Current state:**
- Public network launched **March 15, 2026** alongside "River" (decentralized group chat).
- Alpha — breaking changes multiple times per day. Ian Clarke (creator): "not stable enough for non-technical use... weeks rather than months" before recommendation for general use.
- The December 2025 milestone was sub-second P2P chat latency. The architecture works.

**Data model:**
- Contracts: WASM code defining state validation and merge logic. State is arbitrary bytes. Contracts must implement commutative merge (CRDT semantics — `merge(A, B) = merge(B, A)`).
- Delegates: private per-user agents holding secrets and local state.
- UIs: standard web apps served over the network.
- **Key fit:** Tilemap chunks as contracts with CRDT merge is architecturally natural. Last-write-wins per tile, or union semantics, can be encoded in the contract's merge function. Concurrent edits converge correctly.

**For this game's needs:**

| Use Case | Viability | Notes |
|---|---|---|
| Persistent tilemap chunk storage | Medium | Architecturally fits. Eviction risk for cold/unvisited land. |
| Player proximity matchmaking | Medium | Subscribe to area contracts for presence; sub-second once subscribed. |
| P2P connection coordination | Low-Medium | No "connect to peer X" API. Coordination through contracts, connection established separately. |
| Real-time game packets | Not viable | Not what Freenet is for. Use WebRTC or direct UDP. |
| World state validation contracts | Medium | Contracts enforce validity. Limited to merge semantics, not arbitrary logic. |

**Networking:**
- Small-world routing (not Kademlia DHT). Greedy routing to contract location in ~30 hops.
- UDP hole-punching (QUIC). This is solved — confirmed working in the February 2026 demo.
- Subscription model: subscribe to a contract → receive pushed updates when state changes. Right model for presence/matchmaking.

**SDKs:**
- **Rust** — first-class. `freenet-stdlib`, `freenet-macros`.
- **TypeScript/WASM** — supported.
- **GDScript/Godot** — no native bindings. Best path: Godot communicates with a local Freenet node via WebSocket (Godot has native WebSocket support). Adds local-daemon dependency.
- No npm package. Thin ecosystem outside Rust.

**Claude skill:**
- Real: `github.com/freenet/freenet-agent-skills`. Install as a Claude Code plugin.
- `freenet-dapp-builder` teaches Claude to build Freenet contracts using River as reference architecture.
- Useful for accelerating contract development.

**Top risks:**
1. Breaking changes daily — building on unstable protocol.
2. Network is tiny (launched March 2026) — limited geographic diversity for matchmaking.
3. Data eviction — wilderness chunks with no subscribers get evicted. Active subscribers keep state alive, but empty wilderness is at risk.
4. No ordered operations — CRDT semantics only. Authoritative game logic must stay client-side.
5. Rust-primary ecosystem — contract development requires Rust knowledge.
6. No direct P2P connection API — must extract peer info from network and connect via separate mechanism (WebRTC).

**Recommendation:** Design Freenet integration as an isolated layer. Plan a fallback backend (simple server + SQLite + libp2p or WebRTC for P2P) so the game is not blocked by Freenet instability. Freenet is the right architecture for what you're trying to do — just 6–12 months ahead of being reliable enough to depend on exclusively.

---

## 5. P2P Networking Alternatives

**Rollback netcode is ruled out.** Mutable world and spatial merge are both fundamentally incompatible. Research covered: lockstep, distributed/region authority, multi-witness consensus, optimistic+dispute, CRDT world state, Nakama, real game examples, and hybrid models.

### Options assessed

**Lockstep** — Strong anti-cheat (only inputs broadcast, not state), 2–8 player ceiling, cannot late-join without a full freeze. The spatial merge mechanic requires freezing all players for state transfer — ruled out.

**Distributed/Region Authority** — Best architectural match for both spatial merging AND 100-player towns. Each chunk/region has an authority peer; authority transfers as players move. Godot 4 supports this natively via `set_multiplayer_authority()` + `MultiplayerSynchronizer`. Anti-cheat is weak by default (authority peer can lie). Layered mitigations can harden it. Late-join is clean.

**Multi-witness Consensus** — Best anti-cheat for P2P. Actions require N-of-M witness signatures before committing. 26ms latency at 8 peers, 103ms at 32 peers (Tashi Protocol benchmark). Works for slow-paced events (tile placement, item drops), too slow for 60fps combat. **No Godot library exists today.** Tashi Protocol lists Godot support as "in development." Building from scratch is ~2000–4000 lines GDScript.

**Optimistic + Dispute** — Hard incompatibility with mutable world state (replay is impossible when the world has changed). Skip.

**CRDT world state** — Excellent fit for tile mutations. Any two CRDT stores merge automatically without conflict — exactly how Freenet contracts work. **The spatial merge becomes: merge two CRDT tile stores, which is trivially correct by design.** Does not address real-time position/combat. Published paper (Dantas & Baquero, ACM PaPoC 2025) confirms viability for games.

**Nakama** — Open-source Go game backend with official Godot 4 client. Not a P2P replacement. Best used as a federated signaling/matchmaking layer for WebRTC. Community operators run Nakama nodes; players don't need to. Dropped from real-time path after WebRTC connects.

**What shipped games do:** Minecraft/Terraria use "host is server" — one player's process is authoritative. Simple, proven, good world-state anti-cheat. Valheim is client-authoritative and easily cheated. Factorio uses deterministic lockstep with a server process at scale.

### Recommended architecture

| Layer | Mechanism | Status |
|---|---|---|
| Persistent world state (tiles) | CRDT (LWW-Map per chunk) stored in Freenet | Custom GDScript; aligns with Freenet contracts |
| Real-time gameplay (position, movement) | Region authority via `set_multiplayer_authority()` | Godot 4 native |
| High-value events (tile placement, item drops) | 2-of-N witness signatures before CRDT commit | Custom; no library — Tashi Protocol may ship Godot support |
| Session discovery / WebRTC signaling | Nakama (federated, community-run) | Official Godot client exists |
| Anti-cheat global layer | Freenet contract validation | Prevents cheats from persisting in shared world state |

**Why CRDT solves spatial merging:** When bridge chunks form, the two groups exchange their CRDT chunk stores. No freeze, no negotiation. The merge is correct by the math of CRDTs.

**Open library gap:** Multi-witness consensus has no Godot implementation today. Tashi Protocol is the most credible path to watch. Could phase this in after core gameplay is working.

---

## Key Architectural Decisions Made

1. **Rollback netcode ruled out.** Core game mechanics are fundamentally incompatible.
2. **Networking model**: Region authority for real-time + CRDT for world state + witness layer for high-value events.
3. **Freenet abstracted** behind a backend interface. LAN/local implementation first for testing.
4. **Wilderness chunks are lost** when evicted — regenerate from seed. Impermanence is intentional.
5. **Session merge** = chunk-graph adjacency + CRDT store merge. No hard pause, no state transfer ceremony.

## Remaining Open Questions

1. **Multi-witness threshold**: What quorum for tile placement? 2-of-3 (easy to abuse in small groups), 2-of-5? Needs playtesting.
2. **Settled vs wilderness boundary**: How does a chunk transition from impermanent wilderness to stable settled land? Player structure? Explicit claim action?
3. **Authority for dense towns**: In a 100-player town, who holds regional authority for a shared zone? Elected peer? Rotating? What happens on disconnect?
4. **Bridge formation trigger**: Pure proximity? Mutual signal? Random probability? Affects feel significantly.
5. **Tashi Protocol timeline**: If Godot support ships in the next 3–6 months, the witness layer becomes much cheaper to build.
