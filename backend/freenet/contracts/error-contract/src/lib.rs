/// Commons error-report contract.
///
/// A global contract that accumulates opt-in crash/error telemetry.
/// State = LWW-map of "session_id:error_hash" → ErrorReport.
/// Merge = on collision keep the entry with the higher `ts` (unix seconds).
///
/// Privacy guarantee: contains no player names, positions, chat, world data,
/// or persistent player IDs.  session_id is a random UUID reset each launch.
use freenet_stdlib::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ErrorReport {
    pub error_type: String,
    pub file: String,
    pub line: i32,
    pub phase: String,
    pub game_version: String,
    pub platform: String,
    pub godot_version: String,
    pub ts: f64,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct ErrorContractState {
    /// key: "session_id:error_hash"
    pub reports: HashMap<String, ErrorReport>,
}

impl ErrorContractState {
    /// LWW merge: for each key keep the entry with the higher `ts`.
    pub fn merge(&mut self, other: &ErrorContractState) {
        for (key, other_report) in &other.reports {
            match self.reports.get(key) {
                None => {
                    self.reports.insert(key.clone(), other_report.clone());
                }
                Some(existing) => {
                    if other_report.ts > existing.ts {
                        self.reports.insert(key.clone(), other_report.clone());
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Contract implementation
// ---------------------------------------------------------------------------

struct ErrorContract;

#[contract]
impl ContractInterface for ErrorContract {
    /// Validate that state is well-formed JSON encoding an ErrorContractState.
    fn validate_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        _related: RelatedContracts<'static>,
    ) -> Result<ValidateResult, ContractError> {
        if state.as_ref().is_empty() {
            return Ok(ValidateResult::Valid);
        }
        match serde_json::from_slice::<ErrorContractState>(state.as_ref()) {
            Ok(_) => Ok(ValidateResult::Valid),
            Err(_) => Err(ContractError::InvalidState),
        }
    }

    /// Merge incoming updates into current state using LWW semantics on `ts`.
    fn update_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        data: Vec<UpdateData<'static>>,
    ) -> Result<UpdateModification<'static>, ContractError> {
        let mut current: ErrorContractState = if state.as_ref().is_empty() {
            ErrorContractState::default()
        } else {
            serde_json::from_slice(state.as_ref())
                .map_err(|_| ContractError::InvalidState)?
        };

        for update in data {
            match update {
                UpdateData::State(new_state) => {
                    let incoming: ErrorContractState = serde_json::from_slice(new_state.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                UpdateData::Delta(delta) => {
                    let incoming: ErrorContractState = serde_json::from_slice(delta.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                UpdateData::StateAndDelta { state: s, .. } => {
                    let incoming: ErrorContractState = serde_json::from_slice(s.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                _ => {}
            }
        }

        let serialized = serde_json::to_vec(&current)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(UpdateModification::valid(State::from(serialized)))
    }

    /// Summary = report count encoded as 8 little-endian bytes.
    fn summarize_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
    ) -> Result<StateSummary<'static>, ContractError> {
        if state.as_ref().is_empty() {
            return Ok(StateSummary::from(0u64.to_le_bytes().to_vec()));
        }
        let current: ErrorContractState = serde_json::from_slice(state.as_ref())
            .map_err(|_| ContractError::InvalidState)?;
        let count = current.reports.len() as u64;
        Ok(StateSummary::from(count.to_le_bytes().to_vec()))
    }

    /// Delta = full state (every report may be needed by peers that have none).
    fn get_state_delta(
        _parameters: Parameters<'static>,
        state: State<'static>,
        _summary: StateSummary<'static>,
    ) -> Result<StateDelta<'static>, ContractError> {
        if state.as_ref().is_empty() {
            let empty = ErrorContractState::default();
            let bytes = serde_json::to_vec(&empty)
                .map_err(|_| ContractError::InvalidState)?;
            return Ok(StateDelta::from(bytes));
        }
        Ok(StateDelta::from(state.as_ref().to_vec()))
    }

}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn report(ts: f64) -> ErrorReport {
        ErrorReport {
            error_type: "webrtc_timeout".into(),
            file: "networking/MergeCoordinator.gd".into(),
            line: 0,
            phase: "connecting".into(),
            game_version: "dev".into(),
            platform: "Linux".into(),
            godot_version: "4.3".into(),
            ts,
        }
    }

    #[test]
    fn merge_keeps_higher_ts() {
        let mut a = ErrorContractState::default();
        a.reports.insert("s1:abc123".into(), report(100.0));

        let mut b = ErrorContractState::default();
        b.reports.insert("s1:abc123".into(), report(200.0));

        a.merge(&b);
        assert_eq!(a.reports["s1:abc123"].ts, 200.0);
    }

    #[test]
    fn merge_does_not_overwrite_with_lower_ts() {
        let mut a = ErrorContractState::default();
        a.reports.insert("s1:abc123".into(), report(200.0));

        let mut b = ErrorContractState::default();
        b.reports.insert("s1:abc123".into(), report(100.0));

        a.merge(&b);
        assert_eq!(a.reports["s1:abc123"].ts, 200.0);
    }

    #[test]
    fn merge_adds_new_keys() {
        let mut a = ErrorContractState::default();
        a.reports.insert("s1:aaa".into(), report(100.0));

        let mut b = ErrorContractState::default();
        b.reports.insert("s2:bbb".into(), report(200.0));

        a.merge(&b);
        assert_eq!(a.reports.len(), 2);
    }

    #[test]
    fn summarize_returns_count_bytes() {
        let mut state = ErrorContractState::default();
        state.reports.insert("s1:a".into(), report(1.0));
        state.reports.insert("s2:b".into(), report(2.0));
        let bytes = serde_json::to_vec(&state).unwrap();

        let summary = ErrorContract::summarize_state(
            Parameters::from(vec![]),
            State::from(bytes),
        )
        .unwrap();
        let count = u64::from_le_bytes(summary.as_ref().try_into().unwrap());
        assert_eq!(count, 2);
    }
}
