/// Commons proxy — translates JSON WebSocket (GDScript) ↔ Freenet binary protocol.
///
/// Listens on ws://127.0.0.1:7510  (configurable via COMMONS_PROXY_ADDR)
/// Connects to   ws://localhost:7509/v1/contract/command?encodingProtocol=native  (configurable via FREENET_NODE_URL)
///
/// Chunk contract:   COMMONS_CONTRACT_PATH        (default: ./commons_chunk_contract)
/// Lobby contract:   COMMONS_LOBBY_CONTRACT_PATH  (default: ./commons_lobby_contract)
/// Pairing contract: COMMONS_PAIRING_CONTRACT_PATH (default: ./commons_pairing_contract)
/// Player delegate:  COMMONS_PLAYER_DELEGATE_PATH  (default: ./commons_player_delegate)
/// Error contract:   COMMONS_ERROR_CONTRACT_PATH   (optional — telemetry dropped if unset)
/// Version contract: COMMONS_VERSION_CONTRACT_PATH (optional — version manifest ops no-op if unset)
///
/// All must be versioned packages produced by `fdev build`, NOT raw .wasm files.
/// Build:
///   cd contracts/chunk-contract      && CARGO_TARGET_DIR=../../target fdev build
///   cd contracts/lobby-contract      && CARGO_TARGET_DIR=../../target fdev build
///   cd contracts/pairing-contract    && CARGO_TARGET_DIR=../../target fdev build
///   cd contracts/error-contract      && CARGO_TARGET_DIR=../../target fdev build
///   cd contracts/version-manifest    && CARGO_TARGET_DIR=../../target fdev build
///   cd delegates/player-delegate     && CARGO_TARGET_DIR=../../target fdev build --package-type delegate
use std::{env, path::PathBuf};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "commons_proxy=info".into()),
        )
        .init();

    let listen_addr: std::net::SocketAddr = env::var("COMMONS_PROXY_ADDR")
        .unwrap_or("127.0.0.1:7510".into())
        .parse()
        .expect("Invalid COMMONS_PROXY_ADDR");

    let node_url = env::var("FREENET_NODE_URL")
        .unwrap_or("ws://localhost:7509/v1/contract/command?encodingProtocol=native".into());

    let contract_path = PathBuf::from(
        env::var("COMMONS_CONTRACT_PATH").unwrap_or("commons_chunk_contract".into()),
    );

    let lobby_contract_path = PathBuf::from(
        env::var("COMMONS_LOBBY_CONTRACT_PATH").unwrap_or("commons_lobby_contract".into()),
    );

    let pairing_contract_path = PathBuf::from(
        env::var("COMMONS_PAIRING_CONTRACT_PATH").unwrap_or("commons_pairing_contract".into()),
    );

    let delegate_path = PathBuf::from(
        env::var("COMMONS_PLAYER_DELEGATE_PATH").unwrap_or("commons_player_delegate".into()),
    );

    let error_contract_path: Option<PathBuf> =
        env::var("COMMONS_ERROR_CONTRACT_PATH").ok().map(PathBuf::from);

    let version_contract_path: Option<PathBuf> =
        env::var("COMMONS_VERSION_CONTRACT_PATH").ok().map(PathBuf::from);

    commons_proxy::run_listener(
        listen_addr,
        node_url,
        contract_path,
        lobby_contract_path,
        pairing_contract_path,
        delegate_path,
        error_contract_path,
        version_contract_path,
    )
    .await
    .expect("Proxy failed to start");

    // Park the main task — the listener runs on a spawned task.
    std::future::pending::<()>().await;
}
