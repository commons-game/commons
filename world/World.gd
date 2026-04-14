## World — root scene. Manages quit persistence.
## auto_accept_quit = false so we can persist chunks on quit (Phase 1).
extends Node2D

func _ready() -> void:
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$ChunkManager._persist_all_loaded_chunks()
		get_tree().quit()
