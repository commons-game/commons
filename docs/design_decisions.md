# Freeland — Design Decisions Log
_Last updated: April 2026_

This doc captures design decisions and their reasoning as they're made. Kept separate from the research synthesis so we can track the "why" over time.

---

## Session Merging Mechanic

**Decision:** Merging is chunk-graph adjacency, not hard session merging.

**How it works:**
- Each wandering player/group has a "neighborhood" of loaded wilderness chunks around them.
- When two groups wander close enough (proximity criteria TBD), the system places **bridge chunks** between their two neighborhoods, physically connecting them in space.
- Players can then walk across the bridge into the other group's area.
- If the groups wander far enough apart, the bridge dissolves and their chunk neighborhoods diverge again.

**Why this is better than hard session merging:**
- No "pause both sessions and reconcile state" moment.
- Merging is gradual — players choose to cross or not.
- Conflict resolution is spatial: each group's chunk neighborhood stays owned by that group; only the bridge is shared.
- No need for rollback-style state snapshot/transfer between incompatible simulations.

**Open questions:**
- What triggers bridge formation? Pure proximity? A "signal" from both groups? Random with a probability curve?
- What's the visual/narrative presentation? "A mysterious path appears..."
- What happens to players standing on a bridge when it dissolves?
- How wide are bridges? Single chunk? Multiple?

---

## Wilderness vs Built Areas

**Decision:** Merging/diverging only happens in wilderness (procedurally generated areas). Player-built areas (settlements, towns) are stable and do not merge with other sessions.

**Implication:** The chunk system needs to track a chunk's "type" — wilderness (eligible for merge/churn) vs settled (stable, owned, persistent). The boundary between these is TBD.

---

## Wilderness Chunk Lifecycle

**Decision:** Wilderness chunks are impermanent. Chunks that no one is subscribed to (no nearby players) are eventually lost. This is intentional — "the multiverse churns."

**Why:** Aligns with the multiverse theme. Wilderness is not precious; it regenerates. Only player-meaningful areas (settlements) are preserved long-term.

**Implication for Freenet:** Cold wilderness contracts will be evicted from the network. Chunks regenerate procedurally from their seed on next visit. Player modifications to wilderness chunks need a retention policy — either they're also lost (pure churn), or they're preserved if a player "claims" the chunk, transitioning it from wilderness to settled.

**Future feature idea (not in scope now):** "Lost worlds" — rare, hard-to-find chunks of ancient player-modified wilderness that somehow survived.

---

## Backend Strategy

**Decision:** Abstract the backend behind a clean interface. Implement a LAN/local backend first for development and testing. Freenet is the long-term goal but we're not building against it yet.

**Why:** Freenet is alpha with breaking changes daily. Building against it now would stall the game. The LAN backend lets us validate all the game mechanics without being blocked on network stability.

**Interface should cover:**
- Store/retrieve chunk data (by chunk coordinates)
- Publish player presence in a geographic area
- Subscribe to presence events in nearby areas (for bridge formation triggering)
- Coordinate P2P connection between two peers (exchange connection info)

---

## Session Model

**Decision:** "Last survivor chat room" — fully equal P2P. No hierarchy, no ownership, no special roles.

- A session exists as long as at least one peer is connected to it.
- All peers are equal. No peer has elevated authority by design (though one peer may hold *temporary region authority* for real-time sync purposes — see Networking below).
- There is no game-enforced concept of ownership. Players cannot "own" space as a system rule. Any political structure (kingdoms, guilds, territorial control) is emergent player behavior or a future mod.
- A "town" is not a game object — it's just an emergent description of chunks that are heavily modified and frequently visited.

---

## Networking Model

**Rollback netcode ruled out.** See research synthesis.

**Chosen approach:** Region authority (Godot 4 native) + CRDT world state + reputation-based merge routing.

