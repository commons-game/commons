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

- **Biome difficulty scales with resource value.** Good materials live in dangerous places. The map is a risk/reward map that players memorize over time — that knowledge is power.
- **Shifting lands** (between shrine territories) are the wildest and most dangerous areas, but potentially the most rewarding. No one owns them; no one has pacified them.
- **Shrine territories** are islands of relative safety and expressed identity. Entering someone else's territory means playing by their rules (their mods, their creatures, their tile set).

---

## Open Questions (design, not tech)

1. **Shrine conflict mechanics** — can you destroy someone's shrine? Does it require physical presence? Does it require defeating its defenders first?
2. **Home destruction** — how is a home destroyed? Player must be present? Requires a specific item? Can be griefed from range?
3. **Resource gating** — what are the rare materials that gate the home and shrine? Where do they live on the danger map?
4. **Faction mechanics** — how do tribes/factions form mechanically? Is it purely social, or does the game support shared ownership of structures?
5. **New player experience in a mature world** — what prevents late-game players from instantly destroying new players? Is that even a problem worth solving, or is the "get absorbed by a faction" path the intended answer?

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
