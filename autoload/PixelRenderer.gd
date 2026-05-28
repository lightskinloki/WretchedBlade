extends Node
# PixelRenderer — generates ALL visual assets at runtime using code.
# No image files needed. Everything is drawn pixel by pixel.
#
# How it works: We use Godot's Image class to create a blank canvas,
# paint pixels onto it with set_pixel(), then wrap it in an ImageTexture
# so Sprite2D nodes can display it.

# ── Enums (named categories) ──────────────────────────────────────────────────

# The different sword forms the player can unlock
enum WeaponForm {
	EXECUTIONER,  # Starting form — wide, heavy cleaver
	PHANTOM,      # Unlocked form — thin, ghostly rapier
	INFERNO,      # Unlocked form — jagged, flame-shaped
	HOLLOW,       # Unlocked form — cracked, void-filled
}

# The different tile types for world generation
enum TileType { FLOOR, WALL, NULLSTONE, CHECKPOINT, DOOR, PLATFORM, ABYSS, PRESSURE_PLATE, LOCKED_DOOR }

# Body poses for the Projected Body — each pose is a 16x32 pixel sprite
enum BodyPose {
	IDLE,
	WALK_A,
	WALK_B,
	JUMP,
	LAND,
	ATTACK_1,
	ATTACK_2,
	ATTACK_3,
	DODGE,
	HURT,
	COUNTER,
}

# Enemy types
enum EnemyType { NULLMAN, RIVAL }

# ── Color palette (the Nullpulse aesthetic) ───────────────────────────────────
const C_VOID        := Color(0.05, 0.05, 0.10, 1.0)  # Deep space black
const C_BLADE_BODY  := Color(0.70, 0.80, 0.90, 1.0)  # Cold steel
const C_BLADE_EDGE  := Color(0.92, 0.96, 1.00, 1.0)  # Bright edge highlight
const C_CRACK_GLOW  := Color(0.80, 0.20, 1.00, 1.0)  # Purple crack energy
const C_RUST        := Color(0.55, 0.10, 0.05, 1.0)  # Old blood / rust
const C_BODY_FILL   := Color(0.10, 0.05, 0.15, 0.92) # Dark body fill
const C_BODY_EDGE   := Color(0.40, 0.20, 0.60, 1.0)  # Purple body outline
const C_BODY_EYES   := Color(0.70, 0.00, 1.00, 1.0)  # Violet glowing eyes

# ── Blade generation ──────────────────────────────────────────────────────────

