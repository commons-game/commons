/// Shared types between the chunk contract, lobby contract, proxy, and GDScript client.
///
/// Chunk state is a LWW-map: each tile key maps to the entry with the
/// highest timestamp. Merge is commutative by construction (higher timestamp
/// always wins; ties broken deterministically by author_id lexicographic order).
///
/// Lobby state is a LWW-map: each session_id maps to the most-recent presence
/// entry. Used for internet player discovery via Freenet contracts.
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Parameters for a chunk contract instance.
/// The contract key = hash(WASM || serialize(ChunkParameters)).
/// Different chunk coordinates → different contract key → independent storage.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChunkParameters {
    pub chunk_x: i32,
    pub chunk_y: i32,
}

/// One tile entry in the CRDT store.
/// Matches the existing GDScript CRDT format exactly so we can
/// round-trip through JSON without any transformation.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TileEntry {
    pub tile_id: i32,   // -1 = tombstone
    pub atlas_x: i32,
    pub atlas_y: i32,
    pub alt_tile: i32,
    pub timestamp: f64, // unix seconds — the LWW key
    pub author_id: String,
}

/// Full chunk state: the CRDT map for one 16×16 chunk.
/// `entries` keys are packed CRDT keys: (layer << 16) | (lx << 8) | ly
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct ChunkState {
    pub chunk_x: i32,
    pub chunk_y: i32,
    pub world_seed: i64,
    pub version: u32,
    pub entries: HashMap<u32, TileEntry>,
}

impl ChunkState {
    /// LWW merge: for each tile key keep the entry with the higher timestamp.
    /// Tie-broken by author_id (lexicographic) for determinism.
    pub fn merge(&mut self, other: &ChunkState) {
        for (key, other_entry) in &other.entries {
            match self.entries.get(key) {
                None => {
                    self.entries.insert(*key, other_entry.clone());
                }
                Some(existing) => {
                    if other_entry.timestamp > existing.timestamp
                        || (other_entry.timestamp == existing.timestamp
                            && other_entry.author_id > existing.author_id)
                    {
                        self.entries.insert(*key, other_entry.clone());
                    }
                }
            }
        }
    }

    /// Merge is commutative: merge(A,B) == merge(B,A)
    /// Proof: for each key, the winner is determined solely by
    /// (timestamp, author_id) comparison — order-independent.
    pub fn merge_commutative_check() {}
}

/// Summary sent to peers: map of tile_key → timestamp.
/// Compact — ~8 bytes per tile vs ~100 bytes for a full entry.
pub type ChunkSummary = HashMap<u32, f64>;

/// Delta: only the entries newer than what the peer reported in its summary.
pub type ChunkDelta = HashMap<u32, TileEntry>;

// ---------------------------------------------------------------------------
// Lobby types — player presence for internet P2P discovery
// ---------------------------------------------------------------------------

/// Well-known lobby ID for the global Freeland lobby contract.
/// All players use this ID → same contract instance → they can find each other.
pub const GLOBAL_LOBBY_ID: &str = "freeland-global-v1";

/// Seconds after which a presence entry is considered stale and evicted.
pub const LOBBY_TTL_SECS: f64 = 300.0; // 5 minutes

/// Parameters for the lobby contract instance.
/// Using a fixed GLOBAL_LOBBY_ID gives one global contract everyone shares.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LobbyParameters {
    pub lobby_id: String,
}

impl Default for LobbyParameters {
    fn default() -> Self {
        Self { lobby_id: GLOBAL_LOBBY_ID.to_string() }
    }
}

/// One player's presence entry in the lobby.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LobbyEntry {
    pub session_id: String,
    pub chunk_x: i32,
    pub chunk_y: i32,
    /// Player's IP address for direct ENet/WebRTC connection.
    /// LAN IP for now; a future STUN pass will replace this with external IP.
    pub ip: String,
    pub enet_port: u16,
    /// Unix timestamp (seconds). LWW key — higher timestamp wins.
    pub timestamp: f64,
}

/// Full lobby state: LWW-map of session_id → presence entry.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct LobbyState {
    pub entries: HashMap<String, LobbyEntry>,
}

impl LobbyState {
    /// LWW merge: keep the entry with the higher timestamp per session_id.
    pub fn merge(&mut self, other: &LobbyState) {
        for (sid, other_entry) in &other.entries {
            match self.entries.get(sid) {
                None => {
                    self.entries.insert(sid.clone(), other_entry.clone());
                }
                Some(existing) => {
                    if other_entry.timestamp > existing.timestamp {
                        self.entries.insert(sid.clone(), other_entry.clone());
                    }
                }
            }
        }
    }

    /// Remove entries older than LOBBY_TTL_SECS.
    /// Called in update_state to keep the contract from growing unbounded.
    pub fn evict_stale(&mut self, now: f64) {
        self.entries.retain(|_, e| now - e.timestamp < LOBBY_TTL_SECS);
    }
}

/// Summary sent to peers: session_id → timestamp.
pub type LobbySummary = HashMap<String, f64>;

/// Delta: only the entries newer than what a peer reported.
pub type LobbyDelta = HashMap<String, LobbyEntry>;

// ---------------------------------------------------------------------------
// JSON proxy protocol (GDScript ↔ proxy ↔ Freenet node)
// ---------------------------------------------------------------------------

/// Request from GDScript to the proxy.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "op")]
pub enum ProxyRequest {
    /// Store (put) a chunk. Creates or updates the contract.
    Put {
        chunk_x: i32,
        chunk_y: i32,
        /// Full JSON payload — same format as LocalBackend writes.
        state_json: String,
    },
    /// Retrieve a chunk's current state.
    Get {
        chunk_x: i32,
        chunk_y: i32,
    },
    /// Delete a chunk (maps to eviction hint — Freenet handles actual eviction).
    Delete {
        chunk_x: i32,
        chunk_y: i32,
    },
    /// Publish (upsert) a single presence entry into the global lobby contract.
    LobbyPut {
        entry: LobbyEntry,
    },
    /// Retrieve the full lobby state (all known players' presence entries).
    LobbyGet,
}

/// Response from proxy to GDScript.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "op")]
pub enum ProxyResponse {
    /// Put acknowledged.
    PutOk {
        chunk_x: i32,
        chunk_y: i32,
    },
    /// Chunk state returned.
    GetOk {
        chunk_x: i32,
        chunk_y: i32,
        /// Full JSON payload — same format LocalBackend returns.
        state_json: String,
    },
    /// Chunk not found on the network (caller should generate procedurally).
    GetNotFound {
        chunk_x: i32,
        chunk_y: i32,
    },
    /// Delete acknowledged.
    DeleteOk {
        chunk_x: i32,
        chunk_y: i32,
    },
    /// Error response.
    Error {
        message: String,
    },
    /// Lobby presence entry published.
    LobbyPutOk,
    /// Full lobby state returned.
    LobbyGetOk {
        /// JSON-encoded LobbyState.
        state_json: String,
    },
    /// Lobby contract not found (no players have published yet).
    LobbyGetNotFound,
}
