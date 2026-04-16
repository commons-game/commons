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
// Pairing types — WebRTC signaling for NAT traversal
// ---------------------------------------------------------------------------

/// Pairing contract TTL: 5 minutes.
pub const PAIRING_TTL_SECS: f64 = 300.0;

/// Parameters for a pairing contract instance.
/// Key = hash(WASM || PairingParameters { pairing_key: "{min_sid}:{max_sid}" })
/// Both sides compute the same key deterministically from their session IDs.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PairingParameters {
    pub pairing_key: String,
}

/// One side's contribution to the pairing handshake.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PairingSide {
    /// SDP offer or answer.
    pub sdp: String,
    /// ICE candidates, each encoded as "mid:index:sdp".
    pub ice_candidates: Vec<String>,
    /// Unix timestamp — LWW key if this is re-published.
    pub timestamp: f64,
}

/// Full pairing state: the WebRTC signaling exchange between two players.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct PairingState {
    pub pairing_key: String,
    /// Written by the offerer (lower session ID alphabetically).
    pub offer: Option<PairingSide>,
    /// Written by the answerer after reading the offer.
    pub answer: Option<PairingSide>,
    /// Original creation time for TTL eviction.
    pub created_at: f64,
}

impl PairingState {
    /// LWW merge: keep the side with the higher timestamp; keep earlier created_at.
    pub fn merge(&mut self, other: &PairingState) {
        let merge_side = |mine: &mut Option<PairingSide>, theirs: &Option<PairingSide>| {
            match (mine.as_ref(), theirs.as_ref()) {
                (None, Some(t)) => *mine = Some(t.clone()),
                (Some(m), Some(t)) if t.timestamp > m.timestamp => *mine = Some(t.clone()),
                _ => {}
            }
        };
        merge_side(&mut self.offer, &other.offer);
        merge_side(&mut self.answer, &other.answer);
        // Keep the earlier creation time (the original publish)
        if other.created_at > 0.0
            && (self.created_at == 0.0 || other.created_at < self.created_at)
        {
            self.created_at = other.created_at;
        }
        if self.pairing_key.is_empty() {
            self.pairing_key = other.pairing_key.clone();
        }
    }

    pub fn is_stale(&self, now: f64) -> bool {
        self.created_at > 0.0 && now - self.created_at > PAIRING_TTL_SECS
    }
}

/// Summary: compact representation of what each side has published.
/// Used for efficient delta sync across the Freenet network.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct PairingSummary {
    pub offer_ts: Option<f64>,
    pub answer_ts: Option<f64>,
}

// ---------------------------------------------------------------------------
// Player delegate types — reputation and equipment storage
// ---------------------------------------------------------------------------

/// Request to the player delegate.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PlayerDelegateRequest {
    SaveReputation { player_id: String, data_json: String },
    LoadReputation { player_id: String },
    SaveEquipment { player_id: String, data_json: String },
    LoadEquipment { player_id: String },
    /// Export all secrets for migration when the delegate is upgraded.
    ExportSecrets,
}

/// Response from the player delegate.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PlayerDelegateResponse {
    SaveOk,
    LoadOk { data_json: String },
    LoadNotFound,
    /// (secret_key_str, value_json)
    ExportedSecrets { items: Vec<(String, String)> },
    Error { message: String },
}

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
    /// Publish the offerer's SDP + ICE candidates to the pairing contract.
    PairingPublishOffer {
        pairing_key: String,
        sdp: String,
        ice_candidates: Vec<String>,
        timestamp: f64,
    },
    /// Publish the answerer's SDP + ICE candidates to the pairing contract.
    PairingPublishAnswer {
        pairing_key: String,
        sdp: String,
        ice_candidates: Vec<String>,
        timestamp: f64,
    },
    /// Retrieve the current pairing state (both sides' SDP + ICE if present).
    PairingGet {
        pairing_key: String,
    },
    /// Save player data (reputation or equipment) via the player delegate.
    PlayerSave {
        player_id: String,
        /// "reputation" or "equipment"
        kind: String,
        data_json: String,
    },
    /// Load player data from the player delegate.
    PlayerLoad {
        player_id: String,
        /// "reputation" or "equipment"
        kind: String,
    },
    /// Submit an opt-in error/crash telemetry report.
    /// session_id is a random UUID per-launch — NOT the persistent PlayerIdentity.id.
    ReportError {
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
    },
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
    /// Pairing side published (offer or answer).
    PairingPublishOk {
        pairing_key: String,
    },
    /// Pairing state returned (may have only offer, or both offer+answer).
    PairingGetOk {
        pairing_key: String,
        /// JSON-encoded PairingState.
        state_json: String,
    },
    /// Pairing contract not yet published — no one has written an offer yet.
    PairingGetNotFound {
        pairing_key: String,
    },
    /// Full lobby state returned.
    LobbyGetOk {
        /// JSON-encoded LobbyState.
        state_json: String,
    },
    /// Lobby contract not found (no players have published yet).
    LobbyGetNotFound,
    /// Player data saved successfully.
    PlayerSaveOk {
        player_id: String,
        kind: String,
    },
    /// Player data loaded successfully.
    PlayerLoadOk {
        player_id: String,
        kind: String,
        data_json: String,
    },
    /// No player data found in the delegate (first time, or cleared).
    PlayerLoadNotFound {
        player_id: String,
        kind: String,
    },
    /// Error report acknowledged.
    ReportErrorOk,
}
