/// Freeland player delegate — stores reputation and equipment per player.
///
/// Each player's delegate is local to them. Secrets are keyed by:
///   rep:{player_id}   — JSON-encoded reputation data
///   equip:{player_id} — JSON-encoded equipment data
///
/// The delegate handles `PlayerDelegateRequest` payloads serialized as JSON
/// in the `ApplicationMessage.payload` field, and returns `PlayerDelegateResponse`
/// payloads in the outbound `ApplicationMessage`.
use freenet_stdlib::prelude::*;
use freeland_common::{PlayerDelegateRequest, PlayerDelegateResponse};

pub use freeland_common::{PlayerDelegateRequest as Request, PlayerDelegateResponse as Response};

#[allow(dead_code)]
struct PlayerDelegate;

#[delegate]
impl DelegateInterface for PlayerDelegate {
    fn process(
        ctx: &mut DelegateCtx,
        _params: Parameters<'static>,
        _origin: Option<MessageOrigin>,
        message: InboundDelegateMsg,
    ) -> Result<Vec<OutboundDelegateMsg>, DelegateError> {
        let app_msg = match message {
            InboundDelegateMsg::ApplicationMessage(msg) => msg,
            _ => {
                // Ignore non-application messages (contract notifications, etc.)
                return Ok(vec![]);
            }
        };

        let request: PlayerDelegateRequest =
            serde_json::from_slice(&app_msg.payload).map_err(|e| {
                DelegateError::Other(format!("Failed to deserialize PlayerDelegateRequest: {e}"))
            })?;

        let response = handle_request(ctx, request);

        let response_bytes = serde_json::to_vec(&response).map_err(|e| {
            DelegateError::Other(format!("Failed to serialize PlayerDelegateResponse: {e}"))
        })?;

        Ok(vec![OutboundDelegateMsg::ApplicationMessage(
            ApplicationMessage::new(response_bytes),
        )])
    }
}

#[allow(dead_code)]
fn handle_request(ctx: &mut DelegateCtx, request: PlayerDelegateRequest) -> PlayerDelegateResponse {
    match request {
        PlayerDelegateRequest::SaveReputation { player_id, data_json } => {
            let key = format!("rep:{player_id}");
            if ctx.set_secret(key.as_bytes(), data_json.as_bytes()) {
                PlayerDelegateResponse::SaveOk
            } else {
                PlayerDelegateResponse::Error {
                    message: format!("Failed to save reputation for {player_id}"),
                }
            }
        }

        PlayerDelegateRequest::LoadReputation { player_id } => {
            let key = format!("rep:{player_id}");
            match ctx.get_secret(key.as_bytes()) {
                Some(bytes) => match String::from_utf8(bytes) {
                    Ok(data_json) => PlayerDelegateResponse::LoadOk { data_json },
                    Err(e) => PlayerDelegateResponse::Error {
                        message: format!("Reputation data is not valid UTF-8: {e}"),
                    },
                },
                None => PlayerDelegateResponse::LoadNotFound,
            }
        }

        PlayerDelegateRequest::SaveEquipment { player_id, data_json } => {
            let key = format!("equip:{player_id}");
            if ctx.set_secret(key.as_bytes(), data_json.as_bytes()) {
                PlayerDelegateResponse::SaveOk
            } else {
                PlayerDelegateResponse::Error {
                    message: format!("Failed to save equipment for {player_id}"),
                }
            }
        }

        PlayerDelegateRequest::LoadEquipment { player_id } => {
            let key = format!("equip:{player_id}");
            match ctx.get_secret(key.as_bytes()) {
                Some(bytes) => match String::from_utf8(bytes) {
                    Ok(data_json) => PlayerDelegateResponse::LoadOk { data_json },
                    Err(e) => PlayerDelegateResponse::Error {
                        message: format!("Equipment data is not valid UTF-8: {e}"),
                    },
                },
                None => PlayerDelegateResponse::LoadNotFound,
            }
        }

        PlayerDelegateRequest::ExportSecrets => {
            // Export all known secrets for migration when delegate is upgraded.
            // We export reputation and equipment for "local_player" (the canonical single-player key).
            // In a multi-player scenario this would need to iterate all known player IDs.
            let mut items = Vec::new();
            for prefix in &["rep", "equip"] {
                let key = format!("{prefix}:local_player");
                if let Some(bytes) = ctx.get_secret(key.as_bytes()) {
                    if let Ok(value_json) = String::from_utf8(bytes) {
                        items.push((key, value_json));
                    }
                }
            }
            PlayerDelegateResponse::ExportedSecrets { items }
        }
    }
}
