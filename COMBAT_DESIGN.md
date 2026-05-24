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

Dual-wielding sword construct. Current state: patrol/chase/attack loop.
Planned: full rewrite into proper duel opponent.

**Current State:**
| Property | Value |
|---|---|
| Health | 120 |
| Move Speed | 100 px/s |
| Chase Range | 200 px |
| Attack CD | 1.8s |
| Combo | 3-hit: Right Slash → Left Slash → Cross Slash |
| Combo Chain | Auto-chains if within 65px, resets to 0 otherwise |
| Stun Duration | 1.0s on counter, 0.10s on damage |

**Hitboxes:**
- Per-blade Area2D children of each blade Sprite2D
- Shape: 18×60 Rectangle
- Debug overlay: semi-transparent red ColorRect
- Enable/disable per combo hit (only swinging blade monitors)

**Planned AI Rewrite (target ~550-600 lines):**
Priority-based decision engine reading player state:

| Priority | Decision | Condition |
|---|---|---|
| 1 | Dodge | Player attack windup + Rival in range |
| 2 | Counter | Player attack active + Rival in window |
| 3 | Punish | Player recovery + Rival close |
| 4 | Pressure | Rival advantage, player blocking/passive |
| 5 | Pace | Mid-range (80-140px) — strafe, pause, feint |
| 6 | Approach | Far range — close distance |

**Planned Verbs:**
- Dodge: dash with i-frames, 0.8s cooldown (matches player)
- Counter: parry player windup attacks
- Attack selection: contextual (not sequential) by distance and situation
- Personality: per-Rival randomization (`_aggression`, `_preferred_range`)

---

## Combat Flow Reference

Normal RivalBlade duel loop (future state):
```
Player approaches         → Rival paces (mid-range strafe)
Player attacks (windup)   → Rival reads state → dodge OR counter
Player in recovery        → Rival punishes → attacks
Both at range             → Footsies — approach/dodge/feint
Rival advantage           → Rival presses advantage → attack string
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
