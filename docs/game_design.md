# Commons — Game Design

_Working document — April 2026_

## Vision

A survival RPG where the world is genuinely owned by its players. No central server. No admin. The strong take from the weak, the weak band together, and eventually civilizations form that new players are born into. The game mirrors the evolution of human societies — from terrified individuals scratching for survival to factions shaping the world to their will.

The technology underneath (Freenet, CRDT merging) is not a feature. It's an expression of the game's values: no one can take your world away, no one can reset it, and when two realities meet they merge rather than one winning.

---

## Emotional Arc

```
Fear → Mastery → Expression → Community
```

| Phase | Core feeling | You are |
|-------|-------------|---------|
| Survival | Dread. The night is coming. | An individual |
| Settlement | Hunger. That resource is dangerous to reach. | A settler |
| Territory | Power. I shaped this place. | A lord |
| Civilization | Politics. Who do I trust? | A faction |

New players always enter at Phase 1 regardless of when they join. But late-game, they enter a world already shaped by existing factions — they can be absorbed, protected, exploited, or ignored.

---

## The Spine

These are the phase transitions. Everything else in the tech tree hangs off them.

| Step | What you do | Unlocks | Gate |
|------|-------------|---------|------|
| 1 | Start naked, gather stone and wood by hand | Basic awareness of the world | None |
| 2 | Craft flint knife | Faster gathering, can fight back, first glimpse of dual-force mechanic | Stone + wood |
| 3 | Build first campfire | Survive the night | Flint knife + wood |
| 4 | Claim a home | Permanent spawn anchor — death has memory now | Marrow + Moonstone (night-gated) |
| 5 | Place shrine | Territory locked, island formed in CRDT | Very expensive, multiple rare materials |
| 6 | Upgrade shrine | Mod applied to land — world shaped to your will | See modding_design.md |

The spine is vertical progression. The tech tree fills in horizontally at each step — more tools, more building options, more ways to play — but does not gate the next spine step.

---

## Core Rules

### Death
- Drop full inventory and loadout on death. This is the reward for killing you.
- Respawn naked at home, or at a random location if no home exists.
- No death timer, no resurrection mechanic.

### Home

The home is whatever the player builds. Walls, rooms, hidden chambers — all just tiles. The anchor is **the Tether**.

**The Tether** is a craftable object: 1 Marrow (deep Bloom) + 1 Sinter (deep Still). Two forces in tension, holding each other — and you — in place against the drift. Visually: a crystalline Still spike wound with a slow-pulsing Bloom tendril. Small, distinct, unmistakable.

- One Tether per player. Placing it sets your spawn anchor and locks your home chunks.
- Destroying the enemy's Tether collapses their home claim. Requires at least a Flint Tool — bare hands can't break it.
- The Tether is the raid objective. Players hide it inside their build. Finding it is the attacker's challenge.
- If your Tether is destroyed while you are logged in: stark red text center screen — *"Your Tether has been broken."* Fades after a few seconds. One exception to "in world and subtle" — this is a life event.
- If you are offline when it happens: you find out on next login by spawning naked at a random location.
- Early game: losing your Tether is devastating. Late game: rebuilding is cheap. The emotional weight scales correctly.
- Getting your first Tether placed is the first real inflection point of the game.

### Shrine

The Shrine is the second inflection point. Where the Tether says "I am here," the Shrine says "this is mine."

**Recipe:** 1 Mass Core (drop from Mass mob, tier-3 Bloom) + 1 Form Crystal (drop from Form mob, tier-3 Still) + 1 Ichor + 1 Cipher. All four require deep biome runs or Seam runs. Two hunts, two Seam trips.

**Base function:** locks nearby chunks into a coherent island in the CRDT. Without a Shrine, chunks are contested and ephemeral. With one, territory is real.

**Power:** grows from player presence — the count of players physically inside the territory bubble per tick. A thriving settlement is genuinely more powerful than an abandoned one.

