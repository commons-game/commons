## RemotePlayer — visual representation of a connected peer.
## No input handling. Position is driven by MultiplayerSynchronizer.
## Extends Node2D (not CharacterBody2D) so it never participates in physics.
extends Node2D

func _ready() -> void:
	# Authority isn't preserved by MultiplayerSpawner replication; re-derive it
	# from the node name convention "RemotePlayer_<peer_id>".
	var parts := name.split("_")
	if parts.size() == 2 and parts[1].is_valid_int():
		set_multiplayer_authority(int(parts[1]))

	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.property_set_spawn(NodePath(".:position"), true)
	config.property_set_sync(NodePath(".:position"), true)
	$MultiplayerSynchronizer.replication_config = config

func _draw() -> void:
	draw_rect(Rect2(-8, -8, 16, 16), Color.CYAN)

func _process(_delta: float) -> void:
	queue_redraw()
	if Engine.get_process_frames() % 30 == 0:
		print("RemotePlayer %s pos=%.1f,%.1f authority=%d" % [name, position.x, position.y, get_multiplayer_authority()])
