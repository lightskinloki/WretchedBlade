# Wretched Blade — Godot 4 Setup Guide

## 1. Install Godot 4

Download **Godot 4.3** (or newer) from https://godotengine.org/download
Choose the standard version (not .NET unless you want C#).

---

## 2. Open the project

1. Launch Godot
2. Click **Import**
3. Navigate to `C:\WretchedBlade\`
4. Select `project.godot` → **Import & Edit**

---

## 3. Create the scene files

Godot uses `.tscn` files for scenes. You create these in the editor by building node trees.
Follow each section below exactly. The scripts are already written — you just need to attach them.

---

### Scene: `res://scenes/game/Game.tscn`

**File → New Scene**, then build this tree:

```
Node2D              [name: "Game", script: res://scenes/game/Game.gd]
├── World           [Node2D]
├── Player          [CharacterBody2D, script: res://scripts/player/Player.gd]
│   ├── CollisionShape2D    [shape: RectangleShape2D, size: 20×40]
│   ├── ProjectedBody       [Node2D]
│   │   └── BodySprite      [Sprite2D]
│   ├── WretchedBlade       [Node2D, script: res://scripts/player/WretchedBlade.gd]
│   │   ├── BladeSprite     [Sprite2D, position: (0, -24)]
│   │   └── AttackHitbox    [Area2D]
│   │       └── CollisionShape2D  [shape: RectangleShape2D, size: 40×16, position: (20, -20)]
│   └── Camera2D            [enabled: true, zoom: (2,2)]
├── TouchInput      [CanvasLayer, script: res://scripts/ui/TouchInput.gd]
│   ├── JoystickZone        [Control, anchors: full left half, mouse_filter: Ignore]
│   │   └── JoystickBase    [Control, size: 128×128, visible: false]
│   │       └── Thumb       [Control, size: 48×48, position: (40,40), color: white circle]
│   └── ButtonZone          [Control, anchors: full right half]
│       ├── AttackButton    [Control, size: 80×80, position bottom-right area]
│       ├── JumpButton      [Control, size: 80×80, above AttackButton]
│       └── DodgeButton     [Control, size: 80×80, left of AttackButton]
├── HUD             [CanvasLayer, script: res://scripts/ui/HUD.gd]
│   ├── EssenceLabel        [Label, anchor: top-left, text: "0 ESS"]
│   ├── FormLabel           [Label, anchor: top-center, text: "EXECUTIONER"]
│   └── LostEssenceLabel    [Label, anchor: top-right, text: "", visible: false]
└── DeathScreen     [CanvasLayer, script: res://scripts/ui/DeathScreen.gd, visible: false]
    ├── Background          [ColorRect, anchors: full rect, color: #00000099]
    ├── YouDiedLabel        [Label, anchor: center, text: "YOU DIED", font size: 48]
    ├── HoldPrompt          [Label, anchor: center, text: "Hold to Reconstitute", below YouDied]
    ├── HoldBar             [ProgressBar, anchor: center-bottom, size: 300×20, max: 100]
    └── FlashRect           [ColorRect, anchors: full rect, color: transparent]
└── TransitionScreen [CanvasLayer, script: res://scripts/ui/TransitionScreen.gd, mouse_filter: Ignore]
    ├── BlackOverlay        [ColorRect, anchors: full rect, color: #000000]
    ├── FlashRect           [ColorRect, anchors: full rect, color: #8000CC]
    └── RoomLabel           [Label, anchor: center, text: "", font size: 32, horizontal: center]
```

**Save** as `res://scenes/game/Game.tscn`.
Set it as the main scene: **Project → Project Settings → Application → Run → Main Scene**.

---

## 4. Pixel art rendering setting

The project.godot already sets this, but double-check:
**Project → Project Settings → Rendering → Textures → Canvas Textures → Default Texture Filter → Nearest**

This prevents pixel art from being blurred.

---

## 5. Android export (when ready)

1. **Project → Export → Add → Android**
2. Install the Android build tools when prompted
3. In Export settings, set **Orientation** to Portrait
4. Hit **Export Project**

You'll need Android Studio or the Android SDK installed for this step.

---

## 6. Run the game (PC first)

Press **F5** (or the Play button) to test on PC before exporting.
You can test touch controls with mouse clicks — left half moves, right half has buttons.

---

## 7. File structure reference

```
C:\WretchedBlade\
├── project.godot              ← Project config (autoloads, display settings)
├── autoload\
│   ├── GameManager.gd         ← Game state (death, checkpoints, respawn)
│   ├── EssenceManager.gd      ← Souls currency system
│   ├── PixelRenderer.gd       ← ALL visuals generated here (no image files!)
│   └── LockOn.gd              ← Lock-on singleton (target tracking, facing direction)
├── scenes\
│   └── game\
│       ├── Game.tscn          ← YOU create this in the editor
│       └── Game.gd            ← Main scene logic
├── scripts\
│   ├── player\
│   │   ├── Player.gd          ← The Projected Body (movement, combat routing)
│   │   └── WretchedBlade.gd   ← The TRUE SELF (health = blade visual state)
│   ├── ui\
│   │   ├── TouchInput.gd      ← Virtual joystick + buttons
│   │   ├── HUD.gd             ← Essence count, weapon form name
│   │   ├── DeathScreen.gd     ← "Hold to Reconstitute" mechanic
│   │   └── TransitionScreen.gd ← Room transition fades + flash
│   └── world\
│       └── WorldGenerator.gd  ← Procedural tile rooms
└── SETUP.md                   ← This file
```

---

## 8. Design Philosophy

**Procedural everything — absolute.** Every visual, room, enemy, puzzle, dungeon, region, map, and system is generated at runtime by rule-driven algorithms. Zero pre-made assets. The generation system must be robust and controllable enough to produce exactly the intended experience from parameters alone. This is a hard constraint. Nothing is authored.

**Three-tier structure: Overworld → Region Maps → Dungeons.**

- **Overworld:** Mario-style hub. Nodes represent regions (7 regions, 7 Dominators). Player selects a region.
- **Region Map:** Each region is a connected web of dungeon nodes (DBZ Sparking Zero / Mario 3 style). Enter at a start node, clear dungeons to expand reachable territory. Can only traverse beaten nodes. Carve a path to the boss dungeon — no key-gating, no item-gating, just path. Node count, connections, and layout are fully procedural per playthrough.
- **Dungeon:** A 5-beat procedural run. Enter, fight through, return to region map.

**Five-section dungeon structure.** Every dungeon follows narrative beats, not room counts:
- Approach & Guardian → Puzzle/Challenge → Exploration & Setback → Climax (Boss) → Reward & Resolution

Sections are NOT rooms. Each beat is a design intention; the generator decides how many rooms it needs. A dungeon might have 5 rooms or 20. Room count emerges from difficulty parameters and progression context.

**Replaying dungeons.** Cleared dungeons can be re-entered. Normal enemies and mid-bosses respawn. The section boss is gone. Boss dungeon final rooms offer Echo Mode — fight a phantom of the boss for half essence value, no other rewards.

**Dungeon generation — two-pass system.** Dungeons use a DungeonPlan: a complete read-only data structure generated upfront (Pass 1) describing every room, its section role, puzzle wiring, enemy composition, and checkpoint positions. Pass 2 renders rooms on-demand, executing the plan. Puzzle constraints are resolved entirely in the plan — no room is retroactively modified. Dying drops your essence. Dying again without gaining new essence preserves the old drop — the orb stays until you reach it. Gaining even 1 essence before dying replaces the old orb. Enemies respawn on death but NOT on resting — resting at a checkpoint heals without penalty and preserves room-clearing progress. Checkpoint count scales with dungeon length: 1 per 5 rooms (0 for ≤5 rooms, 1 for 6-10, 2 for 11-15, etc.). The generator places them at natural midpoints, not at section boundaries.

---

## 9. Build order

### Phase 1 — Core Combat (Done)
- [x] Player movement (walk, jump, dodge)
- [x] 3-hit combo attack system (orbital blade arcs, input buffering, lunge)
- [x] Nullman enemy (proximity, core-glow telegraph, pulse radial damage, counter)
- [x] RivalBlade enemy (dual-wield, two-layer AI: priority engine + per-fight learning)
- [x] RivalBlade verbs: dodge (i-frames), counter (parry + riposte), feint, recovery trap, pacing
- [x] Essence system (currency, drops, lost essence orbs)
- [x] Checkpoints and death/respawn
- [x] Hitstop, counter, blade damage states
- [x] Combo counter HUD, room transitions
- [x] Lock-on system (autoload singleton, Tab toggle, facing override, reticle)
- [x] RivalBlade per-blade hitboxes (follow blade sprites, per-combo enable/disable)
- [x] Nullman shard textures (procedural noise-driven, per-seed personality)
- [x] Nullman pulse glow (soft circle via ImageTexture, tweened)

### Phase 2 — Overworld + Region Map
- [ ] Overworld map hub screen (procedural node layout for 7 regions)
- [ ] Region map generator (procedural node web per region, path-based progression)
- [ ] Transition flow: Overworld → Region Map → Dungeon → Region Map → Overworld

### Phase 3 — Dungeon Generator
- [ ] Dungeon generator (5-section beat-driven, variable room count per beat)
- [ ] WorldGenerator refactor (dungeon-level parameters, exit to region map)
- [ ] Puzzle system (pressure plates, breakable walls, platforming triggers)
- [ ] Checkpoint placement (1 per 5 rooms, natural midpoints)
- [ ] Echo Mode for replayed boss dungeon final rooms

### Phase 4 — First Region: Fractured Yards
- [ ] Geocrash visual theme and generation parameters
- [ ] Region map layout (procedural web, start → path → boss node)
- [ ] Dungeon pool (procedural dungeons with Geocrash-themed enemies + puzzles)
- [ ] Guardian: Champion Nullman (Geocrash-aligned)
- [ ] Climax: The Shattered Sovereign (Dominator 1, unlocks Phantom form)
- [ ] Reward flow: Weapon Form + Tuning Fork + optional Lesser Hex

### Phase 5 — Depth Systems
- [ ] Save/load (checkpoints, forms, essence, Hex Affinity)
- [ ] Weapon Form system (absorbed combat philosophy per Dominator)
- [ ] Tuning Fork / Resonance Art system (attunement at checkpoints)
- [ ] Lesser Hex system (buy from defeated Dominators, affects ending)
- [ ] Hex Affinity Score → ending tracking
- [ ] Remaining 6 regions with distinct Hex themes
