extends RefCounted
class_name CampsiteEnvironmentGenerator
# CampsiteEnvironmentGenerator.gd — Procedural Ashen Sanctuary Environment
# Generates ALL visual, structural, and lighting elements for the hub level
# at runtime via PixelRenderer. Zero pre-made assets.
#
# The Ashen Sanctuary overlooks the Severed Lands: a wounded horizon of
# collapsed civilisation, not an enclosed dungeon. Every structure here was
# built by human hands and has endured — the Hearth, the Anvil, the Archives —
# because these ruins sit at a harmonic convergence the Hexes cannot reach.

const TILE_SIZE := 16
const WORLD_WIDTH := 76   # tiles wide (~1216 px)
const GROUND_Y := 23      # tile row where the walkable ground starts
const GROUND_DEPTH := 3   # rows of solid ground beneath the surface

# ── Station X positions (pixel space) ────────────────────────────────────────
# Spaced across the 1216px width so the player traverses the full sanctuary.
const STATION_ARCHIVES_X := 160.0
const STATION_ANVIL_X := 360.0
const STATION_REFLECTOR_X := 520.0
const STATION_HEARTH_X := 640.0
const STATION_ALCOVE_X := 880.0
const STATION_GATE_X := 1080.0

static func build(parent: Node2D, seed_val: int = 77777) -> Dictionary:
	var width := WORLD_WIDTH * TILE_SIZE
	var height := 520
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# ── Layer 1: Far horizon (Z = -20, parallax 0.08x) ──────────────────────
	var far_world := Sprite2D.new()
	far_world.name = "SeveredLandsHorizon"
	far_world.texture = PixelRenderer.generate_far_environment_texture(
		width + 512, height + 240,
		Color(0.055, 0.072, 0.085),
		Color(0.52, 0.22, 0.10),
		seed_val, "campsite"
	)
	far_world.centered = false
	far_world.position = Vector2(-256, -160)
	far_world.z_index = -20
	parent.add_child(far_world)

	# ── Layer 2: Mid-distance ruin silhouettes (Z = -12, parallax 0.24x) ────
	var structures := Sprite2D.new()
	structures.name = "CampsiteRuinSilhouettes"
	structures.texture = PixelRenderer.generate_atmosphere_texture(
		width + 512, height + 240,
		Color.TRANSPARENT,
		Color(0.30, 0.34, 0.36),
		seed_val + 61, 5, 0.85
	)
	structures.centered = false
	structures.position = Vector2(-256, -160)
	structures.z_index = -12
	parent.add_child(structures)

	# ── Layer 3: Ambient light modulation ────────────────────────────────────
	# Warm dusk tones — sanctuary discipline: stable, reliable, no flicker.
	var ambient := CanvasModulate.new()
	ambient.name = "OverworldDuskAmbient"
	ambient.color = Color(0.74, 0.70, 0.63)
	parent.add_child(ambient)

	# ── Layer 4: Solid ground with collision and occluders ───────────────────
	_build_ground(parent, seed_val, rng)

	# ── Layer 5: Procedural station structures ──────────────────────────────
	var ground_px := float(GROUND_Y * TILE_SIZE)
	_add_archives(parent, Vector2(STATION_ARCHIVES_X, ground_px), rng)
	_add_anvil(parent, Vector2(STATION_ANVIL_X, ground_px), rng)
	_add_reflector_pool(parent, Vector2(STATION_REFLECTOR_X, ground_px), rng)
	_add_hearth_and_fork(parent, Vector2(STATION_HEARTH_X, ground_px), rng)
	_add_alcove(parent, Vector2(STATION_ALCOVE_X, ground_px), rng)
	_add_overworld_arch(parent, Vector2(STATION_GATE_X, ground_px), rng)

	# ── Scattered atmospheric debris ────────────────────────────────────────
	_add_scattered_rubble(parent, rng, width, ground_px)

	# ── Build floor spot array for station trigger placement ────────────────
	var spots: Array[Vector2] = []
	for x in range(6, WORLD_WIDTH - 5, 2):
		spots.append(Vector2(x * TILE_SIZE + 8, GROUND_Y * TILE_SIZE - 8))

	return {
		"spawn": Vector2(width * 0.46, GROUND_Y * TILE_SIZE - 8),
		"floor_spots": spots,
		"room_w": WORLD_WIDTH,
		"far_world": far_world,
		"structures": structures,
	}

