extends Node

const CHUNK_SIZE: int = 16       # tiles per chunk side (16x16 = 256 tiles)
const TILE_SIZE: int = 16        # pixels per tile
const LOAD_RADIUS: int = 4       # chunks to keep loaded around player
const UNLOAD_RADIUS: int = 6     # chunks beyond this get unloaded (hysteresis gap prevents thrashing)
const FADE_THRESHOLD: float = 5.0
const WORLD_SEED: int = 12345    # replace with per-world random seed later
