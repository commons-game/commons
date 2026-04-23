/// Commons version manifest contract.
///
/// A single global record updated by the developer on each release.
/// Merge keeps whichever record has the higher `published_at` timestamp.
///
/// Parameters: empty (single global instance — no per-coordinate differentiation).
/// State: JSON-encoded VersionManifest.
use freenet_stdlib::prelude::*;
use serde::{Deserialize, Serialize};

/// The version manifest — a single record updated by the developer on each release.
/// Merge keeps whichever record has the higher `published_at`.
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct VersionManifest {
    /// Human-readable version string, e.g. "0.3.0"
    #[serde(default)]
    pub version: String,
    /// Short git commit hash
    #[serde(default)]
    pub commit: String,
    /// Unix timestamp of when this was published
    #[serde(default)]
    pub published_at: f64,
    /// URL to the release page (must be https://github.com/...)
    #[serde(default)]
    pub download_url: String,
    /// Minimum protocol version required to join games on this release.
    /// If a client's PROTOCOL_VERSION < this, they must update before playing multiplayer.
    #[serde(default)]
    pub min_protocol_version: u32,
}

#[allow(dead_code)]
struct VersionManifestContract;

#[contract]
impl ContractInterface for VersionManifestContract {
    fn validate_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        _related: RelatedContracts<'static>,
    ) -> Result<ValidateResult, ContractError> {
        if state.as_ref().is_empty() {
            return Ok(ValidateResult::Valid);
        }
        let _: VersionManifest = serde_json::from_slice(state.as_ref())
            .map_err(|_| ContractError::InvalidState)?;
        Ok(ValidateResult::Valid)
    }

    fn update_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
        data: Vec<UpdateData<'static>>,
    ) -> Result<UpdateModification<'static>, ContractError> {
        let mut current: VersionManifest = if state.as_ref().is_empty() {
            VersionManifest::default()
        } else {
            serde_json::from_slice(state.as_ref())
                .map_err(|_| ContractError::InvalidState)?
        };

        for update in data {
            let incoming_bytes: Vec<u8> = match update {
                UpdateData::Delta(d) => d.into_owned().to_vec(),
                UpdateData::State(s) => s.into_owned().to_vec(),
                UpdateData::StateAndDelta { state: s, .. } => s.into_owned().to_vec(),
                _ => continue,
            };
            let incoming: VersionManifest = serde_json::from_slice(&incoming_bytes)
                .map_err(|_| ContractError::InvalidState)?;
            if incoming.published_at > current.published_at {
                current = incoming;
            }
        }

        let merged = serde_json::to_vec(&current)
            .map_err(|_| ContractError::InvalidState)?;
        Ok(UpdateModification::valid(State::from(merged)))
    }

    fn summarize_state(
        _parameters: Parameters<'static>,
        state: State<'static>,
    ) -> Result<StateSummary<'static>, ContractError> {
        let m: VersionManifest = if state.as_ref().is_empty() {
            VersionManifest::default()
        } else {
            serde_json::from_slice(state.as_ref()).unwrap_or_default()
        };
        let ts_bytes = m.published_at.to_le_bytes();
        Ok(StateSummary::from(ts_bytes.to_vec()))
    }

    fn get_state_delta(
        _parameters: Parameters<'static>,
        state: State<'static>,
        _summary: StateSummary<'static>,
    ) -> Result<StateDelta<'static>, ContractError> {
        Ok(StateDelta::from(state.as_ref().to_vec()))
    }
}
