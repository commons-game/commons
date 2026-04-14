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

var _session: Object
var _authority: Object

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

func _on_peer_disconnected(peer_id: int) -> void:
	_session.remove_peer(str(peer_id))
	print("World: peer left — id=%d  session_peers=%d" % [peer_id, _session.peer_count()])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$ChunkManager._persist_all_loaded_chunks()
		NetworkManager.disconnect_all()
		get_tree().quit()
