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
##   --dev-render-gym           Load render gym: one of every tile type shown, verify atlas
##   --dev-world-stats          Generate 100 chunks, print density histogram, quit
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
const NecromancerPackScript       := preload("res://mods/builtin/NecromancerPack.gd")
const AlchemistPackScript         := preload("res://mods/builtin/AlchemistPack.gd")
const GravestoneScatterScript     := preload("res://world/generation/GravestoneScatter.gd")
const MobSpawnerScript            := preload("res://world/mobs/MobSpawner.gd")
const EquipmentUIScript           := preload("res://ui/EquipmentUI.gd")

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
	_register_wasd()

	# Dev scene switches — bail out before any normal setup.
	var _early_args := OS.get_cmdline_user_args()
	if OS.get_name() != "Web":
		if "--dev-gym" in _early_args:
			get_tree().change_scene_to_file.call_deferred("res://dev/GymScene.tscn")
			return
		if "--dev-render-gym" in _early_args:
			get_tree().change_scene_to_file.call_deferred("res://dev/RenderGym.tscn")
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

	# Wire ShrineManager signals → HUD and Player appearance
	var sm := $ShrineManager as ShrineManagerScript
	sm.buffs_changed.connect(_on_buffs_changed)
	sm.buffs_changed.connect($Player._on_buffs_changed)
	_setup_hud()
	_setup_mod_editor()
	_setup_builtin_mods()

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
	_setup_equipment_ui()
	_assert_layer_order()
	if not is_web and "--dev-screenshot-cycle" in args:
		_run_screenshot_cycle.call_deferred()
	if not is_web and "--dev-world-stats" in args:
		_run_world_stats.call_deferred()
	if not is_web and "--dev-health-check" in args:
		_health_check_timer = 0.0
		print("HealthCheck: running 30s check, screenshot every 5s")
	# Dev content auto-enables in debug builds (editor / godot4 --path).
	# Pass --no-dev to suppress when you want a clean debug start.
	var dev_mode := not is_web and (OS.is_debug_build() or "--dev-necro-shrine" in args) \
	               and not "--no-dev" in args
	if dev_mode:
		_place_necro_shrine_at_spawn.call_deferred()
	if not is_web and "--dev-alch-shrine" in args:
		_place_alch_shrine_nearby.call_deferred()
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
			var obj_cells: int = chunk.object_layer.get_used_cells().size()
			var phys_layers: int = chunk.object_layer.tile_set.get_physics_layers_count()
			lines.append("Obj tiles: %d  phys_layers: %d" % [obj_cells, phys_layers])
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
	_action_bar.player = $Player
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

## Add WASD keys to the built-in ui_left/right/up/down actions at runtime.
## Avoids editing project.godot; safe to call multiple times (has_action guards).
func _register_wasd() -> void:
	var map := {
		"ui_left":  KEY_A,
		"ui_right": KEY_D,
		"ui_up":    KEY_W,
		"ui_down":  KEY_S,
	}
	for action in map:
		var ev := InputEventKey.new()
		ev.keycode = map[action]
		# Only add if not already present (idempotent across scene reloads)
		var already := false
		for existing in InputMap.action_get_events(action):
			if existing is InputEventKey and (existing as InputEventKey).keycode == map[action]:
				already = true
				break
		if not already:
			InputMap.action_add_event(action, ev)

## Auto-place a necromancer shrine at spawn for visual dev testing.
## Run with: DISPLAY=:100 ./freeland.x86_64 --rendering-driver opengl3 -- --dev-necro-shrine --dev-health-check
func _place_necro_shrine_at_spawn() -> void:
	var json := FileAccess.get_file_as_string("res://mods/bundles/necromancer.json")
	if json.is_empty():
		push_error("_place_necro_shrine_at_spawn: failed to read necromancer.json")
		return
	var sm := $ShrineManager as ShrineManagerScript
	var shrine_id := sm.place_shrine(Vector2i.ZERO, json, "dev")
	print("DevNecroShrine: placed shrine '%s' at origin — walk into chunk (0,0) to activate" % shrine_id)
	# Wait two frames so ChunkManager has loaded the initial chunks around spawn.
	await get_tree().process_frame
	await get_tree().process_frame
	_scatter_gravestones_near(Vector2i.ZERO)

func _scatter_gravestones_near(shrine_chunk: Vector2i) -> void:
	var cm := $ChunkManager as ChunkManager
	var placed := GravestoneScatterScript.scatter(cm, shrine_chunk, Constants.WORLD_SEED)
	print("NecroShrine: scattered %d gravestones near chunk %s" % [placed, shrine_chunk])
	# Drop a bone_armor pickup just east of the shrine
	cm.place_tile(Vector2i(3, 0), 1, 0, Vector2i(3, 1), 0, "world_gen")
	print("NecroShrine: placed bone_armor loot tile at (3,0)")
	# Spawn 3 mobs near the necromancer shrine
	var spawner := MobSpawnerScript.new()
	spawner.name = "MobSpawner"
	add_child(spawner)
	spawner.spawn(Vector2i(0, 0), 3, 8, $ChunkManager, $Player, self)

