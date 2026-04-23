# Commons — Modding System Design
_Working document — April 2026_

## Core Philosophy

Mods are dimensions. When players walk into a modded dimension, the engine loads a different configuration — different tiles, enemies, items, rules. No dimension requires arbitrary code. All behavior is expressed by configuring a predefined schema of primitives.

**Why no user code:**
- Sandboxing arbitrary GDScript/Lua is a nightmare: security, versioning, cross-platform determinism, multiplayer consistency
- Every player in a session must run the same mod — arbitrary code creates desync vectors
- Data is inspectable, diffable, storable in Freenet contracts; code is not safely distributable over P2P

**The Minecraft redstone analogy:**
Redstone doesn't let you write code — it lets you wire together bounded primitives (gates, triggers, timers, comparators) to produce complex emergent behavior. The primitives are safe. The compositions can be surprisingly deep.

This game's modding system is the same idea: a bounded vocabulary of triggers, effects, and conditions that players compose to define behavior. The engine interprets the composition; no custom code runs.

---

## What Players Can Define

### Custom Tiles / Blocks
Fields a mod author specifies:
- `sprite` — reference to a sprite sheet cell
- `solid` — bool, blocks movement
- `passable_by` — list of entity tags that can walk through anyway (e.g., ghosts)
- `on_place` — list of effects triggered when a player places this tile
- `on_remove` — list of effects triggered when removed
- `on_walk` — list of effects triggered when an entity steps on it
- `on_proximity` — list of effects triggered when an entity is within N tiles
- `decay_rate` — how fast this tile degrades without player presence (feeds into chunk weight)
- `tags` — arbitrary labels used by other definitions to reference this tile type

### Custom Entities / Enemies
Fields:
- `sprite` / `sprite_sheet` — visual
- `health`, `damage`, `speed` — base stats
- `movement_pattern` — enum: `idle`, `patrol`, `chase`, `flee`, `wander`, `follow`
- `aggro_conditions` — list of conditions that trigger aggression (e.g., `player_proximity`, `tile_removed_nearby`)
- `on_hit` — effects triggered when struck
- `on_death` — effects triggered on death (drops, spawns, tile changes)
- `on_idle_tick` — periodic effects when not aggro'd
- `loot_table` — weighted list of item references
- `tags` — used by other definitions

### Custom Items
Fields:
- `sprite`
- `item_type` — enum: `consumable`, `placeable`, `equippable`, `talisman`
- `on_use` — effects triggered on use
- `on_equip` / `on_unequip` — effects triggered when equipped/removed
- `passive_effects` — continuous effects while in inventory or equipped
- `merge_pressure_modifier` — float multiplier on the player's loneliness pressure (talismans!)
- `biome_affinity` — biases merge events toward matching biomes
- `tags`

### Custom Biomes / Zones
Fields:
- `tile_set` — weighted palette of tile type references for procedural generation
- `entity_spawns` — weighted spawn table
- `ambient_effects` — passive effects applied to players present in this biome
- `music_track` / `ambient_sound` — audio references
- `sky_color`, `light_level` — visual mood

---

## The Primitive Vocabulary

All behavior is expressed by composing these:

### Triggers (when does something happen)
- `on_place`, `on_remove`, `on_walk`, `on_proximity(radius)`, `on_use`, `on_equip`
- `on_hit(source_tags)`, `on_death`
- `on_timer(interval_seconds)` — periodic
- `on_event(event_name)` — receives a named event broadcast

### Conditions (optional filter on a trigger)
- `has_tag(entity_tag)` — the triggering entity has this tag
- `has_item(item_ref)` — the triggering player carries this item
- `has_buff(buff_ref)` — the triggering entity has this buff
- `health_below(percent)` / `health_above(percent)`
- `tile_at(offset, tile_ref)` — a tile of a specific type exists at a relative position
- `time_of_day(range)` — if game has day/night
- `biome_is(biome_ref)`
- `random(probability)` — random gate

### Effects (what happens)
- `apply_buff(buff_ref, duration)` — add a buff to an entity
- `remove_buff(buff_ref)`
- `deal_damage(amount, damage_type)`
- `heal(amount)`
- `spawn_entity(entity_ref, offset)` — spawn at relative position
- `place_tile(tile_ref, offset)` — modify the world
- `remove_tile(offset)`
- `drop_item(item_ref)`
- `broadcast_event(event_name, radius)` — fire a named event to nearby listeners
- `modify_merge_pressure(delta)` — nudge the player's loneliness pressure
- `play_sound(sound_ref)`
- `show_message(text)` — simple UI notification

