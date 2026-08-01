# Wretched Blade — Procedural 2D Lighting & Shadow System Specification

This document specifies the architecture, integration, and regional behavior of the procedural 2D lighting, shadow ideology, and atmospheric depth system in **Wretched Blade**.

---

## 1. Core Visual Invariants

### 1. Zero Pre-Made Assets (Runtime Procedural Only)
All light masks, radial gradients, directional cones, and shadow occluders are calculated and generated dynamically at runtime via `PixelRenderer.gd` and `WorldGenerator.gd`.

### 2. A Wounded Civilization, Not Generic Fantasy
Every region exhibits human-built industrial systems — transit supports, concrete shells, rusty beams, failed tuning infrastructure — then shows how its Hex has distorted those structures. Hexes are grounded in humanity’s hubris and actions.

### 3. Resonance vs. Hex Lighting Dichotomy
Lighting is split by its underlying cosmic force:
* **Resonance (Harmonic Alignment):** Stable, quiet, structured falloff; warm-white or pale harmonic color; clean, crisp shadows.
* **Hex (Corrupted Discord):** Intrusive, unstable, overbright or swallowed light; irregular flicker; broken color channels; unnatural, distorted shadows.

### 4. Non-Purple World Palette (Blade Anomaly Readability)
Purple (`C_CRACK_GLOW`) is reserved **exclusively** as the signature of the Wretched Blade’s exposed Nullpulse core. World regions use non-purple palettes so the Blade remains instantly readable as a primordial anomaly in every environment.

### 5. Mobile Silhouette Priority
Lighting must **never** obscure combat readability. Backgrounds are darkened first; player and enemy silhouettes maintain strict value contrast. Strong flashes are reserved for attacks, parries, phase changes, and Hex detonations.

---

## 2. Progressive Blade & Core Light

The Blade’s light reveals its true nature as durability degrades:
* **Pristine / High HP (70-100%):** Faint internal seams along the blade edge. The projected body appears stable.
* **Damaged / Mid HP (30-70%):** Visible purple cracks (`C_CRACK_GLOW`). Light leaks onto nearby floor/wall tiles.
* **Critical / Low HP (< 30%):** Unstable purple light pulses continuously, casting small jittery shadows. The projected body looks like an ephemeral puppet orbiting a volatile core.
* **Death / Shatter (0% HP):** The projected body vanishes instantly. The uncontained Blade flares with a blinding Nullpulse flash before screen blackout — the moment the room briefly sees the Blade without its body’s protective fiction.

---

## 3. Regional Shadow Ideologies

Shadows are not merely dark shapes; they express the region’s underlying Hex:

* **Geocrash (*Fractured Yards*):** Structurally broken shadows — hard, heavy, load-bearing cubic angles.
* **Voidrend (*Hollow Expanse*):** Absence around lights — darkness actively creeps inward and swallows light falloff.
* **Echoscream (*Resonant Ruins*):** Duplicate or offset shadow edges (audiovisual resonance echoes).
* **Memoreave (*Forgotten Archive*):** Lingering shadow states — ghost shadows remain briefly after objects move.
* **Nullpulse (*Unraveling Core*):** Harsh, accusatory silhouettes with stark value contrast.
* **Technomantic (*Corroded Expanse*):** Controlled, gridded, industrial spotlights until control visibly fails.

---

## 4. Dominator Visual Authority

Dominators do not merely match their region; the region organizes itself around their presence:
* **Geocrash Dominator (*The Shattered Sovereign*):** Dynamically pulls nearby terrain fracture lines toward its body during attacks.
* **Memoreave Dominator (*The Memory Thief*):** Arena retains ghost-images of previous player positions that linger as temporal echoes.

---

## 5. Sanctuary Visual Discipline

Safe spaces (**Ashen Sanctuary** and region safe rooms) are emotionally legible through lighting:
* Light behaves with absolute reliability: **no flicker, no spectral afterimages, no aggressive cast shadows**.
* Warm, stable harmonic light from the Master Tuning Fork provides an unmistakable sense of safety without requiring a UI label.

---

## 6. Implementation Architecture

### `PixelRenderer.gd`
* `generate_light_mask(radius: int, hardness: float, falloff_type: String) -> ImageTexture`
* Generates harmonic soft masks (Resonance) and erratic/jagged masks (Hex).

### `WorldGenerator.gd`
* Attaches `LightOccluder2D` polygons to solid foreground tiles (`FLOOR`, `WALL`, `NULLSTONE`).
* Spawns background `PointLight2D` nodes on `Z = -10` with Z-range `-20` to `10`.

### `Game.gd` & `Player.gd`
* Updates player light intensity and crack light leakage dynamically based on blade health percentage.
