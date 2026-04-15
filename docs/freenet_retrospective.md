# Freenet Integration Retrospective

**Date:** 2026-04-14  
**Scope:** Phase 6 spike — Freenet chunk contract + proxy + FreenetBackend.gd

---

## What We Built

A full end-to-end path from GDScript → Rust proxy → Freenet node:
- `freeland-chunk-contract`: Freenet contract with LWW-CRDT merge semantics, 6 unit tests
- `freeland-proxy`: JSON-WebSocket ↔ Freenet binary protocol bridge
- `FreenetBackend.gd`: Drop-in IBackend with write-through cache and async signal delivery

Verified: Put chunk (3,7) → GetOk round-trip through a live local Freenet node.

---

## Findings

### 1. Check the quickstart first, not crates.io

**What happened:** We tried `cargo install freenet`. It either didn't install anything useful or installed the wrong binary. The actual Freenet node is installed via the project's own install script.

**Correct install:**
```bash
curl -fsSL https://freenet.org/install.sh | sh
```

**Rule going forward:** For any P2P / decentralized runtime (Freenet, IPFS, libp2p nodes), check the project's quickstart page before reaching for `cargo install`. These projects often publish their own installer because the binary needs more than crates.io can express.

**Action:** Document correct install command in `known_issues.md` ✓ (already done)

---

### 2. fdev CARGO_TARGET_DIR bug — upstream issue

**What happened:** `fdev build` panicked with "Could not find workspace root". Root cause: `env!("CARGO_MANIFEST_DIR")` is baked in at compile time pointing to the cargo registry cache path, not the user's project. fdev uses it to find the workspace root, fails on every real project.

**Workaround:**
```bash
CARGO_TARGET_DIR=$(pwd)/../../target fdev build
```

**Action:** File upstream bug on freenet/freenet-core. The fix is straightforward: use `std::env::current_dir()` or walk up from the contract's manifest path, not the baked-in registry path.

**Lesson:** When a tool panics on a path that looks like `~/.cargo/registry/...`, the tool is using a compile-time path baked into its own binary. That's almost always a bug in the tool.

---

### 3. `versioned_contract_bytes` was the clue we missed

**What happened:** We initially passed raw WASM bytes to `ContractContainer::try_from`. The Freenet node rejected these silently (or returned a confusing error). The fix was to pass the `fdev build` output format: `8-byte version (u64 BE) + 32-byte code hash + raw WASM`.

**The clue that was in the code:** The function name `load_versioned_from_bytes` in the stdlib source was a strong hint that the format is NOT raw WASM. We missed it on the first pass.

**Rule going forward:** When a `try_from` for binary data fails silently, grep the stdlib for `load_*_from_bytes` or `parse_*` to understand the expected wire format before assuming it's raw bytes.

---

### 4. `?encodingProtocol=native` is not documented anywhere a new integrator would find it

**What happened:** Without `?encodingProtocol=native` appended to the WebSocket URL, the Freenet node uses a different serialization (produces a response like `{"Ok": 12}` that bincode decodes as `"invalid value: integer '12', expected 'Ok' or 'Err'"`). The correct URL is not in any README or `--help` output — it was found by reading `fdev`'s source (`commands/v1.rs`).

**Rule going forward:** Before writing a new Freenet WebSocket client, run `fdev execute` against the node first to capture a known-good raw WebSocket session, then model your client after those exact bytes/URL. Don't reverse-engineer from the node's behavior — read fdev source when the client-side protocol is ambiguous.

**Action:** The `?encodingProtocol=native` requirement is now hardcoded in the proxy default URL and documented in `known_issues.md` ✓

---

### 5. No integration smoke test — all errors were discovered at runtime

**What happened:** All five bugs above (wrong install, raw WASM format, missing URL parameter, IPv6/IPv4 mismatch, missing `blocking_subscribe` field) were discovered by running the proxy against a live node. There was no automated test that could have caught them earlier.

**Action:** Add a proxy integration smoke test (see below).

---

## Action Items

