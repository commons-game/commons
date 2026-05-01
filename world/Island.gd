## Island — a single "reality bubble".
##
## Each island owns its own DayClockInstance and tracks which sessions/peers
## are currently part of it. Phase 0b of the per-island clock refactor: the
## type exists and is registered, but no production code resolves through it
## yet. Phase 0c will wire DayClock callsites to resolve through the local
## player's island; Phase 0d will wire MergeCoordinator merge/split events to
## drive island lifecycle.
##
## Held as RefCounted (not Node) for the same reason DayClockInstance is —
## it's a value object owned by IslandRegistry, not a scene-tree participant.
## The owner must call clock.tick(delta) each frame for phase_changed signals
## to fire (the autoload wrapper does this in Phase 0c).
extends RefCounted

const DayClockInstanceScript := preload("res://world/DayClockInstance.gd")

var id: String
## Member session ids. Phase 0c/0d will define exactly what shape this is —
## for now it's a session_id string (matching what NetworkManager hands out
## and what MergeCoordinator already keys on).
var members: Array[String] = []
## The island's clock. Typed as RefCounted because DayClockInstance is not a
## globally-registered class_name; preload the script where you need the type.
var clock: RefCounted

func _init(island_id: String) -> void:
	id = island_id
	clock = DayClockInstanceScript.new()

func add_member(session_id: String) -> void:
	if not members.has(session_id):
		members.append(session_id)

func remove_member(session_id: String) -> void:
	members.erase(session_id)

func has_member(session_id: String) -> bool:
	return members.has(session_id)
