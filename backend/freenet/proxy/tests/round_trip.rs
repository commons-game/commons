/// Integration smoke tests: Put/Get a chunk and lobby presence through the proxy → Freenet node.
///
/// Requires:
///   FREENET_NODE_URL               — ws://...:7509/v1/contract/command?encodingProtocol=native
///   FREELAND_CONTRACT_PATH         — path to the fdev-built chunk contract package
///   FREELAND_LOBBY_CONTRACT_PATH   — path to the fdev-built lobby contract package
///   FREELAND_PAIRING_CONTRACT_PATH — path to the fdev-built pairing contract package
///   FREELAND_PLAYER_DELEGATE_PATH  — path to the fdev-built player delegate package
///
/// Run with:
///   FREENET_NODE_URL=... FREELAND_CONTRACT_PATH=... FREELAND_LOBBY_CONTRACT_PATH=... \
///   FREELAND_PAIRING_CONTRACT_PATH=... FREELAND_PLAYER_DELEGATE_PATH=... \
///     cargo test --features integration -p freeland-proxy -- --nocapture
///
/// The tests are gated behind `cfg(feature = "integration")` so they never run in
/// normal `cargo test` without the flag. This keeps CI green without a live node.
#[cfg(feature = "integration")]
mod integration {
    use freeland_common::{ChunkState, LobbyEntry, LobbyState, ProxyResponse, TileEntry};
    use futures::{SinkExt, StreamExt};
    use std::{collections::HashMap, path::PathBuf};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    fn chunk_contract_path() -> PathBuf {
        let p = PathBuf::from(
            std::env::var("FREELAND_CONTRACT_PATH")
                .expect("FREELAND_CONTRACT_PATH must point to the fdev-built chunk contract package"),
        );
        assert!(
            p.exists(),
            "Chunk contract not found at {}: run `cd contracts/chunk-contract && \
             CARGO_TARGET_DIR=../../target fdev build` first",
            p.display()
        );
        p
    }

    fn lobby_contract_path() -> PathBuf {
        let p = PathBuf::from(
            std::env::var("FREELAND_LOBBY_CONTRACT_PATH")
                .expect("FREELAND_LOBBY_CONTRACT_PATH must point to the fdev-built lobby contract package"),
        );
        assert!(
            p.exists(),
            "Lobby contract not found at {}: run `cd contracts/lobby-contract && \
             CARGO_TARGET_DIR=../../target fdev build` first",
            p.display()
        );
        p
    }

    fn pairing_contract_path() -> PathBuf {
        let p = PathBuf::from(
            std::env::var("FREELAND_PAIRING_CONTRACT_PATH")
                .expect("FREELAND_PAIRING_CONTRACT_PATH must point to the fdev-built pairing contract package"),
        );
        assert!(
            p.exists(),
            "Pairing contract not found at {}: run `cd contracts/pairing-contract && \
             CARGO_TARGET_DIR=../../target fdev build` first",
            p.display()
        );
        p
    }

    fn player_delegate_path() -> PathBuf {
        let p = PathBuf::from(
            std::env::var("FREELAND_PLAYER_DELEGATE_PATH")
                .expect("FREELAND_PLAYER_DELEGATE_PATH must point to the fdev-built player delegate package"),
        );
        assert!(
            p.exists(),
            "Player delegate not found at {}: run `cd delegates/player-delegate && \
             CARGO_TARGET_DIR=../../target fdev build --package-type delegate` first",
            p.display()
        );
        p
    }

    fn node_url() -> String {
        std::env::var("FREENET_NODE_URL").expect(
            "FREENET_NODE_URL must be set to a running Freenet node, e.g. \
             ws://localhost:7509/v1/contract/command?encodingProtocol=native",
        )
    }

    async fn connect_proxy() -> (tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>, std::net::SocketAddr) {
        let bound = freeland_proxy::run_listener(
            "127.0.0.1:0".parse().unwrap(),
            node_url(),
            chunk_contract_path(),
            lobby_contract_path(),
            pairing_contract_path(),
            player_delegate_path(),
        )
        .await
        .expect("Proxy failed to start");

        let (ws, _) = connect_async(format!("ws://{bound}"))
            .await
            .expect("Connect to proxy failed");
        (ws, bound)
    }

    // -------------------------------------------------------------------------
    // Chunk round-trip
    // -------------------------------------------------------------------------

    /// A chunk coord that's unlikely to collide with other tests.
    const TEST_X: i32 = 777;
    const TEST_Y: i32 = 888;

    /// Packed tile key: layer=0, lx=3, ly=5 → (0 << 16) | (3 << 8) | 5
    const TEST_TILE_KEY: u32 = (3 << 8) | 5;

