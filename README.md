# Commons

A decentralized, mod-centric top-down RPG where player worlds diverge and merge.

Built on [Freenet](https://freenet.org) — no central servers, no accounts, no one owns the world but the players.

## Status

Early development. Core systems working: world persistence via Freenet contracts, WebRTC peer-to-peer multiplayer, CRDT tile merging, player identity.

## How it works

Each player runs a local Freenet node. The game world is stored as Freenet contracts — chunks of tiles managed by a CRDT that merges concurrent edits automatically. Two players can diverge (play separately), then reconnect and watch their worlds merge in real time.

## Running locally

### Requirements

- [Godot 4.3](https://godotengine.org/download/)
- [Freenet](https://freenet.org) — `curl -fsSL https://freenet.org/install.sh | sh`
- Rust + `cargo` (for building the proxy)

### Build the proxy

```bash
cd backend/freenet
cargo build --bin commons-proxy
```

### Play

```bash
godot4 --path .
```

The game auto-starts Freenet and the proxy on launch. No terminal needed.

### Local multiplayer test (two instances)

```bash
./scripts/run_multiplayer_local.sh
```

## Project structure

```
autoloads/       GDScript singletons (Backend, PlayerIdentity, ProcessManager, ...)
backend/freenet/ Rust — proxy, contracts, delegates
contracts/       Freenet contracts (chunk storage, lobby, pairing, versioning)
delegates/       Freenet delegates (player identity, signing)
player/          Player controller, appearance, remote player
world/           World, chunk system, CRDT tile store
ui/              Menus, HUD, overlays
scripts/         Dev tooling (local test, build export, publish version)
docs/            Architecture, onboarding, version compatibility
```

## Contributing

Issues and PRs welcome. See `docs/` for architecture notes.

Mods are a first-class goal — modding docs coming once the core is stable.

## License

Code: [GNU Affero General Public License v3.0](LICENSE)  
Assets: [Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
