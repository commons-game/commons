/// Freeland proxy library — core listen/handle logic, extracted so integration tests can use it.
use std::{net::SocketAddr, path::PathBuf, sync::Arc};

use freenet_stdlib::{
    client_api::{ClientRequest, ContractRequest, ContractResponse, HostResponse, WebApi},
    prelude::{
        ContractContainer, ContractInstanceId, Parameters, RelatedContracts, WrappedState,
    },
};
use freeland_common::{
    ChunkParameters, ChunkState, LobbyEntry, LobbyParameters, LobbyState,
    ProxyRequest, ProxyResponse,
};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, connect_async, tungstenite::Message};
use tracing::{error, info, warn};

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Start the proxy listener. Returns the bound address (useful when port 0 is
/// passed for testing). Runs until the listener is dropped / process exits.
pub async fn run_listener(
    listen_addr: SocketAddr,
    node_url: String,
    contract_path: PathBuf,
    lobby_contract_path: PathBuf,
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

    let listener = TcpListener::bind(listen_addr).await?;
    let bound = listener.local_addr()?;
    info!(addr = %bound, "Proxy listening");

    tokio::spawn(async move {
        while let Ok((stream, peer)) = listener.accept().await {
            info!(%peer, "GDScript client connected");
            let url = node_url.clone();
            let cb = contract_bytes.clone();
            let lb = lobby_bytes.clone();
            tokio::spawn(async move {
                if let Err(e) = handle_client(stream, url, cb, lb).await {
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

async fn handle_client(
    stream: TcpStream,
    node_url: String,
    contract_bytes: Arc<Vec<u8>>,
    lobby_bytes: Arc<Vec<u8>>,
) -> anyhow::Result<()> {
    use futures::{SinkExt, StreamExt};

    let mut ws = accept_async(stream).await?;

    let (node_ws, _) = connect_async(&node_url).await?;
    let mut freenet = WebApi::start(node_ws);
    info!(url = %node_url, "Connected to Freenet node");

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

        let response = dispatch(&mut freenet, &contract_bytes, &lobby_bytes, request).await;
        ws.send(Message::Text(serde_json::to_string(&response)?.into()))
            .await?;
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Request dispatch
// ---------------------------------------------------------------------------

async fn dispatch(
    freenet: &mut WebApi,
    contract_bytes: &[u8],
    lobby_bytes: &[u8],
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
        Ok(HostResponse::ContractResponse(ContractResponse::PutResponse { .. })) => {
            ProxyResponse::PutOk { chunk_x, chunk_y }
        }
        Ok(other) => ProxyResponse::Error {
            message: format!("Unexpected response: {other:?}"),
        },
        Err(e) => ProxyResponse::Error { message: format!("Node error: {e}") },
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
    let contract_id: ContractInstanceId = container.id().clone();

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
        Ok(other) => ProxyResponse::Error {
            message: format!("Unexpected response: {other:?}"),
        },
        Err(e) => ProxyResponse::Error { message: format!("Node error: {e}") },
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
        Ok(HostResponse::ContractResponse(ContractResponse::PutResponse { .. })) => {
            ProxyResponse::LobbyPutOk
        }
        Ok(other) => ProxyResponse::Error {
            message: format!("Unexpected response: {other:?}"),
        },
        Err(e) => ProxyResponse::Error { message: format!("Node error: {e}") },
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
    let contract_id: ContractInstanceId = container.id().clone();

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
        Ok(other) => ProxyResponse::Error {
            message: format!("Unexpected response: {other:?}"),
        },
        Err(e) => ProxyResponse::Error { message: format!("Node error: {e}") },
    }
}
