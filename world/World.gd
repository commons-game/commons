## World — root scene. Manages quit persistence and multiplayer bootstrap.
##
## CLI args for local multiplayer simulation:
##   --host [port]              Start as ENet host on given port (default 7777)
##   --join <ip> [port]         Join a host at ip:port (default 127.0.0.1:7777)
##   --dev-instant-merge        Enable instant-merge dev mode (pressure=1, fast broadcast)
##   --dev-screenshot-cycle     Step through 24 day phases, screenshot each, quit
##   --dev-health-check         Run 30s, screenshot every 5s, quit (regression check)
##   --dev-frame-log            Log CanvasModulate + chunk weight every frame (visual bug hunting)
##   --dev-gym                  Load collision gym scene: player inside rock box, verify collision
##
## In-game dev keys:
##   F1    Toggle debug overlay (FPS, phase, chunk weight, vibe, tool, merge pressure)
##   F12   Save numbered screenshot to /tmp/freeland_screenshot_NNN.png
##
## Phase 4 merge lifecycle (auto-discovery, no manual --host/--join needed):
##   UDPPresenceService broadcasts presence → MergeCoordinator discovers peers →
##   connection_needed → NetworkManager.host/join → ENet peer_connected →
##   MergeRPCBus hello exchange → on_peer_connected → merge_ready →
##   send_snapshot → merge_applied.
extends Node2D

const SessionManagerScript        := preload("res://networking/SessionManager.gd")
const RegionAuthorityScript       := preload("res://networking/RegionAuthority.gd")
const RemotePlayerScene           := preload("res://player/RemotePlayer.tscn")
const ModEditorScript             := preload("res://mods/ModEditor.gd")
const ShrineManagerScript         := preload("res://mods/ShrineManager.gd")
const MergeCoordinatorScript      := preload("res://networking/MergeCoordinator.gd")
const UDPPresenceServiceScript    := preload("res://networking/UDPPresenceService.gd")
const MergeRPCBusScript           := preload("res://networking/MergeRPCBus.gd")
const ReputationStoreScript       := preload("res://reputation/ReputationStore.gd")
const MergeRouterScript           := preload("res://reputation/MergeRouter.gd")
const VibeBusScript               := preload("res://world/VibeBus.gd")
const DayNightSystemScript        := preload("res://world/DayNightSystem.gd")
const ActionBarHUDScript          := preload("res://ui/ActionBarHUD.gd")

var _session: Object
var _authority: Object
var _remote_players: Dictionary = {}  # peer_id (int) -> RemotePlayer node
var _hud_label: Label                    # shows active buffs / shrine status
var _merge_label: Label                  # shows merge pressure / state
var _clock_label: Label                  # shows day phase + time-of-day
var _debug_overlay: CanvasLayer = null   # F1 debug overlay
var _debug_label: Label = null           # multi-line debug stats
var _debug_visible: bool = false
var _mod_editor: ModEditorScript         # in-game mod authoring overlay
var _coordinator: Node = null
var _rpc_bus: Node = null
var _reputation_store: ReputationStoreScript = null
var _vibe_bus: Node = null
var _canvas_modulate: CanvasModulate = null
var _action_bar: Node = null
var _screenshot_counter: int = 0
var _dev_frame_log: bool = false         # --dev-frame-log: log every frame
var _health_check_timer: float = -1.0    # --dev-health-check: auto screenshot + quit
var _health_check_counter: int = 0

func _ready() -> void:
	get_tree().auto_accept_quit = false

	# --dev-gym: switch to the collision gym scene immediately, skip all normal setup.
	var _early_args := OS.get_cmdline_user_args()
	if "--dev-gym" in _early_args and OS.get_name() != "Web":
		get_tree().change_scene_to_file.call_deferred("res://dev/GymScene.tscn")
		return

	_session   = SessionManagerScript.new()
	_authority = RegionAuthorityScript.new()

	# Wire NetworkManager signals → SessionManager / RegionAuthority
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)

	# Wire TileMutationBus to ChunkManager as its tile store
	var bus: Node = $TileMutationBus
	bus.tile_store      = $ChunkManager
	bus.local_author_id = PlayerIdentity.id

	# Wire ShrineManager signals → HUD
	var sm := $ShrineManager as ShrineManagerScript
	sm.buffs_changed.connect(_on_buffs_changed)
	_setup_hud()
	_setup_mod_editor()

	# Register spawnable scene programmatically — auto_spawn_list in .tscn is
	# not a valid MultiplayerSpawner property and is silently ignored at runtime.
	$MultiplayerSpawner.add_spawnable_scene("res://player/RemotePlayer.tscn")

	# Bootstrap from CLI args
	var args := OS.get_cmdline_user_args()
	var is_web := OS.get_name() == "Web"
	if not is_web:
		_parse_network_args(args)
		_setup_merge_system(args)
	_setup_action_bar()
	_setup_day_night_system()
	_setup_debug_overlay()
	_assert_layer_order()
	if not is_web and "--dev-screenshot-cycle" in args:
		_run_screenshot_cycle.call_deferred()
	if not is_web and "--dev-health-check" in args:
		_health_check_timer = 0.0
		print("HealthCheck: running 30s check, screenshot every 5s")
	if not is_web and "--dev-frame-log" in args:
		_dev_frame_log = true
		print("FrameLog: per-frame visual logging enabled")