# ── Ground Construction ──────────────────────────────────────────────────────
# Multi-row ground: surface + foundation depth. Occluders on top row for
# sharp shadow projection from hearth fires and station lights.
static func _build_ground(parent: Node2D, seed_val: int, rng: RandomNumberGenerator) -> void:
	for x in range(WORLD_WIDTH):
		for dy in range(GROUND_DEPTH):
			var tile_y := GROUND_Y + dy
			var sprite := Sprite2D.new()
			sprite.name = "AshenGround_%d_%d" % [x, dy]
			# Top row is walkable floor; deeper rows are structural wall/stone
			var tile_type: int
			if dy == 0:
				tile_type = PixelRenderer.TileType.FLOOR
			else:
				tile_type = PixelRenderer.TileType.WALL
			sprite.texture = PixelRenderer.generate_tile_texture(tile_type, (seed_val + x * 31 + dy * 7) % 4)
			sprite.position = Vector2(x * TILE_SIZE + 8, tile_y * TILE_SIZE + 8)
			sprite.z_index = 0
			parent.add_child(sprite)

			# Collision on every solid row
			var body := StaticBody2D.new()
			var collision := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = Vector2(TILE_SIZE, TILE_SIZE)
			collision.shape = shape
			body.position = sprite.position
			body.add_child(collision)
			parent.add_child(body)

			# Light occluders on the top row so fires cast sharp shadows
			if dy == 0:
				_add_tile_occluder(sprite)

	# Occasional rubble tiles sitting ON the ground surface
	for x in range(3, WORLD_WIDTH - 3, 7):
		var rubble := Sprite2D.new()
		rubble.name = "SurfaceRubble_%d" % x
		rubble.texture = PixelRenderer.generate_tile_texture(PixelRenderer.TileType.NULLSTONE, (seed_val + x) % 4)
		rubble.position = Vector2(x * TILE_SIZE + 8, GROUND_Y * TILE_SIZE - 8)
		rubble.z_index = 1
		parent.add_child(rubble)

# ── Station: Attunement Archives ─────────────────────────────────────────────
# Ancient stone scroll stand with a harmonic cyan light sphere.
# The Glass Frequency Scholar studies resonance patterns here.
static func _add_archives(parent: Node2D, ground_pos: Vector2, rng: RandomNumberGenerator) -> void:
	var tex := _generate_archives_texture(rng)
	var sprite := Sprite2D.new()
	sprite.name = "AttunementArchives"
	sprite.texture = tex
	sprite.position = ground_pos + Vector2(0, -tex.get_height() * 0.5)
	sprite.z_index = -1
	parent.add_child(sprite)

	# Harmonic cyan study light — stable, no flicker (sanctuary discipline)
	_add_fire(parent, ground_pos + Vector2(0, -28), Color(0.4, 0.85, 1.0), 64, 0.38)

# ── Station: The Iron Anvil ──────────────────────────────────────────────────
# Dark steel forge anvil with an embedded ember glow.
# The Cinder Forge-Mason strengthens the Blade's edge here.
static func _add_anvil(parent: Node2D, ground_pos: Vector2, rng: RandomNumberGenerator) -> void:
	var tex := _generate_anvil_texture(rng)
	var sprite := Sprite2D.new()
	sprite.name = "IronAnvil"
	sprite.texture = tex
	sprite.position = ground_pos + Vector2(0, -tex.get_height() * 0.5)
	sprite.z_index = -1
	parent.add_child(sprite)

	# Forge ember glow — warm orange, steady (sanctuary discipline)
	_add_fire(parent, ground_pos + Vector2(0, -14), Color(1.0, 0.55, 0.18), 56, 0.52)

