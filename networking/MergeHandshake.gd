## MergeHandshake — propose/accept CRDT exchange for session merging.
##
## Sessions exchange snapshots of their CRDT tile store as plain Dictionaries.
## Each key maps to a record: { "tile_id": String, "ts": float }.
## accept_merge() performs LWW: higher timestamp wins per key.
##
## Usage:
##   var proposal = handshake.propose_merge(session_id, local_crdt, local_peers)
##   # (send proposal to remote peer via TileMutationBus / RPC)
##   var merged   = handshake.accept_merge(remote_proposal, local_crdt)
##   var peers    = handshake.get_combined_peers(local_peers, remote_proposal["peers"])
class_name MergeHandshake

func propose_merge(session_id: String, crdt_snapshot: Dictionary,
		peers: Array) -> Dictionary:
	return {
		"session_id": session_id,
		"crdt": crdt_snapshot.duplicate(true),
		"peers": peers.duplicate()
	}

## Merge a remote proposal's CRDT data with local CRDT data using LWW.
## Returns the merged dictionary (does not modify either input).
func accept_merge(proposal: Dictionary, local_crdt: Dictionary) -> Dictionary:
	var remote_crdt: Dictionary = proposal.get("crdt", {})
	var merged: Dictionary = local_crdt.duplicate(true)
	for key in remote_crdt:
		if not merged.has(key):
			merged[key] = remote_crdt[key].duplicate()
		else:
			var local_ts: float = float(merged[key].get("ts", 0))
			var remote_ts: float = float(remote_crdt[key].get("ts", 0))
			if remote_ts > local_ts:
				merged[key] = remote_crdt[key].duplicate()
	return merged

## Returns the union of two peer id lists with no duplicates.
func get_combined_peers(local_peers: Array, remote_peers: Array) -> Array:
	var seen: Dictionary = {}
	for p in local_peers:
		seen[p] = true
	for p in remote_peers:
		seen[p] = true
	return seen.keys()