| # | Action | Status |
|---|--------|--------|
| 1 | Document `freenet local --ws-api-address 0.0.0.0` and `?encodingProtocol=native` in known_issues | ✓ Done |
| 2 | File upstream `fdev` CARGO_TARGET_DIR bug on freenet/freenet-core | Pending |
| 3 | Add proxy integration smoke test (see below) | Pending |
| 4 | Establish rule: test with `fdev execute` before writing a new Freenet client | ✓ Established |

### Proposed smoke test

```rust
// backend/freenet/proxy/tests/round_trip.rs
// Requires FREENET_NODE_URL env var pointing to a running local node.
// Skip with #[cfg_attr(not(feature = "integration"), ignore)].
#[test]
#[ignore]
fn put_then_get_round_trips() {
    // Spawn proxy, connect WebSocket client, Put chunk (99,99), Get chunk (99,99),
    // assert state_json matches, assert no Error variant.
}
```

This would have caught bugs 2, 3, and 4 above in a single run.

---

## Freenet Version Pinning Strategy

The Freenet node binary auto-updates on startup. This is a significant stability risk:

- Node does a startup check against GitHub and self-updates if a newer version exists
- Node force-exits if it detects peer version mismatch >6h
- There is no `--no-auto-update` CLI flag
- The only discovered env var is `FREENET_TELEMETRY_ENABLED` (unrelated)
- **Key finding:** The binary skips auto-update if it detects it is a "dirty (locally modified) build" (found via `strings ~/.local/bin/freenet`)

### Risks

1. **Breaking API changes**: A node update could change the binary protocol, the `?encodingProtocol=native` URL, or the packaged contract format
2. **Contract hash churn**: If the contract code changes (even trivially), the `ContractInstanceId` changes, making all stored chunks unreachable
3. **fdev/node version skew**: The `fdev` tool and node must match; auto-updating one without the other breaks builds
4. **Forced exit in production**: The >6h peer mismatch exit is designed for network health but is hostile to a game server

### Pinning approach

**Layer 1 — Pin the expected version in source**

Create `backend/freenet/FREENET_VERSION` containing the exact version string we've verified against:
```
freenet 0.1.x
```

Add a startup assertion in the proxy:
```rust
// In main(), before binding the listener:
let node_version = query_node_version(&node_url).await?;
let expected = include_str!("../../FREENET_VERSION").trim();
if !node_version.starts_with(expected) {
    panic!("Freenet node version mismatch. Expected {expected}, got {node_version}. \
            Update FREENET_VERSION if the new version is compatible.");
}
```

**Layer 2 — Lock Cargo.lock**

Commit `backend/freenet/Cargo.lock`. This pins `freenet-stdlib` to an exact version. Combined with the proxy version assertion, we'll catch API drift at startup rather than at runtime.

**Layer 3 — Commit the packaged contract artifact**

The `fdev build` output (versioned WASM package) is deterministic for a given source + `freenet-stdlib` version. Commit it to `backend/freenet/artifacts/freeland_chunk_contract_v<version>`. The proxy loads from this path. This decouples the runtime from `fdev` being installed or the build succeeding.

**Layer 4 — Monitor the upstream changelog**

Watch `freenet/freenet-core` releases. When a new release lands:
1. Read the changelog for protocol/API changes
2. Run the round-trip smoke test against the new node
3. If it passes: update `FREENET_VERSION`, regenerate the contract artifact, commit both
4. If it fails: stay on the pinned version until we've ported the changes

### What to do about auto-update

The "dirty build" finding means we could build from source with a no-op modification to suppress auto-update. That's fragile and adversarial.

**Better approach:** Accept that the user's local node will auto-update. Protect the game by:
1. The proxy version assertion (Layer 1) will refuse to start if the node has incompatibly updated
2. The player sees a clear error: "Node updated, please update Freeland proxy"
3. We ship a script: `scripts/update_freenet_backend.sh` that runs the round-trip test and updates `FREENET_VERSION` if it passes

This is honest about the tradeoff: Freenet auto-update is a feature of their decentralized network's health. We accommodate it rather than fight it, but we make the breakage loud and fast instead of silent and confusing.

### What we do NOT do

- Do NOT try to disable auto-update via environment variables (brittle, may break the network)
- Do NOT pin to a specific binary hash (forces users to manually manage binary versions)
- Do NOT store user chunks in a contract we've compiled ourselves without auditing the contract hash (would make player data dependent on our build environment)