# ── Station: Lineage Reflector ───────────────────────────────────────────────
# Carved stone basin with a glowing, reflective pixel water surface.
# The player looks into the pool to choose their Projected Body lineage.
static func _add_reflector_pool(parent: Node2D, ground_pos: Vector2, rng: RandomNumberGenerator) -> void:
	var tex := _generate_pool_texture(rng)
	var sprite := Sprite2D.new()
	sprite.name = "LineageReflector"
	sprite.texture = tex
	sprite.position = ground_pos + Vector2(0, -tex.get_height() * 0.5 + 4)
	sprite.z_index = -1
	parent.add_child(sprite)

	# Reflective pool light — soft lavender/silver, stable
	_add_fire(parent, ground_pos + Vector2(0, -6), Color(0.7, 0.65, 0.9), 48, 0.30)

# ── Station: Ashen Hearth & Master Tuning Fork ───────────────────────────────
# The central hub landmark. The Master Tuning Fork monolith rises behind the
# hearth fire. This is the emotional anchor of the sanctuary.
static func _add_hearth_and_fork(parent: Node2D, ground_pos: Vector2, rng: RandomNumberGenerator) -> void:
	# Master Tuning Fork monolith (background, behind the hearth)
	var fork_tex := PixelRenderer.generate_campsite_landmark_texture()
	var fork_sprite := Sprite2D.new()
	fork_sprite.name = "MasterTuningFork"
	fork_sprite.texture = fork_tex
	fork_sprite.position = ground_pos + Vector2(0, -fork_tex.get_height() * 0.5 + 6)
	fork_sprite.z_index = -2
	parent.add_child(fork_sprite)

	# Fork base harmonic glow — warm gold, steady
	_add_fire(parent, ground_pos + Vector2(0, -40), Color(1.0, 0.72, 0.36), 138, 0.70)

	# Main hearth fire — the brightest, warmest light in the sanctuary
	_add_fire(parent, ground_pos + Vector2(0, -12), Color(1.0, 0.45, 0.16), 112, 0.85)

	# Flanking campfires — smaller, softer, framing the approach
	_add_fire(parent, ground_pos + Vector2(-120, -10), Color(1.0, 0.67, 0.34), 78, 0.48)
	_add_fire(parent, ground_pos + Vector2(120, -10), Color(1.0, 0.67, 0.34), 78, 0.48)

# ── Station: Fringe Alcove ───────────────────────────────────────────────────
# Scrap shelter with a cobbled counter and a hanging lantern.
# The Dross Scrap-Broker sells whetstone grit and salvage here.
static func _add_alcove(parent: Node2D, ground_pos: Vector2, rng: RandomNumberGenerator) -> void:
	var tex := _generate_alcove_texture(rng)
	var sprite := Sprite2D.new()
	sprite.name = "FringeAlcove"
	sprite.texture = tex
	sprite.position = ground_pos + Vector2(0, -tex.get_height() * 0.5)
	sprite.z_index = -1
	parent.add_child(sprite)

	# Merchant lantern — yellowish, dim, steady
	_add_fire(parent, ground_pos + Vector2(0, -32), Color(0.95, 0.82, 0.4), 52, 0.36)

# ── Station: Overworld Gate Arch ─────────────────────────────────────────────
# A monumental stone archway framing a swirling deployment rift.
# The player steps through to access the Overworld Campaign Map.
static func _add_overworld_arch(parent: Node2D, ground_pos: Vector2, rng: RandomNumberGenerator) -> void:
	var tex := _generate_arch_texture(rng)
	var sprite := Sprite2D.new()
	sprite.name = "OverworldGateArch"
	sprite.texture = tex
	sprite.position = ground_pos + Vector2(0, -tex.get_height() * 0.5)
	sprite.z_index = -1
	parent.add_child(sprite)

	# Rift glow inside the arch — soft red/crimson, steady (deployment energy)
	_add_fire(parent, ground_pos + Vector2(0, -48), Color(0.95, 0.3, 0.25), 72, 0.45)