func _parse_network_args(args: Array) -> void:
	if args.is_empty():
		return
	var i := 0
	while i < args.size():
		match args[i]:
			"--host":
				var port := NetworkManager.DEFAULT_PORT
				if i + 1 < args.size() and args[i + 1].is_valid_int():
					i += 1
					port = int(args[i])
				NetworkManager.host(port)
				_session.start_session()
				_spawn_remote_player(1)  # host's own representation for clients
			"--join":
				var ip   := "127.0.0.1"
				var port := NetworkManager.DEFAULT_PORT
				if i + 1 < args.size() and not args[i + 1].begins_with("--"):
					i += 1
					ip = args[i]
				if i + 1 < args.size() and args[i + 1].is_valid_int():
					i += 1
					port = int(args[i])
				NetworkManager.join(ip, port)
				_session.start_session()
		i += 1

func _setup_merge_system(args: Array) -> void:
	# Reputation — load persisted state before wiring coordinator
	_reputation_store = ReputationStoreScript.new()
	_reputation_store.from_dict(Backend.load_reputation())
	var reputation_router := MergeRouterScript.new()

	var presence := UDPPresenceServiceScript.new()
	presence.name = "UDPPresenceService"

	_coordinator = MergeCoordinatorScript.new()
	_coordinator.name = "MergeCoordinator"
	_coordinator.session_id = _session.session_id
	_coordinator.enet_port = NetworkManager.DEFAULT_PORT
	_coordinator.presence_service = presence
	_coordinator.reputation_store = _reputation_store
	_coordinator.merge_router     = reputation_router
	if "--dev-instant-merge" in args:
		_coordinator.dev_instant_merge = true

	_rpc_bus = MergeRPCBusScript.new()
	_rpc_bus.name = "MergeRPCBus"
	_rpc_bus.chunk_manager = $ChunkManager

	_coordinator.connection_needed.connect(_on_connection_needed)
	_coordinator.merge_ready.connect(_on_merge_ready)
	_coordinator.split_occurred.connect(_on_split_occurred)
	_coordinator.pressure_changed.connect(_on_pressure_changed)
	_rpc_bus.hello_received.connect(_on_hello_received)
	_rpc_bus.merge_applied.connect(_on_merge_applied)

	# Add to tree after all properties are set (triggers _ready() on each node)
	add_child(presence)
	add_child(_coordinator)
	add_child(_rpc_bus)

	# Give Player a reference so it can call update_my_chunk on chunk change
	$Player.coordinator = _coordinator

