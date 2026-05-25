# Wretched Blade — Combat System Design

## Philosophy

Three-button combat (Attack / Dodge / Counter) with lock-on as the foundation.
Lock-on ensures characters always face each other during duels — movement reads as
distance management, not indecision. This is critical for both player readability
and AI behavior.

---

## Lock-On System

### LockOn Autoload (`autoload/LockOn.gd`)

Singleton managing a single target. Provides facing direction, distance queries,
and auto-unlock on target death.

**API:**
- `lock_on(target: Node2D)` — set target, disconnect previous, connect `tree_exited`
- `unlock()` — clear target, emit `target_unlocked`
- `is_locked() -> bool`
- `facing_dir(from_position: Vector2) -> float` — returns `1`/`-1`/`0`
- `distance_to_target(from_position: Vector2) -> float` — returns `INF` if no target
- `get_target_node() -> Node2D` — returns target or `null`
- `get_target_position() -> Vector2`

**Signals:** `target_locked(target)`, `target_unlocked`

### Player Lock-On (`scripts/player/Player.gd`)

| Aspect | Behavior |
|---|---|
| Toggle | Tab key — nearest enemy or unlock |
| Facing | Overrides `is_facing_right` / `body_sprite.flip_h` to face target |
| Movement | Screen-axis left/right independent of facing (strafe) |
| Dodge | No-direction dodge defaults toward locked target (via `is_facing_right`) |
| Reticle | Diamond ring sprite, z=100, 40px above target, pulse tween (0.9→1.3) |

### RivalBlade Facing (`scripts/enemy/RivalBlade.gd`)

- `_facing_dir()` returns direction to player when alive, falls back to `_move_dir`
- `_move_dir` controls patrol/chase movement direction independently
- `_body.flip_h`, `_set_blade_rest_positions()`, `_position_blades()` all use `_facing_dir()`
- This makes lateral movement read as pacing/distance management, not flip-flopping

### Camera (Planned)

- When locked: center horizontal midpoint between player and target
- When unlocked: current behavior (follows player)

---

## Player Combat

### Movement

- **Ground:** `MOVE_SPEED = 200`, screen-axis, strafes when locked
- **Jump:** `JUMP_FORCE = -460`, coyote 0.12s, jump buffer 0.12s
- **Lunge:** `velocity.x = dir * 400` — called by blade on attack start
- **Gravity:** `980 px/s²`, terminal `850 px/s`

### Dodge (`scripts/player/Player.gd:242`)

- `DODGE_SPEED = 500`, `DODGE_TIME = 0.12s`, `DODGE_COOLDOWN = 0.8s`
- Invincibility frames during dodge
- No direction → dash toward facing direction (locked target when locked)
- Disables enemy collision during dodge, re-enables after
- Cancels blade recovery/windup via `blade.try_dodge_cancel()`

### Combo (`scripts/player/WretchedBlade.gd`)

- 3-hit: Slash → Uppercut → Slam (variable per Weapon Form)
- States: `IDLE` → `WINDUP` → `ACTIVE` → `RECOVERY` → `IDLE`
- Input buffering during active/recovery
- Auto-lunge on attack start

### Counter

- C key during enemy windup
- Triggers stun on counterable enemies (RivalBlade `is_counterable()`)
- `_is_countering` local state in Player.gd, 0.2s pose duration

### WretchedBlade (`scripts/player/WretchedBlade.gd`)

The player's real self — a child of Player. Damage goes here.
- `current_state: AttackState` — readable by RivalBlade AI
- `current_combo: int` — which hit in the chain
- `try_dodge_cancel()` — aborts attack for dodge
- `perform_attack()`, `perform_counter()` — verb interface

---

## Enemy Design

### Nullman (`scripts/enemy/Nullman.gd`)

Corrupted terrain shard vibrating with Nullpulse energy.

| Behavior | Detail |
|---|---|
| Detection | 80px proximity to player |
| Telegraph | Core-crack brightening + 1.0→1.15x scale (visible) |
| Attack | Pulse radial damage (60px radius) after windup |
| Counter | Parryable during windup → `countered()` stun |
| Visual | PixelRenderer noise-driven shard, per-seed personality, missing chunks |
| Pulse glow | `generate_glow_texture()` — soft white circle, tweened scale+alpha, z=10 |
| No contact damage | Damage only from windup pulse — cleaner counter play |

**Shard texture:** Procedural jagged shape with top_lean, flare, wobble personality per seed.
Bottom has fracture-surface depth cutoff instead of flat edge.

### RivalBlade (`scripts/enemy/RivalBlade.gd`)

Dual-wielding sword construct with two-layer AI.
915 lines. Two layers: priority decision engine + per-fight learning.

**Layer 1 — Priority Decision Engine:**
Reads `WretchedBlade.current_state` every frame via `_tick_decision()`.
One decision roll per player attack state change (`_dodge_roll_done` / `_counter_roll_done` guards).

| Priority | State | Trigger | Behavior |
|---|---|---|---|
| 1 | `dodge` | Player WINDUP, dist < 80px, CD ready, roll ≤ aggression | 2D dash away from player, i-frames, 0.8s CD, blue flash |
| 2 | `counter` | Player ACTIVE, dist < 90px, CD ready, roll ≤ counter_chance | Parry pose 0.28s, absorbs hit → riposte 10 dmg, 1.2s CD, cyan flash |
| 3 | `attack` (punish) | Player RECOVERY, dist < 65px, attack CD ready | Immediate attack start |
| 4 | `attack` (pressure) | Player idle, dist < preferred_range (55-85px), attack CD ready | Attack with `_pressure_mod` on CD |
| 5 | `pace` | Mid-range 80-145px | Strafe L/R / feint / idle micro-actions |
| 6 | `chase` | Far > 145px or too close < 80px + CD > 0.3s | Approach or back off, vertical tracking |

