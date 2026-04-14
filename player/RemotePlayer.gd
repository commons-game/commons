## RemotePlayer — visual representation of a connected peer.
## No input handling. Position is driven by MultiplayerSynchronizer.
extends CharacterBody2D

func _ready() -> void:
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.property_set_spawn(NodePath(".:position"), true)
	config.property_set_sync(NodePath(".:position"), true)
	$MultiplayerSynchronizer.replication_config = config

func _draw() -> void:
	draw_rect(Rect2(-8, -8, 16, 16), Color.CYAN)