# Generate a sword sprite.
# health_pct: 1.0 = pristine / 0.0 = shattered (not called at 0, player is dead)
# Returns an ImageTexture you can assign to a Sprite2D.texture
func generate_blade_texture(form: WeaponForm, health_pct: float) -> ImageTexture:
	var img := Image.create(12, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	match form:
		WeaponForm.EXECUTIONER: _draw_executioner(img, health_pct)
		WeaponForm.PHANTOM:     _draw_phantom(img, health_pct)
		WeaponForm.INFERNO:     _draw_inferno(img, health_pct)
		WeaponForm.HOLLOW:      _draw_hollow(img, health_pct)

	return ImageTexture.create_from_image(img)

# ── Executioner Blade (starting sword) ────────────────────────────────────────
func _draw_executioner(img: Image, health: float) -> void:
	var noise := _make_noise(randi())
	var w := img.get_width()
	var h := img.get_height()

	for y in range(h):
		var t := float(y) / float(h)  # 0 = tip, 1 = pommel

		# Decide how wide the blade is at this row
		var bw: int
		if t < 0.08:
			bw = 1                                              # Pointed tip
		elif t < 0.62:
			bw = int(lerp(2.0, float(w - 2), (t - 0.08) / 0.54))  # Widening body
		elif t < 0.68:
			bw = w - 2                                          # Guard
		else:
			bw = 3                                              # Handle

		var xs: int = (w - bw) >> 1  # >> 1 = integer divide by 2, no warning
		var xe := xs + bw

		for x in range(xs, xe):
			var is_blade_area := t < 0.68
			var is_guard: bool = t >= 0.62 and t < 0.68
			var is_handle     := t >= 0.68
			var is_edge: bool = (x == xs or x == xe - 1)

			var col: Color
			if is_handle:
				col = Color(0.15, 0.10, 0.06, 1.0)
			elif is_guard:
				col = Color(0.30, 0.28, 0.35, 1.0)
			elif is_edge:
				col = C_BLADE_EDGE
			else:
				col = C_BLADE_BODY

			img.set_pixel(x, y, _apply_damage(col, x, y, health, noise, is_blade_area))

# ── Phantom Blade ─────────────────────────────────────────────────────────────
func _draw_phantom(img: Image, health: float) -> void:
	var noise := _make_noise(randi())
	var w := img.get_width()
	var h := img.get_height()

	for y in range(h):
		var t := float(y) / float(h)
		var bw: int = 2 if t < 0.70 else (4 if t < 0.73 else 2)
		var xs: int = (w - bw) >> 1  # >> 1 = integer divide by 2, no warning

		for x in range(xs, xs + bw):
			var ghost := Color(0.50, 0.70, 1.00, 0.88)
			img.set_pixel(x, y, _apply_damage(ghost, x, y, health, noise, t < 0.70))

# ── Inferno Blade ─────────────────────────────────────────────────────────────
func _draw_inferno(img: Image, health: float) -> void:
	var noise := _make_noise(randi())
	var w := img.get_width()
	var h := img.get_height()

	for y in range(h):
		var t := float(y) / float(h)
		# Jagged flame silhouette using noise
		var jag := noise.get_noise_2d(0.0, float(y) * 0.8)
		var bw  := int(lerp(1.0, float(w - 3), (1.0 - t) * 0.7)) + int(jag * 2.0)
		bw = clamp(bw, 1, w - 2)
		var xs: int = (w - bw) >> 1  # >> 1 = integer divide by 2, no warning

		for x in range(xs, xs + bw):
			var flame := Color(1.0, 0.35 + t * 0.3, 0.0, 1.0)
			if t > 0.65:
				flame = Color(0.15, 0.10, 0.06, 1.0)  # Handle
			img.set_pixel(x, y, _apply_damage(flame, x, y, health, noise, t < 0.65))

# ── Hollow Blade (void-filled) ────────────────────────────────────────────────
func _draw_hollow(img: Image, health: float) -> void:
	var noise := _make_noise(randi())
	var w := img.get_width()
	var h := img.get_height()

	for y in range(h):
		var t := float(y) / float(h)
		var bw: int = int(lerp(1.0, float(w - 2), minf(t * 2.0, 1.0)))
		bw = clamp(bw, 1, w - 2)
		var xs: int = (w - bw) >> 1  # >> 1 = integer divide by 2, no warning

		for x in range(xs, xs + bw):
			var is_edge: bool = (x == xs or x == xs + bw - 1)
			var void_n  := noise.get_noise_2d(float(x) * 4.0, float(y) * 4.0)
			var col: Color
			if is_edge:
				col = Color(0.5, 0.0, 0.8, 1.0)  # Purple edge
			elif void_n > 0.3:
				col = Color.TRANSPARENT            # Holes in the blade (void)
			else:
				col = Color(0.08, 0.02, 0.12, 1.0)
			if col.a > 0.0:
				img.set_pixel(x, y, _apply_damage(col, x, y, health, noise, t < 0.65))

# ── Damage application ────────────────────────────────────────────────────────
# Modifies a pixel color based on how damaged the blade is.
# damage = 0.0 means pristine, 1.0 means almost shattered.
func _apply_damage(base: Color, x: int, y: int, health: float, noise: FastNoiseLite, is_blade: bool) -> Color:
	if not is_blade or health >= 0.99:
		return base

	var damage := 1.0 - health

	# Chips: transparent holes appear at high damage
	var chip_n := noise.get_noise_2d(float(x) * 3.5, float(y) * 3.5)
	if damage > 0.25 and chip_n > (0.72 - damage * 0.45):
		if chip_n > 0.88:
			return Color.TRANSPARENT  # A chip has broken off
		return base.darkened(0.65)    # A deep scratch

	# Dirt and rust buildup
	if damage > 0.15:
		var grime := noise.get_noise_2d(float(x) * 1.2, float(y) * 1.2 + 77.0)
		if grime > 0.38:
			base = base.lerp(C_RUST, damage * 0.5)

	# Crack glow (purple energy bleeds through at high damage — very cool visually)
	if damage > 0.55:
		var crack := noise.get_noise_2d(float(x) * 6.0, float(y) * 6.0 + 150.0)
		if crack > 0.62:
			return C_CRACK_GLOW.lightened(crack * 0.4)

	# General tarnish / darkening
	return base.darkened(damage * 0.35)

# ── Projected Body generation ─────────────────────────────────────────────────
# The humanoid avatar — ALWAYS pristine, never shows damage.
# Returns a Dictionary of all pose textures keyed by BodyPose enum.
func generate_body_textures() -> Dictionary:
	var poses := {}
	for pose in range(11):  # BodyPose has 11 values
		var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		match pose:
			BodyPose.IDLE:     _draw_idle(img)
			BodyPose.WALK_A:   _draw_walk_a(img)
			BodyPose.WALK_B:   _draw_walk_b(img)
			BodyPose.JUMP:     _draw_jump(img)
			BodyPose.LAND:     _draw_land(img)
			BodyPose.ATTACK_1: _draw_attack_1(img)
			BodyPose.ATTACK_2: _draw_attack_2(img)
			BodyPose.ATTACK_3: _draw_attack_3(img)
			BodyPose.DODGE:    _draw_dodge(img)
			BodyPose.HURT:     _draw_hurt(img)
			BodyPose.COUNTER:  _draw_counter(img)
		poses[pose] = ImageTexture.create_from_image(img)
	return poses

# ── Helper: fill a rectangular region with body fill/edge ─────────────────────
func _draw_rect(img: Image, x1: int, y1: int, x2: int, y2: int) -> void:
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			var e: bool = (x == x1 or x == x2 or y == y1 or y == y2)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

# ── Pose: IDLE (neutral standing) ─────────────────────────────────────────────
func _draw_idle(img: Image) -> void:
	_draw_humanoid_head(img, 7, 8)
	_draw_humanoid_neck(img, 7, 8)
	_draw_humanoid_torso(img, 4, 11, 9, 20)
	_draw_humanoid_arms(img, 2, 3, 12, 13, 10, 19)
	_draw_humanoid_legs(img, 4, 6, 9, 11, 20, 31)

# ── Pose: WALK_A (left leg forward, right arm forward) ────────────────────────
func _draw_walk_a(img: Image) -> void:
	_draw_humanoid_head(img, 7, 7)
	_draw_humanoid_neck(img, 7, 8)
	_draw_humanoid_torso(img, 4, 11, 9, 20)
	# Right arm slightly forward (higher)
	_draw_humanoid_arms(img, 2, 3, 12, 13, 11, 18)
	# Left leg shifted forward (slightly higher on canvas = further in perspective)
	for y in range(19, 32):
		for x in range(4, 7):
			var e: bool = (x == 4 or x == 6 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)
	# Right leg normal
	for y in range(20, 32):
		for x in range(9, 12):
			var e: bool = (x == 9 or x == 11 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

# ── Pose: WALK_B (right leg forward, left arm forward) ────────────────────────
func _draw_walk_b(img: Image) -> void:
	_draw_humanoid_head(img, 7, 7)
	_draw_humanoid_neck(img, 7, 8)
	_draw_humanoid_torso(img, 4, 11, 9, 20)
	# Left arm slightly forward
	_draw_humanoid_arms(img, 2, 3, 12, 13, 11, 18)
	# Left leg normal
	for y in range(20, 32):
		for x in range(4, 7):
			var e: bool = (x == 4 or x == 6 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)
	# Right leg shifted forward
	for y in range(19, 32):
		for x in range(9, 12):
			var e: bool = (x == 9 or x == 11 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

# ── Pose: JUMP (legs tucked, arms raised) ─────────────────────────────────────
func _draw_jump(img: Image) -> void:
	_draw_humanoid_head(img, 7, 5)
	_draw_humanoid_neck(img, 7, 8)
	_draw_humanoid_torso(img, 4, 11, 9, 18)
	# Arms raised up and out
	for y in range(7, 15):
		img.set_pixel(2, y, C_BODY_FILL)
		img.set_pixel(3, y, C_BODY_FILL)
		img.set_pixel(12, y, C_BODY_FILL)
		img.set_pixel(13, y, C_BODY_FILL)
	# Legs tucked (shorter, bent)
	for y in range(18, 28):
		for x in range(4, 7):
			var e: bool = (x == 4 or x == 6 or y == 27)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)
		for x in range(9, 12):
			var e: bool = (x == 9 or x == 11 or y == 27)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

# ── Pose: LAND (crouched low) ─────────────────────────────────────────────────
func _draw_land(img: Image) -> void:
	# Head lower (squashed pose)
	_draw_humanoid_head(img, 7, 8)
	# Neck compressed
	_draw_humanoid_neck(img, 7, 10)
	# Torso compressed
	_draw_humanoid_torso(img, 4, 11, 10, 20)
	# Arms slightly out for balance
	for y in range(11, 20):
		img.set_pixel(2, y, C_BODY_FILL)
		img.set_pixel(3, y, C_BODY_FILL)
		img.set_pixel(12, y, C_BODY_FILL)
		img.set_pixel(13, y, C_BODY_FILL)
	# Legs wide and bent (crouched)
	for y in range(20, 32):
		for x in range(3, 7):
			var e: bool = (x == 3 or x == 6 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)
		for x in range(8, 12):
			var e: bool = (x == 8 or x == 11 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

# ── Pose: ATTACK_1 (horizontal slash — leaning forward, arm extended) ─────────
func _draw_attack_1(img: Image) -> void:
	# Head slightly forward
	_draw_humanoid_head(img, 8, 8)
	_draw_humanoid_neck(img, 7, 9)
	# Torso leaning forward (shifted right by 1)
	_draw_humanoid_torso(img, 5, 12, 9, 20)
	# Right arm extended outward (the sword arm)
	for y in range(9, 15):
		for x in range(12, 16):
			img.set_pixel(x, y, C_BODY_FILL)
	# Left arm back
	for y in range(11, 20):
		img.set_pixel(1, y, C_BODY_FILL)
		img.set_pixel(2, y, C_BODY_FILL)
	# Legs braced
	_draw_humanoid_legs(img, 4, 6, 9, 11, 20, 31)

# ── Pose: ATTACK_2 (rising cut — arm raised high, body tilted back) ───────────
func _draw_attack_2(img: Image) -> void:
	_draw_humanoid_head(img, 6, 7)
	_draw_humanoid_neck(img, 7, 8)
	# Torso tilted back (shifted left)
	_draw_humanoid_torso(img, 3, 10, 9, 20)
	# Right arm raised up
	for y in range(4, 12):
		for x in range(11, 14):
			img.set_pixel(x, y, C_BODY_FILL)
	# Left arm down
	for y in range(11, 20):
		img.set_pixel(1, y, C_BODY_FILL)
		img.set_pixel(2, y, C_BODY_FILL)
	_draw_humanoid_legs(img, 4, 6, 9, 11, 20, 31)

# ── Pose: ATTACK_3 (overhead slam — both arms high, body lunging) ─────────────
func _draw_attack_3(img: Image) -> void:
	_draw_humanoid_head(img, 7, 9)
	_draw_humanoid_neck(img, 7, 10)
	# Torso lunging forward
	_draw_humanoid_torso(img, 4, 11, 10, 21)
	# Both arms raised overhead
	for y in range(4, 12):
		img.set_pixel(3, y, C_BODY_FILL)
		img.set_pixel(4, y, C_BODY_FILL)
		img.set_pixel(11, y, C_BODY_FILL)
		img.set_pixel(12, y, C_BODY_FILL)
	# Legs wide stance
	_draw_humanoid_legs(img, 3, 6, 9, 12, 21, 31)

# ── Pose: DODGE (body low, leaning forward, streamlined) ──────────────────────
func _draw_dodge(img: Image) -> void:
	# Head low and forward
	_draw_humanoid_head(img, 8, 10)
	_draw_humanoid_neck(img, 8, 11)
	# Torso compressed and forward
	_draw_humanoid_torso(img, 5, 12, 11, 21)
	# Arms tucked back
	for y in range(12, 19):
		img.set_pixel(3, y, C_BODY_FILL)
		img.set_pixel(4, y, C_BODY_FILL)
	# Legs extended back (running pose)
	for y in range(21, 32):
		for x in range(3, 7):
			var e: bool = (x == 3 or x == 6 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)
		for x in range(7, 11):
			var e: bool = (x == 7 or x == 10 or y == 31)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

# ── Pose: HURT (recoiling backward) ───────────────────────────────────────────
func _draw_hurt(img: Image) -> void:
	# Head tilted back
	_draw_humanoid_head(img, 5, 7)
	_draw_humanoid_neck(img, 6, 8)
	# Torso recoiling (shifted left)
	_draw_humanoid_torso(img, 3, 10, 9, 20)
	# Arms pulled in defensively
	for y in range(10, 18):
		img.set_pixel(3, y, C_BODY_FILL)
		img.set_pixel(4, y, C_BODY_FILL)
		img.set_pixel(11, y, C_BODY_FILL)
		img.set_pixel(12, y, C_BODY_FILL)
	# Legs stepping back
	_draw_humanoid_legs(img, 5, 7, 10, 12, 20, 31)

func _draw_counter(img: Image) -> void:
	# Leaning forward lunge — body reaching toward target
	_draw_humanoid_head(img, 9, 7)
	_draw_humanoid_neck(img, 9, 8)
	_draw_humanoid_torso(img, 6, 13, 9, 20)
	# Arms thrust forward (extended toward target)
	for y in range(9, 17):
		img.set_pixel(12, y, C_BODY_EDGE)
		img.set_pixel(13, y, C_BODY_FILL)
		img.set_pixel(14, y, C_BODY_FILL)
		img.set_pixel(15, y, C_BODY_EDGE)
	# Front leg forward, back leg planted
	_draw_humanoid_legs(img, 8, 10, 7, 9, 20, 31)

# ── Shared body part helpers ──────────────────────────────────────────────────
func _draw_humanoid_head(img: Image, nose_x: int, nose_y: int) -> void:
	for y in range(1, 8):
		for x in range(4, 12):
			var e: bool = (y == 1 or y == 7 or x == 4 or x == 11)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)
	img.set_pixel(6, 3, C_BODY_EYES)
	img.set_pixel(9, 3, C_BODY_EYES)
	img.set_pixel(nose_x, nose_y, C_BODY_EDGE)

func _draw_humanoid_neck(img: Image, x1: int, y_start: int) -> void:
	for y in range(y_start, 10):
		img.set_pixel(x1, y, C_BODY_FILL)
		img.set_pixel(x1 + 1, y, C_BODY_FILL)

func _draw_humanoid_torso(img: Image, x1: int, x2: int, y1: int, y2: int) -> void:
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			var e: bool = (y == y1 or y == y2 or x == x1 or x == x2)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

func _draw_humanoid_arms(img: Image, lx1: int, lx2: int, rx1: int, rx2: int, y1: int, y2: int) -> void:
	for y in range(y1, y2 + 1):
		img.set_pixel(lx1, y, C_BODY_FILL)
		img.set_pixel(lx2, y, C_BODY_FILL)
		img.set_pixel(rx1, y, C_BODY_FILL)
		img.set_pixel(rx2, y, C_BODY_FILL)

func _draw_humanoid_legs(img: Image, lx1: int, lx2: int, rx1: int, rx2: int, y1: int, y2: int) -> void:
	for y in range(y1, y2 + 1):
		for x in range(lx1, lx2 + 1):
			var e: bool = (x == lx1 or x == lx2 or y == y2)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)
		for x in range(rx1, rx2 + 1):
			var e: bool = (x == rx1 or x == rx2 or y == y2)
			img.set_pixel(x, y, C_BODY_EDGE if e else C_BODY_FILL)

# ── Tile generation ───────────────────────────────────────────────────────────
func generate_tile_image(tile_type: TileType, seed_val: int = 0) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var noise := _make_noise(seed_val)
	match tile_type:
		TileType.FLOOR:          _draw_floor(img, noise)
		TileType.WALL:           _draw_wall(img, noise)
		TileType.NULLSTONE:      _draw_nullstone(img, noise)
		TileType.CHECKPOINT:     _draw_checkpoint(img)
		TileType.DOOR:           _draw_door(img, noise)
		TileType.PLATFORM:       _draw_platform(img, noise)
		TileType.ABYSS:          _draw_abyss(img, noise)
		TileType.PRESSURE_PLATE: _draw_pressure_plate(img, noise)
		TileType.LOCKED_DOOR:    _draw_locked_door(img, noise)
		_:                       _draw_wall(img, noise)
	return img

func generate_tile_texture(tile_type: TileType, seed_val: int = 0) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var noise := _make_noise(seed_val)

	match tile_type:
		TileType.FLOOR:           _draw_floor(img, noise)
		TileType.WALL:            _draw_wall(img, noise)
		TileType.NULLSTONE:       _draw_nullstone(img, noise)
		TileType.CHECKPOINT:      _draw_checkpoint(img)
		TileType.DOOR:            _draw_door(img, noise)
		TileType.PLATFORM:        _draw_platform(img, noise)
		TileType.ABYSS:           _draw_abyss(img, noise)
		TileType.PRESSURE_PLATE:  _draw_pressure_plate(img, noise)
		TileType.LOCKED_DOOR:     _draw_locked_door(img, noise)

	return ImageTexture.create_from_image(img)

func _draw_floor(img: Image, noise: FastNoiseLite) -> void:
	for y in range(16):
		for x in range(16):
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, Color(0.10, 0.08, 0.13, 1.0).lightened(n * 0.12))

