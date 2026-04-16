## ErrorReporter — opt-in crash telemetry.
##
## Consent stored in user://telemetry_consent.cfg
## Pending reports survive crashes in user://pending_errors.json
##
## Collected: error type, file, line, game phase, game/platform/Godot version,
##            unix timestamp, random per-session ID (not PlayerIdentity.id)
## Never collected: names, positions, chat, world data, server addresses
extends Node

const CONSENT_PATH  := "user://telemetry_consent.cfg"
const PENDING_PATH  := "user://pending_errors.json"
const GAME_VERSION  := "dev"  ## replaced with commit hash at export

signal consent_changed(opted_in: bool)

var opted_in:      bool   = false
var consent_asked: bool   = false
var _session_id:   String = ""
var phase:         String = "startup"

func _ready() -> void:
	_session_id = _random_uuid()
	_load_consent()
	if opted_in:
		_upload_pending.call_deferred()

func set_phase(p: String) -> void:
	phase = p

func report(error_type: String, file: String, line: int) -> void:
	var entry := {
		"session_id":    _session_id,
		"error_hash":    _hash6(error_type + file + str(line)),
		"error_type":    error_type,
		"file":          file,
		"line":          line,
		"phase":         phase,
		"game_version":  GAME_VERSION,
		"platform":      OS.get_name(),
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"ts":            Time.get_unix_time_from_system(),
	}
	_append_pending(entry)
	if opted_in:
		_try_upload_one(entry)

func set_consent(value: bool) -> void:
	opted_in      = value
	consent_asked = true
	_save_consent()
	if not value:
		_clear_pending()
	else:
		_upload_pending.call_deferred()
	consent_changed.emit(opted_in)

func needs_consent_prompt() -> bool:
	return not consent_asked

# ── pending queue ──────────────────────────────────────────────────────────

func _append_pending(entry: Dictionary) -> void:
	var q := _load_pending()
	q.append(entry)
	_save_pending(q)

func _upload_pending() -> void:
	var q := _load_pending()
	if q.is_empty():
		return
	var remaining: Array = []
	for entry in q:
		var ok: bool = await _try_upload_one(entry)
		if not ok:
			remaining.append(entry)
	_save_pending(remaining)

func _try_upload_one(entry: Dictionary) -> bool:
	var backend := get_node_or_null("/root/Backend")
	if backend == null or not backend.has_method("report_error"):
		return false
	return await backend.report_error(entry)

func _load_pending() -> Array:
	if not FileAccess.file_exists(PENDING_PATH):
		return []
	var f := FileAccess.open(PENDING_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Array else []

func _save_pending(entries: Array) -> void:
	var f := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(entries))
	f.close()

func _clear_pending() -> void:
	if FileAccess.file_exists(PENDING_PATH):
		var abs := ProjectSettings.globalize_path(PENDING_PATH)
		DirAccess.remove_absolute(abs)

# ── consent persistence ────────────────────────────────────────────────────

func _load_consent() -> void:
	if not FileAccess.file_exists(CONSENT_PATH):
		return
	var f := FileAccess.open(CONSENT_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		opted_in      = d.get("opted_in", false)
		consent_asked = d.get("asked",    false)

func _save_consent() -> void:
	var f := FileAccess.open(CONSENT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"opted_in": opted_in, "asked": consent_asked}))
	f.close()

# ── helpers ────────────────────────────────────────────────────────────────

func _random_uuid() -> String:
	var b := func() -> String: return "%02x" % (randi() % 256)
	return "%s%s%s%s-%s%s-%s%s-%s%s-%s%s%s%s%s%s" % [
		b.call(), b.call(), b.call(), b.call(),
		b.call(), b.call(),
		b.call(), b.call(),
		b.call(), b.call(),
		b.call(), b.call(), b.call(), b.call(), b.call(), b.call(),
	]

func _hash6(s: String) -> String:
	var h: int = 5381
	for c in s.to_utf8_buffer():
		h = ((h << 5) + h) ^ c
	return "%06x" % (h & 0xFFFFFF)