# ── Scattered Atmospheric Rubble ─────────────────────────────────────────────
# Small procedural rubble piles scattered between stations to break up the
# flat ground plane and reinforce the wounded-civilisation aesthetic.
static func _add_scattered_rubble(parent: Node2D, rng: RandomNumberGenerator, width: int, ground_px: float) -> void:
	for _i in range(12):
		var rx := rng.randf_range(48.0, float(width) - 48.0)
		# Skip positions near station structures
		if _is_near_station(rx):
			continue
		var rubble := Sprite2D.new()
		rubble.name = "AtmosphericRubble_%d" % _i
		rubble.texture = PixelRenderer.generate_pixel_shard_texture(
			rng.randi_range(4, 10), rng.randi_range(3, 6),
			Color(0.25, 0.22, 0.20).lerp(Color(0.40, 0.35, 0.30), rng.randf())
		)
		rubble.position = Vector2(rx, ground_px - rng.randf_range(2.0, 6.0))
		rubble.z_index = 1
		parent.add_child(rubble)

static func _is_near_station(x: float) -> bool:
	var stations := [STATION_ARCHIVES_X, STATION_ANVIL_X, STATION_REFLECTOR_X,
					  STATION_HEARTH_X, STATION_ALCOVE_X, STATION_GATE_X]
	for sx in stations:
		if absf(x - sx) < 40.0:
			return true
	return false

# ── Tile Occluder Helper ─────────────────────────────────────────────────────
static func _add_tile_occluder(sprite: Sprite2D) -> void:
	var occluder := LightOccluder2D.new()
	var polygon := OccluderPolygon2D.new()
	var half := float(TILE_SIZE) * 0.5
	polygon.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)
	])
	occluder.occluder = polygon
	sprite.add_child(occluder)

# ── Harmonic Fire / Light Helper ─────────────────────────────────────────────
# All sanctuary lights use "harmonic" falloff: stable, no flicker, no spectral
# afterimages, no aggressive shadows. This is sanctuary visual discipline.
static func _add_fire(parent: Node2D, pos: Vector2, color: Color, radius: int, energy: float) -> void:
	var light := PointLight2D.new()
	light.texture = PixelRenderer.generate_light_mask(radius, 0.48, "harmonic")
	light.color = color
	light.energy = energy
	light.position = pos
	light.z_index = -10
	light.range_z_min = -20
	light.range_z_max = 10
	# Sanctuary discipline: shadows disabled in safe spaces
	light.shadow_enabled = false
	parent.add_child(light)

	# Visible light source sprite (the glowing core of the fire/lamp)
	var source := Sprite2D.new()
	source.texture = PixelRenderer.generate_light_mask(8, 0.70, "harmonic")
	source.modulate = color
	source.position = pos
	source.z_index = 1
	parent.add_child(source)

# ══════════════════════════════════════════════════════════════════════════════
# PROCEDURAL STATION TEXTURE GENERATORS
# Every texture below is built pixel-by-pixel at runtime. Zero asset files.
# ══════════════════════════════════════════════════════════════════════════════

