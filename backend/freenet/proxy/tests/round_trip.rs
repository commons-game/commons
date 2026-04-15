/// Integration smoke test: Put then Get a chunk through the proxy → Freenet node.
///
/// Requires:
///   FREENET_NODE_URL  — ws://...:7509/v1/contract/command?encodingProtocol=native
///   FREELAND_CONTRACT_PATH — path to the fdev-built versioned contract package
///
/// Run with:
///   FREENET_NODE_URL=... FREELAND_CONTRACT_PATH=... \
///     cargo test --features integration -p freeland-proxy -- round_trip --nocapture
///
/// The test is gated behind `cfg(feature = "integration")` so it never runs in
/// normal `cargo test` without the flag. This keeps CI green without a live node.
#[cfg(feature = "integration")]
mod integration {
    use freeland_common::{ChunkState, ProxyResponse, TileEntry};
    use futures::{SinkExt, StreamExt};
    use std::{collections::HashMap, path::PathBuf};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    /// A chunk coord that's unlikely to collide with other tests.
    const TEST_X: i32 = 777;
    const TEST_Y: i32 = 888;

    /// Packed tile key: layer=0, lx=3, ly=5 → (0 << 16) | (3 << 8) | 5
    const TEST_TILE_KEY: u32 = (3 << 8) | 5;

    #[tokio::test]
    async fn put_then_get_round_trips() {
        let node_url = std::env::var("FREENET_NODE_URL").expect(
            "FREENET_NODE_URL must be set to a running Freenet node, e.g. \
             ws://localhost:7509/v1/contract/command?encodingProtocol=native",
        );
        let contract_path = PathBuf::from(
            std::env::var("FREELAND_CONTRACT_PATH")
                .expect("FREELAND_CONTRACT_PATH must point to the fdev-built contract package"),
        );
        assert!(
            contract_path.exists(),
            "Contract not found at {}: run `cd contracts/chunk-contract && \
             CARGO_TARGET_DIR=../../target fdev build` first",
            contract_path.display()
        );

        // Bind proxy on an OS-assigned port so tests don't collide.
        let bound = freeland_proxy::run_listener(
            "127.0.0.1:0".parse().unwrap(),
            node_url,
            contract_path,
        )
        .await
        .expect("Proxy failed to start");

        let proxy_url = format!("ws://{bound}");
        let (mut ws, _) = connect_async(&proxy_url).await.expect("Connect to proxy failed");

        // --- Build a minimal ChunkState with one tile entry ---
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

        // --- PUT ---
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

        // --- GET ---
        let get_req = serde_json::json!({
            "op": "Get",
            "chunk_x": TEST_X,
            "chunk_y": TEST_Y
        });
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
}
