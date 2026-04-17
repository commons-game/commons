extends Node

const CHUNK_SIZE: int = 16       # tiles per chunk side (16x16 = 256 tiles)
const TILE_SIZE: int = 16        # pixels per tile
const LOAD_RADIUS: int = 4       # chunks to keep loaded around player
const UNLOAD_RADIUS: int = 6     # chunks beyond this get unloaded (hysteresis gap prevents thrashing)
const FADE_THRESHOLD: float = 5.0
const WORLD_SEED: int = 12345    # replace with per-world random seed later
## Full day/night cycle length in seconds. Override with --day-cycle=<seconds> arg.
## Default 7200 = 60 min day + 60 min night. Use --day-cycle=120 for fast testing.
var DAY_CYCLE_SECONDS: float = 7200.0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--day-cycle="):
			var val := float(arg.split("=")[1])
			if val > 0.0:
				DAY_CYCLE_SECONDS = val
