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

### Biomes and resources

- **Biome difficulty scales with resource value.** Good materials live in dangerous places.
- The map is a risk/reward map that players memorize over time — that knowledge is itself power.
- Biomes are matched at merge seams. When two islands collide, the CRDT connects them at compatible edges — forests bleed into forests, not forests slamming into deserts. Incompatible seams become shifting lands naturally.

### Shrine territories and shifting lands

- **Shrine territories** are islands of relative safety and expressed identity. Entering someone else's territory means playing by their rules.
- **Shifting lands** sit between shrine territories — unclaimed, unmodded, dangerous, and potentially the richest areas in the game. No one has pacified them. No one owns what spawns there.
- When two islands are pushed together by merge pressure, the shifting lands form at the seam between them.

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
