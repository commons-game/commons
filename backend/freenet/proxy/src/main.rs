/// Freeland proxy — translates JSON WebSocket (GDScript) ↔ Freenet binary protocol.
///
/// Listens on ws://127.0.0.1:7510  (configurable via FREELAND_PROXY_ADDR)
/// Connects to   ws://localhost:7509/v1/contract/command?encodingProtocol=native  (configurable via FREENET_NODE_URL)
///
/// Chunk contract:   FREELAND_CONTRACT_PATH        (default: ./freeland_chunk_contract)
/// Lobby contract:   FREELAND_LOBBY_CONTRACT_PATH  (default: ./freeland_lobby_contract)
/// Pairing contract: FREELAND_PAIRING_CONTRACT_PATH (default: ./freeland_pairing_contract)
/// Player delegate:  FREELAND_PLAYER_DELEGATE_PATH  (default: ./freeland_player_delegate)
///
/// All must be versioned packages produced by `fdev build`, NOT raw .wasm files.
/// Build:
///   cd contracts/chunk-contract   && CARGO_TARGET_DIR=../../target fdev build
///   cd contracts/lobby-contract   && CARGO_TARGET_DIR=../../target fdev build
///   cd contracts/pairing-contract && CARGO_TARGET_DIR=../../target fdev build
///   cd delegates/player-delegate  && CARGO_TARGET_DIR=../../target fdev build --package-type delegate
use std::{env, path::PathBuf};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "freeland_proxy=info".into()),
        )
        .init();

    let listen_addr: std::net::SocketAddr = env::var("FREELAND_PROXY_ADDR")
        .unwrap_or("127.0.0.1:7510".into())
        .parse()
        .expect("Invalid FREELAND_PROXY_ADDR");

    let node_url = env::var("FREENET_NODE_URL")
        .unwrap_or("ws://localhost:7509/v1/contract/command?encodingProtocol=native".into());

    let contract_path = PathBuf::from(
        env::var("FREELAND_CONTRACT_PATH").unwrap_or("freeland_chunk_contract".into()),
    );

    let lobby_contract_path = PathBuf::from(
        env::var("FREELAND_LOBBY_CONTRACT_PATH").unwrap_or("freeland_lobby_contract".into()),
    );

    let pairing_contract_path = PathBuf::from(
        env::var("FREELAND_PAIRING_CONTRACT_PATH").unwrap_or("freeland_pairing_contract".into()),
    );

    let delegate_path = PathBuf::from(
        env::var("FREELAND_PLAYER_DELEGATE_PATH").unwrap_or("freeland_player_delegate".into()),
    );

    freeland_proxy::run_listener(
        listen_addr,
        node_url,
        contract_path,
        lobby_contract_path,
        pairing_contract_path,
        delegate_path,
    )
    .await
    .expect("Proxy failed to start");

    // Park the main task — the listener runs on a spawned task.
    std::future::pending::<()>().await;
}
