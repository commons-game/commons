## MergeCoordinator — orchestrates the full merge/split lifecycle.
##
## Responsibilities:
##   - Tick MergePressureSystem while solo
##   - Broadcast presence on a slow timer via the presence service
##   - Evaluate BridgeFormation when a nearby peer is discovered
##   - Emit connection_needed so World can call NetworkManager (decoupled)
##   - Track merged state and run SplitDetector each tick
##   - Reset pressure on split or clean disconnect
##
## Dev mode: set dev_instant_merge = true before adding to the scene tree.
## Pressure starts at 1.0 and broadcast_interval collapses to 1 s.
##
## World wiring:
##   coordinator.presence_service = $FreenetPresenceService
##   coordinator.session_id = session.session_id
##   coordinator.webrtc_pairing_needed.connect(_on_webrtc_pairing_needed)
##   coordinator.merge_ready.connect(func(): merge_rpc_bus.send_snapshot(...))
##   coordinator.split_occurred.connect(_on_split)
extends Node

const MergePressureScript   := preload("res://networking/MergePressureSystem.gd")
const BridgeFormationScript := preload("res://networking/BridgeFormation.gd")
const SplitDetectorScript   := preload("res://networking/SplitDetector.gd")

## Emitted when a bridge gate passes — World starts WebRTCManager offer/answer flow.
signal webrtc_pairing_needed(pairing_key: String, i_am_offerer: bool)
## Emitted after ENet connects and it's time to exchange CRDT snapshots.
signal merge_ready(remote_session_id: String)
## Emitted after SplitDetector threshold is crossed.
## Carries the remote session ID so handlers don't need to reach back into the coordinator.
signal split_occurred(remote_session_id: String)
## Emitted every tick so HUD can display the pressure bar.
signal pressure_changed(pressure: float)

## Set by World from SessionManager.session_id before _ready().
var session_id: String = ""
## Seconds between presence broadcasts (overridden to 1.0 in dev mode).
var broadcast_interval: float = 30.0
## Assigned by World — FreenetPresenceService (or LocalPresenceService in tests).
var presence_service: Object = null
## Phase 5: optional reputation gate. Both must be set for routing to apply.
## If either is null the check is skipped (backward-compat for pre-Phase-5 tests).
var reputation_store: Object = null
var merge_router: Object = null

var _pressure: MergePressureScript
var _bridge: BridgeFormationScript
var _split: SplitDetectorScript

var _my_chunk: Vector2i = Vector2i.ZERO
var _remote_chunk: Vector2i = Vector2i.ZERO
var _remote_session_id: String = ""

## Seconds before an in-flight connection attempt is abandoned and retried.
const MERGING_TIMEOUT := 15.0

## Phase 0d-ii: wall-clock duration over which the lagging clock catches up to
## the leader during a merge. The brief specifies ~10 real seconds; tests
## override via `merge_transition_seconds` to keep scenario runtime short.
var merge_transition_seconds: float = 10.0

var _merging: bool = false         # connection in-flight
var _merging_timer: float = 0.0    # elapsed since _merging = true
var _merged: bool = false          # live merged session
var _broadcast_timer: float = 0.0

## Phase 0d-ii: have we received the remote peer's clock phase yet? merge_ready
## fires before either RPC has landed, so we hold the local-side begin_merge
## until BOTH the local merge_ready handler AND the inbound clock-phase RPC
## have been observed. Both arrive at most once per merge.
var _local_merge_ready: bool = false
var _remote_clock_phase: float = -1.0

## Collapse pressure to 1.0 and use fast broadcast for dev/testing.
## Setter applies the effect immediately so tests that set it after .new()
## (without add_child) see the correct pressure without needing a scene tree.
var dev_instant_merge: bool = false:
	set(value):
		dev_instant_merge = value
		if value and _pressure != null:
			_pressure.pressure = 1.0
			broadcast_interval = 1.0
			_broadcast_timer = broadcast_interval

func _init() -> void:
	_pressure = MergePressureScript.new()
	_bridge   = BridgeFormationScript.new()
	_split    = SplitDetectorScript.new()

func _ready() -> void:
	# Re-apply dev settings in case dev_instant_merge was set before add_child
	# (setter already handles post-new() assignment; this catches pre-tree cases).
	if dev_instant_merge:
		_pressure.pressure = 1.0
		broadcast_interval = 1.0
		_broadcast_timer = broadcast_interval