func _draw_wall(img: Image, noise: FastNoiseLite) -> void:
	for y in range(16):
		for x in range(16):
			var n := (noise.get_noise_2d(float(x) * 1.8, float(y) * 1.8) + 1.0) * 0.5
			var col := Color(0.07, 0.05, 0.10, 1.0)
			col = col.lightened(n * 0.10) if n > 0.6 else col.darkened(0.08)
			img.set_pixel(x, y, col)
	# Top highlight (visible edge of the wall block)
	for x in range(16):
		img.set_pixel(x, 0, img.get_pixel(x, 0).lightened(0.3))

func _draw_nullstone(img: Image, noise: FastNoiseLite) -> void:
	for y in range(16):
		for x in range(16):
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			if n > 0.62:
				img.set_pixel(x, y, Color(0.28, 0.00, 0.48, 1.0).lightened(n * 0.25))
			else:
				img.set_pixel(x, y, Color(0.04, 0.00, 0.09, 1.0))

func _draw_checkpoint(img: Image) -> void:
	img.fill(Color(0.04, 0.02, 0.08, 1.0))
	var glow := Color(0.50, 0.00, 0.80, 1.0)
	# Cross rune pattern
	for i in range(3, 13):
		img.set_pixel(8, i, glow)
		img.set_pixel(i, 8, glow)
	# Corner marks
	for p in [[2,2],[13,2],[2,13],[13,13]]:
		img.set_pixel(p[0], p[1], glow.lightened(0.4))