### Buffs (reusable named stat/behavior modifiers)
Defined separately and referenced by effects:
- `speed_modifier`, `damage_modifier`, `defense_modifier`
- `can_walk_through(tile_tag)` — phasing
- `invisible_to(entity_tag)` — stealth
- `merge_pressure_multiplier(value)`
- `emit_light(radius, color)`
- Duration: timed, permanent, until-removed

---

## Composition Example

A trap tile that slows players, then explodes if they don't move off it:

```yaml
tile:
  id: sticky_trap
  sprite: custom_tiles:trap_01
  solid: false
  on_walk:
    - condition: has_tag(player)
      effects:
        - apply_buff(buff:slowed, duration: 5.0)
        - broadcast_event(event:trap_triggered, radius: 0)
  on_event(trap_triggered):
    - condition: random(0.3)
      effects:
        - deal_damage(15, fire)
        - remove_tile(0,0)
        - place_tile(tile:scorch_mark, 0,0)
```

No code. Fully inspectable data. Every client running this dimension loads the same definition and produces identical behavior.

---

## Shrines — The Mod Authority Object

**Shrines** are the mechanism by which mods take hold in the world. A shrine is a special in-game placeable object (a tile/entity hybrid) that claims a territory of chunks and pushes a mod set onto that territory.

### Properties
- A shrine references one or more mod bundles that it activates within its territory
- Shrine territories are **mutually exclusive** — two shrines cannot claim the same chunk
- The shrine is not tied to any player — it's an object in the world, subject to the same CRDT chunk lifecycle as any tile
- Any player who enters a shrine's territory has the shrine's mod set loaded automatically
- If a shrine is destroyed (removed from the world), its territory reverts to vanilla/wilderness rules

### Why this works

**Mod conflict is now a spatial/gameplay question, not a technical one.** Two mods that define conflicting tile behavior cannot coexist in the same area because two shrines cannot share territory. Conflict resolution happens through gameplay — players contest shrine territory, defend their shrine, build shrines in unexplored wilderness. The engine never has to arbitrate between two active mod sets in the same chunk.

**Cross-mod references become safe within a shrine.** A shrine can bundle multiple mod packs together into a single active set. Within that set, mods can reference each other's definitions freely. The shrine is the namespace boundary — `shrine_A::mod_X` can reference `shrine_A::mod_Y`'s tile types, but a tile from `shrine_B` can never affect `shrine_A`'s territory. Engine never resolves cross-shrine mod interactions.

**Shrines are world objects, not player config.** This means:
- They persist in Freenet chunk contracts like any tile
- They can be discovered, studied, contested, or protected
- A shrine planted in the wilderness and then abandoned still influences that territory (until it fades with chunk weight)
- Shrines can be part of mod definitions themselves — a mod can define "a shrine that spawns itself" as a craftable item, creating a deployable dimension-portal

### Shrine territory mechanics

**Territory is dynamic and organic — not a fixed radius.**
- The shrine chunk is the anchor/seed.
- Modified chunks adjacent to the shrine chunk (or to other chunks already in the territory) automatically join the territory.
- Territory grows outward through player activity: build things, explore, modify tiles → more chunks glue onto the shrine.
- Territory shrinks through abandonment: unvisited/unmodified edge chunks fade and detach, contracting the territory back toward active areas.
- No special structures or explicit claiming action needed — territory is purely emergent from the chunk weight system.

**Neighborhood weight bonus.**
A chunk that is part of a shrine's territory gets a weight multiplier from its neighbors — each adjacent modified chunk in the same territory contributes to its persistence. Isolated modified chunks at the edge fade faster; chunks surrounded by active territory are very durable. This creates organic, blob-like territories that contract from the edges inward when abandoned.

**Shrine boundaries: no-man's land.**
When two shrine territories expand toward each other and their chunks would touch, those boundary chunks revert to **vanilla game defaults** — neither shrine's mod set runs there. This creates a no-man's land buffer between competing shrine territories. Neither side can activate their mods in that contested zone. 

Possible future: the no-man's land could become a special biome ("The Contested Reaches" or similar) — visually distinct, potentially with its own vanilla-plus rules that feel like the two dimensions bleeding into each other without either winning.

