/// Freeland proxy library — core listen/handle logic, extracted so integration tests can use it.
use std::{net::SocketAddr, path::PathBuf, sync::Arc};

use freenet_stdlib::{
    client_api::{
        ClientRequest, ContractRequest, ContractResponse, DelegateRequest, HostResponse, WebApi,
    },
    prelude::{
        ApplicationMessage, ContractContainer, ContractInstanceId, DelegateContainer, DelegateKey,
        InboundDelegateMsg, OutboundDelegateMsg, Parameters, RelatedContracts, WrappedState,
    },
};
use freeland_common::{
    ChunkParameters, ChunkState, LobbyEntry, LobbyParameters, LobbyState,
    PairingParameters, PairingState, PairingSide,
    PlayerDelegateRequest, PlayerDelegateResponse,
    ProxyRequest, ProxyResponse,
};
use serde_json::json;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, connect_async, tungstenite::Message};
use tracing::{debug, error, info, warn};

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Start the proxy listener. Returns the bound address (useful when port 0 is
/// passed for testing). Runs until the listener is dropped / process exits.
#[allow(clippy::too_many_arguments)]
pub async fn run_listener(
    listen_addr: SocketAddr,
    node_url: String,
    contract_path: PathBuf,
    lobby_contract_path: PathBuf,
    pairing_contract_path: PathBuf,
    delegate_path: PathBuf,
    error_contract_path: Option<PathBuf>,
    version_contract_path: Option<PathBuf>,
) -> anyhow::Result<SocketAddr> {
    let contract_bytes = Arc::new(std::fs::read(&contract_path).map_err(|e| {
        anyhow::anyhow!(
            "Failed to read chunk contract from {}: {e}\n\
             Build it with: cd contracts/chunk-contract && \
             CARGO_TARGET_DIR=../../target fdev build",
            contract_path.display()
        )
    })?);
    info!(path = %contract_path.display(), bytes = contract_bytes.len(), "Loaded chunk contract");

    let lobby_bytes = Arc::new(std::fs::read(&lobby_contract_path).map_err(|e| {
        anyhow::anyhow!(
            "Failed to read lobby contract from {}: {e}\n\
             Build it with: cd contracts/lobby-contract && \
             CARGO_TARGET_DIR=../../target fdev build",
            lobby_contract_path.display()
        )
    })?);
    info!(path = %lobby_contract_path.display(), bytes = lobby_bytes.len(), "Loaded lobby contract");

    let pairing_bytes = Arc::new(std::fs::read(&pairing_contract_path).map_err(|e| {
        anyhow::anyhow!(
            "Failed to read pairing contract from {}: {e}\n\
             Build it with: cd contracts/pairing-contract && \
             CARGO_TARGET_DIR=../../target fdev build",
            pairing_contract_path.display()
        )
    })?);
    info!(path = %pairing_contract_path.display(), bytes = pairing_bytes.len(), "Loaded pairing contract");

    // Read delegate bytes at startup so every client connection can load them.
    let delegate_bytes = Arc::new(std::fs::read(&delegate_path).map_err(|e| {
        anyhow::anyhow!(
            "Failed to read player delegate from {}: {e}\n\
             Build it with: cd delegates/player-delegate && \
             CARGO_TARGET_DIR=../../target fdev build --package-type delegate",
            delegate_path.display()
        )
    })?);
    info!(path = %delegate_path.display(), bytes = delegate_bytes.len(), "Loaded player delegate");

    let error_bytes: Option<Arc<Vec<u8>>> = match error_contract_path {
        Some(path) => {
            let b = std::fs::read(&path).map_err(|e| anyhow::anyhow!("Failed to read error contract from {}: {e}", path.display()))?;
            info!(path = %path.display(), bytes = b.len(), "Loaded error contract");
            Some(Arc::new(b))
        }
        None => {
            info!("Error contract not configured — telemetry reports will be dropped");
            None
        }
    };

    let version_bytes: Option<Arc<Vec<u8>>> = match version_contract_path {
        Some(path) => {
            let b = std::fs::read(&path).map_err(|e| anyhow::anyhow!("Failed to read version contract from {}: {e}", path.display()))?;
            info!(path = %path.display(), bytes = b.len(), "Loaded version manifest contract");
            Some(Arc::new(b))
        }
        None => {
            info!("Version contract not configured — version manifest ops will be no-ops");
            None
        }
    };

    let listener = TcpListener::bind(listen_addr).await?;
    let bound = listener.local_addr()?;
    info!(addr = %bound, "Proxy listening");

    tokio::spawn(async move {
        while let Ok((stream, peer)) = listener.accept().await {
            info!(%peer, "GDScript client connected");
            let url = node_url.clone();
            let cb = contract_bytes.clone();
            let lb = lobby_bytes.clone();
            let pb = pairing_bytes.clone();
            let db = delegate_bytes.clone();
            let eb = error_bytes.clone();
            let vb = version_bytes.clone();
            tokio::spawn(async move {
                if let Err(e) = handle_client(stream, url, cb, lb, pb, db, eb, vb).await {
                    error!(%peer, error = %e, "Client handler error");
                }
            });
        }
    });

    Ok(bound)
}

// ---------------------------------------------------------------------------
// Per-client handler
// ---------------------------------------------------------------------------

#[allow(clippy::too_many_arguments)]
async fn handle_client(
    stream: TcpStream,
    node_url: String,
    contract_bytes: Arc<Vec<u8>>,
    lobby_bytes: Arc<Vec<u8>>,
    pairing_bytes: Arc<Vec<u8>>,
    delegate_bytes: Arc<Vec<u8>>,
    error_bytes: Option<Arc<Vec<u8>>>,
    version_bytes: Option<Arc<Vec<u8>>>,
) -> anyhow::Result<()> {
    use futures::{SinkExt, StreamExt};

    let mut ws = accept_async(stream).await?;

    let (node_ws, _) = connect_async(&node_url).await?;
    let mut freenet = WebApi::start(node_ws);
    info!(url = %node_url, "Connected to Freenet node");

    // Load and register the player delegate.
    let delegate_container = DelegateContainer::try_from((
        delegate_bytes.to_vec(),
        Arc::new(Parameters::from(vec![])),
    ))
    .map_err(|e| anyhow::anyhow!("Failed to init player delegate: {e}"))?;
    let delegate_key = delegate_container.key().clone();

    freenet
        .send(ClientRequest::DelegateOp(DelegateRequest::RegisterDelegate {
            delegate: delegate_container,
            cipher: DelegateRequest::DEFAULT_CIPHER,
            nonce: DelegateRequest::DEFAULT_NONCE,
        }))
        .await?;

    // Registration may return Ok or a DelegateResponse (both mean success).
    match freenet.recv().await {
        Ok(HostResponse::Ok) => info!("Player delegate registered"),
        Ok(HostResponse::DelegateResponse { .. }) => info!("Player delegate registered (got DelegateResponse)"),
        Ok(other) => warn!("Unexpected response to RegisterDelegate: {other:?}"),
        Err(e) => warn!("Error waiting for delegate registration: {e}"),
    }

    while let Some(msg) = ws.next().await {
        let msg = match msg {
            Ok(m) => m,
            Err(e) => {
                warn!(error = %e, "WebSocket recv error");
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
                ws.send(Message::Text(serde_json::to_string(&resp)?.into())).await?;
                continue;
            }
        };

        let response = dispatch(
            &mut freenet,
            &contract_bytes,
            &lobby_bytes,
            &pairing_bytes,
            &delegate_key,
            error_bytes.as_deref().map(|v| v.as_slice()),
            version_bytes.as_deref().map(|v| v.as_slice()),
            request,
        )
        .await;
        ws.send(Message::Text(serde_json::to_string(&response)?.into()))
            .await?;
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Request dispatch
// ---------------------------------------------------------------------------

#[allow(clippy::too_many_arguments)]
async fn dispatch(
    freenet: &mut WebApi,
    contract_bytes: &[u8],
    lobby_bytes: &[u8],
    pairing_bytes: &[u8],
    delegate_key: &DelegateKey,
    error_bytes: Option<&[u8]>,
    version_bytes: Option<&[u8]>,
    request: ProxyRequest,
) -> ProxyResponse {
    match request {
        ProxyRequest::Put { chunk_x, chunk_y, state_json } => {
            put_chunk(freenet, contract_bytes, chunk_x, chunk_y, state_json).await
        }
        ProxyRequest::Get { chunk_x, chunk_y } => {
            get_chunk(freenet, contract_bytes, chunk_x, chunk_y).await
        }
        ProxyRequest::Delete { chunk_x, chunk_y } => {
            let empty = serde_json::to_string(&ChunkState::default())
                .unwrap_or_else(|_| "{}".into());
            put_chunk(freenet, contract_bytes, chunk_x, chunk_y, empty).await
        }
        ProxyRequest::LobbyPut { entry } => {
            lobby_put(freenet, lobby_bytes, entry).await
        }
        ProxyRequest::LobbyGet => {
            lobby_get(freenet, lobby_bytes).await
        }
        ProxyRequest::PairingPublishOffer { pairing_key, sdp, ice_candidates, timestamp } => {
            pairing_publish(freenet, pairing_bytes, pairing_key, sdp, ice_candidates, timestamp, true).await
        }
        ProxyRequest::PairingPublishAnswer { pairing_key, sdp, ice_candidates, timestamp } => {
            pairing_publish(freenet, pairing_bytes, pairing_key, sdp, ice_candidates, timestamp, false).await
        }
        ProxyRequest::PairingGet { pairing_key } => {
            pairing_get(freenet, pairing_bytes, pairing_key).await
        }
        ProxyRequest::PlayerSave { player_id, kind, data_json } => {
            let req = match kind.as_str() {
                "reputation" => PlayerDelegateRequest::SaveReputation {
                    player_id: player_id.clone(),
                    data_json,
                },
                "equipment" => PlayerDelegateRequest::SaveEquipment {
                    player_id: player_id.clone(),
                    data_json,
                },
                other => {
                    return ProxyResponse::Error {
                        message: format!("Unknown player data kind: {other}"),
                    }
                }
            };
            player_delegate_call(freenet, delegate_key, req, &player_id, &kind).await
        }
        ProxyRequest::PlayerLoad { player_id, kind } => {
            let req = match kind.as_str() {
                "reputation" => PlayerDelegateRequest::LoadReputation {
                    player_id: player_id.clone(),
                },
                "equipment" => PlayerDelegateRequest::LoadEquipment {
                    player_id: player_id.clone(),
                },
                other => {
                    return ProxyResponse::Error {
                        message: format!("Unknown player data kind: {other}"),
                    }
                }
            };
            player_delegate_call(freenet, delegate_key, req, &player_id, &kind).await
        }
        ProxyRequest::ReportError {
            session_id, error_hash, error_type, file, line,
            phase, game_version, platform, godot_version, ts,
        } => {
            match error_bytes {
                None => {
                    // Not configured — silently accept to avoid spamming the client.
                    ProxyResponse::ReportErrorOk
                }
                Some(eb) => {
                    report_error(
                        freenet, eb,
                        session_id, error_hash, error_type, file, line,
                        phase, game_version, platform, godot_version, ts,
                    )
                    .await
                }
            }
        }
        ProxyRequest::GetVersionManifest => {
            match version_bytes {
                None => ProxyResponse::VersionManifestNotFound,
                Some(vb) => get_version_manifest(freenet, vb).await,
            }
        }
        ProxyRequest::PutVersionManifest { manifest_json } => {
            match version_bytes {
                None => ProxyResponse::VersionManifestNotFound,
                Some(vb) => put_version_manifest(freenet, vb, manifest_json).await,
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Put (store chunk)
// ---------------------------------------------------------------------------

async fn put_chunk(
    freenet: &mut WebApi,
    contract_bytes: &[u8],
    chunk_x: i32,
    chunk_y: i32,
    state_json: String,
) -> ProxyResponse {
    let params = match make_params(chunk_x, chunk_y) {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((contract_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("Contract init: {e}") },
    };

    let state_bytes = state_json.into_bytes();
    let put = ClientRequest::ContractOp(ContractRequest::Put {
        contract: container,
        state: WrappedState::from(state_bytes),
        related_contracts: RelatedContracts::default(),
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(put).await {
        return ProxyResponse::Error { message: format!("Send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::PutResponse { .. }))
        | Ok(HostResponse::ContractResponse(ContractResponse::UpdateResponse { .. })) => {
            ProxyResponse::PutOk { chunk_x, chunk_y }
        }
        Ok(other) => {
            warn!(op = "put_chunk", chunk_x, chunk_y, response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: format!("put_chunk({chunk_x},{chunk_y}): unexpected node response") }
        }
        Err(e) => {
            warn!(op = "put_chunk", chunk_x, chunk_y, error = %e, "Freenet node error");
            ProxyResponse::Error { message: format!("put_chunk({chunk_x},{chunk_y}): {e}") }
        }
    }
}

// ---------------------------------------------------------------------------
// Get (retrieve chunk)
// ---------------------------------------------------------------------------

async fn get_chunk(
    freenet: &mut WebApi,
    contract_bytes: &[u8],
    chunk_x: i32,
    chunk_y: i32,
) -> ProxyResponse {
    let params = match make_params(chunk_x, chunk_y) {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((contract_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("Contract init: {e}") },
    };
    let contract_id: ContractInstanceId = *container.id();

    let get = ClientRequest::ContractOp(ContractRequest::Get {
        key: contract_id,
        return_contract_code: false,
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(get).await {
        return ProxyResponse::Error { message: format!("Send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::GetResponse { state, .. })) => {
            let state_json = match std::str::from_utf8(state.as_ref()) {
                Ok(s) => s.to_string(),
                Err(_) => {
                    return ProxyResponse::Error {
                        message: "State is not valid UTF-8".into(),
                    }
                }
            };
            ProxyResponse::GetOk { chunk_x, chunk_y, state_json }
        }
        Ok(HostResponse::ContractResponse(ContractResponse::NotFound { .. })) => {
            ProxyResponse::GetNotFound { chunk_x, chunk_y }
        }
        Ok(other) => {
            warn!(op = "get_chunk", chunk_x, chunk_y, response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: format!("get_chunk({chunk_x},{chunk_y}): unexpected node response") }
        }
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("missing contract") {
                debug!(op = "get_chunk", chunk_x, chunk_y, "contract not yet created");
                ProxyResponse::GetNotFound { chunk_x, chunk_y }
            } else {
                warn!(op = "get_chunk", chunk_x, chunk_y, error = %e, "Freenet node error");
                ProxyResponse::Error { message: format!("get_chunk({chunk_x},{chunk_y}): {e}") }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_params(chunk_x: i32, chunk_y: i32) -> Result<Arc<Parameters<'static>>, String> {
    let cp = ChunkParameters { chunk_x, chunk_y };
    serde_json::to_vec(&cp)
        .map(|b| Arc::new(Parameters::from(b)))
        .map_err(|e| format!("Params serialization: {e}"))
}

fn make_pairing_params(pairing_key: &str) -> Result<Arc<Parameters<'static>>, String> {
    let pp = PairingParameters { pairing_key: pairing_key.to_string() };
    serde_json::to_vec(&pp)
        .map(|b| Arc::new(Parameters::from(b)))
        .map_err(|e| format!("Pairing params serialization: {e}"))
}

fn make_lobby_params() -> Result<Arc<Parameters<'static>>, String> {
    let lp = LobbyParameters::default();
    serde_json::to_vec(&lp)
        .map(|b| Arc::new(Parameters::from(b)))
        .map_err(|e| format!("Lobby params serialization: {e}"))
}

// ---------------------------------------------------------------------------
// Lobby put (publish presence)
// ---------------------------------------------------------------------------

/// Publish a single presence entry by putting a single-entry LobbyState.
/// The lobby contract's update_state merges it with existing entries.
async fn lobby_put(
    freenet: &mut WebApi,
    lobby_bytes: &[u8],
    entry: LobbyEntry,
) -> ProxyResponse {
    let params = match make_lobby_params() {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((lobby_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("Lobby contract init: {e}") },
    };

    // Wrap the single entry in a LobbyState so update_state can merge it.
    let mut single = LobbyState::default();
    single.entries.insert(entry.session_id.clone(), entry);
    let state_bytes = match serde_json::to_vec(&single) {
        Ok(b) => b,
        Err(e) => return ProxyResponse::Error { message: format!("Serialize lobby entry: {e}") },
    };

    let put = ClientRequest::ContractOp(ContractRequest::Put {
        contract: container,
        state: WrappedState::from(state_bytes),
        related_contracts: RelatedContracts::default(),
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(put).await {
        return ProxyResponse::Error { message: format!("Send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::PutResponse { .. }))
        | Ok(HostResponse::ContractResponse(ContractResponse::UpdateResponse { .. })) => {
            ProxyResponse::LobbyPutOk
        }
        Ok(other) => {
            warn!(op = "lobby_put", response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: "lobby_put: unexpected node response".into() }
        }
        Err(e) => {
            warn!(op = "lobby_put", error = %e, "Freenet node error");
            ProxyResponse::Error { message: format!("lobby_put: {e}") }
        }
    }
}

// ---------------------------------------------------------------------------
// Lobby get (retrieve all presence entries)
// ---------------------------------------------------------------------------

async fn lobby_get(
    freenet: &mut WebApi,
    lobby_bytes: &[u8],
) -> ProxyResponse {
    let params = match make_lobby_params() {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((lobby_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("Lobby contract init: {e}") },
    };
    let contract_id: ContractInstanceId = *container.id();

    let get = ClientRequest::ContractOp(ContractRequest::Get {
        key: contract_id,
        return_contract_code: false,
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(get).await {
        return ProxyResponse::Error { message: format!("Send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::GetResponse { state, .. })) => {
            let state_json = match std::str::from_utf8(state.as_ref()) {
                Ok(s) => s.to_string(),
                Err(_) => {
                    return ProxyResponse::Error {
                        message: "Lobby state is not valid UTF-8".into(),
                    }
                }
            };
            ProxyResponse::LobbyGetOk { state_json }
        }
        Ok(HostResponse::ContractResponse(ContractResponse::NotFound { .. })) => {
            ProxyResponse::LobbyGetNotFound
        }
        Ok(other) => {
            warn!(op = "lobby_get", response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: "lobby_get: unexpected node response".into() }
        }
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("missing contract") {
                debug!(op = "lobby_get", "lobby contract not yet created");
                ProxyResponse::LobbyGetNotFound
            } else {
                warn!(op = "lobby_get", error = %e, "Freenet node error");
                ProxyResponse::Error { message: format!("lobby_get: {e}") }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Pairing publish (offer or answer)
// ---------------------------------------------------------------------------

/// Publish one side's SDP + ICE to the pairing contract.
/// `is_offer=true` writes the offer field; `false` writes the answer field.
async fn pairing_publish(
    freenet: &mut WebApi,
    pairing_bytes: &[u8],
    pairing_key: String,
    sdp: String,
    ice_candidates: Vec<String>,
    timestamp: f64,
    is_offer: bool,
) -> ProxyResponse {
    let params = match make_pairing_params(&pairing_key) {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((pairing_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("Pairing contract init: {e}") },
    };

    let side = PairingSide { sdp, ice_candidates, timestamp };
    let state = if is_offer {
        PairingState {
            pairing_key: pairing_key.clone(),
            offer: Some(side),
            answer: None,
            created_at: timestamp,
        }
    } else {
        PairingState {
            pairing_key: pairing_key.clone(),
            offer: None,
            answer: Some(side),
            created_at: 0.0,
        }
    };

    let state_bytes = match serde_json::to_vec(&state) {
        Ok(b) => b,
        Err(e) => return ProxyResponse::Error { message: format!("Serialize pairing state: {e}") },
    };

    let put = ClientRequest::ContractOp(ContractRequest::Put {
        contract: container,
        state: WrappedState::from(state_bytes),
        related_contracts: RelatedContracts::default(),
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(put).await {
        return ProxyResponse::Error { message: format!("Send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::PutResponse { .. }))
        | Ok(HostResponse::ContractResponse(ContractResponse::UpdateResponse { .. })) => {
            ProxyResponse::PairingPublishOk { pairing_key }
        }
        Ok(other) => {
            warn!(op = "pairing_publish", %pairing_key, response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: format!("pairing_publish({pairing_key}): unexpected node response") }
        }
        Err(e) => {
            warn!(op = "pairing_publish", %pairing_key, error = %e, "Freenet node error");
            ProxyResponse::Error { message: format!("pairing_publish({pairing_key}): {e}") }
        }
    }
}

// ---------------------------------------------------------------------------
// Pairing get
// ---------------------------------------------------------------------------

async fn pairing_get(
    freenet: &mut WebApi,
    pairing_bytes: &[u8],
    pairing_key: String,
) -> ProxyResponse {
    let params = match make_pairing_params(&pairing_key) {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((pairing_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("Pairing contract init: {e}") },
    };
    let contract_id: ContractInstanceId = *container.id();

    let get = ClientRequest::ContractOp(ContractRequest::Get {
        key: contract_id,
        return_contract_code: false,
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(get).await {
        return ProxyResponse::Error { message: format!("Send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::GetResponse { state, .. })) => {
            let state_json = match std::str::from_utf8(state.as_ref()) {
                Ok(s) => s.to_string(),
                Err(_) => return ProxyResponse::Error {
                    message: "Pairing state is not valid UTF-8".into(),
                },
            };
            ProxyResponse::PairingGetOk { pairing_key, state_json }
        }
        Ok(HostResponse::ContractResponse(ContractResponse::NotFound { .. })) => {
            ProxyResponse::PairingGetNotFound { pairing_key }
        }
        Ok(other) => {
            warn!(op = "pairing_get", %pairing_key, response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: format!("pairing_get({pairing_key}): unexpected node response") }
        }
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("missing contract") {
                debug!(op = "pairing_get", %pairing_key, "pairing contract not yet created");
                ProxyResponse::PairingGetNotFound { pairing_key }
            } else {
                warn!(op = "pairing_get", %pairing_key, error = %e, "Freenet node error");
                ProxyResponse::Error { message: format!("pairing_get({pairing_key}): {e}") }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Player delegate call
// ---------------------------------------------------------------------------

/// Send a `PlayerDelegateRequest` to the registered player delegate and await
/// the `PlayerDelegateResponse`, translating it to a `ProxyResponse`.
async fn player_delegate_call(
    freenet: &mut WebApi,
    delegate_key: &DelegateKey,
    request: PlayerDelegateRequest,
    player_id: &str,
    kind: &str,
) -> ProxyResponse {
    let payload = match serde_json::to_vec(&request) {
        Ok(b) => b,
        Err(e) => {
            return ProxyResponse::Error {
                message: format!("Serialize delegate request: {e}"),
            }
        }
    };

    let op = ClientRequest::DelegateOp(DelegateRequest::ApplicationMessages {
        key: delegate_key.clone(),
        params: Parameters::from(vec![]),
        inbound: vec![InboundDelegateMsg::ApplicationMessage(ApplicationMessage::new(payload))],
    });

    if let Err(e) = freenet.send(op).await {
        return ProxyResponse::Error {
            message: format!("Delegate send failed: {e}"),
        };
    }

    let values = match freenet.recv().await {
        Ok(HostResponse::DelegateResponse { values, .. }) => values,
        Ok(other) => {
            warn!(op = "player_delegate_call", %player_id, %kind, response = ?other, "Unexpected Freenet response");
            return ProxyResponse::Error {
                message: format!("player_{kind}({player_id}): unexpected node response"),
            }
        }
        Err(e) => {
            warn!(op = "player_delegate_call", %player_id, %kind, error = %e, "Freenet node error");
            return ProxyResponse::Error {
                message: format!("player_{kind}({player_id}): {e}"),
            }
        }
    };

    // Find the ApplicationMessage in the outbound values.
    let app_msg = values.into_iter().find_map(|v| {
        if let OutboundDelegateMsg::ApplicationMessage(m) = v {
            Some(m)
        } else {
            None
        }
    });

    let app_msg = match app_msg {
        Some(m) => m,
        None => {
            return ProxyResponse::Error {
                message: "Delegate returned no ApplicationMessage".into(),
            }
        }
    };

    let delegate_response: PlayerDelegateResponse = match serde_json::from_slice(&app_msg.payload) {
        Ok(r) => r,
        Err(e) => {
            return ProxyResponse::Error {
                message: format!("Deserialize delegate response: {e}"),
            }
        }
    };

    match delegate_response {
        PlayerDelegateResponse::SaveOk => ProxyResponse::PlayerSaveOk {
            player_id: player_id.to_string(),
            kind: kind.to_string(),
        },
        PlayerDelegateResponse::LoadOk { data_json } => ProxyResponse::PlayerLoadOk {
            player_id: player_id.to_string(),
            kind: kind.to_string(),
            data_json,
        },
        PlayerDelegateResponse::LoadNotFound => ProxyResponse::PlayerLoadNotFound {
            player_id: player_id.to_string(),
            kind: kind.to_string(),
        },
        PlayerDelegateResponse::Error { message } => ProxyResponse::Error { message },
        PlayerDelegateResponse::ExportedSecrets { .. } => ProxyResponse::Error {
            message: "Unexpected ExportedSecrets response to Save/Load request".into(),
        },
    }
}

// ---------------------------------------------------------------------------
// Report error (telemetry)
// ---------------------------------------------------------------------------

/// PUT a single error report into the error contract.
#[allow(clippy::too_many_arguments)]
async fn report_error(
    freenet: &mut WebApi,
    error_bytes: &[u8],
    session_id: String,
    error_hash: String,
    error_type: String,
    file: String,
    line: i32,
    phase: String,
    game_version: String,
    platform: String,
    godot_version: String,
    ts: f64,
) -> ProxyResponse {
    // Error contract uses empty parameters (single global instance).
    let params = Arc::new(Parameters::from(vec![]));
    let container = match ContractContainer::try_from((error_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("Error contract init: {e}") },
    };

    let key = format!("{session_id}:{error_hash}");
    let report = json!({
        "error_type": error_type,
        "file": file,
        "line": line,
        "phase": phase,
        "game_version": game_version,
        "platform": platform,
        "godot_version": godot_version,
        "ts": ts,
    });
    let state = json!({ "reports": { key: report } });
    let state_bytes = match serde_json::to_vec(&state) {
        Ok(b) => b,
        Err(e) => return ProxyResponse::Error { message: format!("Serialize error report: {e}") },
    };

    let put = ClientRequest::ContractOp(ContractRequest::Put {
        contract: container,
        state: WrappedState::from(state_bytes),
        related_contracts: RelatedContracts::default(),
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(put).await {
        return ProxyResponse::Error { message: format!("Send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::PutResponse { .. }))
        | Ok(HostResponse::ContractResponse(ContractResponse::UpdateResponse { .. })) => {
            ProxyResponse::ReportErrorOk
        }
        Ok(other) => {
            warn!(op = "report_error", response = ?other, "Unexpected Freenet response");
            // Return Ok anyway — telemetry failure should not surface as a client error.
            ProxyResponse::ReportErrorOk
        }
        Err(e) => {
            warn!(op = "report_error", error = %e, "Freenet node error");
            // Same reasoning: don't surface telemetry errors to game client.
            ProxyResponse::ReportErrorOk
        }
    }
}

// ---------------------------------------------------------------------------
// Get version manifest
// ---------------------------------------------------------------------------

async fn get_version_manifest(
    freenet: &mut WebApi,
    version_bytes: &[u8],
) -> ProxyResponse {
    let params = Arc::new(Parameters::from(vec![]));
    let container = match ContractContainer::try_from((version_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("version contract init: {e}") },
    };
    let contract_id: ContractInstanceId = *container.id();

    let get = ClientRequest::ContractOp(ContractRequest::Get {
        key: contract_id,
        return_contract_code: false,
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(get).await {
        return ProxyResponse::Error { message: format!("get_version_manifest: send failed: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::GetResponse { state, .. })) => {
            match std::str::from_utf8(state.as_ref()) {
                Ok(s) => ProxyResponse::VersionManifestOk { manifest_json: s.to_string() },
                Err(_) => ProxyResponse::Error { message: "version manifest state not valid UTF-8".into() },
            }
        }
        Ok(HostResponse::ContractResponse(ContractResponse::NotFound { .. })) => {
            ProxyResponse::VersionManifestNotFound
        }
        Ok(other) => {
            warn!(op = "get_version_manifest", response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: "get_version_manifest: unexpected node response".into() }
        }
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("missing contract") {
                ProxyResponse::VersionManifestNotFound
            } else {
                warn!(op = "get_version_manifest", error = %e, "Freenet node error");
                ProxyResponse::Error { message: format!("get_version_manifest: {e}") }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Put version manifest
// ---------------------------------------------------------------------------

async fn put_version_manifest(
    freenet: &mut WebApi,
    version_bytes: &[u8],
    manifest_json: String,
) -> ProxyResponse {
    let params = Arc::new(Parameters::from(vec![]));
    let container = match ContractContainer::try_from((version_bytes.to_vec(), params)) {
        Ok(c) => c,
        Err(e) => return ProxyResponse::Error { message: format!("version contract init: {e}") },
    };

    let put = ClientRequest::ContractOp(ContractRequest::Put {
        contract: container,
        state: WrappedState::from(manifest_json.into_bytes()),
        related_contracts: RelatedContracts::default(),
        subscribe: false,
        blocking_subscribe: false,
    });

    if let Err(e) = freenet.send(put).await {
        return ProxyResponse::Error { message: format!("put_version_manifest: {e}") };
    }

    match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::PutResponse { .. }))
        | Ok(HostResponse::ContractResponse(ContractResponse::UpdateResponse { .. })) => {
            ProxyResponse::PutVersionManifestOk
        }
        Ok(other) => {
            warn!(op = "put_version_manifest", response = ?other, "Unexpected Freenet response");
            ProxyResponse::Error { message: "put_version_manifest: unexpected node response".into() }
        }
        Err(e) => {
            warn!(op = "put_version_manifest", error = %e, "Freenet node error");
            ProxyResponse::Error { message: format!("put_version_manifest: {e}") }
        }
    }
}
