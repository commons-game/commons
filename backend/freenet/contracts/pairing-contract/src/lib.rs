/// Freeland pairing contract — WebRTC signaling exchange for NAT traversal.
///
/// One contract instance per player pair, keyed by PairingParameters { pairing_key }.
/// The pairing key is "{min_sid}:{max_sid}" — both players compute the same key.
///
/// Flow:
///   1. Offerer writes PairingState { offer: Some(...), answer: None }
///   2. Answerer reads offer, writes PairingState { answer: Some(...) }
///      (contract merge keeps both offer and answer)
///   3. Offerer reads answer, applies remote description — connection forms.
///
/// Contract is ephemeral: entries older than PAIRING_TTL_SECS are evicted.
use freenet_stdlib::prelude::*;
#[allow(unused_imports)] // PAIRING_TTL_SECS used in #[cfg(test)] only
use freeland_common::{PairingState, PairingSummary, PAIRING_TTL_SECS};

struct PairingContract;

#[contract]
impl ContractInterface for PairingContract {
    fn validate_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        _related: RelatedContracts<'static>,
    ) -> Result<ValidateResult, ContractError> {
        if state.as_ref().is_empty() {
            return Ok(ValidateResult::Valid);
        }
        match serde_json::from_slice::<PairingState>(state.as_ref()) {
            Ok(_) => Ok(ValidateResult::Valid),
            Err(_) => Err(ContractError::InvalidState),
        }
    }

    fn update_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        data: Vec<UpdateData<'static>>,
    ) -> Result<UpdateModification<'static>, ContractError> {
        let mut current: PairingState = if state.as_ref().is_empty() {
            PairingState::default()
        } else {
            serde_json::from_slice(state.as_ref())
                .map_err(|_| ContractError::InvalidState)?
        };

        for update in data {
            match update {
                UpdateData::State(new_state) => {
                    let incoming: PairingState = serde_json::from_slice(new_state.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                UpdateData::StateAndDelta { state: s, .. } => {
                    let incoming: PairingState = serde_json::from_slice(s.as_ref())
                        .map_err(|_| ContractError::InvalidState)?;
                    current.merge(&incoming);
                }
                _ => {}
            }
        }

        // Evict if stale (use latest side timestamp as "now" approximation)
        let latest_ts = [
            current.offer.as_ref().map(|s| s.timestamp),
            current.answer.as_ref().map(|s| s.timestamp),
        ]
        .into_iter()
        .flatten()
        .fold(f64::NEG_INFINITY, f64::max);

        if latest_ts > f64::NEG_INFINITY && current.is_stale(latest_ts) {
            // Stale — return empty state (eviction)
            return Ok(UpdateModification::valid(State::from(vec![])));
        }

        let serialized = serde_json::to_vec(&current)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(UpdateModification::valid(State::from(serialized)))
    }

    /// Summary: just the timestamps of each side (compact representation).
    fn summarize_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
    ) -> Result<StateSummary<'static>, ContractError> {
        let summary = if state.as_ref().is_empty() {
            PairingSummary::default()
        } else {
            let current: PairingState = serde_json::from_slice(state.as_ref())
                .map_err(|_| ContractError::InvalidState)?;
            PairingSummary {
                offer_ts: current.offer.as_ref().map(|s| s.timestamp),
                answer_ts: current.answer.as_ref().map(|s| s.timestamp),
            }
        };
        let bytes = serde_json::to_vec(&summary)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(StateSummary::from(bytes))
    }

    /// Delta: send full state if either side is newer than peer's summary.
    fn get_state_delta(
        _parameters: Parameters<'static>,
        state: State<'static>,
        summary: StateSummary<'static>,
    ) -> Result<StateDelta<'static>, ContractError> {
        if state.as_ref().is_empty() {
            return Ok(StateDelta::from(vec![]));
        }
        let current: PairingState = serde_json::from_slice(state.as_ref())
            .map_err(|_| ContractError::InvalidState)?;
        let peer: PairingSummary = if summary.as_ref().is_empty() {
            PairingSummary::default()
        } else {
            serde_json::from_slice(summary.as_ref())
                .map_err(|_| ContractError::InvalidState)?
        };

        let offer_newer = current
            .offer
            .as_ref()
            .map(|s| peer.offer_ts.is_none_or(|pt| s.timestamp > pt))
            .unwrap_or(false);
        let answer_newer = current
            .answer
            .as_ref()
            .map(|s| peer.answer_ts.is_none_or(|pt| s.timestamp > pt))
            .unwrap_or(false);

        if offer_newer || answer_newer {
            // Send full state — pairing data is small (a few KB at most)
            let bytes = serde_json::to_vec(&current)
                .map_err(|_| ContractError::InvalidState)?;
            Ok(StateDelta::from(bytes))
        } else {
            Ok(StateDelta::from(vec![]))
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use freeland_common::PairingSide;

    fn side(sdp: &str, ts: f64) -> PairingSide {
        PairingSide {
            sdp: sdp.to_string(),
            ice_candidates: vec!["mid:0:candidate:1".to_string()],
            timestamp: ts,
        }
    }

    fn state_with_offer(ts: f64) -> PairingState {
        PairingState {
            pairing_key: "alice:bob".to_string(),
            offer: Some(side("offer-sdp", ts)),
            answer: None,
            created_at: ts,
        }
    }

    fn state_with_both(offer_ts: f64, answer_ts: f64) -> PairingState {
        PairingState {
            pairing_key: "alice:bob".to_string(),
            offer: Some(side("offer-sdp", offer_ts)),
            answer: Some(side("answer-sdp", answer_ts)),
            created_at: offer_ts,
        }
    }

    #[test]
    fn merge_adds_answer_to_offer_only_state() {
        let mut state = state_with_offer(100.0);
        let answer_update = PairingState {
            pairing_key: "alice:bob".to_string(),
            offer: None,
            answer: Some(side("answer-sdp", 200.0)),
            created_at: 0.0,
        };
        state.merge(&answer_update);
        assert!(state.offer.is_some());
        assert!(state.answer.is_some());
        assert_eq!(state.answer.unwrap().sdp, "answer-sdp");
    }

    #[test]
    fn merge_keeps_newer_offer() {
        let mut a = state_with_offer(100.0);
        let b = PairingState {
            pairing_key: "alice:bob".to_string(),
            offer: Some(side("newer-offer", 200.0)),
            answer: None,
            created_at: 200.0,
        };
        a.merge(&b);
        assert_eq!(a.offer.unwrap().sdp, "newer-offer");
    }

    #[test]
    fn merge_keeps_older_created_at() {
        let mut a = state_with_offer(100.0);
        a.created_at = 50.0;
        let mut b = state_with_offer(200.0);
        b.created_at = 150.0;
        a.merge(&b);
        assert_eq!(a.created_at, 50.0);  // older wins
    }

    #[test]
    fn merge_is_commutative() {
        let offer_only = state_with_offer(100.0);
        let both = state_with_both(100.0, 200.0);

        let mut ab = offer_only.clone();
        ab.merge(&both);

        let mut ba = both.clone();
        ba.merge(&offer_only);

        assert_eq!(ab.offer.as_ref().map(|s| s.timestamp), ba.offer.as_ref().map(|s| s.timestamp));
        assert_eq!(ab.answer.as_ref().map(|s| s.timestamp), ba.answer.as_ref().map(|s| s.timestamp));
    }

    #[test]
    fn stale_detection() {
        let mut state = state_with_offer(100.0);
        state.created_at = 100.0;
        assert!(state.is_stale(100.0 + PAIRING_TTL_SECS + 1.0));
        assert!(!state.is_stale(100.0 + PAIRING_TTL_SECS - 1.0));
    }

    #[test]
    fn delta_sent_when_answer_newer() {
        let state = state_with_both(100.0, 200.0);
        let peer_summary = PairingSummary { offer_ts: Some(100.0), answer_ts: None };

        let state_bytes = serde_json::to_vec(&state).unwrap();
        let summary_bytes = serde_json::to_vec(&peer_summary).unwrap();

        let delta = PairingContract::get_state_delta(
            Parameters::from(vec![]),
            State::from(state_bytes),
            StateSummary::from(summary_bytes),
        ).unwrap();

        assert!(!delta.as_ref().is_empty());
    }

    #[test]
    fn no_delta_when_peer_up_to_date() {
        let state = state_with_offer(100.0);
        let peer_summary = PairingSummary { offer_ts: Some(100.0), answer_ts: None };

        let state_bytes = serde_json::to_vec(&state).unwrap();
        let summary_bytes = serde_json::to_vec(&peer_summary).unwrap();

        let delta = PairingContract::get_state_delta(
            Parameters::from(vec![]),
            State::from(state_bytes),
            StateSummary::from(summary_bytes),
        ).unwrap();

        assert!(delta.as_ref().is_empty());
    }
}
