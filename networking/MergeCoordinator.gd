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
##   coordinator.presence_service = $UDPPresenceService
##   coordinator.session_id = session.session_id
##   coordinator.connection_needed.connect(_on_connection_needed)
##   coordinator.merge_ready.connect(func(): merge_rpc_bus.send_snapshot(...))
##   coordinator.split_occurred.connect(_on_split)
extends Node

const MergePressureScript   := preload("res://networking/MergePressureSystem.gd")
const BridgeFormationScript := preload("res://networking/BridgeFormation.gd")
const SplitDetectorScript   := preload("res://networking/SplitDetector.gd")

## Emitted when a bridge gate passes — World connects via NetworkManager.
signal connection_needed(remote_ip: String, remote_enet_port: int, i_am_host: bool)
## Emitted after ENet connects and it's time to exchange CRDT snapshots.
signal merge_ready(remote_session_id: String)
## Emitted after SplitDetector threshold is crossed.
signal split_occurred
## Emitted every tick so HUD can display the pressure bar.
signal pressure_changed(pressure: float)

## Set by World from SessionManager.session_id before _ready().
var session_id: String = ""
## Seconds between presence broadcasts (overridden to 1.0 in dev mode).
var broadcast_interval: float = 30.0
## ENet port to advertise in presence broadcasts.
var enet_port: int = 7777
## Assigned by World — UDPPresenceService (or LocalPresenceService in tests).
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

var _merging: bool = false   # connection in-flight
var _merged: bool = false    # live merged session
var _broadcast_timer: float = 0.0

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
		if _split.should_dissolve(_my_chunk, _remote_chunk):
			_do_split()
		return

	if not _merging:
		_pressure.peer_count = 1
		_pressure.tick(delta)
		pressure_changed.emit(_pressure.pressure)

		_broadcast_timer += delta
		if _broadcast_timer >= broadcast_interval and presence_service != null:
			_broadcast_timer = 0.0
			presence_service.publish_presence(session_id, _my_chunk, enet_port)

## Called by Player each chunk-change to keep coordinator position current.
func update_my_chunk(chunk: Vector2i) -> void:
	_my_chunk = chunk
	if presence_service != null:
		presence_service.subscribe_area(session_id, chunk, 50,
			Callable(self, "_on_peer_discovered"))

## Called externally in tests or by presence service directly.
func _on_peer_discovered(remote_sid: String, remote_chunk: Vector2i,
		remote_ip: String, remote_enet_port: int) -> void:
	if _merging or _merged:
		return
	if not _bridge.should_form_bridge(_my_chunk, remote_chunk,
			_pressure.pressure, _pressure.pressure):
		return
	# Phase 5: reputation routing gate — skip if either is unset (backward compat)
	if reputation_store != null and merge_router != null:
		if not merge_router.can_merge(session_id, remote_sid, reputation_store):
			return
	_merging = true
	var i_am_host: bool = session_id < remote_sid
	connection_needed.emit(remote_ip, remote_enet_port, i_am_host)

## Called by World when the ENet peer_connected signal fires.
func on_peer_connected(remote_sid: String, remote_chunk: Vector2i) -> void:
	_remote_session_id = remote_sid
	_remote_chunk = remote_chunk
	_merged = true
	_merging = false
	_pressure.peer_count = 2
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
	split_occurred.emit()