- High power → chunks resist decay, territory holds at its full extent
- Low power → edge chunks fade back to shifting lands, territory contracts inward
- No power → slow but steady contraction; the Shrine never disappears without being physically destroyed
- The Shrine is permanent unless destroyed. Territory is not.

**Visual:** a `PointLight2D` whose energy and range scale with power. Dim and close when weak. Vivid and far-reaching when strong. At night it becomes a beacon — visible long before you reach it. A glowing Shrine means someone is home and active. A dim one is new or abandoned.

**Appearance:** rooted but reaching. Anchored to the ground, both forces visible and in motion — a Still crystal core with Bloom tendrils slowly rotating around it. Pulse rate reflects power level. The two forces never quite touch.

**Territory and chunk retention:** see modding_design.md for full mechanics.
**Mod upgrades:** see modding_design.md.

### Shrine vs Shrine
- Two shrine territories never touch.
- The shifting lands between them are unclaimed — neither mod set applies there.
- This is the frontier: dangerous, contested, and where wars are fought.
- Neither player can directly attack the other's shrine territory through their own shrine mechanics. Conflict is physical: you have to go there.

---

## Day / Night

The day pulls you out. The night terrifies you.

- **Day** — peaceful enough to explore, gather, build. The world is beautiful. The map calls to you.
- **Night** — something is out there. Mob behavior changes, danger scales up. Being caught far from shelter is a real threat.

The day/night cycle is the heartbeat of the game. It creates a natural session rhythm: push out during the day, survive the night, assess what you gathered, plan tomorrow.

Night cannot be skipped from within an island. The clock advances in real time — you survive it or you don't. Fresh spawns without a Tether wake at dawn (see *Spawn timing* below), but once you're in the world, time moves at its own pace.

*(The clock is scoped per island, not globally — see `Per-island time of day` in the Deferred Design section for how merges blend two island clocks into one.)*

### Night serves three purposes