func _draw_door(img: Image, noise: FastNoiseLite) -> void:
	# Deep void center
	img.fill(Color(0.02, 0.00, 0.05, 1.0))
	# Purple frame border
	var frame := Color(0.35, 0.00, 0.55, 1.0)
	for x in range(16):
		img.set_pixel(x, 0, frame)
		img.set_pixel(x, 15, frame)
	for y in range(16):
		img.set_pixel(0, y, frame)
		img.set_pixel(15, y, frame)
	# Inner glow swirl with noise
	var inner_glow := Color(0.60, 0.00, 0.90, 0.8)
	for y in range(2, 14):
		for x in range(2, 14):
			var n := (noise.get_noise_2d(float(x) * 3.0, float(y) * 3.0) + 1.0) * 0.5
			if n > 0.55:
				var swirl := inner_glow.darkened(n * 0.3)
				swirl.a = 0.5 + n * 0.4
				img.set_pixel(x, y, swirl)

func _draw_platform(img: Image, noise: FastNoiseLite) -> void:
	for y in range(16):
		for x in range(16):
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, Color(0.15, 0.10, 0.18, 1.0).lightened(n * 0.10))
	# Top edge highlight
	for x in range(16):
		img.set_pixel(x, 0, img.get_pixel(x, 0).lightened(0.4))
	# Side edge accents
	for y in range(16):
		img.set_pixel(0, y, img.get_pixel(0, y).lightened(0.2))
		img.set_pixel(15, y, img.get_pixel(15, y).lightened(0.2))

