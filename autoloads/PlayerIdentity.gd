## PlayerIdentity — persistent player UUID.
##
## Generates a UUID v4 on first run, stores it in user://player_identity.cfg,
## and loads the same ID on every subsequent run.
##
## Usage:
##   PlayerIdentity.id  →  "a3f1c2d4-..."
##
## Phase 6+: replace storage with Freenet node key derivation.
extends Node

const _STORAGE_PATH := "user://player_identity.cfg"

var id: String = ""

func _ready() -> void:
	id = _load_or_generate(_STORAGE_PATH)
	print("PlayerIdentity: id=%s" % id)

## Load from path if it exists; otherwise generate, persist, and return.
## Accepts a custom path so unit tests can use a temp file.
func _load_or_generate(path: String) -> String:
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var stored := f.get_line().strip_edges()
			f.close()
			if not stored.is_empty():
				return stored
	var new_id := _generate_uuid()
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw:
		fw.store_line(new_id)
		fw.close()
	return new_id

## Generate a random UUID v4.
func _generate_uuid() -> String:
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = randi() % 256
	b[6] = (b[6] & 0x0F) | 0x40  # version 4
	b[8] = (b[8] & 0x3F) | 0x80  # variant bits
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0],  b[1],  b[2],  b[3],
		b[4],  b[5],
		b[6],  b[7],
		b[8],  b[9],
		b[10], b[11], b[12], b[13], b[14], b[15]
	]
