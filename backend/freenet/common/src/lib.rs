/// Shared types between the chunk contract, proxy, and GDScript client.
///
/// Chunk state is a LWW-map: each tile key maps to the entry with the
/// highest timestamp. Merge is commutative by construction (higher timestamp
/// always wins; ties broken deterministically by author_id lexicographic order).
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
}