func _process(delta: float) -> void:
	if _merged:
		# Phase 0d-ii: drive the active island's merge transition each frame.
		# IslandRegistry.tick_merge ticks the active clock so phase_changed
		# fires for any boundary crossings during the ramp; it auto-completes
		# the merge (creates the merged island, swaps active) once the local
		# clock has caught up to the convergence target.
		if IslandRegistry.is_merging():
			IslandRegistry.tick_merge(delta)
		if _split.should_dissolve(_my_chunk, _remote_chunk):
			_do_split()
		return

	if _merging:
		_merging_timer += delta
		if _merging_timer >= MERGING_TIMEOUT:
			push_warning("MergeCoordinator: connection attempt timed out after %.1fs — resetting" \
				% MERGING_TIMEOUT)
			_merging = false
			_merging_timer = 0.0
		return

	_pressure.peer_count = 1
	_pressure.tick(delta)
	pressure_changed.emit(_pressure.pressure)

	_broadcast_timer += delta
	if _broadcast_timer >= broadcast_interval and presence_service != null:
		_broadcast_timer = 0.0
		presence_service.publish_presence(session_id, _my_chunk)

## Called by Player each chunk-change to keep coordinator position current.
func update_my_chunk(chunk: Vector2i) -> void:
	_my_chunk = chunk
	if presence_service != null:
		presence_service.subscribe_area(session_id, chunk, 50,
			Callable(self, "_on_peer_discovered"))

## Called externally in tests or by presence service directly.
## remote_protocol_version defaults to 0 for backward-compat with callers that
## do not yet pass it (e.g. tests using LocalPresenceService).
func _on_peer_discovered(remote_sid: String, remote_chunk: Vector2i,
		remote_ip: String, remote_enet_port: int,
		remote_protocol_version: int = 0) -> void:
	if _merging or _merged:
		return
	# Protocol version gate: refuse to pair with peers on a different version.
	if remote_protocol_version != 0 and remote_protocol_version != GameVersion.PROTOCOL_VERSION:
		push_warning("MergeCoordinator: skipping peer — protocol version mismatch (theirs=%d ours=%d)" % [
			remote_protocol_version, GameVersion.PROTOCOL_VERSION
		])
		return
	if not _bridge.should_form_bridge(_my_chunk, remote_chunk,
			_pressure.pressure, _pressure.pressure):
		return
	# Phase 5: reputation routing gate — skip if either is unset (backward compat)
	if reputation_store != null and merge_router != null:
		if not merge_router.can_merge(session_id, remote_sid, reputation_store):
			return
	_merging = true
	_merging_timer = 0.0
	var i_am_offerer: bool = session_id < remote_sid
	var pairing_key := _make_pairing_key(session_id, remote_sid)
	webrtc_pairing_needed.emit(pairing_key, i_am_offerer)

## Called by World when the ENet peer_connected signal fires.
func on_peer_connected(remote_sid: String, remote_chunk: Vector2i) -> void:
	_remote_session_id = remote_sid
	_remote_chunk = remote_chunk
	_merged = true
	_merging = false
	_pressure.peer_count = 2
	# Phase 0d-ii: kick off the clock-phase exchange. Both peers send their
	# current total_phase; whichever side's RPC arrives second triggers
	# begin_merge on both sides (independently).
	_local_merge_ready = true
	_send_local_clock_phase()
	_maybe_begin_island_merge()
	merge_ready.emit(remote_sid)

## Called by World when the ENet peer_disconnected signal fires.
func on_peer_disconnected() -> void:
	if _merged:
		_do_split()
	else:
		_merging = false

## Called by World when the remote peer's position updates (from synchronizer).
func update_remote_chunk(chunk: Vector2i) -> void:
	_remote_chunk = chunk

## Manually tick the coordinator (used in tests without scene tree).
func tick(delta: float) -> void:
	_process(delta)

# --- Accessors for tests ---

func get_pressure() -> float:
	return _pressure.pressure

func is_merged() -> bool:
	return _merged

func reset_value() -> float:
	return _pressure.reset_value

func get_my_chunk() -> Vector2i:
	return _my_chunk

func get_remote_session_id() -> String:
	return _remote_session_id

# --- Internal ---