# ── Archives Texture (32x40) ─────────────────────────────────────────────────
# A stone scroll stand: two columns supporting a horizontal shelf, with
# small scroll/book shapes resting on top.
static func _generate_archives_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var w := 32
	var h := 40
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var stone := Color(0.35, 0.38, 0.42)
	var stone_dark := Color(0.22, 0.24, 0.28)
	var scroll := Color(0.72, 0.68, 0.58)
	var binding := Color(0.4, 0.85, 1.0)  # Cyan harmonic accent

	# Left column
	for y in range(14, h):
		for x in range(4, 8):
			image.set_pixel(x, y, stone_dark if x == 4 else stone)
	# Right column
	for y in range(14, h):
		for x in range(24, 28):
			image.set_pixel(x, y, stone_dark if x == 24 else stone)
	# Shelf crossbeam
	for x in range(3, 29):
		for y in range(14, 17):
			image.set_pixel(x, y, stone)
	# Scroll shapes on shelf
	for x in range(9, 14):
		for y in range(8, 14):
			image.set_pixel(x, y, scroll)
	for x in range(16, 23):
		for y in range(10, 14):
			image.set_pixel(x, y, scroll)
	# Harmonic binding glow (small accent dots)
	image.set_pixel(11, 9, binding)
	image.set_pixel(19, 11, binding)
	image.set_pixel(14, 12, binding)

	return ImageTexture.create_from_image(image)

# ── Anvil Texture (28x24) ────────────────────────────────────────────────────
# A heavy dark steel anvil: wide flat top surface, tapered horn,
# thick base block. Ember pixels embedded in the striking surface.
static func _generate_anvil_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var w := 28
	var h := 24
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var iron := Color(0.18, 0.20, 0.26)
	var iron_light := Color(0.32, 0.34, 0.38)
	var ember := Color(1.0, 0.55, 0.18)

	# Anvil face (flat striking surface)
	for x in range(4, 24):
		for y in range(4, 9):
			image.set_pixel(x, y, iron_light if y == 4 else iron)
	# Horn (left taper)
	for x in range(1, 5):
		image.set_pixel(x, 6, iron_light)
		image.set_pixel(x, 7, iron)
	# Waist (narrow middle)
	for x in range(8, 20):
		for y in range(9, 13):
			image.set_pixel(x, y, iron)
	# Base block (wide, heavy)
	for x in range(4, 24):
		for y in range(13, h):
			image.set_pixel(x, y, iron if y > 13 else iron_light)
	# Ember glow on striking surface
	image.set_pixel(10, 5, ember)
	image.set_pixel(14, 6, ember)
	image.set_pixel(18, 5, ember)
	# Edge highlight
	for x in range(4, 24):
		image.set_pixel(x, 4, iron_light)

	return ImageTexture.create_from_image(image)

# ── Reflector Pool Texture (36x18) ───────────────────────────────────────────
# A carved stone basin: low walls on each side, with a reflective
# pixel water surface between them. Soft lavender/silver tones.
static func _generate_pool_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var w := 36
	var h := 18
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var stone := Color(0.38, 0.36, 0.40)
	var stone_light := Color(0.50, 0.48, 0.52)
	var water_dark := Color(0.15, 0.12, 0.28)
	var water_light := Color(0.35, 0.30, 0.55)
	var shimmer := Color(0.72, 0.68, 0.92)

	# Left basin wall
	for y in range(4, h):
		for x in range(2, 6):
			image.set_pixel(x, y, stone_light if x == 5 else stone)
	# Right basin wall
	for y in range(4, h):
		for x in range(30, 34):
			image.set_pixel(x, y, stone_light if x == 30 else stone)
	# Basin floor
	for x in range(2, 34):
		for y in range(h - 3, h):
			image.set_pixel(x, y, stone)
	# Water surface
	for x in range(6, 30):
		for y in range(8, h - 3):
			var water_col := water_dark.lerp(water_light, rng.randf() * 0.5)
			image.set_pixel(x, y, water_col)
	# Shimmer highlights on water
	for _i in range(6):
		var sx := rng.randi_range(8, 28)
		var sy := rng.randi_range(9, h - 5)
		image.set_pixel(sx, sy, shimmer)

	return ImageTexture.create_from_image(image)