func _draw_abyss(img: Image, noise: FastNoiseLite) -> void:
	for y in range(16):
		for x in range(16):
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var col := Color(0.01, 0.00, 0.03, 1.0)
			if n > 0.85:
				col = Color(0.06, 0.00, 0.12, 1.0)
			img.set_pixel(x, y, col)
	# Faint purple edge glow
	var edge_glow := Color(0.15, 0.00, 0.25, 0.6)
	for x in range(16):
		img.set_pixel(x, 0, edge_glow)
		img.set_pixel(x, 15, edge_glow)
	for y in range(16):
		img.set_pixel(0, y, edge_glow)
		img.set_pixel(15, y, edge_glow)

func _draw_pressure_plate(img: Image, noise: FastNoiseLite) -> void:
	img.fill(Color(0.04, 0.02, 0.08, 1.0))
	for y in range(2, 14):
		for x in range(2, 14):
			var dist := Vector2(float(x) - 7.5, float(y) - 7.5).length()
			var n := (noise.get_noise_2d(float(x) * 2.0, float(y) * 2.0) + 1.0) * 0.5
			if dist < 6.0:
				var glow := Color(0.25, 0.00, 0.45, 1.0).lightened(n * 0.2 - dist * 0.04)
				img.set_pixel(x, y, glow)
	# Inner ring
	var ring := Color(0.40, 0.00, 0.65, 1.0)
	for a in range(16):
		var ax := int(7.5 + sin(float(a) * 0.4) * 4.5)
		var ay := int(7.5 + cos(float(a) * 0.4) * 4.5)
		img.set_pixel(ax, ay, ring)

