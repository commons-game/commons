/// Freeland chunk contract.
///
/// Each chunk (x, y) is a separate contract instance.
/// State = LWW-map of tile entries (JSON-encoded ChunkState).
/// Merge = commutative by construction: higher timestamp wins per tile key.
///
/// Contract key = hash(this_wasm || ChunkParameters{x, y})
/// so each chunk coordinate maps to a unique, independently-evictable contract.
use freenet_stdlib::prelude::*;
use freeland_common::{ChunkDelta, ChunkState, ChunkSummary};

/// Tracks breaking changes to the chunk contract WASM.
/// Incrementing this changes the contract instance IDs, making old world data
/// inaccessible (world reset). Increment rarely and document it explicitly.
/// Current: 1 (initial implementation)
pub const CONTRACT_VERSION: u32 = 1;

struct ChunkContract;

#[contract]
impl ContractInterface for ChunkContract {
    /// Validate that state is well-formed JSON encoding a ChunkState.
    /// We do not require cryptographic signatures on tile data — the witness
    /// layer (multi-peer confirmation) handles anti-cheat at a higher level.
    fn validate_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        _related: RelatedContracts<'static>,
    ) -> Result<ValidateResult, ContractError> {
        if state.as_ref().is_empty() {
            // Empty state is valid — contract just created, no tiles yet.
            return Ok(ValidateResult::Valid);
        }
        match serde_json::from_slice::<ChunkState>(state.as_ref()) {
            Ok(_) => Ok(ValidateResult::Valid),
            Err(_) => Err(ContractError::InvalidState),
        }
    }

    /// Merge incoming updates into current state using LWW semantics.
    /// Each UpdateData can be a full State replacement or a Delta (subset of tiles).
    fn update_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        data: Vec<UpdateData<'static>>,
    ) -> Result<UpdateModification<'static>, ContractError> {
        let mut current: ChunkState = if state.as_ref().is_empty() {
            ChunkState::default()
        } else {
            serde_json::from_slice(state.as_ref())
                .map_err(|_| ContractError::InvalidState)?
        };

        for update in data {
            match update {
                UpdateData::State(new_state) => {
                    // Full state replacement: merge into current (LWW per tile).
                    let incoming: ChunkState = serde_json::from_slice(new_state.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                UpdateData::Delta(delta) => {
                    // Delta: a subset of tile entries to merge in.
                    let incoming: ChunkDelta = serde_json::from_slice(delta.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    for (key, entry) in incoming {
                        match current.entries.get(&key) {
                            None => { current.entries.insert(key, entry); }
                            Some(existing) => {
                                if entry.timestamp > existing.timestamp
                                    || (entry.timestamp == existing.timestamp
                                        && entry.author_id > existing.author_id)
                                {
                                    current.entries.insert(key, entry);
                                }
                            }
                        }
                    }
                }
                UpdateData::StateAndDelta { state: s, .. } => {
                    let incoming: ChunkState = serde_json::from_slice(s.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                _ => {} // RelatedState variants — not used for chunks
            }
        }

        let serialized = serde_json::to_vec(&current)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(UpdateModification::valid(State::from(serialized)))
    }

    /// Summary = map of tile_key → timestamp.
    /// Compact: ~8 bytes/tile vs ~100 bytes for a full entry.
    fn summarize_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
    ) -> Result<StateSummary<'static>, ContractError> {
        if state.as_ref().is_empty() {
            let empty: ChunkSummary = Default::default();
            let bytes = serde_json::to_vec(&empty)
                .map_err(|_| ContractError::InvalidState)?;
            return Ok(StateSummary::from(bytes));
        }
        let current: ChunkState = serde_json::from_slice(state.as_ref())
            .map_err(|_| ContractError::InvalidState)?;
        let summary: ChunkSummary = current
            .entries
            .iter()
            .map(|(k, e)| (*k, e.timestamp))
            .collect();
        let bytes = serde_json::to_vec(&summary)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(StateSummary::from(bytes))
    }

    /// Delta = only tiles with timestamp newer than what the peer reported.
    fn get_state_delta(
        _parameters: Parameters<'static>,
        state: State<'static>,
        summary: StateSummary<'static>,
    ) -> Result<StateDelta<'static>, ContractError> {
        if state.as_ref().is_empty() {
            let empty: ChunkDelta = Default::default();
            let bytes = serde_json::to_vec(&empty)
                .map_err(|_| ContractError::InvalidState)?;
            return Ok(StateDelta::from(bytes));
        }
        let current: ChunkState = serde_json::from_slice(state.as_ref())
            .map_err(|_| ContractError::InvalidState)?;
        let peer_summary: ChunkSummary = serde_json::from_slice(summary.as_ref())
            .map_err(|_| ContractError::InvalidState)?;

        let delta: ChunkDelta = current
            .entries
            .iter()
            .filter(|(key, entry)| {
                peer_summary
                    .get(key)
                    .map_or(true, |&peer_ts| entry.timestamp > peer_ts)
            })
            .map(|(k, e)| (*k, e.clone()))
            .collect();

        let bytes = serde_json::to_vec(&delta)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(StateDelta::from(bytes))
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use freeland_common::TileEntry;

    fn tile(timestamp: f64, author: &str) -> TileEntry {
        TileEntry {
            tile_id: 0,
            atlas_x: 1,
            atlas_y: 0,
            alt_tile: 0,
            timestamp,
            author_id: author.to_string(),
        }
    }

    fn state_with(entries: Vec<(u32, TileEntry)>) -> ChunkState {
        ChunkState {
            chunk_x: 0,
            chunk_y: 0,
            world_seed: 12345,
            version: 1,
            entries: entries.into_iter().collect(),
        }
    }

    #[test]
    fn merge_is_commutative() {
        let mut a = state_with(vec![(1, tile(100.0, "alice")), (2, tile(200.0, "alice"))]);
        let b = state_with(vec![(2, tile(300.0, "bob")), (3, tile(150.0, "bob"))]);

        let mut a2 = a.clone();
        let b2 = b.clone();

        a.merge(&b);   // A then B
        a2.merge(&b2); // same, just verifying clone works

        // merge(A, B) == merge(B, A)
        let mut b_copy = state_with(vec![(2, tile(300.0, "bob")), (3, tile(150.0, "bob"))]);
        let a_copy = state_with(vec![(1, tile(100.0, "alice")), (2, tile(200.0, "alice"))]);
        b_copy.merge(&a_copy);

        assert_eq!(a.entries.len(), b_copy.entries.len());
        for key in a.entries.keys() {
            assert_eq!(
                a.entries[key].timestamp,
                b_copy.entries[key].timestamp
            );
        }
    }

    #[test]
    fn merge_higher_timestamp_wins() {
        let mut a = state_with(vec![(1, tile(100.0, "alice"))]);
        let b = state_with(vec![(1, tile(200.0, "bob"))]);
        a.merge(&b);
        assert_eq!(a.entries[&1].author_id, "bob");
        assert_eq!(a.entries[&1].timestamp, 200.0);
    }

    #[test]
    fn merge_tie_broken_by_author_id() {
        let mut a = state_with(vec![(1, tile(100.0, "alice"))]);
        let b = state_with(vec![(1, tile(100.0, "bob"))]); // same timestamp, "bob" > "alice"
        a.merge(&b);
        assert_eq!(a.entries[&1].author_id, "bob");
    }

    #[test]
    fn merge_identity() {
        let mut a = state_with(vec![(1, tile(100.0, "alice"))]);
        let empty = ChunkState::default();
        let original = a.clone();
        a.merge(&empty);
        assert_eq!(a.entries.len(), original.entries.len());
        assert_eq!(a.entries[&1].author_id, "alice");
    }

    #[test]
    fn merge_is_associative() {
        let a = state_with(vec![(1, tile(100.0, "alice"))]);
        let b = state_with(vec![(1, tile(200.0, "bob")), (2, tile(50.0, "bob"))]);
        let c = state_with(vec![(2, tile(75.0, "carol")), (3, tile(300.0, "carol"))]);

        // (A merge B) merge C
        let mut ab = a.clone();
        ab.merge(&b);
        ab.merge(&c);

        // A merge (B merge C)
        let mut bc = b.clone();
        bc.merge(&c);
        let mut a_bc = a.clone();
        a_bc.merge(&bc);

        assert_eq!(ab.entries.len(), a_bc.entries.len());
        for key in ab.entries.keys() {
            assert_eq!(ab.entries[key].timestamp, a_bc.entries[key].timestamp);
            assert_eq!(ab.entries[key].author_id, a_bc.entries[key].author_id);
        }
    }

    #[test]
    fn delta_only_contains_newer_entries() {
        let state = state_with(vec![
            (1, tile(100.0, "alice")),
            (2, tile(200.0, "alice")),
            (3, tile(300.0, "alice")),
        ]);
        // Peer already has tile 1 at ts=100 and tile 2 at ts=150 (older)
        let peer_summary: ChunkSummary = [(1, 100.0), (2, 150.0)].into_iter().collect();

        let serialized_state = serde_json::to_vec(&state).unwrap();
        let serialized_summary = serde_json::to_vec(&peer_summary).unwrap();

        let delta_bytes = ChunkContract::get_state_delta(
            Parameters::from(vec![]),
            State::from(serialized_state),
            StateSummary::from(serialized_summary),
        ).unwrap();

        let delta: ChunkDelta = serde_json::from_slice(delta_bytes.as_ref()).unwrap();
        // tile 1: peer has ts=100, state has ts=100 → NOT in delta
        // tile 2: peer has ts=150, state has ts=200 → IN delta
        // tile 3: peer doesn't have it → IN delta
        assert!(!delta.contains_key(&1));
        assert!(delta.contains_key(&2));
        assert!(delta.contains_key(&3));
    }
}
