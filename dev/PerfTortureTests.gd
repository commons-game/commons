## PerfTortureTests — performance torture suite for Freeland.
## Instantiated by World._run_perf_torture() when --perf-torture is passed.
## Tests run sequentially; each cleans up before the next.
## Results are saved to user://perf_baselines/<timestamp>.json and printed to stdout.
extends Node

const MobSpawnerScript := preload("res://world/mobs/MobSpawner.gd")

signal all_tests_finished(results: Array)  # Array of result Dictionaries

var _chunk_manager = null  # ChunkManager — set by World before run_all()
var _player: Node = null   # Player node — set by World
var _world: Node = null    # World node — set by World

func run_all() -> void:
	var results: Array = []
	results.append(await _test_chunk_flood())
	results.append(await _test_mob_ramp())
	results.append(await _test_tile_flood())
	results.append(await _test_chunk_thrash())
	emit_signal("all_tests_finished", results)
	_print_summary(results)
	_save_results(results)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

# ─── Test 1: Chunk Flood ────────────────────────────────────────────────────

func _test_chunk_flood() -> Dictionary:
	print("[PERF] === chunk_flood starting ===")
	var chunks_loaded := 0
	var total_usec := 0
	var peak_usec := 0
	var slowest_coords := Vector2i.ZERO

	for cy in range(-5, 6):
		for cx in range(-5, 6):
			var coords := Vector2i(cx, cy)
			if _chunk_manager._loaded_chunks.has(coords):
				continue
			var t0 := Time.get_ticks_usec()
			_chunk_manager._load_chunk(coords)
			var elapsed := Time.get_ticks_usec() - t0
			total_usec += elapsed
			chunks_loaded += 1
			if elapsed > peak_usec:
				peak_usec = elapsed
				slowest_coords = coords

	await get_tree().process_frame

	# Unload everything except (0,0)
	var to_unload := _chunk_manager._loaded_chunks.keys().duplicate()
	for coords in to_unload:
		if coords != Vector2i(0, 0):
			_chunk_manager.force_unload_chunk_no_persist(coords)

	await get_tree().process_frame

	var total_ms := total_usec / 1000.0
	var avg_ms := (total_ms / chunks_loaded) if chunks_loaded > 0 else 0.0
	var peak_ms := peak_usec / 1000.0

	print("[PERF] chunk_flood  chunks=%d  total=%.1fms  avg=%.1fms  peak=%.1fms @ %s" % [
		chunks_loaded, total_ms, avg_ms, peak_ms, slowest_coords])

	return {
		"name": "chunk_flood",
		"chunks_loaded": chunks_loaded,
		"total_ms": total_ms,
		"avg_ms": avg_ms,
		"peak_ms": peak_ms,
		"slowest_coords": [slowest_coords.x, slowest_coords.y],
		"summary": "chunk_flood  chunks=%d  total=%.1fms  avg=%.1fms  peak=%.1fms @ %s" % [
			chunks_loaded, total_ms, avg_ms, peak_ms, slowest_coords],
	}

# ─── Test 2: Mob Ramp ──────────────────────────────────────────────────────