func _draw_locked_door(img: Image, noise: FastNoiseLite) -> void:
	img.fill(Color(0.02, 0.00, 0.05, 1.0))
	var frame := Color(0.45, 0.00, 0.60, 1.0)
	for x in range(16):
		img.set_pixel(x, 0, frame)
		img.set_pixel(x, 15, frame)
	for y in range(16):
		img.set_pixel(0, y, frame)
		img.set_pixel(15, y, frame)
	# Lock icon — cross with a keyhole
	var lock_col := Color(0.60, 0.00, 0.90, 1.0)
	var dark_lock := Color(0.30, 0.00, 0.50, 1.0)
	for y in range(5, 11):
		for x in range(5, 11):
			img.set_pixel(x, y, lock_col)
	for y in range(7, 10):
		for x in range(6, 10):
			img.set_pixel(x, y, dark_lock)
	img.set_pixel(8, 6, Color(0.02, 0.00, 0.05, 1.0))
	# Cross bar
	for x in range(3, 7):
		img.set_pixel(x, 4, lock_col)

# ── Enemy generation ────────────────────────────────────────────────────────
func generate_enemy_texture(enemy_type: EnemyType, seed_val: int = 0) -> ImageTexture:
	match enemy_type:
		EnemyType.NULLMAN: return _generate_nullman_texture(seed_val if seed_val != 0 else 42)
		EnemyType.RIVAL:   return _generate_rival_texture()
	return ImageTexture.new()

