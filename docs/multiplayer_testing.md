# Multiplayer Testing

Verified in this order before flipping `Backend.use_freenet = true` in production.

## What "multiplayer" means in Commons

Two transport layers, not one:

1. **Live peer sync over WebRTC/RPC.** `TileMutationBus.broadcast_mutation`
   goes through Godot's `MultiplayerAPI`. Real-time mirror of tile placements,
   removes, and mutations. **Already wired.**
2. **Freenet contracts for chunk persistence.** `FreenetBackend` swaps in for
   `LocalBackend`. Only touches chunk save/load at the storage boundary.

Flipping `use_freenet` is a **storage** flip. Live sync is independent.

---

## The four tiers

### Tier 1 — In-process two-peer harness (fast loop, run on every change)

`PuppetCluster` spawns two `World` instances in one headless Godot, each with
its own `ChunkManager` / `Player` / `TileMutationBus`. The buses are wired
via `_test_peer_buses` so local mutations mirror synchronously through the
same `apply_remote_mutation` code path real RPC uses. No network layer.

Run a scenario:

```bash
godot4 --headless --path . -- --puppet-cluster-scenario=res://tests/scenarios/<name>.gd
```

Existing scenarios (`tests/scenarios/cross_peer_*.gd`):

| Scenario | Invariant |
|---|---|
| `cross_peer_campfire_sync.gd` | Place and remove mirror both directions; scenes spawn/despawn on both peers. |
| `cross_peer_tether_broken_by_stranger.gd` | Breaking peer A's Tether from peer B clears A's home anchor via `tile_removed`. |
| `cross_peer_chunk_on_join.gd` | Late joiner loads a chunk containing structures placed by another peer; `_spawn_structures_for_chunk` rebuilds them from shared CRDT storage. |
| `cross_peer_crdt_lww.gd` | Later timestamp wins across peers; stale remote writes are rejected and don't clobber newer state. |

CRDT property test (`tests/unit/test_crdt_convergence_property.gd`) runs 25
random mutation sequences × 3 invariants (commutativity, two-peer convergence,
merge associativity + idempotency) on every `cargo test` pass.

Writing a new cluster scenario: `_run(ps: Array)` receives `[puppet_A, puppet_B]`.
Call `a.world().get_node("TileMutationBus").request_place_tile(...)` on one peer
and assert the effect on the other peer via the Puppet query API.

### Tier 2 — Proxy round-trip integration test (before Freenet flip)

`backend/freenet/proxy/tests/round_trip.rs`. Spawns the proxy against a live
Freenet node, does a `Put`+`Get` round-trip for chunks and lobby entries.
Catches: wire protocol drift, contract format drift, encoding-protocol
(`?encodingProtocol=native`) regressions, node API changes.

Gated behind `#[cfg(feature = "integration")]` so default `cargo test` stays
green without a node.

Run it:

```bash
# Start a local Freenet node in another terminal:
freenet local --ws-api-address 0.0.0.0:50509

# Then:
scripts/run-freenet-integration.sh
```

The script builds contracts via `fdev`, exports the required env vars, and
invokes `cargo test --features integration`.

### Tier 3 — Freenet version pinning

`backend/freenet/FREENET_VERSION` records the node version we've verified
against via Tier 2. First line == version string from `freenet --version`,
or `unpinned` if no pin has been established.

Update the pin after verifying a new node version:

```bash
scripts/update_freenet_pin.sh
```

Runs Tier 2 first; if green, writes the current node's version to the pin
file. On failure, leaves the pin alone so drift is visible.

Layer 2 (Cargo.lock) and Layer 3 (committed fdev-built contract artifacts)
from the retrospective complete the pinning story — Cargo.lock is already
committed; committed artifacts are a follow-up when we have a stable fdev
build pipeline.

### Tier 4 — Two-process end-to-end (deferred)

Not built. Would launch two headless `godot4 --puppet-scenario=...`
processes sharing a real backend, assert final state across both. Build on
demand when a bug escapes tiers 1–3.

---

## Pre-flip checklist

Before flipping `Backend.use_freenet = true` as the default:

- [ ] All `tests/scenarios/cross_peer_*.gd` pass
- [ ] `tests/unit/test_crdt_convergence_property.gd` passes on the current code
- [ ] `scripts/run-freenet-integration.sh` passes against a locally-installed
      Freenet node
- [ ] `scripts/update_freenet_pin.sh` has been run; `FREENET_VERSION` is not
      `unpinned`
- [ ] `Cargo.lock` is committed (should already be — verify with `git ls-files
      backend/freenet/Cargo.lock`)

When the full list is green, flipping `use_freenet` is its own commit.
