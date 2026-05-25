# Wretched Blade — Dungeon Boss Generator

## Core Design

Every dungeon boss is a **Nullman** — a human ego that collided with the Nullpulse
during one of the seven Hexocausts and was warped into existence. The Hex that
corrupted them determines their theme; their pre-corruption identity (encoded as
body type) determines their fighting style. The combination of body type + Hex
theme + difficulty + phase produces a unique boss every dungeon.

**Region Dominators** (The Shattered Sovereign, etc.) are a separate system —
hand-authored ancient Nullmen who retained their identity. They share the
`BossEnemy` base class but are individually designed, not generated.

---

## Generation Pipeline

```
DungeonPlan                         BossBlueprint
┌─────────────────┐                ┌──────────────────────┐
│ seed            │────hex_theme──→│ hex_theme            │
│ hex_theme       │    body_type   │ body_type            │
│ difficulty      │    difficulty  │ body_stats (derived) │
│ room_dimensions │                │ abilities[]          │
└─────────────────┘                │ phase_count          │
         │                         │ arena_hazards[]      │
         ↓                         │ visual_params        │
   BossEnemy.spawn_for_dungeon(blueprint)
         │
         ↓
   BossEnemy instance
   ├── body (Sprite2D via PixelRenderer)
   ├── hitbox (body_type determines shape/size)
   ├── ability_patterns[]
   ├── phase_controller
   ├── arena_manager (door lock, hazards)
   └── health_bar_ui
```

---

## Axis 1 — Body Types (7)

Each body type defines physical framework: hitbox dimensions, base stats, slot
count, movement behavior, and available ability pool. Abilities are shared across
body types but filtered by compatibility rules.

| # | Type | Hitbox | HP× | Speed | Vertical | Slots | Stagger | Movement AI |
|---|------|--------|-----|-------|----------|-------|---------|-------------|
| 1 | Bruiser | 48×64 | 1.8× | 60 | Low | 2-3 | High | Walk toward → stop → attack. Slow turn. Short chase before reset |
| 2 | Skirmisher | 32×48 | 1.0× | 100 | Mid | 2-3 | Mid | RivalBlade-like pacing. Strafe, approach, back off. Combo-oriented |
| 3 | Skitterer | 20×28 | 0.6× | 160 | High | 1-2 | Low | Erratic. Quick advance → flurry → retreat. Wall-jump capable |
| 4 | Sentinel | 36×52 | 2.0× | 0 | None | 2-4 | Very High | Rooted at spawn. Vision cone turns to face player. Ranged pressure |
| 5 | Stalker | 28×44 | 0.8× | 120 | High | 2 | Low | Teleport-behind. Hit-and-run. Prefers flanking angles |
| 6 | Colossus | 80×96 | 3.0× | 30 | None | 3-4 | Extreme | Room-filling. Slow advances. Must dodge, not block. Spectacle attacks |
| 7 | Wraith | 24×40 | 0.7× | 110 | Extreme | 1-2 | None | Passes through terrain/floor. Ethereal drift. Uncounterable by default |

### Body Type → Lore Inference

The pre-corruption identity encoded by each body type is never stated to the
player, but informs the generation parameters and makes each fight feel distinct:

| Type | Pre-Nullman archetype | Fight feel |
|------|-----------------------|------------|
| Bruiser | Stubborn, unyielding, dominant | Heavy impact, slow but relentless |
| Skirmisher | Adaptive, tactical, competitive | Duel-like, responsive, fair |
| Skitterer | Anxious, reactive, desperate | Chaotic, punishing, disorienting |
| Sentinel | Devoted, protective, rigid | Defensive, positional, attrition |
| Stalker | Hunted, paranoid, predatory | Ambush, pressure, misdirection |
| Colossus | Overwhelmed consumed, too much ego | Spectacle, terror, methodical |
| Wraith | Dissolved identity, barely holding | Alien, unfair, otherworldy |

---

## Axis 2 — Hex Themes (7)

Each theme corresponds to one of the seven Hexocausts. The theme determines
visual palette, arena hazards, and ability flavor. **Composite** is reserved for
the final Dominator and is NOT used for dungeon bosses.