- **Region authority**: For real-time sync (player positions, movement), whichever peer is present in a region temporarily holds authority for it. Authority transfers as players move. No peer holds authority permanently — consistent with the equal-peer session model.
- **CRDT world state**: All tile mutations are stored as a CRDT (Last-Write-Wins Map per chunk). Any two chunk stores merge automatically — this is what makes spatial merging trivial and late-join clean.
- **High-value event witnessing**: Tile placements and significant world events require multi-peer witness confirmation before committing to the CRDT. **No external library for this** — will be built in GDScript when needed. Tashi Protocol (which has this built in) is intentionally excluded as a dependency (too early-stage, like Freenet).
- **Signaling / NAT traversal**: For LAN testing, direct IP. For internet play, Freenet's built-in UDP hole-punching serves as the discovery/signaling layer — no additional signaling server needed long-term. May need a minimal interim signaling solution before Freenet is stable enough.

**Player count targets:**
- Wilderness encounters: 2–8 players initially
- Towns: scale slowly; 100 players is a long-term target, not a day-one requirement

---

## Chunk Lifecycle (Activity-Based Persistence)

**Decision:** Chunk lifespan is determined purely by modification weight and player activity. Nothing is permanent.

**How it works:**
- Each chunk has a *weight* — a score derived from how many tiles have been player-modified and how recently players visited.
- Higher weight = longer persistence before the chunk fades.
- Chunks with no weight (untouched procedural wilderness, no visitors) fade quickly and regenerate from seed on next visit.
- Even heavily modified chunks eventually fade if completely abandoned.
- **Neighborhood bonus**: Chunks that are part of a shrine territory get a weight multiplier from adjacent modified chunks in the same territory. A chunk surrounded by active territory is much more durable than an isolated modified chunk at the edge. This makes territories contract naturally from the edges inward when abandoned, rather than decaying uniformly.

**Why:** Reinforces the "fluctuating multiverse" theme. Wilderness is impermanent. Only places where people *are* have stable existence.

**Future feature idea:** "Lost worlds" — highly modified chunks that somehow survived but are forgotten. Could be rendered as ruins when rediscovered. Not in scope now but the weight system naturally supports detecting these.

**Implication for Freenet:** Freenet's LRU eviction of cold contracts aligns perfectly with this design. Cold chunk contracts evict naturally. The weight system maps to subscription activity on the contract — subscribed peers keep it alive.

---

## Bridge Formation (Spatial Merging Trigger)

**Decision:** Probability-based with talisman modifiers.

**Default mechanic — "loneliness pressure":**
- Each player/session has a merge pressure value (0.0–1.0).
- Pressure slowly increases while a player is in an unmerged session (alone or within their existing group).
- On merge/split, pressure resets to low and ramps back up over time.
- Merge events are a random roll weighted by current pressure — high pressure = high probability per interval.
- Linear ramp to start; will shape from real play data later.
- This creates a natural "the universe wants to connect you" dynamic. Solitude requires active maintenance.

**Talisman/item system:**
- In-game items (talismans, charms, etc.) can modify merge probability, bias toward biome types, attract or repel specific session types.
- Examples: "Ward of Solitude" (reduces merge chance), "Compass of the Lost" (increases chance, biases toward specific biomes), "Talisman of Chaos" (opts into the chaos pool — see Reputation).
- These are content/gameplay items, not engine features. The engine just exposes merge probability as a tunable parameter.

**Open question:** What's the visual/narrative framing when a bridge appears? ("A strange path materializes at the edge of the forest...")

---

## Reputation and Merge Routing

**Decision:** No bans. Social routing via reputation.

**How it works:**
- Players can report others. Highly reported players are flagged.
- Flagged players are routed into a separate merge pool — they can still find other players, but only others who opted into chaotic/adversarial interactions.
- "Talisman of Chaos" = an item that opts a player INTO the chaos pool voluntarily. This means PvP-oriented players can find each other without ruining cooperative players' experiences.
- Result: a soft social filter, not a punitive ban system.

**Why no bans:** Consistent with the "no central authority" philosophy. No one owns the network; no one has the power to ban. Reputation is just a routing preference.

**Implementation note:** Reputation state could be a Freenet contract — decentralized, tamper-resistant, no single operator in control.

---

## Mods / Dimensions

**Concept (future scope, not current):** Mods are dimensions in the multiverse. Players walk into areas with different rules. Not in scope for initial development — mentioned so architecture doesn't preclude it.

---

## Mods / Dimensions

**Concept (future scope, not current):** Mods are dimensions in the multiverse. Players can walk to areas with different rules. Selection is random unless players craft items that guide their dimensional travel. Not in scope for initial development — mentioned here so architecture doesn't preclude it.
