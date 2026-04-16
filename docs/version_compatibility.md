# Version Compatibility

## Three rules

### 1. Contract code changes = world reset
The chunk contract WASM hash is part of the contract instance key. Changing
the contract code produces different instance IDs — clients on the new version
cannot read chunks written by the old version.

`CONTRACT_VERSION` in `GameVersion.gd` tracks this. Increment it deliberately,
document the reason, and treat it as a world reset event. The goal is for
`CONTRACT_VERSION` to stay at 1 indefinitely. Keep the contract code thin:
it should only validate JSON structure and merge LWW maps. All game logic
lives in GDScript.

### 2. Tile type IDs are immutable
Tile type IDs (e.g. `"bone_armor"`, `"chest"`) are CRDT map keys. Old chunks
have old tile layouts. If a tile type's schema changes, give it a new ID —
never change what an existing ID means. Removal is safe (old tiles become
unrecognised and are ignored). Renaming is a breaking change.

### 3. RPC/protocol changes = PROTOCOL_VERSION bump
Any change to RPC method names, signatures, or message formats requires
incrementing `PROTOCOL_VERSION` in `GameVersion.gd`. Clients refuse to pair
with peers on a different protocol version and show a version mismatch message.

`PROTOCOL_VERSION` is advertised in `LobbyEntry` and checked by
`MergeCoordinator` before any WebRTC pairing attempt.

## Version manifest

The developer publishes a version manifest to the Freenet network using
`scripts/publish_version.sh`. The manifest contains:

- `version` — human-readable release string
- `commit` — short git hash
- `published_at` — unix timestamp (merge keeps the newest)
- `download_url` — GitHub releases URL (must be `https://github.com/`)
- `min_protocol_version` — minimum protocol version required for multiplayer

The game checks this on startup (background, non-blocking). If an update is
available it shows a banner. If `min_protocol_version > PROTOCOL_VERSION`,
the banner is red and says "Update required to join multiplayer games."

## What survives updates

| Change type | World survives? | Protocol bump? |
|---|---|---|
| New tile types | Yes | No |
| New optional CRDT fields | Yes | No |
| New GDScript game mechanics | Yes | No |
| New RPC methods (additive) | Yes | No |
| Renamed/removed RPC methods | No | Yes |
| Contract code change | No (world reset) | Yes |
| Rename existing tile type | No | Yes |

## Publishing a release

```bash
# Build the version contract if not already done
cd backend/freenet/contracts/version-manifest
CARGO_TARGET_DIR=../../target PATH="$HOME/.cargo/bin:$PATH" fdev build

# Start freenet network + freeland-proxy (with version contract path set)
./scripts/run_multiplayer_local.sh --freenet

# Publish the manifest (in another terminal)
./scripts/publish_version.sh 0.3.0 https://github.com/you/freeland/releases/tag/v0.3.0
# For a breaking release:
./scripts/publish_version.sh 0.4.0 https://github.com/you/freeland/releases/tag/v0.4.0 2
```