| Theme | Lore | Visual Palette | Damage Type | Player read |
|-------|------|----------------|-------------|-------------|
| Geocrash | Stone & earth corrupted by seismic Nullpulse resonance | Brown, amber, gray. Jagged cracks, dust particles, crude stone plating | Crushing | Boss feels heavy. Attacks leave terrain changes |
| Voidrend | Reality torn open by void frequency | Deep purple, black, toxic green. Rippling void edges, stars in darkness | Void | Boss warps space. Teleports, summons darkness |
| Echoscream | Sonic resonance weaponized as torture | White, cyan, blue. Concentric shockwave rings, translucent ripples | Sonic | Everything is telegraphed audibly/visually. Patterns are rhythmic |
| Memoreave | Psychic imprint of memories forced into matter | Pink, violet, translucent white. Afterimages, fractal edges | Psychic | Boss creates illusions — clones, fake terrain, confusion effects |
| Nullpulse | Raw uninhibited Nullpulse corruption | White-void center, crimson edges. Pulsing radial waves, tendril wisps | Null (true damage) | No resistance. Health drain. Stand clear of AoE |
| Technomantic | Machinery & industry corrupted by forced resonance | Steel gray, orange glow, electric blue. Geometric patterns, spark arcs, gear shapes | Arcane | Boss uses constructs — turrets, beams, drones. Fight the battlefield |
| Composite | All seven Hexes resonating together | Shifts between all palettes. Flickers randomly per second | Variable | Mirrors player. Unpredictable. Reserved for Throne of Ashes (not dungeon gen) |

### Theme → Ability Flavor Mapping

Every ability (from Axis 3) gets a visual/thematic coat of paint based on Hex theme.

