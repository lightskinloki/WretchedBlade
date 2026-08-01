# Wretched Blade — Background Generation System Architecture

This document specifies the architecture, generation pipeline, aesthetic invariants, and regional behaviors of the **Procedural Background Generation System** in **Wretched Blade**.

---

## 1. Core Architectural Invariants

### 1. 100% Runtime Procedural Generation (Zero Asset Files)
Every background wall, structural column, industrial beam, transit support, and atmospheric element is calculated and painted at runtime via code. There are zero PNG/JPG files, sprite sheets, or pre-authored background scenes.

### 2. A Wounded Civilization, Not Generic Fantasy
Backgrounds depict humanity's industrial relics — concrete shells, structural pillars, cable anchors, transit supports, storage alcoves, and failed tuning infrastructure — deformed and scarred by regional Hex cataclysms.

### 3. Parallax Layering & Z-Index Depth
The background system organizes geometry across distinct depth layers to turn 2D pixel space into a physical, layered environment:
* **Background Deep Scenery (`Z = -15` to `-10`):** Parallax wall grid, structural pillars, and distant ruin silhouettes.
* **Background Emitters & Conduits (`Z = -10`):** Glowing energy rifts, lava vents, and sonic nodes that project light forward.
* **Playable Foreground Geometry (`Z = 0`):** Walkable floors, platforms, destructible tiles, player, and enemies.
* **Forward Occlusion (`Z = 0`):** Foreground tiles feature `LightOccluder2D` polygons that block background light projections, casting sharp shadows forward onto the scene.

---

## 2. The Three-Pass Background Generation Pipeline

```
┌────────────────────────┐     ┌────────────────────────┐     ┌────────────────────────┐
│   Pass 1: Planning     │ ──> │   Pass 2: Terrain      │ ──> │   Pass 3: Rendering    │
│ Assigns role, theme &  │     │ Builds skeleton grid,  │     │ Paints pixel textures, │
│  complexity rating     │     │ pillars & alcoves      │     │ spawns sprites & lights│
└────────────────────────┘     └────────────────────────┘     └────────────────────────┘
```

### Pass 1: Graph Planning (`DungeonGenerator.gd` / `DungeonGraph.gd`)
* Assigns room archetype roles (`SANCTUARY`, `GUARD_POST`, `BRIDGE_SPAN`, `STORAGE_VAULT`, `COLLAPSED_HALL`, `RITUAL_CHAMBER`, `WATCHTOWER`, `QUARRY`, `BOSS_ARENA`).
* Assigns linear path complexity ($0.0 - 1.0$) and regional Hex theme (`geocrash`, `voidrend`, `echoscream`, `memoreave`, `nullpulse`, `technomantic`).

### Pass 2: Terrain & Skeleton Generation (`RoomTerrainGenerator.gd` / `RoomArchetype.gd`)
* `RoomArchetype.apply_skeleton()` places structural background elements anchored to room dimensions and complexity:
  * **Guard Post:** Sentry platforms & rubble piles.
  * **Bridge Span:** Support pillars beneath the path, railings, & cable anchors.
  * **Storage Vault:** Ceiling pillars descending toward path & wall alcoves.
  * **Watchtower:** Stepped platforms & background window cutouts.
  * **Quarry:** Excavation covers & stone blocks.
* Structure counts and sizes scale smoothly via `lerpf(base, max, complexity)`.

### Pass 3: Procedural Pixel Texture Painting & Physical Building (`WorldGenerator.gd` / `PixelRenderer.gd`)
* `PixelRenderer.gd` paints procedural pixel textures into memory for tile types (`FLOOR`, `WALL`, `NULLSTONE`, `CHECKPOINT`, `PLATFORM`, `DOOR`).
* `WorldGenerator.gd` places tile sprites on the correct Z-layers, attaches `StaticBody2D` colliders, instantiates `HexBreakableTile` nodes, and sets up light occluders.

---

## 3. Regional Hex Background Personalities

Background structures adapt visually to reflect the dominant Hex:

1. **Geocrash (*The Fractured Yards*):**
   * **Industrial Relics:** Heavy concrete shells, shattered beams, angular blocky geometry.
   * **Hex Distortion:** Cubic ruins suspended at unnatural angles, fractured stone columns.
   * **Palette:** Grays, rust, dusty amber.

2. **Voidrend (*The Hollow Expanse*):**
   * **Industrial Relics:** Isolated transit supports overlooking deep abysses.
   * **Hex Distortion:** Scooped-out background void, floating island silhouettes in empty space.
   * **Palette:** Pitch-black void, deep indigo, sickly green accents.

3. **Echoscream (*The Resonant Ruins*):**
   * **Industrial Relics:** Sound-warping towers, communication relays, metal tuning tines.
   * **Hex Distortion:** Translucent glitch walls, silver/cyan conduit rings.
   * **Palette:** Silvers, pale cyan, audiovisual glitch artifacts.

4. **Memoreave (*The Forgotten Archive*):**
   * **Industrial Relics:** Monumental libraries, record vaults, stone archives.
   * **Hex Distortion:** Perspective-shifted archways, ghostly temporal echoes.
   * **Palette:** Faded sepia, washed gray, ghostly white.

5. **Nullpulse (*The Unraveling Core*):**
   * **Industrial Relics:** Heavy core reactor containment walls.
   * **Hex Distortion:** Visually unraveling pillars, crackling energy edges, fragmenting background walls.
   * **Palette:** Dark charcoal, white-void center, violent crimson pulse.

6. **Technomantic (*The Corroded Expanse*):**
   * **Industrial Relics:** Decaying machinery grids, rusted pipes, industrial conduits.
   * **Hex Distortion:** Bio-mechanical fusion — organic growth sprouting from metal beams.
   * **Palette:** Steel gray, orange rust, electric cyan.

---

## 4. Ashen Sanctuary Hub Background (`CampsiteHub.gd`)

The central campaign hub (**Ashen Sanctuary**) is constructed using the exact same procedural pipeline (`DungeonGraph` + `RoomTerrainGenerator` + `WorldGenerator`):
* **Background Architecture:** Procedural stone tile walls (`TileType.WALL`) and background pillars (`TileType.NULLSTONE`).
* **Monolithic Focal Point:** A massive **Master Tuning Fork Monolith** behind the central hearth that hums with a soft harmonic pulse.
* **Atmosphere:** Warm hearth fire embers drifting upward across cold, ancient stone ruins.
