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

var _session: Object
var _authority: Object
var _remote_players: Dictionary = {}  # peer_id (int) -> RemotePlayer node

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
	bus.local_author_id = "player_local"   # Phase 5+: use real player id

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

func _on_peer_connected(peer_id: int) -> void:
	_session.add_peer(str(peer_id))
	print("World: peer joined — id=%d  session_peers=%d" % [peer_id, _session.peer_count()])
	if multiplayer.is_server():
		# Host spawns a RemotePlayer node representing the new client.
		# MultiplayerSpawner replicates it; the client's synchronizer drives position.
		var remote := RemotePlayerScene.instantiate()
		remote.name = "RemotePlayer_%d" % peer_id
		remote.set_multiplayer_authority(peer_id)
		_remote_players[peer_id] = remote
		add_child(remote)
		print("World: spawned RemotePlayer for peer %d" % peer_id)
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$ChunkManager._persist_all_loaded_chunks()
		NetworkManager.disconnect_all()
		get_tree().quit()