    #[tokio::test]
    async fn put_then_get_round_trips() {
        let (mut ws, _) = connect_proxy().await;

        let mut entries: HashMap<u32, TileEntry> = HashMap::new();
        entries.insert(
            TEST_TILE_KEY,
            TileEntry {
                tile_id: 1,
                atlas_x: 1,
                atlas_y: 0,
                alt_tile: 0,
                timestamp: 1_000_000.0,
                author_id: "test".into(),
            },
        );
        let state = ChunkState {
            chunk_x: TEST_X,
            chunk_y: TEST_Y,
            world_seed: 0,
            version: 1,
            entries,
        };
        let state_json = serde_json::to_string(&state).unwrap();

        // PUT
        let put_req = serde_json::json!({
            "op": "Put",
            "chunk_x": TEST_X,
            "chunk_y": TEST_Y,
            "state_json": state_json
        });
        ws.send(Message::Text(put_req.to_string().into())).await.unwrap();

        let put_raw = ws.next().await.unwrap().unwrap();
        let put_resp: ProxyResponse =
            serde_json::from_str(put_raw.to_text().unwrap()).expect("Put response not valid JSON");
        assert!(
            matches!(put_resp, ProxyResponse::PutOk { chunk_x: TEST_X, chunk_y: TEST_Y }),
            "Expected PutOk, got: {put_resp:?}"
        );

        // GET
        let get_req = serde_json::json!({ "op": "Get", "chunk_x": TEST_X, "chunk_y": TEST_Y });
        ws.send(Message::Text(get_req.to_string().into())).await.unwrap();

        let get_raw = ws.next().await.unwrap().unwrap();
        let get_resp: ProxyResponse =
            serde_json::from_str(get_raw.to_text().unwrap()).expect("Get response not valid JSON");

        match get_resp {
            ProxyResponse::GetOk { chunk_x, chunk_y, state_json: returned_json } => {
                assert_eq!(chunk_x, TEST_X);
                assert_eq!(chunk_y, TEST_Y);
                let returned: ChunkState =
                    serde_json::from_str(&returned_json).expect("Returned state not valid JSON");
                assert!(
                    returned.entries.contains_key(&TEST_TILE_KEY),
                    "Expected tile key {TEST_TILE_KEY} in returned state, got keys: {:?}",
                    returned.entries.keys().collect::<Vec<_>>()
                );
            }
            other => panic!("Expected GetOk, got: {other:?}"),
        }

        ws.close(None).await.ok();
    }

    // -------------------------------------------------------------------------
    // Lobby round-trip
    // -------------------------------------------------------------------------

    #[tokio::test]
    async fn lobby_put_then_get_round_trips() {
        let (mut ws, _) = connect_proxy().await;

        let ts = 9_999_000.0_f64; // far future — won't be evicted as stale
        let entry = LobbyEntry {
            session_id: "integration-test-player".into(),
            chunk_x: 42,
            chunk_y: -7,
            ip: "127.0.0.1".into(),
            enet_port: 7777,
            timestamp: ts,
        };

        // LOBBY PUT
        let put_req = serde_json::json!({
            "op": "LobbyPut",
            "entry": {
                "session_id": entry.session_id,
                "chunk_x": entry.chunk_x,
                "chunk_y": entry.chunk_y,
                "ip": entry.ip,
                "enet_port": entry.enet_port,
                "timestamp": entry.timestamp
            }
        });
        ws.send(Message::Text(put_req.to_string().into())).await.unwrap();

        let put_raw = ws.next().await.unwrap().unwrap();
        let put_resp: ProxyResponse =
            serde_json::from_str(put_raw.to_text().unwrap()).expect("LobbyPut response not valid JSON");
        assert!(
            matches!(put_resp, ProxyResponse::LobbyPutOk),
            "Expected LobbyPutOk, got: {put_resp:?}"
        );

        // LOBBY GET
        ws.send(Message::Text(r#"{"op":"LobbyGet"}"#.into())).await.unwrap();

        let get_raw = ws.next().await.unwrap().unwrap();
        let get_resp: ProxyResponse =
            serde_json::from_str(get_raw.to_text().unwrap()).expect("LobbyGet response not valid JSON");

        match get_resp {
            ProxyResponse::LobbyGetOk { state_json } => {
                let lobby: LobbyState =
                    serde_json::from_str(&state_json).expect("LobbyState not valid JSON");
                assert!(
                    lobby.entries.contains_key("integration-test-player"),
                    "Expected 'integration-test-player' in lobby, got keys: {:?}",
                    lobby.entries.keys().collect::<Vec<_>>()
                );
                let returned = &lobby.entries["integration-test-player"];
                assert_eq!(returned.chunk_x, 42);
                assert_eq!(returned.chunk_y, -7);
                assert_eq!(returned.timestamp, ts);
            }
            ProxyResponse::LobbyGetNotFound => {
                panic!("LobbyGetNotFound — lobby contract not yet published; try again after put propagates");
            }
            other => panic!("Expected LobbyGetOk, got: {other:?}"),
        }

        ws.close(None).await.ok();
    }
}
