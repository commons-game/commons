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
