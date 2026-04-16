/// freeland-dev-proxy — in-memory stand-in for the Freenet proxy.
///
/// Speaks the exact same WebSocket JSON protocol as freeland-proxy so GDScript
/// needs zero changes. No Freenet node or contract binaries required.
///
/// Usage:
///   cargo run --bin freeland-dev-proxy
///   # or after cargo build --release:
///   ./target/release/freeland-dev-proxy
///
/// Listens on ws://127.0.0.1:7510 by default (FREELAND_PROXY_ADDR to override).
/// State is shared in-process across all connected GDScript clients — suitable
/// for running two game instances on the same machine.
use std::{
    collections::HashMap,
    net::SocketAddr,
    sync::{Arc, RwLock},
};

use freeland_common::{ProxyRequest, ProxyResponse};
use futures::{SinkExt, StreamExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use tracing::{error, info, warn};

// ---------------------------------------------------------------------------
// Shared in-memory state
// ---------------------------------------------------------------------------

#[derive(Default)]
struct DevState {
    /// Lobby: session_id → entry dict (stored as serde_json::Value for simplicity)
    lobby: HashMap<String, serde_json::Value>,
    /// Pairing: pairing_key → {"offer": …, "answer": …}
    pairings: HashMap<String, serde_json::Value>,
    /// Chunks: (chunk_x, chunk_y) → state_json
    chunks: HashMap<(i32, i32), String>,
    /// Player data: "rep:<player_id>" or "equip:<player_id>" → data_json
    player_data: HashMap<String, String>,
    /// Version manifest JSON (None until PutVersionManifest is called)
    version_manifest: Option<String>,
}

type State = Arc<RwLock<DevState>>;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "freeland_dev_proxy=info,info".into()),
        )
        .init();

    // Accept address as first CLI arg, then env var, then default.
    let listen_addr: SocketAddr = std::env::args()
        .nth(1)
        .or_else(|| std::env::var("FREELAND_PROXY_ADDR").ok())
        .unwrap_or_else(|| "127.0.0.1:7510".into())
        .parse()
        .expect("Invalid listen address (pass as first arg or FREELAND_PROXY_ADDR env var)");

    let state: State = Arc::new(RwLock::new(DevState::default()));
    let listener = TcpListener::bind(listen_addr)
        .await
        .expect("Failed to bind");
    let bound = listener.local_addr().unwrap();
    info!(addr = %bound, "Dev proxy listening (in-memory mode — no Freenet required)");

    while let Ok((stream, peer)) = listener.accept().await {
        info!(%peer, "GDScript client connected");
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_client(stream, state).await {
                error!(%peer, error = %e, "Client handler error");
            }
        });
    }
}

// ---------------------------------------------------------------------------
// Per-client handler
// ---------------------------------------------------------------------------

