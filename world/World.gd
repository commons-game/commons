## World — root scene. Manages quit persistence and multiplayer bootstrap.
##
## CLI args for local multiplayer simulation:
##   --host [port]              Start as ENet host on given port (default 7777)
##   --join <ip> [port]         Join a host at ip:port (default 127.0.0.1:7777)
##   --dev-instant-merge        Enable instant-merge dev mode (pressure=1, fast broadcast)
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

var _session: Object
var _authority: Object
var _remote_players: Dictionary = {}  # peer_id (int) -> RemotePlayer node
var _hud_label: Label                    # shows active buffs / shrine status
var _merge_label: Label                  # shows merge pressure / state
var _mod_editor: ModEditorScript         # in-game mod authoring overlay
var _coordinator: Node = null
var _rpc_bus: Node = null
var _reputation_store: ReputationStoreScript = null

func _ready() -> void:
	get_tree().auto_accept_quit = false

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
	_parse_network_args(args)
	_setup_merge_system(args)

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

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_F5:
			# Clean quit for testing via xpra JS keyboard injection
			_notification(NOTIFICATION_WM_CLOSE_REQUEST)
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$ChunkManager._persist_all_loaded_chunks()
		if _reputation_store != null:
			Backend.save_reputation(_reputation_store.to_dict())
		NetworkManager.disconnect_all()
		get_tree().quit()
