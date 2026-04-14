extends Node

## CoordUtils — sole coordinate conversion authority.
## Three coordinate spaces: world tile coords, chunk coords, local tile coords.
## NEVER do inline arithmetic elsewhere — always call these helpers.

static func world_to_chunk(w: Vector2i) -> Vector2i:
	## Floor-divide world tile coords by CHUNK_SIZE to get chunk coords.
	## Uses floorf() NOT % — GDScript % returns negative for negative operands.
	return Vector2i(int(floorf(float(w.x) / Constants.CHUNK_SIZE)),
	                int(floorf(float(w.y) / Constants.CHUNK_SIZE)))

static func world_to_local(w: Vector2i) -> Vector2i:
	## Returns position within chunk. Always [0, CHUNK_SIZE-1].
	return Vector2i(((w.x % Constants.CHUNK_SIZE) + Constants.CHUNK_SIZE) % Constants.CHUNK_SIZE,
	                ((w.y % Constants.CHUNK_SIZE) + Constants.CHUNK_SIZE) % Constants.CHUNK_SIZE)

static func chunk_local_to_world(chunk: Vector2i, local: Vector2i) -> Vector2i:
	## Inverse of world_to_chunk + world_to_local.
	## Round-trip: chunk_local_to_world(world_to_chunk(p), world_to_local(p)) == p
	return Vector2i(chunk.x * Constants.CHUNK_SIZE + local.x,
	                chunk.y * Constants.CHUNK_SIZE + local.y)

static func make_crdt_key(layer: int, lx: int, ly: int) -> int:
	## Pack layer + local x + local y into a single int key.
	## With CHUNK_SIZE=16, local coords fit in 8 bits. Layer 0=ground, 1=objects.
	return (layer << 16) | (lx << 8) | ly
