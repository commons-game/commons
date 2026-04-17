/// Freeland lobby contract.
///
/// Single global contract instance (LobbyParameters { lobby_id: GLOBAL_LOBBY_ID }).
/// State = LWW-map of session_id → LobbyEntry (player presence).
/// Merge = commutative by construction: higher timestamp wins per session_id.
///
/// Stale entries (older than LOBBY_TTL_SECS) are evicted on every update_state
/// call so the contract size stays bounded regardless of churn.
///
/// Contract key = hash(this_wasm || LobbyParameters{lobby_id: "freeland-global-v1"})
/// All players worldwide share the same contract key → same Freenet DHT slot.
use freenet_stdlib::prelude::*;
use freeland_common::{LobbyDelta, LobbyState, LobbySummary, LOBBY_TTL_SECS};

struct LobbyContract;

#[contract]
impl ContractInterface for LobbyContract {
    /// Validate that state is well-formed JSON encoding a LobbyState.
    fn validate_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        _related: RelatedContracts<'static>,
    ) -> Result<ValidateResult, ContractError> {
        if state.as_ref().is_empty() {
            return Ok(ValidateResult::Valid);
        }
        match serde_json::from_slice::<LobbyState>(state.as_ref()) {
            Ok(_) => Ok(ValidateResult::Valid),
            Err(_) => Err(ContractError::InvalidState),
        }
    }

    /// Merge incoming updates using LWW semantics, then evict stale entries.
    fn update_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        data: Vec<UpdateData<'static>>,
    ) -> Result<UpdateModification<'static>, ContractError> {
        let mut current: LobbyState = if state.as_ref().is_empty() {
            LobbyState::default()
        } else {
            serde_json::from_slice(state.as_ref())
                .map_err(|_| ContractError::InvalidState)?
        };

        for update in data {
            match update {
                UpdateData::State(new_state) => {
                    let incoming: LobbyState = serde_json::from_slice(new_state.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                UpdateData::Delta(delta) => {
                    let incoming: LobbyDelta = serde_json::from_slice(delta.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    let patch = LobbyState { entries: incoming };
                    current.merge(&patch);
                }
                UpdateData::StateAndDelta { state: s, .. } => {
                    let incoming: LobbyState = serde_json::from_slice(s.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                _ => {}
            }
        }

        // Evict stale entries to keep contract size bounded.
        // Use a fixed "now" approximation: max timestamp across all entries + 0
        // (we have no wall clock in WASM). Instead we rely on the proxy to send
        // real timestamps; entries that are LOBBY_TTL_SECS behind the freshest
        // entry are considered stale.
        let max_ts = current
            .entries
            .values()
            .map(|e| e.timestamp)
            .fold(f64::NEG_INFINITY, f64::max);
        if max_ts > f64::NEG_INFINITY {
            current.entries.retain(|_, e| max_ts - e.timestamp < LOBBY_TTL_SECS);
        }

        let serialized = serde_json::to_vec(&current)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(UpdateModification::valid(State::from(serialized)))
    }

    /// Summary = map of session_id → timestamp.
    fn summarize_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
    ) -> Result<StateSummary<'static>, ContractError> {
        if state.as_ref().is_empty() {
            let empty: LobbySummary = Default::default();
            let bytes = serde_json::to_vec(&empty)
                .map_err(|_| ContractError::InvalidState)?;
            return Ok(StateSummary::from(bytes));
        }
        let current: LobbyState = serde_json::from_slice(state.as_ref())
            .map_err(|_| ContractError::InvalidState)?;
        let summary: LobbySummary = current
            .entries
            .iter()
            .map(|(sid, e)| (sid.clone(), e.timestamp))
            .collect();
        let bytes = serde_json::to_vec(&summary)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(StateSummary::from(bytes))
    }

    /// Delta = entries newer than what the peer reported in its summary.
    fn get_state_delta(
        _parameters: Parameters<'static>,
        state: State<'static>,
        summary: StateSummary<'static>,
    ) -> Result<StateDelta<'static>, ContractError> {
        if state.as_ref().is_empty() {
            let empty: LobbyDelta = Default::default();
            let bytes = serde_json::to_vec(&empty)
                .map_err(|_| ContractError::InvalidState)?;
            return Ok(StateDelta::from(bytes));
        }
        let current: LobbyState = serde_json::from_slice(state.as_ref())
            .map_err(|_| ContractError::InvalidState)?;
        let peer_summary: LobbySummary = serde_json::from_slice(summary.as_ref())
            .map_err(|_| ContractError::InvalidState)?;

        let delta: LobbyDelta = current
            .entries
            .iter()
            .filter(|(sid, entry)| {
                peer_summary
                    .get(*sid)
                    .is_none_or(|&peer_ts| entry.timestamp > peer_ts)
            })
            .map(|(sid, e)| (sid.clone(), e.clone()))
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
    use freeland_common::LobbyEntry;

    fn entry(session_id: &str, timestamp: f64) -> LobbyEntry {
        LobbyEntry {
            session_id: session_id.to_string(),
            chunk_x: 0,
            chunk_y: 0,
            ip: "192.168.1.1".to_string(),
            enet_port: 7777,
            timestamp,
            protocol_version: 0,
        }
    }

    fn state_with(entries: Vec<LobbyEntry>) -> LobbyState {
        LobbyState {
            entries: entries.into_iter().map(|e| (e.session_id.clone(), e)).collect(),
        }
    }

    #[test]
    fn merge_higher_timestamp_wins() {
        let mut a = state_with(vec![entry("alice", 100.0)]);
        let b = state_with(vec![entry("alice", 200.0)]);
        a.merge(&b);
        assert_eq!(a.entries["alice"].timestamp, 200.0);
    }

    #[test]
    fn merge_keeps_lower_when_winning() {
        let mut a = state_with(vec![entry("alice", 300.0)]);
        let b = state_with(vec![entry("alice", 100.0)]);
        a.merge(&b);
        assert_eq!(a.entries["alice"].timestamp, 300.0);
    }

    #[test]
    fn merge_adds_new_session() {
        let mut a = state_with(vec![entry("alice", 100.0)]);
        let b = state_with(vec![entry("bob", 100.0)]);
        a.merge(&b);
        assert_eq!(a.entries.len(), 2);
    }

    #[test]
    fn merge_is_commutative() {
        let a = state_with(vec![entry("alice", 100.0), entry("bob", 50.0)]);
        let b = state_with(vec![entry("bob", 200.0), entry("carol", 75.0)]);

        let mut ab = a.clone();
        ab.merge(&b);

        let mut ba = b.clone();
        ba.merge(&a);

        assert_eq!(ab.entries.len(), ba.entries.len());
        for sid in ab.entries.keys() {
            assert_eq!(ab.entries[sid].timestamp, ba.entries[sid].timestamp);
        }
    }

    #[test]
    fn evict_stale_removes_old_entries() {
        let now = 1000.0;
        let mut state = state_with(vec![
            entry("fresh", now - 10.0),
            entry("stale", now - LOBBY_TTL_SECS - 1.0),
        ]);
        state.evict_stale(now);
        assert!(state.entries.contains_key("fresh"));
        assert!(!state.entries.contains_key("stale"));
    }

    #[test]
    fn delta_only_contains_newer_entries() {
        let state = state_with(vec![
            entry("alice", 100.0),
            entry("bob", 200.0),
            entry("carol", 300.0),
        ]);
        // Peer already has alice at ts=100 and bob at ts=150 (older than 200)
        let peer_summary: LobbySummary = [
            ("alice".to_string(), 100.0),
            ("bob".to_string(), 150.0),
        ].into_iter().collect();

        let serialized_state = serde_json::to_vec(&state).unwrap();
        let serialized_summary = serde_json::to_vec(&peer_summary).unwrap();

        let delta_bytes = LobbyContract::get_state_delta(
            Parameters::from(vec![]),
            State::from(serialized_state),
            StateSummary::from(serialized_summary),
        ).unwrap();

        let delta: LobbyDelta = serde_json::from_slice(delta_bytes.as_ref()).unwrap();
        assert!(!delta.contains_key("alice"));  // peer already has current ts
        assert!(delta.contains_key("bob"));     // peer is behind
        assert!(delta.contains_key("carol"));   // peer doesn't know carol
    }
}
