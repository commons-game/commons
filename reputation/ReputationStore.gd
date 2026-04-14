## ReputationStore — in-memory report and chaos-pool state.
## Extended by LocalBackend for disk persistence; used directly in tests.
##
## Design:
##   - Each (reporter, target) pair counts once (spam prevention).
##   - Self-reports are silently ignored.
##   - Players auto-promoted to chaos pool when report_count >= REPORT_THRESHOLD.
##   - opt_into_chaos_pool() allows voluntary promotion regardless of count.
##   - No bans — chaos pool is a routing preference, not a punishment.
class_name ReputationStore

const REPORT_THRESHOLD := 3

# target_id -> { report_count: int, in_chaos_pool: bool }
var _records: Dictionary = {}

# target_id -> Set of reporter_ids (Dictionary used as set)
var _reporters: Dictionary = {}

func submit_report(reporter_id: String, target_id: String, _reason: String) -> void:
	if reporter_id == target_id:
		return
	if not _reporters.has(target_id):
		_reporters[target_id] = {}
	if _reporters[target_id].has(reporter_id):
		return  # already reported by this player
	_reporters[target_id][reporter_id] = true
	_ensure_record(target_id)
	_records[target_id]["report_count"] += 1
	if _records[target_id]["report_count"] >= REPORT_THRESHOLD:
		_records[target_id]["in_chaos_pool"] = true

func opt_into_chaos_pool(player_id: String) -> void:
	_ensure_record(player_id)
	_records[player_id]["in_chaos_pool"] = true

func is_in_chaos_pool(player_id: String) -> bool:
	return _records.get(player_id, {}).get("in_chaos_pool", false)

func get_report_count(player_id: String) -> int:
	return _records.get(player_id, {}).get("report_count", 0)

func get_reputation_flags(player_id: String) -> Dictionary:
	return {
		"report_count": get_report_count(player_id),
		"in_chaos_pool": is_in_chaos_pool(player_id)
	}

## Serialise the full store to a plain Dictionary (for Backend persistence).
func to_dict() -> Dictionary:
	return {"records": _records.duplicate(true), "reporters": _reporters.duplicate(true)}

## Restore state from a Dictionary previously returned by to_dict().
## Safe to call with an empty dict (no-op).
func from_dict(data: Dictionary) -> void:
	_records   = (data.get("records",   {}) as Dictionary).duplicate(true)
	_reporters = (data.get("reporters", {}) as Dictionary).duplicate(true)

func _ensure_record(player_id: String) -> void:
	if not _records.has(player_id):
		_records[player_id] = {"report_count": 0, "in_chaos_pool": false}