async fn handle_client(stream: TcpStream, state: State) -> anyhow::Result<()> {
    let mut ws = accept_async(stream).await?;

    while let Some(msg) = ws.next().await {
        let msg = match msg {
            Ok(m) => m,
            Err(e) => {
                warn!(error = %e, "WS recv error");
                break;
            }
        };

        let text = match msg {
            Message::Text(t) => t,
            Message::Close(_) => break,
            _ => continue,
        };

        let request: ProxyRequest = match serde_json::from_str(&text) {
            Ok(r) => r,
            Err(e) => {
                let resp = ProxyResponse::Error {
                    message: format!("Bad request JSON: {e}"),
                };
                ws.send(Message::Text(
                    serde_json::to_string(&resp).unwrap().into(),
                ))
                .await?;
                continue;
            }
        };

        let response = dispatch(&state, request);
        ws.send(Message::Text(serde_json::to_string(&response)?.into()))
            .await?;
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

fn dispatch(state: &State, req: ProxyRequest) -> ProxyResponse {
    match req {
        // --- Chunk store ---
        ProxyRequest::Put { chunk_x, chunk_y, state_json } => {
            state
                .write()
                .unwrap()
                .chunks
                .insert((chunk_x, chunk_y), state_json);
            ProxyResponse::PutOk { chunk_x, chunk_y }
        }
        ProxyRequest::Get { chunk_x, chunk_y } => {
            let s = state.read().unwrap();
            match s.chunks.get(&(chunk_x, chunk_y)) {
                Some(j) => ProxyResponse::GetOk {
                    chunk_x,
                    chunk_y,
                    state_json: j.clone(),
                },
                None => ProxyResponse::GetNotFound { chunk_x, chunk_y },
            }
        }
        ProxyRequest::Delete { chunk_x, chunk_y } => {
            state.write().unwrap().chunks.remove(&(chunk_x, chunk_y));
            ProxyResponse::PutOk { chunk_x, chunk_y }
        }

        // --- Lobby ---
        ProxyRequest::LobbyPut { entry } => {
            let mut s = state.write().unwrap();
            let val = serde_json::to_value(&entry).unwrap_or(serde_json::Value::Null);
            s.lobby.insert(entry.session_id.clone(), val);
            info!(session_id = %entry.session_id, "Lobby: player published presence");
            ProxyResponse::LobbyPutOk
        }
        ProxyRequest::LobbyGet => {
            let s = state.read().unwrap();
            let lobby_map: serde_json::Value =
                serde_json::json!({ "entries": s.lobby });
            match serde_json::to_string(&lobby_map) {
                Ok(j) => ProxyResponse::LobbyGetOk { state_json: j },
                Err(e) => ProxyResponse::Error {
                    message: format!("Serialize lobby: {e}"),
                },
            }
        }

        // --- Pairing ---
        ProxyRequest::PairingPublishOffer {
            pairing_key,
            sdp,
            ice_candidates,
            timestamp,
        } => {
            let mut s = state.write().unwrap();
            let entry = s
                .pairings
                .entry(pairing_key.clone())
                .or_insert_with(|| serde_json::json!({"offer": null, "answer": null}));
            entry["offer"] = serde_json::json!({
                "sdp": sdp,
                "ice_candidates": ice_candidates,
                "timestamp": timestamp,
            });
            info!(pairing_key = %pairing_key, "Pairing: offer published");
            ProxyResponse::PairingPublishOk { pairing_key }
        }
        ProxyRequest::PairingPublishAnswer {
            pairing_key,
            sdp,
            ice_candidates,
            timestamp,
        } => {
            let mut s = state.write().unwrap();
            let entry = s
                .pairings
                .entry(pairing_key.clone())
                .or_insert_with(|| serde_json::json!({"offer": null, "answer": null}));
            entry["answer"] = serde_json::json!({
                "sdp": sdp,
                "ice_candidates": ice_candidates,
                "timestamp": timestamp,
            });
            info!(pairing_key = %pairing_key, "Pairing: answer published");
            ProxyResponse::PairingPublishOk { pairing_key }
        }
        ProxyRequest::PairingGet { pairing_key } => {
            let s = state.read().unwrap();
            match s.pairings.get(&pairing_key) {
                Some(v) => match serde_json::to_string(v) {
                    Ok(j) => ProxyResponse::PairingGetOk {
                        pairing_key,
                        state_json: j,
                    },
                    Err(e) => ProxyResponse::Error {
                        message: format!("Serialize pairing: {e}"),
                    },
                },
                None => ProxyResponse::PairingGetNotFound { pairing_key },
            }
        }

        // --- Player data (reputation / equipment) ---
        ProxyRequest::PlayerSave {
            player_id,
            kind,
            data_json,
        } => {
            let key = format!("{kind}:{player_id}");
            state.write().unwrap().player_data.insert(key, data_json);
            info!(player_id = %player_id, kind = %kind, "Player data saved");
            ProxyResponse::PlayerSaveOk {
                player_id,
                kind,
            }
        }
        ProxyRequest::PlayerLoad { player_id, kind } => {
            let key = format!("{kind}:{player_id}");
            match state.read().unwrap().player_data.get(&key).cloned() {
                Some(data_json) => ProxyResponse::PlayerLoadOk {
                    player_id,
                    kind,
                    data_json,
                },
                None => ProxyResponse::PlayerLoadNotFound { player_id, kind },
            }
        }

        // --- Telemetry (no-op in dev proxy) ---
        ProxyRequest::ReportError { .. } => ProxyResponse::ReportErrorOk,

        // --- Version manifest (in-memory stub) ---
        ProxyRequest::GetVersionManifest => {
            let s = state.read().unwrap();
            match &s.version_manifest {
                Some(j) => ProxyResponse::VersionManifestOk { manifest_json: j.clone() },
                None => ProxyResponse::VersionManifestNotFound,
            }
        }
        ProxyRequest::PutVersionManifest { manifest_json } => {
            state.write().unwrap().version_manifest = Some(manifest_json);
            ProxyResponse::PutVersionManifestOk
        }
    }
}