Shrines cannot be moved (they are tiles, not carried objects). Displacing a shrine requires destroying it, which collapses its territory back to wilderness.

---

## Mods as Freenet Contracts

A mod bundle is a set of definition files (YAML source → compiled binary). Stored as a Freenet contract:
- Contract state = the compiled mod bundle bytes
- Content-addressed — tamper-evident, you get exactly what the shrine references
- Players entering shrine territory subscribe to the mod contract and download the bundle
- No code executes; the Godot client interprets the bundle against the primitive vocabulary

Mod properties on the network:
- **P2P distributed** — no central mod repository, no approval process
- **Tamper-evident** — content-addressed Freenet contracts
- **Inspectable** — players can read a shrine's mod definition before walking in
- **Offline-cacheable** — downloaded once, reused across sessions

---

## In-Game Mod Editor

**Decision: Build early, not MVP.** The editor is central to the game's identity — if mods are dimensions and dimensions are the multiverse, then the editor is how the multiverse gets populated. A YAML-only workflow is a developer tool; an in-game editor is a player feature.

**Approach:** Build on top of the same primitive vocabulary used at runtime. The editor is just a UI for constructing the data structures the engine already interprets. No special editor-only logic.

**Rough scope:**
- Tile painter for custom sprites
- Field editor for triggers/conditions/effects (dropdown selection, not text input)
- Preview window showing a small sandbox of the mod's behavior
- "Publish to shrine" action that packages the bundle and creates a shrine object in the world

The editor itself can be a mod of sorts — it's just a special UI layer over the same data model.

---

## Constraints and Anti-Abuse

Because mods are data, not code:
- No file system access, no network calls, no process spawning — impossible by design
- Effects vocabulary is the complete set of things that can happen
- Worst a malicious mod can do: create annoying gameplay. Cannot compromise the client.
- Shrine territorial exclusivity prevents mod griefing at distance — you have to physically place a shrine to affect an area
- Reputation system applies to mod bundles — reported/flagged bundles get lower discovery weight and merge-routing deprioritization

**Determinism:** All effects are deterministic given the same inputs. Mods cannot introduce desync.

---

## Shrine Boundary Behavior (when mods turn off)

Three distinct cases, each with a simple rule:

**Enemies / mod-defined entities:**
Take damage as they approach the shrine boundary. Die at the border. Like a vampire in sunlight — they cannot cross. This naturally contains shrine creatures within their territory, creates an interesting defensive/offensive tactic (lure enemies to the border), and needs zero complex state management.

**Player-carried mod items:**
Remain in inventory but become **dormant** — they exist as objects but have no effects outside their shrine's territory. When the player re-enters the shrine's territory, they reactivate automatically. Side effect: players can carry items from one dimension as trophies or tools in another, as long as they're willing to travel back to activate them. Emergent cross-dimension gameplay with no special engineering.

**Buffs from mod effects:**
Simply disappear at the boundary. No graceful transition. Buff was granted by that dimension's rules; outside those rules, it doesn't exist.

**Editor timeline:** Post core single-player tile loop, pre-multiplayer. This gives a working editing experience for authoring test content before multiplayer complexity enters.

---

## What This Doesn't Support (intentionally)

- Custom UI screens / HUDs
- New movement/physics mechanics
- Custom network protocols
- AI behavior beyond the `movement_pattern` enum
- Persistent cross-session player state mutations

These can expand over time by extending the primitive vocabulary — never by adding user code.

---

## Open Questions

1. **Format pipeline**: YAML source (human-authored) → compiled binary (Freenet storage). Need a `commons-mod-compiler` tool. Part of the in-game editor's "publish" action.
2. **Versioning**: Pinned. A shrine always runs the exact mod bundle version it was built with (content-addressed). To update, a player must physically go to the shrine in-game and select the new version — the shrine then stores the new content hash. This is intentional: updates require presence and intent, not background auto-apply.
3. **Performance budget on triggers**: Max active effect listeners per chunk. No way to know without testing — design the system with a configurable cap, tune from data.
4. **Shrine territory size and expansion mechanics**: Fixed radius vs buildable? What's the UX for seeing territory boundaries?
5. **Editor timeline**: Not MVP but early. Define "early" — after core single-player loop? After basic multiplayer? Needs a milestone anchor.
