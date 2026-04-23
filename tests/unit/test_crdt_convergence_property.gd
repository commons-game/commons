## Property-style CRDT test: generate random mutation sequences across two
## simulated peers, apply them in random orders, assert both converge to
## identical state.
##
## Narrow unit tests check a handful of LWW cases by construction; this
## spreads a wider net — commutativity + idempotency + tombstone ordering
## under thousands of synthetic permutations. One RNG seed per invariant so
## failures are reproducible.
extends GdUnitTestSuite

const OPS_PER_RUN   := 40
const COORD_RANGE   := 4   # small grid so collisions are frequent
const TILE_IDS      := [0, 1, 2, 3, -1]  # -1 = remove (tombstone)
const RUNS_PER_TEST := 25

func _key(entry: Dictionary) -> String:
	if entry.is_empty():
		return "<empty>"
	return "%d@%.6f/%s" % [entry["tile_id"], entry["timestamp"], entry.get("author_id", "")]

## Run `ops` against a store. `ops` is an Array of [ts, layer, x, y, tile_id, author].
## tile_id == -1 means remove_tile (tombstone).
func _apply(store: CRDTTileStore, ops: Array) -> void:
	for op in ops:
		var ts: float = op[0]
		var layer: int = op[1]
		var pos := Vector2i(op[2], op[3])
		var tile_id: int = op[4]
		var author: String = op[5]
		if tile_id < 0:
			store.remove_tile(layer, pos, author, ts)
		else:
			store.set_tile(layer, pos, tile_id, Vector2i(tile_id, 0), 0, author, ts)

## Canonicalise a store's _data into a sorted string for comparison.
func _fingerprint(store: CRDTTileStore) -> String:
	var keys: Array = store._data.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%d:%s" % [k, _key(store._data[k])])
	return "|".join(parts)

func _gen_ops(rng: RandomNumberGenerator) -> Array:
	var ops: Array = []
	var base_ts := 1_000_000.0
	for _i in range(OPS_PER_RUN):
		# Jitter within a narrow window so same-coord collisions line up at
		# closely-spaced timestamps — the interesting LWW regime.
		var ts := base_ts + rng.randf_range(0.0, 100.0)
		var layer := 0 if rng.randf() < 0.5 else 1
		var x := rng.randi_range(-COORD_RANGE, COORD_RANGE)
		var y := rng.randi_range(-COORD_RANGE, COORD_RANGE)
		var tid: int = TILE_IDS[rng.randi_range(0, TILE_IDS.size() - 1)]
		var author := "peer_A" if rng.randf() < 0.5 else "peer_B"
		ops.append([ts, layer, x, y, tid, author])
	return ops

func test_convergence_under_delivery_reordering() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0DE
	for run in range(RUNS_PER_TEST):
		var ops := _gen_ops(rng)
		var store_in_order := CRDTTileStore.new()
		_apply(store_in_order, ops)
		var shuffled := ops.duplicate()
		shuffled.shuffle()
		var store_shuffled := CRDTTileStore.new()
		_apply(store_shuffled, shuffled)
		var fp_a := _fingerprint(store_in_order)
		var fp_b := _fingerprint(store_shuffled)
		assert_that(fp_a).is_equal(fp_b) \
			.override_failure_message("run=%d: in-order vs shuffled diverged" % run)

func test_convergence_between_two_peers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBEEF
	for run in range(RUNS_PER_TEST):
		var ops := _gen_ops(rng)
		# Peer A applies in the original order; peer B applies in a different
		# random permutation. Both must end identical.
		var a := CRDTTileStore.new()
		var b := CRDTTileStore.new()
		_apply(a, ops)
		var shuffled := ops.duplicate()
		shuffled.shuffle()
		_apply(b, shuffled)
		assert_that(_fingerprint(a)).is_equal(_fingerprint(b)) \
			.override_failure_message("run=%d: two-peer converge failed" % run)

func test_merge_is_idempotent_and_associative() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xFACE
	for run in range(RUNS_PER_TEST):
		var ops := _gen_ops(rng)
		var a := CRDTTileStore.new()
		var b := CRDTTileStore.new()
		var c := CRDTTileStore.new()
		# Partition ops across three peers.
		for i in range(ops.size()):
			match i % 3:
				0: _apply(a, [ops[i]])
				1: _apply(b, [ops[i]])
				2: _apply(c, [ops[i]])
		# (A ⋃ B) ⋃ C vs A ⋃ (B ⋃ C)
		var left := CRDTTileStore.new()
		_apply(left, ops)  # all three peers' ops in sequence
		var merged_ab := CRDTTileStore.new()
		merged_ab.merge(a); merged_ab.merge(b); merged_ab.merge(c)
		var merged_bc := CRDTTileStore.new()
		var bc := CRDTTileStore.new()
		bc.merge(b); bc.merge(c)
		merged_bc.merge(a); merged_bc.merge(bc)
		assert_that(_fingerprint(merged_ab)).is_equal(_fingerprint(merged_bc)) \
			.override_failure_message("run=%d: (A⋃B)⋃C != A⋃(B⋃C)" % run)
		# Idempotency: re-merging A into itself changes nothing.
		var a_fp := _fingerprint(a)
		a.merge(a)
		assert_that(_fingerprint(a)).is_equal(a_fp) \
			.override_failure_message("run=%d: A.merge(A) changed A" % run)
