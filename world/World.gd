## World — root scene. Manages quit persistence and multiplayer bootstrap.
##
## CLI args for local multiplayer simulation:
##   --host [port]        Start as host on given port (default 7777)
##   --join <ip> [port]   Join a host at ip:port (default 127.0.0.1:7777)
##
## Example (two terminals):
##   godot --path . -- --host
##   godot --path . -- --join 127.0.0.1
extends Node2D

const SessionManagerScript  := preload("res://networking/SessionManager.gd")
const RegionAuthorityScript := preload("res://networking/RegionAuthority.gd")
const RemotePlayerScene     := preload("res://player/RemotePlayer.tscn")
const ModEditorScript       := preload("res://mods/ModEditor.gd")

var _session: Object
var _authority: Object
var _remote_players: Dictionary = {}  # peer_id (int) -> RemotePlayer node
var _hud_label: Label               # shows active buffs / shrine status
var _mod_editor: Node               # ModEditor CanvasLayer

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
	# Use get_node() which returns Variant so dynamic signal lookup works.
	get_node("ShrineManager").buffs_changed.connect(_on_buffs_changed)
	_setup_hud()
	_setup_mod_editor()

	# Register spawnable scene programmatically — auto_spawn_list in .tscn is
	# not a valid MultiplayerSpawner property and is silently ignored at runtime.
	$MultiplayerSpawner.add_spawnable_scene("res://player/RemotePlayer.tscn")

	# Bootstrap from CLI args
	var args := OS.get_cmdline_user_args()
	_parse_network_args(args)

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

func _on_peer_disconnected(peer_id: int) -> void:
	_session.remove_peer(str(peer_id))
	print("World: peer left — id=%d  session_peers=%d" % [peer_id, _session.peer_count()])
	if _remote_players.has(peer_id):
		_remote_players[peer_id].queue_free()
		_remote_players.erase(peer_id)
		print("World: removed RemotePlayer for peer %d" % peer_id)

func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	# Semi-transparent background panel
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

func _setup_mod_editor() -> void:
	_mod_editor = ModEditorScript.new()
	add_child(_mod_editor)
	_mod_editor.shrine_manager = get_node("ShrineManager")
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
	# F5 = clean quit for testing via xpra JS keyboard injection
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_notification(NOTIFICATION_WM_CLOSE_REQUEST)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$ChunkManager._persist_all_loaded_chunks()
		NetworkManager.disconnect_all()
		get_tree().quit()
