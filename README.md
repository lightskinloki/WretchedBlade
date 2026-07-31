# Wretched Blade

> [!CAUTION]
> **ABSOLUTE PROJECT RULE**: 100% RUNTIME PROCEDURAL GENERATION. ZERO PRE-MADE ASSETS. ZERO EXCEPTIONS.
> Everything — rooms, UI, background scenery, hub sanctuaries, enemies, player, maps — MUST be procedurally generated at runtime via `PixelRenderer`, `RoomTerrainGenerator`, and `WorldGenerator`. Any attempt to use static image assets, ad-hoc shape placeholders, or non-procgen bypasses is a critical violation. See [CORE_RULES.md](file:///c:/WretchedBlade/CORE_RULES.md).

A 2D souls-like ARPG built entirely from procedurally generated pixel art.
No image assets. Zero exceptions. Every single aspect is runtime-generated.

## Design Pillars

### 1. Procedural Everything — Absolute

Every visual, room, enemy, puzzle, dungeon, region, map, and system is generated at runtime by rule-driven algorithms. There are zero pre-made assets — no tilemaps, no sprite sheets, no hand-placed encounters, no hand-authored layouts. The generation system must be robust and controllable enough to produce exactly the intended experience from parameters alone. This is a hard constraint. Nothing is authored.

**The Procedural Invariant:** Every coordinate, dimension, and structural element in room generation must arise from a rule evaluated at generation time — never from a fixed constant, ratio, or pre-determined template. A room that always places a pillar at 35% width is not procedural; it is a parameterized template that will eventually produce an untraversable room at some combination of dimensions and portal positions. The generation system starts from portal positions and builds outward, guaranteeing traversal by constructive rules, not by carving doorways into a fixed layout. See `design philosophys and lore/Dungeon Generation Pipeline - Architecture Plan.txt` Section VIII for the full specification.

### 2. The WretchedBlade

The player's true self is a floating sword — a primordial Nullman born from the First Hexocaust. The tiny projected body (1.25x scale) is a puppet of localized Nullpulse energy. It stays pristine forever. Damage, blood, cracks, and wear only appear on the blade. The blade orbits the body on attack arcs, telekinetically linked. The player is the sword.

### 3. Three-Input Combat

- **Attack (Z)**: 3-hit combo chain (Slash → Uppercut → Thrust). Orbital blade arcs, auto-lunge to nearest enemy, input buffering.
- **Dodge (X/Shift)**: Invincibility frames, repositioning.
- **Counter (C)**: Parry timing during enemy windup, triggers stun.

One-button flow (Arkham) with vertical depth and juggling (Bayonetta/DMC).

### 4. Overworld → Region Maps → Dungeons

The game has a three-tier structure, all procedural:

**Overworld Map** — A Mario-style hub screen. Nodes represent regions, not dungeons. The player selects a region to enter.

**Region Maps** — Each region (Fractured Yards, Hollow Expanse, etc.) is a connected web of dungeon nodes (DBZ Sparking Zero / Mario 3 style). The player enters at a starting node and clears dungeons to expand their reachable territory. They can only traverse nodes they have beaten. The boss dungeon node becomes reachable once a path of beaten dungeons connects to it. Not all dungeons need to be cleared — only enough to carve a path. The node count, connections, and layout are fully procedural per playthrough.

Each region is ruled by a Dominator — an ancient Nullman embodying that region's Hex. Defeating the Dominator weakens their grip on the region and grants a new Weapon Form and Tuning Fork.

**Dungeons** — Each node on the region map is a procedural 5-section dungeon run (see pillar 5). The player enters, fights through, and returns to the region map on completion.

There are 7 regions, one per Dominator, plus the final Throne of Ashes.

### 5. Five-Section Dungeon Structure

Every dungeon follows this narrative beat map (adapted from TTRPG design):

| Section | Beat | Gameplay |
|---|---|---|
| **1. Approach & Guardian** | Entry + first obstacle | Safe entry room, then a champion enemy that establishes the dungeon's threat and theme |
| **2. Puzzle / Challenge** | Non-combat change of pace | Dungeon-specific challenge: pressure plates, breakable walls, platforming gaps, corpse puzzles, or unique mechanics |
| **3. Exploration & Setback** | Deepening stakes + complication | Series of rooms with escalating encounters, ending with a mid-way ambush, blocked path, or other complication |
| **4. Climax** | Boss confrontation | Major threat — mini-boss for standard dungeons, Dominator phase for boss dungeons |
| **5. Reward & Resolution** | Payoff | Essence cache, form fragment, checkpoint, lore node, shortcut back to region map |

**Critical: sections are NOT rooms.** A section is a thematic beat. The generator decides how many rooms each beat needs — a Puzzle could be 1 room or 3, Exploration & Setback could be 4 rooms or 12. Room count emerges from difficulty parameters and progression context, never from fixed ranges.

**Replaying dungeons:** Cleared dungeons can be re-entered. Normal enemies and mid-bosses respawn. The section boss is gone. If the dungeon was a boss dungeon, the final room offers a choice: take the exit, or activate **Echo Mode** — fight a phantom of the boss for half its essence value (no other rewards).

### Dungeon Generation Architecture — Two-Pass System

Dungeon generation is a two-pass process to support puzzle wiring and coherent design.

**Pass 1 — Planning:** Generates a `DungeonPlan` — a complete read-only data structure describing the entire dungeon before any node exists. This includes:

- Section layout: how many rooms per beat, their order and connections
- Room metadata: section type, room type, width/height, tile grid template
- Puzzle wiring: which triggers (pressure plates, breakable walls) wire to which locks (doors, blocked paths), with room indices as references
- Enemy composition: which enemies spawn in which rooms, their formations
- Checkpoint positions: which room indices contain checkpoints
- Boss data (for boss dungeons): arena layout, phase triggers

The plan is a flat array of room plans, each room plan containing all data needed to render it. Puzzle wiring is resolved entirely in the plan — the generator never needs to modify a room retroactively.

**Pass 2 — Rendering:** Walks the `DungeonPlan` room-by-room. For each room:
1. Generate tile geometry (`WorldGenerator` with section-aware parameters)
2. Instantiate sprites, collision, enemies, puzzle elements
3. Wire puzzle triggers to their target locks (both nodes exist in the scene, connection is straightforward)

Rooms are rendered on-demand as the player approaches exits, but the plan guarantees every room's constraints are satisfied before any room is rendered. This makes puzzle generation feasible: a pressure plate in room 3 can lock a door in room 7 because the plan already knows about both rooms and their relationship.

### 6. Death, Essence & Checkpoint Loop

**Essence is persistent and unbankable** (Elden Ring-style). No vault, no deposit — the only way to secure it is to survive the dungeon and return to the region map.

- **Essence drops on death** at the player's position as a Lost Essence orb.
- **Recovery is unlimited — as long as you gain nothing.** If you die en route to your old drop without collecting a single essence, the orb stays. If you gained even 1 essence before dying, the old orb is replaced by a new one at your current death spot.
- **Enemies respawn on death, not on resting.** Every death is a full room reset. Resting at a checkpoint heals without penalty — enemies stay dead, cleared rooms stay cleared.
- **Checkpoints scale with dungeon length:** 1 checkpoint per 5 rooms (0 for ≤5 rooms, 1 for 6-10, 2 for 11-15, etc.). The generator places them at natural midpoints, not at section boundaries.

**Two failure modes:**
- Die with new essence → old drop replaced (standard souls loss)
- Die with zero new essence → drop stays (patient recovery rewarded)

**Two recovery approaches:**
- Fight through — kill enemies (risks gaining essence, putting old drop at stake)
- Sprint through — dodge everything (risks dying before reaching orb, preserves drop)

### 7. Regions, Dominators & Progression

The player's goal: permakill all 7 Dominators across the Severed Lands. The Wretched Blade is the only entity capable of permanently ending a Nullman — other Nullmen simply reform.

Each region is defined by the Hex that scarred it (Geocrash, Voidrend, Echoscream, Memoreave, Nullpulse, Technomantic Corruption, Composite). Defeating a Dominator grants:
- A new Weapon Form (absorbed combat philosophy + Hexic resonance)
- A Tuning Fork, granting a Resonance Art (non-corrupting alignment ability)
- The option to take on a Lesser Hex (adds to Hex Affinity Score — affects ending)

Hex Affinity Score tracks how much corruption the player has embraced. Higher scores push toward darker endings. Ending choices branch into distinct NG+ modes.

The 7 Dominators and their regions:
1. The Shattered Sovereign — Fractured Yards (Geocrash)
2. The Void Echo — Hollow Expanse (Voidrend)
3. The Screaming Spire — Resonant Ruins (Echoscream)
4. The Memory Thief — Forgotten Archive (Memoreave)
5. The Nullpulse Heart — Unraveling Core (Nullpulse)
6. The Rust Tyrant — Corroded Expanse (Technomantic)
7. The Final Echo — Throne of Ashes (Composite — the Blade's inverse)

## Lore

The world was our own. Humanity discovered the fundamental frequencies of reality (Resonance) and created Tuning Forks — artifacts of harmony. But ambition twisted this knowledge into Hexes — violent, discordant frequencies forced onto the Nullpulse. Seven Hexocausts followed, each tearing deeper wounds in reality and spawning the Nullmen: human ego imprinted onto the Nullpulse in the moment of the First Hexocaust's psychic shockwave.

The Wretched Blade is different. It was not formed from human consciousness hitting the Nullpulse, but the *Nullpulse* violently colliding with the *collective human subconscious* — a reverse-formed Nullman, the scar of the Nullpulse on the human psyche. It took all seven cycles of cataclysm to fully manifest. It alone can permakill other Nullmen.

The world is now the Severed Lands — a wasteland of ash, rust, bone, shattered concrete, and reality-broken territories where the rules of existence degrade the deeper you go. Humans survive alongside Nullmen as resilient, mortal competitors.

## How to Run

Open the project in Godot 4 (`project.godot` at `C:\WretchedBlade`), ensure `Game.tscn` is set as the main scene (Project → Project Settings → Application → Run → Main Scene), and press **F5**.

*Note: This is a living build. Script changes may require reloading the project to take effect.*

## Current Build State

### Implemented
- Combat system: 3-hit combo with orbital blade arcs, input buffering, auto-lunge
- Enemies: Nullman (proximity detection, core-glow telegraph, pulse radial damage, counter/stun), RivalBlade (dual-wield, two-layer AI: priority decision engine + per-fight learning, dodge/counter/punish/pressure/pace footsies, feint, recovery traps, adaptive combo bias)
- Lock-on system: `LockOn` autoload singleton, Tab to toggle nearest enemy, facing override when locked
- Lock-on reticle: diamond targeting ring with pulse animation, follows locked target
- World generation: Procedural rooms (floor, platforms, nullstone, abyss pits), linear room-to-room transitions
- Systems: Essence currency, checkpoints, lost essence orbs, hitstop (real-time clock), counter system, death/respawn
- Blade visual states: damage stages, shatter threshold
- Combo counter HUD with milestone colors
- Per-attack windup fractions (Slam 0.35, Uppercut 0.0)
- Nullman shard visuals: procedural noise-driven jagged texture with per-seed personality, missing-chunk mechanic, fracture-surface bottom
- Nullman pulse glow: soft white circle via PixelRenderer ImageTexture pipeline, tweened scale+alpha
- RivalBlade per-blade hitboxes: hitboxes follow blade sprites as children, per-combo-hit enable/disable
- Velocity spike detector: prints physics stacking collisions from move_and_slide for debugging
- Damage-source logging: player take_damage prints caller file/line/function via get_stack()
- NaN safety: safe_margin 1.0px on CharacterBody2D + post-move_and_slide sanitize
- RivalBlade counter deflect system: absorbs hits during counter, ripostes 10 dmg to player
- RivalBlade learning system: feint, recovery traps, dodge-direction combo bias, aggression-adaptive pressure_mod
- Named constants extracted: COMBO_WINDOW, LUNGE_RANGE, COUNTER_RANGE, COUNTER_DAMAGE, layer masks

### In Development
- Overworld map hub screen
- Region map generation (procedural node web, path-based progression)
- Dungeon generator (5-section beat-driven runs with variable room counts)
- Puzzle system (pressure plates, breakable walls, platforming, corpse puzzles)
- Seven regions with distinct Hex themes and generation parameters
- Dominator boss AI (multi-phase, Hex-themed attack patterns)
- Weapon Form system (absorbed from defeated Dominators)
- Tuning Fork / Resonance Art system
- Essence sinks: Lesser Hex purchases, Resonance Art fuel
- Death/essence loop with safe recovery rule
- Echo Mode for replaying boss dungeons
- Checkpoint placement (1 per 5 rooms, generator-placed)
- Lock-on camera: center between player and locked target
- Save/load persistence
- Ending system (Hex Affinity Score → multiple endings → NG+ modes)

## Technical
- **Engine**: Godot 4 (GDScript, strict typing)
- **Rendering**: `PixelRenderer` autoload — all textures generated at runtime via `ImageTexture`
- **Platforms**: Mobile-first (touch controls, haptic), PC secondary
- **No external assets**: Zero images, zero audio files
