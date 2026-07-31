# ABSOLUTE PROJECT RULE — 100% RUNTIME PROCEDURAL GENERATION

> [!CAUTION]
> **THIS RULE IS NON-NEGOTIABLE AND ABSOLUTE.**
> Violation of this rule in any file, feature, UI, scene, or system will be treated as a critical regression and intentional sabotage.

## 🚨 The Zero Pre-Made Assets Invariant

1. **Zero Pre-Made Assets**:
   - **NO** pre-rendered sprite sheets, NO static PNG/JPG/SVG image files, NO pre-built hand-authored scene templates, NO fallback shape primitive hacks (`ColorRect` standalone UI/station placeholders).
   - Every single visual asset (tiles, blades, bodies, enemies, bosses, maps, HUD icons, status reticles, background scenery, sanctuary structures) **MUST** be generated programmatically at runtime.

2. **Unified Engine Pipeline (`PixelRenderer` + `RoomTerrainGenerator` + `WorldGenerator`)**:
   - Every single level, room, hub, sanctuary, dungeon, map, or environment **MUST** use the exact same procedural pipeline:
     - `PixelRenderer` to render raw pixel textures into memory via code.
     - `DungeonGraph` + `RoomTerrainGenerator` / `RoomArchetype` to calculate grid geometry.
     - `WorldGenerator` to instantiate physics colliders, tiles, and scene geometry.

3. **Rule Enforcement**:
   - If ANY code or proposed change bypasses `WorldGenerator`, `PixelRenderer`, or `RoomTerrainGenerator` to draw static shapes or inject ungenerated content, it **MUST BE DESTROYED AND REPLACED IMMEDIATELY**.
   - No exceptions. No shortcuts. No temporary placeholders.
