/// Freeland proxy — translates JSON WebSocket (GDScript) ↔ Freenet binary protocol.
///
/// Listens on ws://127.0.0.1:7510  (configurable via FREELAND_PROXY_ADDR)
/// Connects to   ws://127.0.0.1:50509/v1/contract/command  (configurable via FREENET_NODE_URL)
///
/// Contract WASM loaded from FREELAND_WASM_PATH (default: ./freeland-chunk-contract.wasm).
/// Each Put/Get derives the ContractInstanceId from the WASM hash + ChunkParameters{x,y}.
use std::{env, path::PathBuf, sync::Arc};

use freenet_stdlib::{
    client_api::{ClientRequest, ContractRequest, ContractResponse, HostResponse, WebApi},
    prelude::{
        ContractContainer, ContractInstanceId, Parameters, RelatedContracts, WrappedState,
    },
};
use freeland_common::{ChunkParameters, ChunkState, ProxyRequest, ProxyResponse};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, connect_async, tungstenite::Message};
use tracing::{error, info, warn};

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "freeland_proxy=info".into()),
        )
        .init();

    let listen_addr = env::var("FREELAND_PROXY_ADDR").unwrap_or("127.0.0.1:7510".into());
    let node_url = env::var("FREENET_NODE_URL")
        .unwrap_or("ws://127.0.0.1:50509/v1/contract/command".into());
    let wasm_path = PathBuf::from(
        env::var("FREELAND_WASM_PATH").unwrap_or("freeland-chunk-contract.wasm".into()),
    );

    let wasm_bytes = Arc::new(
        std::fs::read(&wasm_path).unwrap_or_else(|e| {
            panic!("Failed to read WASM from {}: {e}", wasm_path.display())
        }),
    );
    info!(path = %wasm_path.display(), bytes = wasm_bytes.len(), "Loaded contract WASM");

    let listener = TcpListener::bind(&listen_addr)
        .await
        .expect("Failed to bind proxy listener");
    info!(addr = %listen_addr, "Proxy listening");

    while let Ok((stream, peer)) = listener.accept().await {
        info!(%peer, "GDScript client connected");
        let node_url = node_url.clone();
        let wasm = wasm_bytes.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_client(stream, node_url, wasm).await {
                error!(%peer, error = %e, "Client handler error");
            }
        });
    }
}

// ---------------------------------------------------------------------------
// Per-client handler
// ---------------------------------------------------------------------------

async fn handle_client(
    stream: TcpStream,
    node_url: String,
    wasm_bytes: Arc<Vec<u8>>,
) -> anyhow::Result<()> {
    use futures::{SinkExt, StreamExt};

    let mut ws = accept_async(stream).await?;

    // Connect to the Freenet node for this client session.
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

        let response = dispatch(&mut freenet, &wasm_bytes, request).await;
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
    wasm_bytes: &[u8],
    request: ProxyRequest,
) -> ProxyResponse {
    match request {
        ProxyRequest::Put {
            chunk_x,
            chunk_y,
            state_json,
        } => put_chunk(freenet, wasm_bytes, chunk_x, chunk_y, state_json).await,

        ProxyRequest::Get { chunk_x, chunk_y } => {
            get_chunk(freenet, wasm_bytes, chunk_x, chunk_y).await
        }

        ProxyRequest::Delete { chunk_x, chunk_y } => {
            // Freenet doesn't support hard deletes.
            // We write an empty ChunkState to effectively tombstone it.
            let empty = serde_json::to_string(&ChunkState::default())
                .unwrap_or_else(|_| "{}".into());
            put_chunk(freenet, wasm_bytes, chunk_x, chunk_y, empty).await
        }
    }
}

// ---------------------------------------------------------------------------
// Put (store chunk)
// ---------------------------------------------------------------------------

async fn put_chunk(
    freenet: &mut WebApi,
    wasm_bytes: &[u8],
    chunk_x: i32,
    chunk_y: i32,
    state_json: String,
) -> ProxyResponse {
    let params = match make_params(chunk_x, chunk_y) {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((wasm_bytes.to_vec(), params)) {
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
    wasm_bytes: &[u8],
    chunk_x: i32,
    chunk_y: i32,
) -> ProxyResponse {
    let params = match make_params(chunk_x, chunk_y) {
        Ok(p) => p,
        Err(e) => return ProxyResponse::Error { message: e },
    };
    let container = match ContractContainer::try_from((wasm_bytes.to_vec(), params)) {
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

/// Returns parameters wrapped in `Arc` so it satisfies the
/// `Deref<Target = Parameters<'_>>` bound on `ContractContainer::try_from`.
fn make_params(chunk_x: i32, chunk_y: i32) -> Result<Arc<Parameters<'static>>, String> {
    let cp = ChunkParameters { chunk_x, chunk_y };
    serde_json::to_vec(&cp)
        .map(|b| Arc::new(Parameters::from(b)))
        .map_err(|e| format!("Params serialization: {e}"))
}