# ── Alcove Texture (32x36) ───────────────────────────────────────────────────
# A scrap shelter: three walls forming a lean-to with a cobbled counter
# in front and a hanging lantern bracket on the right wall.
static func _generate_alcove_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var w := 32
	var h := 36
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var wood := Color(0.30, 0.22, 0.14)
	var wood_light := Color(0.42, 0.34, 0.22)
	var metal := Color(0.35, 0.35, 0.38)
	var lantern := Color(0.95, 0.82, 0.4)

	# Back wall
	for x in range(4, 28):
		for y in range(2, 6):
			image.set_pixel(x, y, wood)
	# Left wall
	for y in range(2, h):
		for x in range(2, 6):
			image.set_pixel(x, y, wood if x > 3 else wood_light)
	# Right wall (shorter, lean-to)
	for y in range(2, h - 4):
		for x in range(26, 30):
			image.set_pixel(x, y, wood if x < 29 else wood_light)
	# Roof slope (left to right, descending)
	for x in range(4, 28):
		var roof_y := 2 + int(float(x - 4) * 0.12)
		if roof_y < h:
			image.set_pixel(x, roof_y, wood_light)
	# Counter (cobbled metal surface)
	for x in range(6, 26):
		for y in range(h - 8, h - 5):
			image.set_pixel(x, y, metal)
	# Lantern bracket on right wall
	image.set_pixel(27, 8, metal)
	image.set_pixel(27, 9, metal)
	image.set_pixel(26, 10, lantern)
	image.set_pixel(27, 10, lantern)
	# Scrap items on counter
	for _i in range(4):
		var ix := rng.randi_range(8, 24)
		image.set_pixel(ix, h - 9, metal)
		image.set_pixel(ix + 1, h - 9, wood_light)

	return ImageTexture.create_from_image(image)

# ── Overworld Gate Arch Texture (64x96) ──────────────────────────────────────
# A monumental stone archway: two massive pillars supporting a curved
# arch overhead, with a swirling energy rift visible through the opening.
static func _generate_arch_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var w := 64
	var h := 96
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var stone := Color(0.30, 0.28, 0.32)
	var stone_light := Color(0.45, 0.42, 0.46)
	var rift_core := Color(0.85, 0.25, 0.20)
	var rift_edge := Color(0.55, 0.15, 0.12)

	# Left pillar
	for y in range(16, h):
		for x in range(4, 16):
			var col := stone_light if (x == 4 or x == 15) else stone
			image.set_pixel(x, y, col)
	# Right pillar
	for y in range(16, h):
		for x in range(48, 60):
			var col := stone_light if (x == 48 or x == 59) else stone
			image.set_pixel(x, y, col)
	# Arch curve (semicircular top connecting the pillars)
	var cx := w / 2
	var cy := 24
	var outer_r := 28
	var inner_r := 20
	for x in range(4, 60):
		for y in range(0, 40):
			var dx := float(x - cx)
			var dy := float(y - cy)
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= float(outer_r) and dist >= float(inner_r) and y <= cy:
				image.set_pixel(x, y, stone_light if dist >= float(outer_r - 2) else stone)
	# Keystone at arch apex
	for x in range(cx - 3, cx + 4):
		for y in range(cy - outer_r, cy - outer_r + 5):
			if y >= 0:
				image.set_pixel(x, y, stone_light)
	# Rift energy inside the archway
	for x in range(16, 48):
		for y in range(24, h - 8):
			var dx := float(x - cx)
			var dy := float(y - 56)
			var dist := sqrt(dx * dx + dy * dy) / 24.0
			if dist < 1.0 and rng.randf() > 0.3:
				var col := rift_core.lerp(rift_edge, dist)
				image.set_pixel(x, y, col)
	# Pillar base blocks (wider foundation)
	for x in range(1, 19):
		for y in range(h - 6, h):
			image.set_pixel(x, y, stone)
	for x in range(45, 63):
		for y in range(h - 6, h):
			image.set_pixel(x, y, stone)

	return ImageTexture.create_from_image(image)