func _do_split() -> void:
	_merged = false
	_merging = false
	_split.on_dissolve(_pressure)
	_pressure.peer_count = 1
	# Phase 0d-ii: clear the merge-handshake state so a future re-merge with
	# the same peer doesn't start with stale phase data.
	_local_merge_ready = false
	_remote_clock_phase = -1.0
	# Phase 0d-ii: ask IslandRegistry to fork off a fresh island for us with
	# the current converged clock state preserved (no rewind). Both peers do
	# this independently with their own session-derived id so neither peer
	# ends up on the other's solo island.
	IslandRegistry.split_from_merge(_split_island_id())
	split_occurred.emit(_remote_session_id)

# ---------------------------------------------------------------------------
# Phase 0d-ii: clock-phase exchange + island lifecycle wiring
# ---------------------------------------------------------------------------
#
# When merge_ready fires on this peer:
#   1. We snapshot our active clock's total_phase.
#   2. We RPC it to the remote peer via _receive_clock_phase.
#   3. We attempt _maybe_begin_island_merge — succeeds only if we've ALSO
#      received the remote phase (the remote will RPC us in step 2 of theirs).
#
# When _receive_clock_phase fires on this peer:
#   1. We store the remote phase.
#   2. We attempt _maybe_begin_island_merge — succeeds only if our local
#      merge_ready has also fired.
#
# This handshake is necessary because merge_ready is a local event triggered
# by ENet peer_connected; the remote's clock phase is a separate piece of
# state that arrives via RPC. The two events race and either order is valid.
#
# Test injection: scenarios that don't have a real MultiplayerAPI (e.g. the
# PuppetCluster harness) call inject_remote_clock_phase() directly to bypass
# the RPC and exercise the rest of the orchestration.

## Compute the deterministic merged island id from the two session ids. Both
## peers compute the same id by sorting the two ids lexicographically.
func _merged_island_id() -> String:
	var ids := [session_id, _remote_session_id]
	ids.sort()
	return "merge:" + ids[0] + ":" + ids[1]

## The id our solo island takes when we split off. Stable per session.
func _split_island_id() -> String:
	return "solo:" + session_id

## Send our active island's current total_phase to the remote peer.
func _send_local_clock_phase() -> void:
	var local_total_phase: float = _local_total_phase()
	if is_inside_tree() and multiplayer.has_multiplayer_peer():
		rpc("_receive_clock_phase", local_total_phase)
	# (Tests without an MP peer must call inject_remote_clock_phase() to
	# simulate the inbound RPC; the outbound is a no-op in that path.)

## Read the active island's clock total_phase. Defensive against the unlikely
## case where IslandRegistry hasn't initialised yet (autoload-ordering bugs).
func _local_total_phase() -> float:
	var island = IslandRegistry.active_island()
	if island == null:
		return 0.0
	var clock = island.clock
	return float(clock.day_count()) + clock.phase_fraction()

@rpc("any_peer", "reliable")
func _receive_clock_phase(remote_total_phase: float) -> void:
	_remote_clock_phase = remote_total_phase
	_maybe_begin_island_merge()

## Test hook: inject the remote phase as if it had arrived via _receive_clock_phase.
## Used by PuppetCluster scenarios where there's no real MultiplayerAPI between
## the two in-process peers.
func inject_remote_clock_phase(remote_total_phase: float) -> void:
	_receive_clock_phase(remote_total_phase)

## Begin the island-merge transition once both halves of the handshake have
## arrived (local merge_ready + remote clock-phase RPC). Called from both
## halves; whichever runs second is the one that actually triggers begin_merge.
func _maybe_begin_island_merge() -> void:
	if not _local_merge_ready or _remote_clock_phase < 0.0:
		return
	var merged_id := _merged_island_id()
	IslandRegistry.begin_merge(_remote_clock_phase, merge_transition_seconds, merged_id)
	# One-shot: clear the remote phase so a stuck handshake from a previous
	# session can't replay. Local _local_merge_ready stays true until split
	# (it represents "we are merged", not "we've signalled begin").
	_remote_clock_phase = -1.0

## Called by World when a WebRTC attempt fails — resets so the next presence
## broadcast can retry pairing.
func reset_for_retry() -> void:
	_merging = false
	_merging_timer = 0.0

## Deterministic pairing key: same result regardless of which side computes it.
func _make_pairing_key(sid_a: String, sid_b: String) -> String:
	if sid_a < sid_b:
		return sid_a + ":" + sid_b
	return sid_b + ":" + sid_a
