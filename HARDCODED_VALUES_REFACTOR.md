# Hardcoded Room-Dimension Values — Refactor Plan

**Goal**: Eliminate all 148+ hardcoded room-dimension constants (`room_h - 4`, `ROOM_W`, `h - 5`, etc.) across the codebase and replace with dynamic derivation from portal anchors or grid scans.

**Guiding principle**: Every coordinate calculation must derive from either a portal floor anchor or a full-height grid scan — never from `room_h - N`.

---

## Phase 0 — Utility: `RoomAnchorHelper.gd` (new file)

Create a static utility class under `scripts/world/` that provides:

- `get_walkable_floor_y(grid, x_col) -> int` — scans column from bottom up, returns first `TILE_FLOOR` row
- `get_celling_y(grid, x_col) -> int` — scans column from top down, returns first non-empty row
- `get_room_floor_ceiling(grid) -> Dictionary` — returns `{floor_lo, floor_hi, ceil_lo, ceil_hi}` across all columns
- `clamp_to_room(x, y, w, h)` — safe bounds clamping with margin

Used by all other phases.

---

## Phase 1 — `WorldGenerator.gd` triggers/spawn (`~50` instances)

**File**: `scripts/world/WorldGenerator.gd`

### Changes:
1. **`ROOM_W / ROOM_H` constants** → replace with `_get_dungeon_dimensions()` that reads from region config
2. **`_spawn_nullman` floor_y calc** → use `_find_enemy_spawn_y` full-height scan (DONE)
3. **`_spawn_shard`, `_spawn_interactable` positions** → derive from portal anchors, not hardcoded offsets
4. **Room placement offsets** → use `slot.get_floor_anchor()` instead of `w/2`, `h-4`, etc.
5. **`room_h - 4` in spawn methods** → replace with `_find_enemy_spawn_y` or anchor-based Y

---

## Phase 2 — `RoomTerrainGenerator.gd` terrain/decor (`~30` instances)

**File**: `scripts/room/RoomTerrainGenerator.gd`

### Changes:
1. **Bridge carving termination** → already uses `grid[y][x] == TILE_FLOOR` check (GOOD)
2. **Spike/chest placement Y** → replace `room_h - N` with floor-anchor-based Y
3. **Wall-fill loops** → use actual grid bounds, not `ROOM_H - 1`
4. **Crate/debris spawn** → scan floor column, place N rows above

---

## Phase 3 — `RegionTheme.gd` bounds (`~22` instances)

**File**: `scripts/world/RegionTheme.gd`

### Changes:
1. **`h - 1`, `h - 2` in shape modifiers** → replace with `_get_anchor_y_range().y` or grid scan result
2. **`w / 2` centering** → replace with `slot.get_floor_anchor().x` where portal context exists
3. **Shape region clamping** → use `clamp_to_room` from RoomAnchorHelper

---

## Phase 4 — `RoomArchetype.gd` fallbacks / skeleton bounds (`~25` instances)

**File**: `scripts/world/RoomArchetype.gd`

### Changes:
1. **`_get_anchor_y_range` fallback** → `h - 4` replaced with `h - 2` or grid scan
2. **Skeleton generators** → use `_get_anchor_y_range` result everywhere (already pattern in most)
3. **`clampi(y, 2, h - 3)` in `_connect_two_floors`** → replace with anchor-based clamp
4. **Rubble/base-of-room refs** → use `h - 1` derived from grid height

---

## Phase 5 — `Game.gd` bounds (`~12` instances)

**File**: `scenes/game/Game.gd`

### Changes:
1. **Spawn Y formula** → use `_find_spawn_from_grid` result (already anchor-based for X; Y needs same)
2. **Room-bound camera clamp** → derive from room pixel dimensions, not `ROOM_W * TILE_SIZE`
3. **Portal interaction zone** → derive from portal slot anchor, not hardcoded offset

---

## Phase 6 — `Player.gd` bounds (`~9` instances)

**File**: `scripts/player/Player.gd`

### Changes:
1. **Edge-of-room checks** → replace `ROOM_W * TILE_SIZE` with actual room size from parent
2. **Climb/vault bounds** → derive from grid scan instead of `room_h - N`
3. **Camera limit constants** → store in RoomAnchorHelper and reference

---

## Implementation Order

1. Phase 0 — RoomAnchorHelper.gd
2. Phase 1 — WorldGenerator.gd (spawn positions, room dimensions)
3. Phase 2 — RoomTerrainGenerator.gd (decor placement)
4. Phase 3 — RegionTheme.gd (shape bounds)
5. Phase 4 — RoomArchetype.gd (skeleton fallbacks)
6. Phase 5 — Game.gd (spawn, camera)
7. Phase 6 — Player.gd (edge/climb bounds)

Each phase produces a working build. Verify with 5+ seed dungeon traversals after each phase.
