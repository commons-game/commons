## EventLog — append-only JSONL session log.
##
## Every interesting event gets one line in `user://logs/events_<unix>.jsonl`.
## Each line is a self-contained JSON object with a timestamp, frame number,
## event type, and event-specific fields. This is the authoritative record
## of what happened in a session — used for bug reports, Puppet assertions,
## and offline analysis.
##
## Public API:
##   EventLog.record("tile_place", {"coords": Vector2i, "layer": int, ...})
##   EventLog.set_enabled(false)         — silence logging (tests may disable)
##   EventLog.log_file_path() -> String   — current log file path
##   EventLog.snapshot() -> Array         — all events this session (in-memory)
##
## Note: `record` rather than `log` because Godot has a global `log()` math
## function. `log_file_path` rather than `get_path` because Node.get_path() is
## already defined and returns a NodePath.
##
## Hook points live in the callers — EventLog itself only writes. Keep the
## event vocabulary documented in docs/dev_testing.md.
extends Node

signal event_logged(event_type: String, data: Dictionary)

var _enabled: bool = true
var _file: FileAccess = null
var _path: String = ""
var _frame: int = 0
var _events: Array = []   # in-memory mirror; used by Puppet for assertions

const MAX_IN_MEMORY := 2000  # cap so a long session doesn't OOM

func _ready() -> void:
	var logs_dir := "user://logs"
	if not DirAccess.dir_exists_absolute(logs_dir):
		DirAccess.make_dir_recursive_absolute(logs_dir)
	var t := int(Time.get_unix_time_from_system())
	_path = "%s/events_%d.jsonl" % [logs_dir, t]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("EventLog: could not open %s for writing" % _path)
		return
	record("session_start", {"unix_time": t})

func _process(_delta: float) -> void:
	_frame += 1

func record(event_type: String, data: Dictionary = {}) -> void:
	if not _enabled or _file == null:
		return
	var line := _serialize(event_type, data)
	_file.store_line(line)
	_file.flush()  # small write volume; flush every event for crash-safety
	if _events.size() < MAX_IN_MEMORY:
		_events.append({"type": event_type, "data": data, "frame": _frame})
	event_logged.emit(event_type, data)

func set_enabled(v: bool) -> void:
	_enabled = v

func log_file_path() -> String:
	return _path

func snapshot() -> Array:
	return _events.duplicate()

## Filter in-memory events by type. Useful for Puppet assertions.
## Returns an Array of {type, data, frame} entries.
func events_of(event_type: String) -> Array:
	return _events.filter(func(e): return e.get("type", "") == event_type)

func _serialize(event_type: String, data: Dictionary) -> String:
	var entry := {
		"t": Time.get_unix_time_from_system(),
		"frame": _frame,
		"type": event_type,
		"data": _sanitize(data),
	}
	return JSON.stringify(entry)

## Vector2i and similar non-JSON-native types need converting.
func _sanitize(data: Dictionary) -> Dictionary:
	var out := {}
	for k in data.keys():
		var v = data[k]
		if v is Vector2i:
			out[k] = [v.x, v.y]
		elif v is Vector2:
			out[k] = [v.x, v.y]
		elif v is Dictionary:
			out[k] = _sanitize(v)
		else:
			out[k] = v
	return out