func _test_mob_ramp() -> Dictionary:
	print("[PERF] === mob_ramp starting ===")
	const BATCH_SIZE := 10
	const MAX_MOBS := 200
	const STABILIZE_FRAMES := 60
	const MEASURE_FRAMES := 20
	const SPAWN_RADIUS := 20

	var spawner := MobSpawnerScript.new()
	_world.add_child(spawner)

	var all_mobs: Array = []
	var mobs_at_60fps := 0
	var mobs_at_30fps := 0
	var final_fps := 0.0

	while all_mobs.size() < MAX_MOBS:
		# Spawn a batch
		var new_mobs := spawner.spawn(
			Vector2i(0, 0), BATCH_SIZE, SPAWN_RADIUS,
			_chunk_manager, _player, _world)
		all_mobs.append_array(new_mobs)

		# Wait for FPS to stabilize (60 frames)
		for _i in range(STABILIZE_FRAMES):
			await get_tree().process_frame

		# Measure average FPS over next 20 frames
		var fps_sum := 0.0
		for _i in range(MEASURE_FRAMES):
			fps_sum += Engine.get_frames_per_second()
			await get_tree().process_frame
		var avg_fps := fps_sum / MEASURE_FRAMES
		final_fps = avg_fps

		var mob_count := all_mobs.size()
		print("[PERF] mob_ramp  mobs=%d  fps=%.0f" % [mob_count, avg_fps])

		if avg_fps >= 60.0:
			mobs_at_60fps = mob_count
		if avg_fps >= 30.0:
			mobs_at_30fps = mob_count

		if avg_fps < 20.0:
			break  # no point going further

	# Cleanup
	for mob in all_mobs:
		if is_instance_valid(mob):
			mob.queue_free()
	spawner.queue_free()
	await get_tree().process_frame

	var final_count := all_mobs.size()
	return {
		"name": "mob_ramp",
		"batch_size": BATCH_SIZE,
		"mobs_at_60fps": mobs_at_60fps,
		"mobs_at_30fps": mobs_at_30fps,
		"final_mob_count": final_count,
		"final_fps": final_fps,
		"summary": "mob_ramp  60fps_threshold=%d  30fps_threshold=%d  final_count=%d  final_fps=%.0f" % [
			mobs_at_60fps, mobs_at_30fps, final_count, final_fps],
	}

# ─── Test 3: Tile Flood ────────────────────────────────────────────────────

func _test_tile_flood() -> Dictionary:
	print("[PERF] === tile_flood starting ===")
	const TOTAL_MUTATIONS := 2000
	const CHUNK_SIDE := 16  # Constants.CHUNK_SIZE

	# Ensure chunk (0,0) is loaded
	if not _chunk_manager._loaded_chunks.has(Vector2i(0, 0)):
		_chunk_manager._load_chunk(Vector2i(0, 0))
		await get_tree().process_frame

	var mutated_coords: Array = []

	var frame_start_usec := Time.get_ticks_usec()
	var t0 := Time.get_ticks_usec()

	for i in range(TOTAL_MUTATIONS):
		var lx := i % CHUNK_SIDE
		var ly := (i / CHUNK_SIDE) % CHUNK_SIDE
		var world_coords := Vector2i(lx, ly)  # chunk (0,0) → world == local
		_chunk_manager.place_tile(world_coords, 1, 0, Vector2i(0, 1), 0, "perf_test")
		if not mutated_coords.has(world_coords):
			mutated_coords.append(world_coords)

	var total_usec := Time.get_ticks_usec() - t0
	var frame_cost_usec := Time.get_ticks_usec() - frame_start_usec

	await get_tree().process_frame

	# Cleanup — remove all placed tiles
	for coords in mutated_coords:
		_chunk_manager.remove_tile(coords, 1, "perf_test")

	await get_tree().process_frame

	var total_ms := total_usec / 1000.0
	var frame_cost_ms := frame_cost_usec / 1000.0
	var rate := int(TOTAL_MUTATIONS / (total_ms / 1000.0)) if total_ms > 0 else 0

	print("[PERF] tile_flood  mutations=%d  total=%.1fms  rate=%d/sec  frame_cost=%.1fms" % [
		TOTAL_MUTATIONS, total_ms, rate, frame_cost_ms])

	return {
		"name": "tile_flood",
		"mutations": TOTAL_MUTATIONS,
		"total_ms": total_ms,
		"mutations_per_sec": rate,
		"avg_frame_ms_during": frame_cost_ms,
		"summary": "tile_flood  mutations=%d  total=%.1fms  rate=%d/sec  frame_cost=%.1fms" % [
			TOTAL_MUTATIONS, total_ms, rate, frame_cost_ms],
	}

# ─── Test 4: Chunk Thrash ──────────────────────────────────────────────────