func _setup_debug_overlay() -> void:
	_debug_overlay = CanvasLayer.new()
	_debug_overlay.layer = 20   # above everything
	_debug_overlay.name = "DebugOverlay"
	add_child(_debug_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bg.custom_minimum_size = Vector2(320, 200)
	bg.position = Vector2(-324, 4)
	_debug_overlay.add_child(bg)
	_debug_label = Label.new()
	_debug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_label.position = Vector2(-320, 8)
	_debug_label.custom_minimum_size = Vector2(316, 196)
	_debug_label.add_theme_font_size_override("font_size", 11)
	_debug_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_debug_label.text = ""
	_debug_overlay.add_child(_debug_label)
	_debug_overlay.hide()

func _build_debug_text() -> String:
	var lines: Array = []
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	# Day/night
	var phase := DayClock.phase_fraction()
	lines.append("Phase: %.4f  sky_a: %.2f" % [phase, DayClock.sky_alpha()])
	# CanvasModulate
	if _canvas_modulate != null:
		var c := _canvas_modulate.color
		lines.append("CanvasMod: (%.2f, %.2f, %.2f)" % [c.r, c.g, c.b])
	# Player chunk + weight + z_index
	var player := $Player as Node2D
	lines.append("Player z: %d  pos: (%.0f,%.0f)" % [player.z_index, player.global_position.x, player.global_position.y])
	var last_chunk = player.get("_last_chunk")
	if last_chunk != null:
		lines.append("Chunk: %s" % str(last_chunk))
		var chunk = $ChunkManager.get_chunk(last_chunk)
		if chunk != null:
			lines.append("Weight: %.3f  mods: %d" % [chunk.weight, chunk.modification_count])
			lines.append("Fading: %s" % str(chunk.is_fading))
	# VibeBus
	if _vibe_bus != null:
		lines.append("Tension: %.2f  Tone: %.2f" % [_vibe_bus.get_tension(), _vibe_bus.get_tone()])
	# Active tool
	var inv = player.get("inventory")
	if inv != null:
		var tool: Dictionary = inv.get_active_tool()
		lines.append("Tool: %s" % (str(tool.get("id", "—")) if not tool.is_empty() else "—"))
	# Coordinator
	if _coordinator != null:
		lines.append("Merged: %s  P: %.2f" % [str(_coordinator.is_merged()), _coordinator.get_pressure()])
	lines.append("")
	lines.append("[F1 to hide]")
	return "\n".join(lines)

func _setup_action_bar() -> void:
	_action_bar = ActionBarHUDScript.new()
	_action_bar.name = "ActionBarHUD"
	_action_bar.inventory = $Player.inventory
	add_child(_action_bar)
	_action_bar.refresh()

func _setup_day_night_system() -> void:
	# CanvasModulate tints all 2D content for the day/night visual.
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "CanvasModulate"
	_canvas_modulate.color = Color.WHITE  # DayNightSystem drives this each frame
	add_child(_canvas_modulate)

	_vibe_bus = VibeBusScript.new()
	_vibe_bus.name = "VibeBus"
	add_child(_vibe_bus)

	var dns := DayNightSystemScript.new()
	dns.name = "DayNightSystem"
	dns.canvas_modulate = _canvas_modulate
	dns.vibe_bus = _vibe_bus
	add_child(dns)

func _spawn_remote_player(peer_id: int) -> void:
	var remote := RemotePlayerScene.instantiate()
	remote.name = "RemotePlayer_%d" % peer_id
	remote.set_multiplayer_authority(peer_id)
	_remote_players[peer_id] = remote
	add_child(remote)
	print("World: spawned RemotePlayer_%d" % peer_id)

func _on_peer_connected(peer_id: int) -> void:
	_session.add_peer(str(peer_id))
	print("World: peer joined — id=%d  session_peers=%d" % [peer_id, _session.peer_count()])
	if multiplayer.is_server():
		# Host spawns a RemotePlayer node representing the new client.
		# MultiplayerSpawner replicates it; the client's synchronizer drives position.
		_spawn_remote_player(peer_id)
	else:
		# Client: assert authority over our own Player so the synchronizer
		# sends our position to the host (and on to other peers).
		var own_id := multiplayer.get_unique_id()
		$Player.set_multiplayer_authority(own_id)
		print("World: set Player authority → %d" % own_id)
	# Phase 4: exchange hello for CRDT merge handshake
	if _rpc_bus != null and _coordinator != null:
		_rpc_bus.send_hello(_session.session_id, _coordinator.get_my_chunk())

func _on_peer_disconnected(peer_id: int) -> void:
	_session.remove_peer(str(peer_id))
	print("World: peer left — id=%d  session_peers=%d" % [peer_id, _session.peer_count()])
	if _remote_players.has(peer_id):
		_remote_players[peer_id].queue_free()
		_remote_players.erase(peer_id)
		print("World: removed RemotePlayer for peer %d" % peer_id)
	if _coordinator != null:
		_coordinator.on_peer_disconnected()

# ---------------------------------------------------------------------------
# Phase 4 merge signal handlers
# ---------------------------------------------------------------------------

func _on_connection_needed(remote_ip: String, remote_enet_port: int, i_am_host: bool) -> void:
	print("World: merge connection needed — ip=%s port=%d host=%s" \
		% [remote_ip, remote_enet_port, str(i_am_host)])
	if i_am_host:
		NetworkManager.host(remote_enet_port)
	else:
		NetworkManager.join(remote_ip, remote_enet_port)

func _on_hello_received(remote_sid: String, remote_chunk: Vector2i) -> void:
	if _coordinator != null:
		_coordinator.on_peer_connected(remote_sid, remote_chunk)

func _on_merge_ready(_remote_session_id: String) -> void:
	print("World: merge_ready — sending snapshot")
	if _rpc_bus != null:
		_rpc_bus.send_snapshot()

func _on_merge_applied() -> void:
	print("World: merge_applied")
	_merge_label.text = "[Merged — R: report]"

func _on_split_occurred() -> void:
	print("World: split occurred")
	_merge_label.text = ""
	NetworkManager.disconnect_all()

func _on_pressure_changed(pressure: float) -> void:
	if _coordinator != null and not _coordinator.is_merged():
		_merge_label.text = "[Seeking: %.0f%%]" % (pressure * 100.0)
	# Loneliness / seeking energy feeds tension into the vibe.
	if _vibe_bus != null:
		_vibe_bus.push("merge_pressure", pressure * 0.4, 0.0, 5.0)

func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	# Semi-transparent background panel (shrine / buff row)
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg.position = Vector2(4, 4)
	bg.custom_minimum_size = Vector2(280, 28)
	bg.modulate = Color(0, 0, 0, 0.55)
	hud.add_child(bg)
	_hud_label = Label.new()
	_hud_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud_label.position = Vector2(8, 8)
	_hud_label.add_theme_font_size_override("font_size", 14)
	_hud_label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	_hud_label.text = ""
	hud.add_child(_hud_label)
	# Merge pressure / state row (below shrine row)
	var merge_bg := Panel.new()
	merge_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	merge_bg.position = Vector2(4, 36)
	merge_bg.custom_minimum_size = Vector2(220, 24)
	merge_bg.modulate = Color(0, 0, 0, 0.55)
	hud.add_child(merge_bg)
	_merge_label = Label.new()
	_merge_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_merge_label.position = Vector2(8, 40)
	_merge_label.add_theme_font_size_override("font_size", 12)
	_merge_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	_merge_label.text = ""
	hud.add_child(_merge_label)
	# Clock row — shows current day phase and time-of-day label
	var clock_bg := Panel.new()
	clock_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	clock_bg.position = Vector2(4, 64)
	clock_bg.custom_minimum_size = Vector2(220, 24)
	clock_bg.modulate = Color(0, 0, 0, 0.55)
	hud.add_child(clock_bg)
	_clock_label = Label.new()
	_clock_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_clock_label.position = Vector2(8, 68)
	_clock_label.add_theme_font_size_override("font_size", 12)
	_clock_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_clock_label.text = ""
	hud.add_child(_clock_label)

func _setup_mod_editor() -> void:
	_mod_editor = ModEditorScript.new()
	add_child(_mod_editor)
	_mod_editor.shrine_manager = $ShrineManager as ShrineManagerScript
	_mod_editor.player         = $Player

func _on_buffs_changed(buffs: Array) -> void:
	if buffs.is_empty():
		_hud_label.text = "[Shrine: inactive]"
	else:
		var names := []
		for b in buffs:
			names.append(b["buff_id"])
		_hud_label.text = "[Shrine active] Buffs: %s" % ", ".join(names)

func _process(delta: float) -> void:
	if _clock_label == null:
		return
	var phase := DayClock.phase_fraction()
	var tod: String
	if phase < 0.12:
		tod = "dawn"
	elif phase < 0.30:
		tod = "morning"
	elif phase < 0.45:
		tod = "afternoon"
	elif phase < 0.55:
		tod = "dusk"
	elif phase < 0.70:
		tod = "evening"
	elif phase < 0.80:
		tod = "midnight"
	else:
		tod = "night"
	_clock_label.text = "[%.3f — %s]" % [phase, tod]

	# --- F1 debug overlay ---
	if _debug_visible and _debug_label != null:
		_debug_label.text = _build_debug_text()

	# --- --dev-frame-log ---
	if _dev_frame_log and _canvas_modulate != null:
		var c := _canvas_modulate.color
		var player_chunk = ($Player as Node2D).get("_last_chunk")  # Variant — .get() is always Variant
		var cw_text := ""
		if player_chunk != null:
			var chunk = $ChunkManager.get_chunk(player_chunk)
			if chunk != null:
				cw_text = "  chunk_w=%.2f" % chunk.weight
		print("FRAME: phase=%.4f cm=(%.2f,%.2f,%.2f)%s" % [phase, c.r, c.g, c.b, cw_text])

	# --- --dev-health-check ---
	if _health_check_timer >= 0.0:
		_health_check_timer += delta
		var interval := 5.0
		var total := 30.0
		var expected_shot := int(_health_check_timer / interval)
		if expected_shot > _health_check_counter:
			_health_check_counter = expected_shot
			var img := get_viewport().get_texture().get_image()
			var path := "/tmp/freeland_health_%02d_t%.0fs.png" % [_health_check_counter, _health_check_timer]
			img.save_png(path)
			print("HealthCheck [%d/6] t=%.1fs → %s" % [_health_check_counter, _health_check_timer, path])
		if _health_check_timer >= total:
			print("HealthCheck complete — %d screenshots in /tmp/freeland_health_*.png" % _health_check_counter)
			get_tree().quit()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_F1:
			_debug_visible = not _debug_visible
			if _debug_overlay != null:
				if _debug_visible:
					_debug_overlay.show()
				else:
					_debug_overlay.hide()
		KEY_F5:
			# Clean quit for testing via xpra JS keyboard injection
			_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		KEY_F12:
			# Save screenshot to /tmp/freeland_screenshot_NNN.png
			_screenshot_counter += 1
			var img := get_viewport().get_texture().get_image()
			var path := "/tmp/freeland_screenshot_%03d.png" % _screenshot_counter
			img.save_png(path)
			_merge_label.text = "[Screenshot %03d]" % _screenshot_counter
			print("Screenshot: %s" % path)
		KEY_R:
			# Report the currently-merged peer
			if _coordinator != null and _coordinator.is_merged() \
					and _reputation_store != null:
				var remote_sid: String = _coordinator.get_remote_session_id()
				if not remote_sid.is_empty():
					_reputation_store.submit_report(
						_session.session_id, remote_sid, "player report")
					Backend.save_reputation(_reputation_store.to_dict())
					_merge_label.text = "[Reported]"
					print("World: reported peer %s" % remote_sid)

## --dev-screenshot-cycle: step DayClock through a full cycle, capture one
## screenshot per step, then quit. Output: /tmp/freeland_cycle_NN_phaseX.XXX.png
## Steps = 24 gives one shot per "game hour" (each phase-increment = 1/24).
func _run_screenshot_cycle() -> void:
	const STEPS := 24
	print("Screenshot cycle: capturing %d frames..." % (STEPS + 1))
	for i in range(STEPS + 1):
		var phase := float(i) / float(STEPS)
		DayClock._time_override = phase * Constants.DAY_CYCLE_SECONDS
		# Let DayNightSystem._process fire so CanvasModulate updates
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "/tmp/freeland_cycle_%02d_phase%.3f.png" % [i, phase]
		img.save_png(path)
		print("  [%02d/24] phase=%.3f → %s" % [i, phase, path])
	print("Screenshot cycle complete.")
	get_tree().quit()

## Verify rendering layer invariants at startup.
## Called from _ready() so misconfiguration is caught immediately rather than
## discovered by eye during gameplay. push_error is non-fatal so the game still
## runs — you'll see the warning in stdout/stderr.
func _assert_layer_order() -> void:
	var player := $Player as Node2D
	if player.z_index <= 1:
		push_error("Layer order broken: Player.z_index=%d should be > 1 (ObjectLayer=1)" % player.z_index)
	# First loaded chunk ground/object layers are checked once they exist.
	# Use call_deferred so ChunkManager has had time to load the first chunk.
	_check_chunk_layer_order.call_deferred()

func _check_chunk_layer_order() -> void:
	var cm := $ChunkManager as ChunkManager
	var coords: Array = cm.get_loaded_chunk_coords()
	if coords.is_empty():
		return
	var chunk: ChunkData = cm.get_chunk(coords[0])
	if chunk == null:
		return
	if chunk.ground_layer.z_index != 0:
		push_error("Layer order: GroundLayer.z_index=%d (expected 0)" % chunk.ground_layer.z_index)
	if chunk.object_layer.z_index != 1:
		push_error("Layer order: ObjectLayer.z_index=%d (expected 1)" % chunk.object_layer.z_index)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$ChunkManager._persist_all_loaded_chunks()
		if _reputation_store != null:
			Backend.save_reputation(_reputation_store.to_dict())
		NetworkManager.disconnect_all()
		get_tree().quit()
