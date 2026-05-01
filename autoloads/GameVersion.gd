## GameVersion — single source of truth for version constants.
##
## PROTOCOL_VERSION: bump when RPC signatures change or contract code changes.
##   Clients refuse to pair with peers on a different protocol version.
##   Incrementing this is a breaking change — communicate it clearly.
##
## GAME_VERSION: human-readable release string. Replaced with commit hash at
##   export time. Used in error reports and the update banner.
##
## CONTRACT_VERSION: tracks chunk contract WASM changes. Incrementing means
##   old world data is no longer accessible (world reset). Do this rarely and
##   document it explicitly.
extends Node

const PROTOCOL_VERSION: int    = 1
const GAME_VERSION:     String = "dev"
const CONTRACT_VERSION: int    = 1

## Boot-time stamp into godot.log so playtest sessions can answer
## "is this binary current?" without re-deriving build provenance.
##
## dev/build.sh sed-replaces GAME_VERSION with "<git-sha> <iso-date>" before
## export, so a stale binary's log shows an older SHA than HEAD on the dev
## server. Without this print we ran an Apr-23 binary for a week and didn't
## notice. See dev/build.sh / dev/play.sh for the workflow chain.
func _ready() -> void:
	print("[GameVersion] %s (protocol %d)" % [GAME_VERSION, PROTOCOL_VERSION])