**Layer 2 — Per-Fight Learning:**
All counters reset on Rival death.

| Track | Threshold | Adaptation |
|---|---|---|
| Player countered ≥2/4 times | Feint_unlocked / feint_aggressive | `_feint_chance` 0.35 / 0.65 — abort windup at 45%, snap to dodge or pace |
| Player dodges same direction 5+ times | Dodge pattern detected | `_attack_dir_bias` → `_choose_combo_start()` biases toward that sweep (Hit 0 for right, Hit 1 for left) |
| Player punishes recovery ≥2/4 times | Recovery trap armed / aggressive | `_recovery_trap_chance` 0.30 / 0.55 — snap from recovery into counter when player starts windup |
| Attack rate calculated every 5s | Passive (< 0.5/s) → pressure | `_pressure_mod = 0.6` (attack CD × 0.6) |
| Attack rate calculated every 5s | Aggressive (> 2/s) → reaction | `_counter_chance += 0.25` (cap 0.95), pressure_mod = 1.0 |

**Personality** (per Rival instance, randomized in `_ready`):
- `_aggression: float` (0.3–0.9) — probability to dodge
- `_preferred_range: float` (55–85px) — pressure attack distance
- `_counter_chance: float` (0.3–0.8) — probability to attempt counter

**States:** `patrol` | `chase` | `pace` | `attack` | `dodge` | `counter` | `stun`

**Movement:**
- `MOVE_SPEED = 100`, `VERTICAL_SPEED = 75` — 2D tracking (X + Y)
- Patrol: horizontal patrol + vertical drift toward spawn height
- Chase: approach or back off (< 42px → retreat) + vertical player tracking
- Pace: 30% strafe L / 30% strafe R / 18% feint burst / 22% idle
- Dodge: 2D normalized away from player, `DODGE_SPEED = 320`

**Combo System:**
- 3-hit: Right Slash → Left Slash → Cross Slash (with dodge-bias combo start)
- Combo chain: auto-chain within 65px, non-sequential via `_choose_combo_start()`
- First hit of fresh chain biased 70% toward dodge-catching sweep (after 5+ observations)
- Attack CD: `ATTACK_CD_BASE (1.8) × _pressure_mod`

**Hitboxes:**
- Per-blade Area2D children of each blade Sprite2D
- Shape: 18×60 Rectangle
- Debug overlay: semi-transparent red ColorRect
- Enable/disable per combo hit (only swinging blade monitors)
- Damage per hit: `RIVAL_COMBO[stage]["damage"]` (8/8/14)

**Combat Interface:**
- `is_counterable()` — true during attack windup
- `countered()` — player parried → stun 1.0s, pink flash, calls `_adapt_counter_response()`
- `take_damage()` — if countering → absorb + riposte 10 dmg; else normal stagger/death
- `_on_hitbox_entered()` — if dodging → i-frame skip; else deal per-combo damage
- `_notification(NOTIFICATION_PREDELETE)` — logs death state for debugging

**Counter Deflect:** If hit by player during counter state, Rival absorbs the blow, flashes bright blue, and deals `COUNTER_RIPOSTE_DAMAGE (10)` back to the player. Only one successful counter deflect per counter window.

**Feint:** At 45% windup remaining, rolls against `_feint_chance`. If triggered: abort windup, snap blades to rest (0.12s), yellow flash. If dodge CD ready → execute dodge; else → pace state.

**Recovery Trap:** During recovery phase, monitors player blade state. If player enters WINDUP, rolls against `_recovery_trap_chance`. If triggered: snap blades to rest (0.08s), immediately start counter.

---

## Combat Flow Reference

Typical RivalBlade duel loop:
```
Player approaches         → Rival paces (mid-range strafe)
Player attacks (windup)   → Rival reads state → dodge OR counter
Player in recovery        → Rival punishes → attacks
Both at range             → Footsies — approach/dodge/feint
Rival advantage           → Rival presses advantage → attack string
Player counters           → Rival learns → adapts (feint, recovery trap, bias)
```

Key: `WretchedBlade.current_state` is exposed — Rival reads this for all decisions.
`Player.is_dodging` / `Player.is_invincible` are also readable.

---

## File Reference

| File | Role |
|---|---|
| `autoload/LockOn.gd` | Lock-on singleton (target, facing, distance) |
| `autoload/PixelRenderer.gd` | All runtime-generated textures (blade, body, enemies, tiles, glow, reticle) |
| `autoload/GameManager.gd` | Game state, death, respawn |
| `autoload/EssenceManager.gd` | Essence currency tracking |
| `scripts/player/Player.gd` | Projected Body (movement, dodge, combat routing, lock-on input) |
| `scripts/player/WretchedBlade.gd` | True self (health, attack combos, blade visual state) |
| `scripts/enemy/Nullman.gd` | Terrain shard enemy (proximity, pulse, counter) |
| `scripts/enemy/RivalBlade.gd` | Sword construct enemy (dual-wield, combo AI, facing) |
| `scripts/world/WorldGenerator.gd` | Procedural room generation |