## Place alchemist shrine one chunk east of spawn for side-by-side mod testing.
func _place_alch_shrine_nearby() -> void:
	var json := FileAccess.get_file_as_string("res://mods/bundles/alchemist.json")
	if json.is_empty():
		push_error("_place_alch_shrine_nearby: failed to read alchemist.json")
		return
	var sm := $ShrineManager as ShrineManagerScript
	# Place one chunk east so you can walk between necromancer and alchemist territories
	var tile_pos := Vector2i(Constants.CHUNK_SIZE, 0)
	var shrine_id := sm.place_shrine(tile_pos, json, "dev")
	print("DevAlchShrine: placed shrine '%s' — walk east ~%d tiles to enter" % [shrine_id, Constants.CHUNK_SIZE])

func _setup_builtin_mods() -> void:
	var necro := NecromancerPackScript.new()
	necro.name = "NecromancerPack"
	add_child(necro)
	var alch := AlchemistPackScript.new()
	alch.name = "AlchemistPack"
	add_child(alch)

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

## --dev-world-stats: generate a 10×10 grid of chunks, print density histogram, quit.
## Use this whenever you change ProceduralGenerator thresholds or noise types to
## verify density is in the expected range without needing to load the full game.
func _run_world_stats() -> void:
	const RADIUS := 5           # 10×10 = 100 chunks
	const EXPECTED_TREE_PCT := 10.0   # warn if mean tree density on grass drops below this
	print("WorldStats: sampling %d chunks (seed=%d)…" % [(RADIUS * 2) * (RADIUS * 2), Constants.WORLD_SEED])

	var total_tiles   := 0
	var total_grass   := 0
	var total_dirt    := 0
	var total_stone   := 0
	var total_water   := 0
	var total_trees   := 0
	var total_rocks   := 0
	var min_trees     := 9999
	var max_trees     := 0
	var zero_tree_chunks := 0
	var chunk_count   := 0

	for cy in range(-RADIUS, RADIUS):
		for cx in range(-RADIUS, RADIUS):
			var entries := ProceduralGenerator.generate_chunk(
				Vector2i(cx, cy), Constants.WORLD_SEED)
			var grass := 0; var dirt := 0; var stone := 0; var water := 0
			var trees := 0; var rocks := 0
			for k in entries:
				var layer := (int(k) >> 16) & 0xFF
				var ax: int = entries[k]["atlas_x"]
				if layer == 0:
					match ax:
						0: grass += 1
						1: dirt  += 1
						2: stone += 1
						3: water += 1
				elif layer == 1:
					if ax == 0: trees += 1
					else:        rocks += 1
			total_grass += grass; total_dirt += dirt
			total_stone += stone; total_water += water
			total_trees += trees; total_rocks += rocks
			total_tiles += entries.size()
			if trees == 0: zero_tree_chunks += 1
			if trees < min_trees: min_trees = trees
			if trees > max_trees: max_trees = trees
			chunk_count += 1

	var pct := func(n: int) -> String:
		return "%.1f%%" % (100.0 * n / total_tiles)

	print("─────────────────────────────────────")
	print("WorldStats: %d chunks  %d total tiles" % [chunk_count, total_tiles])
	print("  grass  %5d  %s" % [total_grass,  pct.call(total_grass)])
	print("  dirt   %5d  %s" % [total_dirt,   pct.call(total_dirt)])
	print("  stone  %5d  %s" % [total_stone,  pct.call(total_stone)])
	print("  water  %5d  %s" % [total_water,  pct.call(total_water)])
	print("  trees  %5d  %s  (per-chunk: min=%d max=%d mean=%.1f)" % [
		total_trees, pct.call(total_trees),
		min_trees, max_trees, float(total_trees) / chunk_count])
	print("  rocks  %5d  %s  (per-chunk mean=%.1f)" % [
		total_rocks, pct.call(total_rocks), float(total_rocks) / chunk_count])
	print("  zero-tree chunks: %d/%d (%.0f%%)" % [
		zero_tree_chunks, chunk_count, 100.0 * zero_tree_chunks / chunk_count])
	if total_grass > 0:
		var tree_on_grass := 100.0 * total_trees / total_grass
		print("  tree density on grass: %.1f%%" % tree_on_grass)
		if tree_on_grass < EXPECTED_TREE_PCT:
			push_error("WorldStats: tree density %.1f%% < expected %.1f%% — check generator" \
				% [tree_on_grass, EXPECTED_TREE_PCT])
	print("─────────────────────────────────────")
	get_tree().quit()

func _setup_equipment_ui() -> void:
	var ui := EquipmentUIScript.new()
	ui.name = "EquipmentUI"
	add_child(ui)
	ui.call("init", $Player)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$ChunkManager._persist_all_loaded_chunks()
		if _reputation_store != null:
			Backend.save_reputation(_reputation_store.to_dict())
		# Save equipment state for the local player.
		var player_eq = $Player.get("equipment")
		if player_eq != null:
			var eq_data: Dictionary = player_eq.call("to_dict")
			Backend.save_equipment(eq_data)
		NetworkManager.disconnect_all()
		get_tree().quit()
