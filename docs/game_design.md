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
| 2 | Craft flint tool | Faster gathering, can fight back | Stone + wood |
| 3 | Build first camp (fire + bedroll) | Survive the night | Flint + wood |
| 4 | Claim a home | Permanent spawn anchor — death has memory now | Rare material from dangerous area |
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
- One per player. Destroyable by other players.
- Early game: losing your home is devastating — you lose your spawn anchor.
- Late game: rebuilding is cheap. The emotional weight scales correctly.
- Getting your first home is the first real inflection point of the game.

### Shrine
- One per player. Independent of the player — persists after you die.
- Base function: locks nearby chunks into a coherent island in the CRDT. Without a shrine, your chunks are contested and ephemeral. With one, your territory is real.
- Grows as a chunk ball outward from the anchor point (see modding_design.md for territory mechanics).
- Upgrades apply mods to the territory (see modding_design.md).
- Placing a shrine is the second inflection point of the game.

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
| 3 — Rare *(home gate)* | **Marrow** — deep biological, taken from something living | **Sinter** — fused mineral, formed under pressure |
| 4 — Seam only *(shrine gate)* | **Ichor** — pure Bloom, unstable, alive | **Cipher** — pure Still, a pattern that perfects whatever holds it |

Tier 4 materials only exist in the Seam. Getting them requires surviving the most dangerous zone in the game.

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