**1. Danger** — Sprouts spawn at dusk, flee at dawn. Night-exclusive mob variants planned (things that don't exist in daylight — seeing one for the first time creates real dread).

**2. Resource opportunity** — certain materials only appear at night. Bioluminescent fungi in Mire, frost crystals in Hollow. Night is dangerous but profitable if you're skilled enough to work it. The campfire becomes a decision point: stay safe or risk it for the good stuff.

**3. Heightened merge pressure** — the universe pushes hardest at night. Merge pressure ramp rate multiplied ~2x after dusk. The vibe cues hit hardest in the dark. A merge at night is more dangerous because you're already exposed. This is when the world feels thinnest.

### The bedroll

Removed from the spine. A campfire is the step-3 milestone — build fire, survive the night. The bedroll is a comfort item: sleep near it for passive health regen. No skip-to-dawn (shared clock). Deferred to later implementation.

Dangerous biomes near valuable resources mean the question is always: *do I push deeper, carrying what I've already got, or do I bank it first?* Full loot drop makes this genuinely tense.

---

## World Structure

### Personal islands

Every player starts on their own procedurally generated island centered on their spawn point. Danger radiates outward from the center — the further you venture, the harder it gets. You are completely alone on your island until the universe pushes you into contact with another.

This means:
- The danger gradient is personal, not global. Your deep zones are shaped by your island's generation.
- Two players who merge may have very different maps — asymmetry creates trade dynamics and strategic asymmetry.
- Early game isolation is not safety. It is a different kind of danger (see: merge pressure below).

### The two forces

The world is shaped by two natural forces. They are not good and evil — they are philosophical opposites, both indifferent to the player. You are a mortal scavenging at the edge of a war between gods who do not know your name.

**Bloom** — growth, chaos, consumption. It spreads, absorbs, transforms. Organic, fungal, bioluminescent. It does not want to destroy — it wants to become everything. Left unchecked it covers the world in slow unstoppable growth.

**Still** — order, refinement, preservation. It perfects and holds. Crystalline, geometric, cold. A forest touched by Still becomes a forest of glass — perfect, eternal, dead. It does not want to rule — it wants to fix things in their ideal form forever.

The horror of each: taken to its extreme, both end the world. Pure Bloom is everything dissolving into undifferentiated growth. Pure Still is a perfect crystal tomb.

Resources are harvested from the conflict — Bloom materials are things the growth force left behind or is in the process of becoming. Still materials are crystallized remnants, the residue of refinement. The most potent materials of each exist where the forces grind directly against each other.

### Biomes

Six biomes plus one special zone. Named by force and intensity:

| Tier | Bloom | Still |
|------|-------|-------|
| 1 — Heartland | **Verdant** — soft, living, familiar | **Moraine** — worn smooth, old stone, glacial |
| 2 — Wildlands | **Tangle** — dense, hungry, getting strange | **Shard** — geometric outcrops, crystal formations |
| 3 — Deep | **Mire** — deep fungal, bioluminescent, wrong | **Hollow** — calcified, petrified, silent as a held breath |

**The Seam** — where Bloom and Still grind against each other directly. Reality is unstable here. Neither force dominates. The shrine-tier materials exist only here, created by the friction between the two forces. This is the Rift at the edge of every island.

### Expansion grammar

Every future biome is one of three things:
- A pure expression of one force at a new tier or character (underground, coastal, elevated)
- A blend — one force dominant, the other present as a scar or intrusion
- A contested zone — neither force strong, the space between (e.g. *Scar*, *Breach*)

Names follow the same register: short, real words, slightly repurposed. One or two syllables. No compound words. Only name biomes when building them.

### Shrine territories and shifting lands

- **Shrine territories** drift toward the character of their construction materials — Bloom materials pull the territory toward growth, Still materials toward crystal. Mixed materials create unstable contested ground inside your own territory.
- **Shifting lands** sit between shrine territories — unclaimed, unmodded, dangerous, and potentially the richest areas in the game. No one has pacified them.
- When two islands merge, the shifting lands form at the seam between them. If the two shrines are of opposing forces, that seam is volatile.

---

## The Universe as Antagonist

**The universe pushes players together and pulls them apart. This is not fully under player control.**

Players do not choose when to merge with another player's world. Merge pressure is a force the universe exerts — driven by time, isolation, and proximity in the network of connected worlds. Left alone long enough, your island will drift toward others. After a merge, worlds may drift apart again.

This is the central tension of the game. You are never truly safe in isolation, and you are never truly in control of who you meet.

### Merge pressure

Each player has a loneliness pressure value that builds over time in isolation. As it rises, the probability of merging with another player's world increases. It resets after a merge event.

- **High pressure** — merge is imminent. You don't know who.
- **Low pressure** — recently merged, stable for now.

This means isolation is a temporary state, not a permanent choice. You can delay contact. You cannot prevent it forever.

### Talismans — the player's tool

Talismans are rare items that let players nudge merge pressure, not control it. They are the game's primary mechanism for exercising agency over the universe's will.

Examples of talisman effects:
- Slow the buildup of loneliness pressure (delay the next merge)
- Accelerate pressure toward a specific known player (seek contact)
- Bias the merge toward worlds with compatible biomes (safer seams)
- Temporarily repel a merge that is already in progress (not guaranteed)

Talismans are expensive, finite, and earned — not crafted from common materials. They are late-game tools for players who have already established themselves and want to manage their political situation.

**Talismans nudge. The universe decides.**

### The vibe system — how the player feels pressure

There is no merge pressure bar. The world tells you.

Merge pressure feeds into the VibeBus (tension axis). The world reads that tension and expresses it through the environment. A veteran player learns to read the signs. A new player just gets scared and doesn't know why. Both are correct responses.

**Low pressure — nothing unusual.** Normal world.

**Medium pressure — the world gets strange.**
- Wind picks up
- Ambient sounds shift — something slightly off, hard to name
- Animals look in one direction
- Screen edges desaturate slightly
- Your shadow flickers

**High pressure — something is close.**
- Distant lights on the horizon (another player's fire or shrine glow)
- Strange footprints in soft ground
- The sky at the edge of the map changes hue
- A sound you can't place

**Merge imminent — the seam opens.**
- Ground shifts at the edge of loaded chunks
- Tiles from another biome flicker in and out at the periphery
- A low heartbeat sound
- Then the other island slides into view

All cues are diegetic — they exist in the world, not as UI. The world is the interface.

---

## Materials

Harvested from the conflict between forces. Bloom materials are things the growth force left behind or is becoming. Still materials are crystallized remnants, residue of refinement. Seam materials exist only where the forces grind directly against each other.

| Tier | Bloom | Still |
|------|-------|-------|
| 1 — Common | **Pulp** — raw organic matter | **Grit** — ground stone, mineral dust |
| 2 — Uncommon | **Spore** — concentrated Bloom essence | **Vein** — crystalline mineral thread |
| 3 — Rare *(home gate)* | **Marrow** — deep biological, only drops from the Bloom night mob | **Moonstone** — crystallises on Hollow stone surfaces at night, dissolves at dawn |
| 4 — Seam only *(shrine gate)* | **Ichor** — pure Bloom, unstable, alive | **Cipher** — pure Still, a pattern that perfects whatever holds it |

Tier 3 materials are night-gated: Marrow comes from hunting the bioluminescent Bloom night creature; Moonstone must be harvested from the Hollow before dawn. Both gate the Tether. Tier 4 materials only exist in the Seam.

---

## Mobs

Creatures are expressions of whichever force dominates their biome — not monsters with backstories, but manifestations of Bloom or Still at different intensities. Weft is the exception: it belongs to neither force and exists only in the Seam.

| Tier | Bloom | Still |
|------|-------|-------|
| 1 — Verdant / Moraine | **Sprout** — something small that used to be an animal, beginning to change | **Mote** — a drifting crystalline fragment, passive until disturbed |
| 2 — Tangle / Shard | **Tendril** — fast, aggressive, reaching | **Facet** — geometric, precise, repetitive |
| 3 — Mire / Hollow | **Mass** — a thing that was several things, now one | **Form** — something perfected into a weapon, no wasted motion |
| Seam | **Weft** | **Weft** |

Weft is singular — one name regardless of which side of the Seam you approach from. It's neither force. It's the collision. It shouldn't have a comfortable name.

---

## The Flint Knife

The first crafted object and the first lesson in dual-force mechanics.

**Recipe:** stone + wood (same as the old flint tool).
**Function:** harvesting tool and weapon. No split — one object does both.

**The reveal effect:** when a mob is killed with the flint knife, it briefly shows its other side before dying. A Bloom creature momentarily crystallizes — Still structure flickering through it. A Still creature briefly pulses with organic warmth and color before shattering. Then it's gone.

This is not a power-up. It is the world showing something true: every creature is both forces underneath, expressed as one. The knife — itself both forces — cuts through the expression to the nature beneath. The vibe distortion quiets for a moment as a side effect, not a reward.

No tooltip. No explanation. The player sees it happen and wonders why.

---

## The Night

Night is one of the first enemies of the game. It takes away your vision, changes what is alive in the world, and makes reality less stable. It also offers things the day does not.

### Darkness

The player has a personal light — a lantern carried at all times — that lights roughly **8 tiles** around them. Enough to read the ground and see mobs approaching, not enough to see what's in the distance. The campfire is your intelligence radius — bigger and brighter, a place you can sit and watch the dark. Everything beyond the campfire is unknown.

The lantern makes you visible. In tier 1 biomes this is pure upside — light repels the things that hunt there. In tier 3 biomes you're advertising your position to things that hunt by light. A deep-biome player learns to crouch-douse or drop the lantern before closing in on prey.

### Light and mob behavior — the gradient

Mob behavior toward light follows the danger gradient of the island:

| Biome tier | Light behavior |
|------------|---------------|
| Tier 1 — Verdant / Moraine | Light repels. Sprouts and Motes flee campfire. The campfire is safety. |
| Tier 2 — Tangle / Shard | Mixed. Some creatures flee, some ignore, some probe the edges. |
| Tier 3 — Mire / Hollow | Light attracts. The campfire is a beacon. Mass and Form variants are drawn to it. |

New players learn: campfire = good. Then the world starts teaching the deeper rule. In the deep biomes, building a fire means committing to defend it.

**Bloom vs Still flavor:** Bloom creatures are drawn to warmth in the deep (organic, growth-seeking — a campfire in the Mire is like leaving food out). Still creatures are drawn to structure — in the Hollow, your built fire is interesting to something that perfects things.

### Campfire healing

Within campfire radius, 5 seconds out of combat → slow passive regeneration. Enough to matter over a minute of rest. Enough reason to return between raids, not just to escape mobs.

In tier 3 biomes this creates a clock: the fire heals you but draws enemies. Rest long enough to recover, leave before the next wave arrives.

### Night mobs

Two night-exclusive creatures gate the path to the Tether:

**The Bloom night mob** — bioluminescent. You can see it from far away, which means it can see you. Moves fast, dies quickly. Drops **Marrow**. The glow makes it findable but makes hunting it a mutual visibility problem. Lives in Tangle and Mire.

**The Still night mob** — barely visible until it's on top of you. Slow, high HP, hits hard. **Moonstone** does not drop from it — instead, Moonstone crystallises on Hollow stone surfaces where these creatures have been. You harvest the ground they've touched. Lives in Shard and Hollow.

Both vanish at dawn. Marrow does not drop from trees during the day. Moonstone does not form in daylight. The Tether requires the night.

### Merge pressure at night

Merge pressure ramp rate doubles after dusk. The vibe cues hit hardest in the dark — distant lights on the horizon are visible in a way they aren't during the day. Night is when you first *see* evidence of another player. The paranoia of "is that a campfire I didn't build?" is a night experience specifically.

### Moon phases

The moon advances one phase per in-game day, cycling through **new → waxing → full → waning → new** over ~8 days. The current phase changes the night in ways you learn to read:

| Phase | Night character |
|-------|----------------|
| **New moon** | Dread night. Near-total darkness beyond your lantern. Pale mobs more numerous, lower HP but more aggressive. Moonstone yield is highest — the Still is hungriest. |
| **Waxing / waning** | Standard night. Baseline spawns, baseline yield. |
| **Full moon** | Hunt night. Ambient light is enough to see the horizon. Pale mobs are fewer but stronger — high-HP, high-damage variants. Wisp glow is brighter. A good night to push into a deep biome if you can handle the bigger fish. |

The moon is visible in the sky and its phase is the only "UI" — you glance up and know what you're in for. Experienced players plan raids around the cycle: new moon for Moonstone farming, full moon for Marrow hunting, standard nights for everything else.

Moon phase is a second independent dimension layered on day/night — it collapses and blends across merges the same way time does (see deferred section).

### Spawn timing

When a player dies without a Tether anchor (fresh spawn, no home), they re-enter the world at **dawn** — local time for their island jumps forward if needed so the sunrise is waiting for them. This is non-negotiable: new players and the unanchored get a fair start. Every new reality begins in daylight.

Players who die *with* a Tether respawn at the Tether anchor at **current local time** — if it's the middle of the night, you wake up in the dark at your home and deal with it. The Tether promises continuity, not protection.

In effect: the Tether trades a fair respawn for a fixed location. The choice to build one is a choice to stop running from the clock.

---

## Design Principle: In World and Subtle

**The world communicates. The UI does not.**

No notifications. No bars. No popups. If something is happening, the world shows it. A good player reads the world. A new player gets scared and doesn't know why. Both are correct responses.

This principle governs every system — merge pressure, health, hunger, faction tension, force dominance. When designing a new mechanic, the question is always: *how does the world show this*, not *how does the UI show this*.

---

## The Merge Moment

No notification is sent when a merge occurs. The world simply changes.

### Phase 1 — Premonition *(before the merge)*
The vibe cues escalate as pressure builds. The world gets strange. A good player is already paying attention and preparing. See: *The vibe system* above.

### Phase 2 — The Merge *(the moment itself)*
Quiet and disorienting. No cutscene, no loading screen, no sound effect. You're walking and the ground is slightly different than it was. A tile you didn't place. A path that wasn't there. The world has shifted at the edges while you weren't looking. A bad player doesn't notice for a while.

### Phase 3 — The Hunt *(post-merge, pre-contact)*
Two players in a merged world, neither has seen the other. This is a full gameplay phase — reading signs, tracking, deciding whether to hide or hunt.

Signs a good player reads:
- **Disturbed tiles** — freshly harvested trees, dug ground, placed objects that aren't yours
- **Warmth** — a fire still burning, embers that are fresh
- **Tracks** — footprints in Bloom biomes, crystalline impressions in Still biomes
- **Absence** — mobs that should be here aren't. Something spooked them.
- **Light** — at night, another player's torch or campfire glow visible before they are
- **Force reaction** — if their shrine is Bloom and yours is Still, the Bloom starts creeping toward your territory before you ever see them

### Phase 4 — Contact
The first moment you see the other player. Earned, not given. If you read the signs you saw them first. If you didn't, you didn't.

The merge is an information asymmetry game. Both players share the same world but have different knowledge of it. The player who reads the signs faster has the advantage. That skill gap is meaningful and learnable — a veteran doesn't just have better gear, they notice things a new player walks past.

---

## Deferred Design (not forgotten)

- **Light mechanics** — how mobs and the world respond to artificial light. Torches, campfires, shrine glow. Does light repel Sprouts? Does it attract Tendrils? Does Still territory extinguish flame? Revisit when mob system is built.

### Per-island time of day

Time of day is a **per-island** property, not a global one. Each simulation island advances its own clock; when two islands merge, the lagging clock accelerates to catch the leader and the two merge into a single clock that both peers read identically. Time of day is a *reality dimension* — another axis the multiverse varies along, alongside biome layout, faction, and force.

**Why this is the right direction:**

1. **Fair starts.** A player who respawns without a Tether needs the world to be survivable. If we can drop them into an island that's currently at dawn, the fairness problem solves itself without breaking the "night cannot be skipped" rule for anchored players.
2. **Thematic fit.** Reality-merging is the core of the game. Two realities having different times is more interesting than two realities having the same time, and time blending across a merge is a signal the player can *read* — a second sun appearing on the horizon, a sudden gradient across the ground, the light shifting faster than it should. These are vibe cues we don't have to invent; they emerge from the mechanic.
3. **Cheap dimension.** Time collapses faster than other dimensions (tiles, structures, factions). A brief blend of lighting is visually coherent and narratively meaningful. It doesn't require rewriting the world — just interpolating a single scalar.
4. **Future hooks.** Moon phases, weather, seasonal effects can all piggyback on the same per-island clock. Any time-dependent system gets this for free once the clock is island-scoped.

**What we're giving up:**

- The ability to say "everyone faces night together." This was a coordination primitive — all players share a countdown. With per-island time, synchronized events have to be driven by something other than the clock (e.g., merge pressure, in-world signals).
- Simplicity. One global `DayClock.now()` becomes `island.day_clock.now()`, which means passing an island context into every lighting/mob/weather system that reads the clock.

**How it works as built:**

- **Island is a first-class type.** An `Island` (RefCounted, in `world/Island.gd`) owns one `DayClockInstance` and tracks its members by `session_id`. `IslandRegistry` (autoload) holds every live island and exposes `active_island()` — the one the local session currently inhabits. A peer always has at least one island; the session starts with a single default island.
- **`DayClock` is a shim.** The autoload no longer owns its clock. Every method (`is_daytime()`, `phase_fraction()`, `sky_alpha()`, `moon_phase()`, etc.) forwards to `IslandRegistry.active_island().clock`. Callsites are unchanged — `DayClock.is_daytime()` still works everywhere — but the answer now depends on which island is active.
- **Active-island swap.** `IslandRegistry.set_active_island(id)` emits `active_island_changed`; the shim rebinds its `phase_changed` relay to the new clock and calls `resync_phase()` so a stale `_last_is_day` doesn't fire spuriously. If the swap crosses a day/night boundary (old clock said day, new clock says night, or vice versa) the shim emits a synthetic `phase_changed` so `NightDarkness` and `NightSpawner` flip immediately.
- **Merge transition (the actual mechanic).** When ENet connects two peers, `MergeCoordinator` runs a two-phase handshake: each side fires `_local_merge_ready` locally and RPCs its current `total_phase` to the other side as `_remote_clock_phase`. Whichever event lands second on a peer triggers `IslandRegistry.begin_merge(remote_phase, 10s, merged_id)`. Either order is valid. The lagging peer's clock calls `accelerate_to(target_total_phase, 10s)` — its `_time_offset` ramps forward over 10 wall-seconds so its phase catches the leader. The leading peer's `accelerate_to` is a no-op (target ≤ current; never rewind). During the ramp, `MergeCoordinator._process` calls `IslandRegistry.tick_merge(delta)` so day/night boundaries crossed mid-ramp still emit `phase_changed`. Once the lagging clock reports `is_accelerating() == false` and has caught the target, both peers swap their active island to the merged one.
- **Deterministic merged-island id.** The merged island's id is `"merge:" + sorted_session_ids.join(":")`, computed identically on both peers. Both create the merged island independently and seed its clock by setting `_time_offset = target_unix_time - wall_now`, so the two freshly-constructed clocks land at observationally identical phases — no clock-object RPC needed.
- **Split.** When the merge dissolves, each peer calls `IslandRegistry.split_from_merge("solo:" + session_id)`. The session-scoped id is stable across reconnects and never collides with the partner's solo island. The new island's clock is seeded from the current converged total phase — never rewound. After a peer has merged once and split, its active island is its `solo:` island, not the original `default`.

**What's still deferred** (will land later — not blocking Phase 1):

- **Per-chunk visual blend across the merge seam** — the "second sun on the horizon" / sky-gradient effect from the original sketch. The clock data is per-island already, but the lighting pipeline still draws one sky for the local viewport.
- **Per-island moon phases.** `moon_phase()` works per-clock today, but no system exposes a different moon to a remote-island observer.
- **Spawn picker preferring near-dawn islands.** Fresh spawns still resolve to whichever island the spawn system picks; the picker doesn't yet weight by clock phase.
- **Persistence.** Islands and their clocks are ephemeral — created at session start, destroyed at exit. Tying islands to the Tether/home concept (so a peer's solo island survives across sessions) is a later phase.

---

## Open Questions (design, not tech)

1. **Shrine conflict mechanics** — can you destroy someone's shrine? Does it require physical presence? Does it require defeating its defenders first? Is the home's physical object (the flag) the same model as the shrine anchor?
2. **Home destruction** — tied to a physical object that must be found and destroyed. Requires presence, creating real risk for the attacker.
3. **Resource gating** — what are the rare materials that gate the home and shrine? Where do they live on the danger map? (needs a biome draft)
4. **Faction mechanics** — how do tribes/factions form mechanically? Is it purely social, or does the game support shared ownership of structures/shrines?
5. **New player experience in a mature world** — what prevents late-game players from instantly destroying new players? Is that even a problem worth solving, or is "get absorbed by a faction" the intended answer?
6. **Merge pressure tuning** — how fast does loneliness build? Is it time-based, activity-based, or both? What does a merge event actually feel like moment-to-moment?

---

## What This Doc Is Not

This is not a tech tree. The tech tree is derived from this once the spine is stable.  
This is not a feature list. Features are how we implement the emotional beats above.  
This is not final. It will be wrong in places. Update it when it is.

---

## Related Docs

- `modding_design.md` — shrine territory mechanics, mod system, primitive vocabulary
- `architecture.md` — how Freenet contracts map to game state
- `phase_0_1_plan.md` — current implementation status