# Nullstone shard — a broken crystal fragment from the Cataclysm.
# Each shard is uniquely shaped: one might be a long splinter, another a blocky
# chunk, a third a jagged wedge. The colour palette stays consistent so they're
# instantly recognisable as the same enemy type.
func _generate_nullman_texture(seed_val: int) -> ImageTexture:
	var img := Image.create(12, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var body := Color(0.08, 0.04, 0.15, 0.95)
	var edge := Color(0.25, 0.00, 0.45, 1.0)
	var core := Color(0.50, 0.00, 0.80, 1.0)

	# Dedicated higher-frequency noise for detailed fracture surfaces
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = 0.35
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	n.fractal_gain = 0.5

	# Determine overall "personality" of this shard from the seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	# Top-lean: how narrow the tip is (0 = very sharp, 1 = blunt)
	var top_lean := rng.randf_range(0.0, 1.0)
	# Flare: how much wider the bottom is vs the top (0 = columnar, 1 = flared)
	var flare := rng.randf_range(0.2, 1.0)
	# Wobble: how much the centre shifts side-to-side
	var wobble := rng.randf_range(0.0, 3.0)

	for y in range(20):
		var t := float(y) / 19.0

		# Centre wanders left/right (sinuous crystal growth or fracture offset)
		var cx := 6.0 + n.get_noise_2d(t * 1.2, 0.0) * wobble

		# Width profile — not a simple cone; width can ebb, flow, pinch
		var profile := n.get_noise_2d(t * 0.7, 50.0) * 0.5 + 0.5
		# Mix the noise profile with a tapered lerp so top is still generally narrower
		var taper: float = lerp(top_lean, 4.5, pow(t, 1.0 + 0.5 * n.get_noise_2d(t * 0.5, 100.0)))
		var base_hw: float = lerp(taper, profile * 5.0, flare * 0.6)

		# "Missing chunk" — sharp indentation
		var chunk_noise := n.get_noise_2d(t * 2.5, 300.0)
		if chunk_noise > 0.55:
			base_hw *= 0.35
		elif chunk_noise < -0.55:
			base_hw *= 1.6

		# Per-edge independent jitter
		var l_j := n.get_noise_2d(t * 2.0, 200.0) * 3.0
		var r_j := n.get_noise_2d(t * 2.0, 250.0) * 3.0

		var x1 := int(cx - base_hw + l_j)
		var x2 := int(cx + base_hw + r_j)

		# Bottom 4 rows: fracture surface — overrides normal width with a jagged
		# cross-section so the shard looks broken, not designed to sit on the floor.
		if y >= 16:
			var f_cx := 6.0 + n.get_noise_2d(float(y) * 2.0, 700.0) * 3.0
			var f_hw := 1.0 + (n.get_noise_2d(float(y) * 3.0, 800.0) * 0.5 + 0.5) * 4.5
			var f_l := n.get_noise_2d(float(y) * 3.5, 500.0) * 3.0
			var f_r := n.get_noise_2d(float(y) * 3.5, 600.0) * 3.0
			x1 = int(f_cx - f_hw + f_l)
			x2 = int(f_cx + f_hw + f_r)

		x1 = clampi(x1, 0, 10)
		x2 = clampi(x2, x1 + 1, 12)

		for x in range(x1, x2):
			# Fracture rows: per-column jagged depth so the bottom is broken, not flat.
			# Each column has its own cutoff row driven by noise — pixels below it are
			# transparent, giving the shard a genuinely shattered lower edge.
			if y >= 16:
				var col_depth_n := n.get_noise_2d(float(x) * 5.0, 400.0)  # -1..1
				var col_bottom := 16 + int((col_depth_n * 0.5 + 0.5) * 3.0)  # 16..19
				if y > col_bottom:
					continue
			var is_edge: bool = x == x1 or x == x2 - 1
			var is_core: bool = y >= 6 and y <= 15 and x >= 3 and x <= 8 and \
				n.get_noise_2d(float(x) * 0.6, float(y) * 0.6) > 0.0
			img.set_pixel(x, y, core if is_core else (edge if is_edge else body))

	return ImageTexture.create_from_image(img)

func _generate_rival_texture() -> ImageTexture:
	var img := Image.create(14, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	# Animated rival blade (similar to player blade but jagged/rival style)
	# Use same blade palette but with enemy colors
	var blade_body := Color(0.30, 0.30, 0.40, 1.0)  # Darker blade
	var blade_edge := Color(0.60, 0.60, 0.70, 1.0)  # Lighter edge
	var blade_glow := Color(0.40, 0.00, 0.60, 1.0)  # Darker purple glow
	for y in range(48):
		var t := float(y) / 48.0
		var bw: int
		if t < 0.08:      bw = 1
		elif t < 0.62:  bw = int(lerp(2.0, 10.0, (t - 0.08) / 0.54))
		elif t < 0.68:  bw = 10
		else:             bw = 3
		var xs := (12 - bw) >> 1
		var xe := xs + bw
		for x in range(xs, xe):
			var is_edge: bool = (x == xs or x == xe - 1)
			var col := blade_edge if is_edge else blade_body
			# Add rival-specific jagged noise
			var n := (FastNoiseLite.new().get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			if n > 0.7 and t < 0.68:
				col = blade_glow.lightened(n * 0.3)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

# ── Helpers ───────────────────────────────────────────────────────────────────
func _make_noise(seed_val: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = 0.25
	return n

# Soft white glow circle for enemy pulse visuals. Tint via sprite.modulate.
func generate_glow_texture(px_radius: int) -> ImageTexture:
	var size := px_radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c := Vector2(px_radius - 0.5, px_radius - 0.5)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(c)
			if d <= px_radius:
				var a := 1.0 - (d / px_radius)
				a *= a
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

# Small diamond reticle for lock-on targeting indicator.
func generate_lockon_reticle() -> ImageTexture:
	var size := 24
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := size / 2.0
	var cy := size / 2.0
	for y in range(size):
		for x in range(size):
			var dx := absf(x - cx) - 0.5
			var dy := absf(y - cy) - 0.5
			var manhattan := dx + dy
			if manhattan >= 7.0 and manhattan <= 11.0:
				var a := 1.0
				if manhattan < 8.0:
					a = manhattan - 7.0
				elif manhattan > 10.0:
					a = 11.0 - manhattan
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * 0.7))
	return ImageTexture.create_from_image(img)