| Base ability | Geocrash | Voidrend | Echoscream | Memoreave | Nullpulse | Technomantic |
|---|---|---|---|---|---|---|
| Ground Slam | Rubble eruption. Creates stone platform | Void eruption. Leaves dark pool on ground | Sonic boom. Ring expands outward | Psychic blast. Fractal ripple on ground | Pulse burst. Tendrils radiate from impact | Shockwave. Metal plates lift, sparks fly |
| Charge (rush) | Boulder roll. Cracks trail behind | Shadow dash. Leaves afterimage trail | Sonic dash. Speed lines + ring trail | Identical clone charge (player can't tell which is real) | Void slide. Trail of Null essence | Rocket boost. Exhaust flame trail |
| Ranged projectile | Thrown rubble (lobbed arc) | Shadow bolt (homing, slow, dark trail) | Sonic bolt (instant, thin, blue line) | Psychic bolt (slow, translucent, wobbly fake) | Null orb (telegraphed big ball) | Missile (dumb-fire, explosion on contact) |
| Summon Minion | Stone fragment — small Nullman, slow | Shadow copy — translucent, 1 HP | Echo clone — emits ping on hit | Memory fragment — fading, deals psychic DoT | Null spawn — pulses damage aura | Drone — floats, fires periodically |
| Phase transition | Screen shake, rubble falls from ceiling | Darkness pulse, ambient dark, void tears appear | Ring expansion, screen flash white | Screen static, clone of previous phase appears briefly | Bright flash, Null tendrils sweep arena | Sparks rain, metal screech sound |

---

## Axis 3 — Ability Definitions

### Universal (any body type)

| # | Ability | Windup | Active | Recovery | CD | Range | Counterable | Phase | Notes |
|---|---------|--------|--------|----------|----|-------|-------------|-------|-------|
| U1 | Dodge Dash | 0.05s | 0.12s | 0.05s | 2.5s | Self | No | 1+ | Brief i-frame, thematic trail, repositions 60px |
| U2 | Phase Shift | 0.5s | 0.8s | 0.3s | — | Full | No | Trigger | Plays on phase transition. AoE burst, knockback, 1s boss invuln |
| U3 | Summon Minion | 0.4s | 0.1s | 0.3s | 8.0s | Near boss | No | 1+ | Summons 1-2 theme-flavored minions (small Nullmen or theme-specific) |

### Bruiser Pool (7)

| # | Ability | Windup | Active | Recovery | CD | Range | Damage | Phase | Counterable | Notes |
|---|---------|--------|--------|----------|-----|-------|--------|-------|-------------|-------|
| B1 | Ground Slam | 0.6s | 0.3s | 0.5s | 4.0s | Close (AoE 60px) | 14 | 1 | Yes (last 0.2s of windup) | Shockwave travels along floor. Jump to dodge |
| B2 | Heavy Swipe | 0.4s | 0.25s | 0.4s | 2.5s | Close (180° arc) | 10 | 1 | Yes (mid windup) | Wide arc. Catches rolls behind |
| B3 | Charge | 0.5s | 0.6s | 0.3s | 5.0s | Any → wall | 12 | 1 | Yes (startup window) | Stops at wall. Leaves hazard trail. Boss recovers on hit |
| B4 | Rubble Toss | 0.3s | — | 0.4s | 3.0s | Far (lobbed) | 8 | 1 | No | AoE on landing (40px radius). Lobbed over obstacles |
| B5 | Stomp | 0.15s | 0.1s | 0.2s | 2.0s | Point-blank | 6 | 1 | No | Quick interrupt. Breaks player combos |
| B6 | Body Slam | 0.5s | 0.4s | 0.5s | 6.0s | Any | 16 | 2 | Partial (jump arc) | Leaps to player position. Damage on landing |
| B7 | Enrage | 0.3s | 6.0s duration | — | 12.0s | Self | — | 2 | Yes (cast window) | +30% speed, +25% damage for 6s. Boss glows phase color |

### Skirmisher Pool (7)

| # | Ability | Windup | Active | Recovery | CD | Range | Damage | Phase | Counterable | Notes |
|---|---------|--------|--------|----------|-----|-------|--------|-------|-------------|-------|
| S1 | Combo Slash | 0.15s per hit | 0.12s per hit | 0.1s per hit | 2.0s | Close | 6×2 or 6×3 | 1 | Yes (hit 1 only) | 2-3 hit chain. Uses RivalBlade arc positioning |
| S2 | Dash Strike | 0.2s | 0.25s | 0.2s | 3.0s | Mid-Far | 10 | 1 | Yes (travel hitbox) | Gap closer + strike in one motion |
| S3 | Whirlwind | 0.3s | 0.4s | 0.3s | 4.0s | Close (360° AoE) | 8 (×2 hits) | 1 | Partial (first frame only) | Two-hit spin. Tight counter window |
| S4 | Throw Weapon | 0.2s | 0.3s travel | 0.2s | 2.5s | Far | 7 | 1 | No | Boomerang. Returns to boss. Hits twice if player moves into return path |
| S5 | Kick | 0.15s | 0.1s | 0.15s | 1.8s | Close | 5 | 1 | Yes | Knockback. Sets up spacing |
| S6 | Parry | 0.1s | 0.3s | 0.2s | 4.0s | Self | 10 riposte | 2 | No | Counter stance. If player hits it → boss ripostes. Mind-game |
| S7 | Uppercut | 0.2s | 0.15s | 0.25s | 3.0s | Close | 9 | 2 | Yes (late windup) | Launches player airborne. Sets up air follow-up |

### Skitterer Pool (7)

| # | Ability | Windup | Active | Recovery | CD | Range | Damage | Phase | Counterable | Notes |
|---|---------|--------|--------|----------|-----|-------|--------|-------|-------------|-------|
| K1 | Quick Swipe | 0.08s | 0.08s | 0.1s | 1.2s | Close | 4 | 1 | Yes (tight 0.05s) | Very fast. Requires prediction to counter |
| K2 | Leap Attack | 0.2s | 0.3s travel | 0.15s | 3.0s | Far | 7 | 1 | Partial (landing only) | Pounces to player position |
| K3 | Venom Spit | 0.15s | — | 0.15s | 2.5s | Far | 3 + DoT | 1 | No | Leaves poison pool on ground (DoT 2s, 1/sec) |
| K4 | Bind | 0.2s | 1.2s effect | 0.2s | 5.0s | Mid | 0 | 2 | No | Roots player for 1.2s. Boss approaches during root |
| K5 | Evade | 0.0s | 0.2s | 0.0s | 2.0s | Self | — | 1 | No | Quick teleport dodge. Repositions behind player. Can trigger mid-combo |
| K6 | Flurry | 0.1s | 0.4s | 0.2s | 4.0s | Close | 3×5 | 2 | No | Rapid 5-hit. Low per-hit, high total. Boss locked in place |
| K7 | Venom Burst | 0.5s | 0.2s | 0.3s | 6.0s | Close AoE | 8 | 2 | Yes (charge window) | Charged poison explosion. Punishable with counter |

### Sentinel Pool (7)

| # | Ability | Windup | Active | Recovery | CD | Range | Damage | Phase | Counterable | Notes |
|---|---------|--------|--------|----------|-----|-------|--------|-------|-------------|-------|
| N1 | Volley | 0.3s | 0.5s | 0.3s | 3.0s | Far | 5×3 | 1 | No | 3-projectile spread |
| N2 | Ground Pulse | 0.5s | 0.3s | 0.4s | 4.0s | Mid AoE | 10 | 1 | Yes (charge-up) | Radial expanding circle. Jump to dodge |
| N3 | Summon Minion | 0.4s | 0.1s | 0.3s | 8.0s | Near boss | — | 1 | No | Same as universal U3, included for Sentinels that get extra minion focus |
| N4 | Beam | 0.6s | 0.5s | 0.4s | 5.0s | Full arena | 14 | 2 | Partial (charge only) | Charged line. Boss rotates toward player during charge |
| N5 | Shield | 0.2s | 2.0s | 0.2s | 6.0s | Self | — | 2 | No | Invulnerable for 2s. Can't attack. Good time to reposition/heal |
| N6 | Mine | 0.2s | — | 0.2s | 3.5s | Mid | 10 | 1 | No | Places proximity mine on ground. 40px detonation radius |
| N7 | Artillery | 0.4s | 0.8s delayed | 0.3s | 5.0s | Far | 12 | 2 | No | Marker on player position → 1s delay → large AoE |

### Stalker Pool (7)

| # | Ability | Windup | Active | Recovery | CD | Range | Damage | Phase | Counterable | Notes |
|---|---------|--------|--------|----------|-----|-------|--------|-------|-------------|-------|
| L1 | Shadow Strike | 0.1s | 0.15s | 0.2s | 2.0s | Any | 8 | 1 | Partial (arrival frame) | Teleport to player + melee. Tight counter on reappearance |
| L2 | Claw Swipe | 0.12s | 0.1s | 0.12s | 1.5s | Close | 5 | 1 | Yes | Standard melee. Quick |
| L3 | Phase Walk | 0.0s | 2.0s | 0.1s | 5.0s | Self | 2× next | 2 | No | Invisible 2s. Next attack deals double damage. Can't hit player while invisible |
| L4 | Shadow Bolt | 0.2s | 0.4s travel | 0.2s | 2.5s | Far | 6 | 1 | No | Homing projectile. Slow enough to dodge |
| L5 | Backstab | 0.1s | 0.1s | 0.2s | 3.0s | Close | 12 | 2 | No | Only triggers if behind player. Heavy damage. Dodged by facing boss |
| L6 | Clone | 0.3s | 0.1s | 0.2s | 8.0s | Self | — | 1 | No | Creates 1 decoy (1 HP). Decoy mimics attacks (deals 0 damage). Disappears on hit |
| L7 | Tether | 0.3s | 0.5s pull | 0.2s | 4.0s | Mid | 0 | 2 | Yes (cast window) | Connects to player → pulls them toward boss over 0.5s. Interrupt with counter |

### Colossus Pool (7)

| # | Ability | Windup | Active | Recovery | CD | Range | Damage | Phase | Counterable | Notes |
|---|---------|--------|--------|----------|-----|-------|--------|-------|-------------|-------|
| C1 | Giant Fist | 0.8s | 0.35s | 0.6s | 5.0s | Close | 20 | 1 | Yes (late windup) | Massive damage. Telegraph is obvious. Room shakes |
| C2 | Stomp | 0.3s | 0.2s | 0.3s | 4.0s | Full (shockwave) | 8 | 1 | No | Screen shake. Jump to avoid shockwave (platforming check) |
| C3 | Eye Beam | 0.5s | 0.8s sweep | 0.4s | 6.0s | Full | 16 | 2 | Yes (startup glow) | Slow sweeping beam. Dodge through or behind cover |
| C4 | Meteor | 0.6s | 0.6s delay | 0.3s | 7.0s | Any | 18 | 2 | No | Targeted. Long windup. Big zone (80px radius) |
| C5 | Earthquake | 0.4s | 1.0s | 0.5s | 8.0s | Full | 12 | 3 | Yes (windup) | Phase transition or enrage attack. Continuous screen shake. Jump to avoid |
| C6 | Summon Rubble | 0.3s | 0.5s | 0.3s | 6.0s | Arena | — | 2 | No | Raises/lowers 3-4 floor sections. Changes arena layout |
| C7 | Roar | 0.6s | 0.3s | 0.3s | 7.0s | Full | 0 (stun 1s) | 3 | Yes (charge window) | Stuns player for 1s if not interrupted. Boss approaches during stun |

### Wraith Pool (7)

| # | Ability | Windup | Active | Recovery | CD | Range | Damage | Phase | Counterable | Notes |
|---|---------|--------|--------|----------|-----|-------|--------|-------|-------------|-------|
| W1 | Ghost Touch | 0.1s | 0.08s | 0.1s | 1.5s | Close | 5 | 1 | No | Pierces player i-frames (partial). Feels unfair — balanced by low damage |
| W2 | Shadow Orb | 0.3s | 0.6s travel | 0.2s | 3.0s | Far | 7 | 1 | No | Homing orb. Follows player until hit or timeout (3s) |
| W3 | Phase Shift | 0.1s | 1.5s | 0.1s | 6.0s | Self | — | 1 | No | Wraith becomes intangible. Passes through terrain. Can't be hit |
| W4 | Spectral Wail | 0.4s | 0.3s | 0.3s | 5.0s | Mid AoE | 5 + slow | 2 | Yes (cast) | Cone AoE. Reduces player speed 40% for 2.5s |
| W5 | Ethereal Bind | 0.35s | 1.5s effect | 0.3s | 6.0s | Mid | 1×3 DoT | 2 | Yes (cast) | Roots player 1.5s. Deals 3 ticks of 1 damage. Wraith approaches |
| W6 | Possess | 0.3s | 1.2s effect | 0.2s | 7.0s | Mid | 0 | 2 | No | Inverts player controls for 1.2s. Left → right, jump → crouch |
| W7 | Banshee Scream | 0.5s | 0.3s | 0.4s | 6.0s | Close-Mid cone | 14 | 3 | Yes (windup) | Cone scream. Interrupts player action. Huge damage |

---

## Axis 4 — Ability Selection Algorithm

```
generate_boss(seed, hex_theme, difficulty, room_dimensions):

    1. Roll body_type from difficulty-weighted distribution:
       - Easy (diff < 0.3):   Skitterer 35% | Skirmisher 35% | Bruiser 20% | Sentinel 10%
       - Medium (0.3–0.7):    Skirmisher 30% | Bruiser 25% | Sentinel 20% | Stalker 15% | Skitterer 10%
       - Hard (> 0.7):        Colossus 25% | Stalker 20% | Skirmisher 20% | Wraith 15% | Sentinel 10% | Bruiser 10%
       (Any body type can appear at any difficulty — this is distribution bias, not exclusivity)

    2. Calculate slots (1-3) from body type + difficulty bonus:
       base_slots = body_type.min_slots   # 1-2
       bonus = 0 if difficulty < 0.3 else (1 if difficulty < 0.7 else 2)
       slots = min(base_slots + bonus, body_type.max_slots)

    3. Select abilities:
       pool = body_type.ability_pool + [U3 Summon Minion if difficulty > 0.5 AND body_type != Sentinel]
       selected = []

       # Phase 1 guarantee: pick 1-2 abilities that have phase=1
       phase1_pool = [a for a in pool if a.phase == 1]
       selected += pick_random(phase1_pool, max(1, slots - 1))

       # Phase 2 ability: add 1 from phase≤2
       if slots > selected.size():
           phase2_pool = [a for a in pool if a.phase <= 2 and a not in selected]
           if phase2_pool: selected += [pick_random(phase2_pool)]

       # Phase 3 ability: add 1 from phase≤3 (for hard dungeons)
       if slots > selected.size():
           phase3_pool = [a for a in pool if a.phase <= 3 and a not in selected]
           if phase3_pool: selected += [pick_random(phase3_pool)]

    4. Universal abilities:
       always_add(U1 Dodge Dash) if body_type != Sentinel
       always_add(U2 Phase Shift) — phase transition

    5. Build blueprint with:
       - body_type, hex_theme, difficulty
       - phase_abilities[phase1][], phase_abilities[phase2][], phase_abilities[phase3][]
       - body_stats (HP×, speed, hitbox from body_type table)
       - arena_hazards (from hex_theme, 1-2 per phase)
       - visual_params (palette, body color, glow color)
```

---

## Axis 5 — Phase Generation

| Rule | Detail |
|------|--------|
| **Phase count** | 2 phases if difficulty < 0.4, else 3 phases |
| **Phase 1 trigger** | Starting state |
| **Phase 2 trigger** | 50% HP remaining |
| **Phase 3 trigger** | 25% HP remaining (only if 3-phase boss) |
| **Speed increase** | +10% move speed per phase |
| **New ability** | +1 ability unlocked per phase. Phase 2 abilities unlock at 50% HP, Phase 3 at 25% |
| **Phase shift animation** | Boss freezes 0.5s → flash + shockwave (60px AoE, knockback + 8 damage) → boss invuln 1s → new phase begins |
| **Visual change** | Boss sprite re-rendered per phase: more cracked/damaged, brighter core glow, color shift toward pure theme color |
| **Arena escalation** | Phase 1: no hazards. Phase 2: 1 hazard type activates. Phase 3: all hazards + intensified version |
| **Cooldown reset** | All ability cooldowns reset on phase transition |
| **Pattern reset** | Boss pattern cycle resets. Phase 2/3 starts with new ability as opener |

---

## Axis 6 — Arena Generation

Boss rooms use `RoomArchetype.Archetype.RITUAL_CHAMBER` which generates a central
raised platform with steps and corner platforms.

### Door Lock

When the player enters a boss room:
1. WorldGenerator spawns the boss at the center of the arena
2. BossEnemy emits `boss_room_entered` on next physics frame after player fully enters
3. Door lock: adds a `StaticBody2D` collision block over the entry portal
4. Optional visual: stone door rising / energy wall / darkness barrier (theme-dependent)
5. Door unlocks on boss death

### Arena Hazards (by Theme)

Generated from the hex_theme. 1-2 hazards per boss fight, activated by phase.

| Theme | Hazard | Phase | Mechanic |
|-------|--------|-------|----------|
| Geocrash | Collapsing floor | 2 | Floor tiles flash → collapse 1s later. Player falls → respawn on platform + minor damage |
| Geocrash | Rising pillars | 2 | Stone pillars rise from floor (player can stand on them). Block line of sight. 3-4 locations |
| Geocrash | Rubble piles | 1 | Existing terrain debris. Blocks movement. Destroyable by boss abilities |
| Voidrend | Void pool | 2 | Dark pool on ground. Standing in it = 2 dmg/sec. Expands over time |
| Voidrend | Darkness zone | 2 | Circular area where player vision is reduced to 40px. Lasts 4s |
| Voidrend | Teleport pad | 3 | Two pads. Touching one sends player to the other |
| Echoscream | Resonance crystal | 1 | Crystal on wall. Next damage player takes is amplified 1.5×. Destroyable |
| Echoscream | Echo field | 2 | Zone that copies damage dealt to player onto boss (or vice versa). 6s duration |
| Memoreave | Confusion field | 2 | Large zone where player controls are scrambled (jump→dodge) |
| Memoreave | Illusion wall | 1 | Fake wall/floor that looks real but isn't. Player falls through |
| Memoreave | Memory fragment | 3 | Shows ghost of where player stood 2s ago. Deals DoT if player is near it |
| Nullpulse | Corruption cyst | 2 | Cyst grows on wall. If boss touches it → heals 5 HP. Player can destroy it |
| Nullpulse | Null zone | 1 | Zone on ground. Player standing in it loses 3 essence/sec (no HP damage) |
| Nullpulse | Pulse node | 3 | Node emits pulse every 4s. Radial damage wave. Jump to dodge. Destroyable |
| Technomantic | Wall turret | 2 | Turret on wall. Fires at player every 3s. Destroyable (15 HP) |
| Technomantic | Tesla coil | 2 | Arc of electricity between two coils. Walking between them = damage. Can be destroyed |
| Technomantic | Conveyor | 1 | Forced movement on floor section. Pushes player toward hazard or boss |

### Camera

When the player locks onto a boss:
- Camera centers on midpoint between player and boss
- Zoom adjusts based on boss body type (reflected in BossBlueprint):
  - Bruiser/Skirmisher/Sentinel/Stalker/Wraith: 1.8×
  - Skitterer: 2.0× (smaller, needs less space)
  - Colossus: 1.4× (much larger, needs more visibility)
- Camera returns to normal on boss death or unlock

---

## Axis 7 — Sprite Generation

`PixelRenderer.generate_boss_texture(blueprint)` produces the boss sprite at runtime.

### Generation Pipeline per Phase

1. **Base silhouette** — outline from body type template:
   - Bruiser: Wide rectangle with rounded top, slight shoulders
   - Skirmisher: Taller rectangle, defined shoulders
   - Skitterer: Small circle/oval with legs/appendages
   - Sentinel: Wide base, tapered top. Pillar-like
   - Stalker: Narrow, elongated, crouched
   - Colossus: Massive rectangle filling most of sprite
   - Wraith: Wispy, irregular edges, gaps

2. **Theme texture overlay** — noise-driven pattern matching the hex theme:
   - Geocrash: Stone crack noise, sediment bands
   - Voidrend: Voronoi void cells, star speckle
   - Echoscream: Concentric ring patterns, wave interference
   - Memoreave: Fractal branching, color gradients
   - Nullpulse: Radial gradient from white center to red edge
   - Technomantic: Grid lines, gear teeth, rivet dots

3. **Core glow** — center bright spot, intensity varies by Hex

4. **Phase decoration** — additive per phase:
   - Phase 1: Clean silhouette, full theme texture
   - Phase 2: Crack lines appear, core glow brighter, missing chunks (10-15% of silhouette)
   - Phase 3: Heavy cracking, 20-30% missing, core exposed, color desaturated toward white

### Texture Size Reference

| Body Type | Texture Size | Scale | Screen Presence |
|-----------|-------------|-------|-----------------|
| Bruiser | 32×48 | 1.5× | Fairly large |
| Skirmisher | 24×36 | 1.25× | Human-sized |
| Skitterer | 16×20 | 1.0× | Small, fast |
| Sentinel | 28×40 | 1.3× | Towering |
| Stalker | 22×36 | 1.2× | Lanky |
| Colossus | 60×72 | 1.5× | Room-filling |
| Wraith | 20×32 | 1.1× | Ethereal |

---

## Axis 8 — Difficulty Tuning

Difficulty value (0.0–1.0) comes from the dungeon generator and affects:

| Parameter | Easy (0.0) | Medium (0.5) | Hard (1.0) |
|-----------|-----------|-------------|------------|
| HP multiplier | 0.7× | 1.0× | 1.4× |
| Move speed | -15% | 0% | +20% |
| Ability slots | 1 | 1-2 | 2-3 |
| Ability CD multiplier | 1.3× (longer CD) | 1.0× | 0.8× (shorter CD) |
| Phases | 2 | 2 | 3 |
| Phase 2 ability unlock | At 40% HP | At 50% HP | At 60% HP |
| Phase 3 ability unlock | — | — | At 30% HP |
| Arena hazards | 0 | 1 | 2 |
| Minion count | 0 | 1 | 2 |
| Counter window | +30% longer | Normal | -20% shorter |
| Boss body type bias | Skitterer/Skirmisher | Balanced | Colossus/Stalker/Wraith |

---

## Axis 9 — Lore Integration Rules

1. **Every dungeon boss is a Nullman** — corrupted human ego. The generation
   pipeline is not just a gameplay mechanic; it's diegetic. The `body_type` roll
   represents the psychological profile of the person who was corrupted. The
   `hex_theme` represents which Hexocaust they died in.

2. **The Wretched Blade's permakill** — when a boss dies, it doesn't just
   dissolve. The Blade absorbs the freed ego into the Nullpulse. This is why
   bosses drop essence. The Blade is the only entity capable of this. Other
   Nullmen simply reform.

3. **Region Dominators** (The Shattered Sovereign, etc.) are the same kind of
   entity — Nullmen — but they have survived long enough to consume enough
   ambient corruption to retain their pre-Hexocaust identity. That's why they
   have names, unique designs, and are hand-authored instead of generated. They
   are not procedurally generated because they are individuals, not fragments.

4. **Dungeon bosses cannot spawn near their region's Dominator room** — the
   Dominator's presence suppresses lesser Nullmen. If a boss dungeon node is
   adjacent to the region boss node, the dungeon boss is always one tier weaker
   (fewer abilities, less HP). This is lore-informed: the Dominator is draining
   power from nearby corruption.

5. **Composite theme is never rolled for dungeon bosses** — it represents the
   Throne of Ashes, where all seven Hexes resonate together. Only the final boss
   uses Composite.

---

## BossEnemy Base Class (`scripts/enemy/BossEnemy.gd`)

```
BossEnemy (extends CharacterBody2D)
│
├── Properties
│   ├── max_hp: int
│   ├── current_hp: int
│   ├── phase: int (1-3)
│   ├── body_type: int (enum)
│   ├── hex_theme: int (enum)
│   ├── blueprint: BossBlueprint (readonly, generated)
│   ├── is_arena_active: bool
│   └── is_boss_defeated: bool
│
├── Signals
│   ├── boss_room_locked
│   ├── boss_defeated
│   ├── phase_changed(phase: int)
│   └── health_changed(hp: int, max_hp: int)
│
├── Public Methods
│   ├── static spawn_for_dungeon(blueprint: BossBlueprint, position: Vector2, room_dimensions: Vector2i) -> BossEnemy
│   ├── take_damage(amount: int, knockback: Vector2)
│   ├── is_counterable() -> bool
│   ├── countered() — stun + damage bonus
│   └── get_blueprint() -> BossBlueprint
│
├── Internal Systems
│   ├── _phase_controller — checks HP thresholds, triggers phase transitions
│   ├── _pattern_controller — cycles through current phase's abilities, manages cooldowns
│   ├── _movement_ai — per-body-type movement logic (chase, strafe, teleport, root)
│   ├── _arena_manager — door lock/unlock, hazard spawn/destroy
│   ├── _camera_controller — lock-on zoom override
│   └── _visual_state — sprite render per phase, damage flash, death animation
```

### BossBlueprint (Data Class)

```
BossBlueprint:
    seed: int
    body_type: int
    hex_theme: int
    difficulty: float
    
    body_stats:
        hitbox_size: Vector2
        hp_multiplier: float
        move_speed: float
        vertical_tracking: float (0.0 = none, 1.0 = full)
        stagger_resistance: float (0.0 = fragile, 1.0 = unstoppable)
        slot_count: int
    
    phase_abilities: Array[Array]  # per phase: list of ability IDs
    universal_abilities: Array[int]
    
    arena_hazards: Array[int]  # hazard type IDs
    hazard_phases: Array[int]  # which phase each hazard activates in
    
    camera_zoom: float
    sprite_size: Vector2
    sprite_params: Dictionary  # passed to PixelRenderer
```

---

## Data Tables (Separate Files)

| File | Content |
|------|---------|
| `scripts/enemy/boss_data/body_types.gd` | 7 body type definitions (stats, hitbox, slots, movement AI type) |
| `scripts/enemy/boss_data/body_ability_pools.gd` | Ability IDs per body type + universal pool |
| `scripts/enemy/boss_data/ability_definitions.gd` | All 49 abilities as data Dictionaries (timing, damage, phase, counterable, flavor mapping) |
| `scripts/enemy/boss_data/hex_themes.gd` | 7 theme definitions (palette, hazard pool, visual params) |
| `scripts/enemy/boss_data/arena_hazards.gd` | Hazard definitions (type, activation rules, visual) |
| `scripts/enemy/boss_data/difficulty_scaling.gd` | Difficulty parameter modifiers |
| `scripts/enemy/boss_data/generation_rules.gd` | Body type → ability selection algorithm, difficulty body bias, phase rules |

---

## Build Order

| Step | What | Depends On |
|------|------|------------|
| 1 | `scripts/enemy/boss_data/` — all data tables (body_types, ability_definitions, hex_themes, arena_hazards, difficulty_scaling, generation_rules) | Nothing |
| 2 | `boss_abilities/` — 49 individual ability scripts (each extends a shared AbilityBase) | Data tables |
| 3 | `BossEnemy.gd` — base class (health, phase engine, pattern controller, movement AI, arena manager, camera stub) | Data tables, abilities |
| 4 | `PixelRenderer.generate_boss_texture()` — boss sprite generation per body_type + hex_theme + phase | Body type data, hex theme data |
| 5 | `BossBlueprint` generator — takes seed + hex_theme + difficulty → complete blueprint | Data tables, generation rules |
| 6 | Boss arena hazards — hazard node spawning per type | Hex theme data |
| 7 | Boss Health Bar UI — CanvasLayer, show/hide, HP tween, phase markers | BossEnemy signals |
| 8 | WorldGenerator boss spawn hook — detect boss room, generate blueprint, instantiate BossEnemy, lock doors | BossEnemy, BossBlueprint, arena hazards |
| 9 | Integration test — adjust parameters until one generated boss plays well end-to-end | Everything above |
| 10 | Region Dominators (FUTURE) — hand-authored BossEnemy overrides | Base class + data tables for reference |