func _test_chunk_thrash() -> Dictionary:
	print("[PERF] === chunk_thrash starting ===")
	const DURATION_S := 20.0
	const TELEPORT_INTERVAL_S := 0.5
	const TILE_SIZE := 16   # Constants.TILE_SIZE
	const CHUNK_SIZE := 16  # Constants.CHUNK_SIZE

	var elapsed_s := 0.0
	var chunk_crossings := 0
	var loads_triggered := 0
	var frame_times: Array = []
	var last_teleport_s := 0.0
	var teleport_index := 0
	var last_queue_size := 0
	var last_progress_s := 0.0

	# Build the 6×6 grid of chunk centers: cx,cy in range(-3, 3)
	var positions: Array = []
	for cy in range(-3, 3):
		for cx in range(-3, 3):
			positions.append(Vector2(
				cx * CHUNK_SIZE * TILE_SIZE + TILE_SIZE * 0.5 * CHUNK_SIZE,
				cy * CHUNK_SIZE * TILE_SIZE + TILE_SIZE * 0.5 * CHUNK_SIZE))

	var test_start_usec := Time.get_ticks_usec()

	while elapsed_s < DURATION_S:
		var frame_t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_elapsed_ms := (Time.get_ticks_usec() - frame_t0) / 1000.0
		frame_times.append(frame_elapsed_ms)

		elapsed_s = (Time.get_ticks_usec() - test_start_usec) / 1_000_000.0

		# Detect load bursts: queue went from 0 → >0
		var q_size := _chunk_manager._load_queue.size()
		if last_queue_size == 0 and q_size > 0:
			loads_triggered += 1
		last_queue_size = q_size

		# Teleport player every 0.5s
		if elapsed_s - last_teleport_s >= TELEPORT_INTERVAL_S:
			last_teleport_s = elapsed_s
			var target_pos: Vector2 = positions[teleport_index % positions.size()]
			teleport_index += 1
			chunk_crossings += 1
			_player.position = target_pos
			var tile_pos := Vector2i(
				int(target_pos.x / TILE_SIZE),
				int(target_pos.y / TILE_SIZE))
			_chunk_manager.update_player_position(tile_pos)

		# Progress print every 5s
		if elapsed_s - last_progress_s >= 5.0:
			last_progress_s = elapsed_s
			var peak_so_far := 0.0
			for ft in frame_times:
				if ft > peak_so_far:
					peak_so_far = ft
			print("[PERF] chunk_thrash  t=%.0fs  crossings=%d  peak=%.1fms" % [
				elapsed_s, chunk_crossings, peak_so_far])

	# Compute stats
	var peak_ms := 0.0
	var sum_ms := 0.0
	for ft in frame_times:
		sum_ms += ft
		if ft > peak_ms:
			peak_ms = ft
	var avg_ms := sum_ms / frame_times.size() if frame_times.size() > 0 else 0.0

	print("[PERF] chunk_thrash  duration=%.0fs  crossings=%d  peak=%.1fms  avg=%.1fms  load_bursts=%d" % [
		DURATION_S, chunk_crossings, peak_ms, avg_ms, loads_triggered])

	return {
		"name": "chunk_thrash",
		"duration_s": DURATION_S,
		"chunk_crossings": chunk_crossings,
		"peak_frame_ms": peak_ms,
		"avg_frame_ms": avg_ms,
		"loads_triggered": loads_triggered,
		"summary": "chunk_thrash  duration=%.0fs  crossings=%d  peak=%.1fms  avg=%.1fms  load_bursts=%d" % [
			DURATION_S, chunk_crossings, peak_ms, avg_ms, loads_triggered],
	}

# ─── Results persistence ───────────────────────────────────────────────────

func _save_results(results: Array) -> void:
	var dir := "user://perf_baselines"
	DirAccess.make_dir_recursive_absolute(dir)
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/%s.json" % [dir, ts]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"timestamp": ts, "tests": results}, "\t"))
		f.close()
		print("[PERF] Results saved to %s" % path)

# ─── Summary printer ──────────────────────────────────────────────────────

func _print_summary(results: Array) -> void:
	print("═══════════════════════════════════════")
	print("PERF TORTURE RESULTS")
	print("═══════════════════════════════════════")
	for r in results:
		print("  %s" % r.get("summary", r.get("name", "?")))
	print("═══════════════════════════════════════")
