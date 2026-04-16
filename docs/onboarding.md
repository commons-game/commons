# Player Onboarding

## How it works

Freeland is peer-to-peer. There's no central server. Each player's game
automatically manages the local Freenet node and proxy — no setup required.

On first launch, the game:
1. Starts `freenet network` (your local P2P node)
2. Starts `freeland-proxy` (local bridge between the game and Freenet)
3. Shows "Connected" when ready

Both processes are shut down when you close the game.

## What gets installed

Nothing is installed to your system. The `freenet` binary updates itself
to `~/.local/bin/freenet` on first run (Freenet's standard install location).
`freeland-proxy` runs from the game directory and leaves no traces.

## Distribution layout

```
freeland.x86_64          <- game binary
bin/
  freenet                <- Freenet node binary
  freeland-proxy         <- local proxy bridge
  freeland_chunk_contract
  freeland_lobby_contract
  freeland_pairing_contract
  freeland_player_delegate
  freeland_error_contract
  freeland_version_manifest
```

## If Freenet isn't found

If `freenet` isn't found alongside the game or in `~/.local/bin`, the menu
shows an error with installation instructions. Run:
```
curl -fsSL https://freenet.org/install.sh | sh
```
Then restart the game.

## Developer mode

To manage processes manually (e.g. when developing), pass:
```
godot4 --path . -- --no-managed-backend
```
The game will skip auto-starting Freenet and the proxy.
