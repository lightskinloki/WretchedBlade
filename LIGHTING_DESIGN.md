# Wretched Blade — Procedural 2D Lighting System Design

This document specifies the architecture, integration, and regional behavior of the procedural 2D lighting and shadows system in **Wretched Blade**.

---

## 1. System Philosophy

In accordance with the **Finite Design Philosophy (Constraint as Catalyst)**, the lighting system relies on **zero pre-made asset files**. All light maps, textures, and occluders are calculated, generated, and placed dynamically at runtime via code.

Lighting serves three core purposes:
1. **Physical Atmospheric Depth:** Background lights project outward to cast shadows from foreground platforms toward the screen, turning a flat 2D projection into a layered physical space.
2. **Combat telegraphing:** Faint lights illuminate hazards, parry windows, and windup states.
3. **Mechanical Volatility:** The Wretched Blade's light intensity increases as it degrades, revealing dark areas while raising enemy detection range.

---

## 2. Parallax Silhouetting & Layering

To achieve a sense of depth, the lighting system splits elements across Z-Index ranges and uses Godot's built-in light ranges.

```
       [ Z-Index Layering & Projection ]
       
   Background Z-Index (-15 to -10)
   ┌────────────────────────────────┐
   │  Glowing Conduit / Fissure     │  <-- Spawns PointLight2D
   └────────────────────────────────┘      (Z-Range: -20 to 10)
                  │
                  ▼ (Light projects forward)
                  
   Foreground Z-Index (0 to 5)
   ┌────────────────────────────────┐
   │  Walkable Platform / Pillars   │  <-- Casts shadows outward via
   └────────────────────────────────┘      LightOccluder2D polygons
                  │
                  ▼
   Screen / Player viewport
```

### Z-Index Structure
* **Background Layer (`Z = -10`):** Parallax scenery, background walls, columns, and background emitters (e.g., conduits, lava vents).
* **Playable Foreground (`Z = 0`):** Walkable floor, platforms, destructible tiles, enemies, and the player.
* **Light Range Configuration:** 
  * Background `PointLight2D` nodes are configured with `range_z_min = -20` and `range_z_max = 10`.
  * This range forces background lights to project forward, illuminating the player, enemies, and foreground tiles.
  * Foreground geometry contains `LightOccluder2D` polygons, which block these background projections, casting sharp shadows forward to create structural depth.

---

## 3. Background Generation Pipeline Integration

Lighting is resolved as a three-pass system matching the level generator pipeline.

```
┌────────────────────────┐     ┌────────────────────────┐     ┌────────────────────────┐
│   Pass 1: Planning     │ ──> │   Pass 2: Terrain      │ ──> │   Pass 3: Rendering    │
│  Decides light-emitters │     │ Generates light-tiles  │     │ Spawns PointLight2Ds   │
└────────────────────────┘     └────────────────────────┘     └────────────────────────┘
```

### Pass 1: Planning (`DungeonGenerator.gd` / `DungeonGraph.gd`)
* The dungeon graph marks specific room nodes as having background details or lighting overrides (e.g., a "dark cavern" or "illuminated terminal hall").
* The graph metadata specifies light emitter frequencies and color parameters for that seed.

### Pass 2: Room Terrain & Background (`RoomTerrainGenerator.gd`)
* When generating background tiles and columns, the generator places specific tile IDs or metadata markers representing light sources (e.g., `BG_LANTERN`, `BG_ENERGY_CONDUIT`, `BG_LAVA_FISSURE`).

### Pass 3: Rendering (`WorldGenerator.gd`)
* When building the grid:
  1. The generator renders background tiles onto a background TileMap layer.
  2. For each glowing emitter tile found:
     * A `PointLight2D` is instantiated at the center of the tile.
     * The light's texture is queried from [PixelRenderer.gd](file:///c:/WretchedBlade/autoload/PixelRenderer.gd) (radial soft circle or directional cone generated on-the-fly).
     * The light's properties (intensity, color, flickering noise) are attached.
  3. For each solid foreground tile:
     * A `LightOccluder2D` is added to block Z-Index projects.

---

## 4. Regional Hex Styles

Lighting colors, flickers, and shadow properties are modified dynamically by the active region's Hex:

### Geocrash (Fractured Yards)
* **Ambient Lighting:** Dusty, dim orange/amber.
* **Background Emitters:** Flickering magma fissures.
* **Light Pattern:** Low-frequency brown noise flicker (flame-like).
* **Shadows:** Hard, sharp rock shadows.

### Voidrend (Hollow Expanse)
* **Ambient Lighting:** Deep space indigo/purple.
* **Background Emitters:** Distant star echos and void rifts.
* **Light Pattern:** Steady, high-contrast, sharp point lights.
* **Shadows:** Highly elongated, dramatic shadow projections.

### Echoscream (Resonant Ruins)
* **Ambient Lighting:** Melancholy magenta/dark violet.
* **Background Emitters:** Unstable sonic nodes.
* **Light Pattern:** Rapid, glitchy light intensity jumps (sine-wave sweep).
* **Shadows:** Vibrating/oscillating shadow boundaries.

### Nullpulse (Unraveling Core)
* **Ambient Lighting:** Dark, cold charcoal grey.
* **Background Emitters:** High-energy localized Nullpulse rifts.
* **Light Pattern:** Rhythmic, deep pulses (glow breathing).
* **Shadows:** High-contrast, stark silhouettes.

### Technomantic (Corroded Expanse)
* **Ambient Lighting:** Dull grey-green.
* **Background Emitters:** Neon green/cyan energy grids and terminal blocks.
* **Light Pattern:** Periodic grid sweeps (spotlights rotating).
* **Shadows:** Perfectly geometric, grid-aligned shadows.

---

## 5. Script Reference (Proposed additions)

### 5.1 `PixelRenderer.gd` Updates
```gdscript
# Generates a procedural radial gradient light mask texture
func generate_light_mask(px_radius: int, hardness: float) -> ImageTexture
```

### 5.2 `WorldGenerator.gd` Emitter Placement
```gdscript
# Spawns lights and attaches them to corresponding background structures
func _spawn_background_lights(grid: Array, parent: Node2D) -> void
```
