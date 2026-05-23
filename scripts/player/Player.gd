extends CharacterBody2D
# Player.gd — the Projected Body.
#
# This node IS NOT the player's true self — it's a temporary construct.
# The real player is WretchedBlade (the sword), which lives as a child of this node.
# Damage always goes to the blade, never to this body.

signal player_hurt

# ── Constants ─────────────────────────────────────────────────────────────────
const MOVE_SPEED    := 200.0   # Pixels per second
const JUMP_FORCE    := -460.0  # Negative = upward in Godot's coordinate system
const GRAVITY       := 980.0   # Pixels per second squared
const MAX_FALL      := 850.0   # Terminal velocity

const COYOTE_TIME   := 0.12    # Seconds you can still jump after walking off an edge
const JUMP_BUFFER   := 0.12    # Seconds a jump input is remembered before landing

# Physics layers (must match WorldGenerator)
const LAYER_GEOMETRY := 1
const LAYER_ENEMY    := 2

const DODGE_SPEED    := 500.0   # Pixels per second
const DODGE_TIME     := 0.12    # Seconds
const DODGE_COOLDOWN := 0.80

const WALK_POSE_INTERVAL := 0.18  # Seconds between walk pose swaps

# ── Node references ($ means "find child node named X") ───────────────────────
@onready var blade:       Node2D   = $WretchedBlade
@onready var body_sprite: Sprite2D = $ProjectedBody/BodySprite
@onready var camera:      Camera2D = $Camera2D

# ── Input state (set by TouchInput.gd signals) ────────────────────────────────
var input_move:          float = 0.0
var input_move_vertical: float = 0.0
var input_jump:          bool  = false
var input_attack:        bool  = false
var input_dodge:         bool  = false
var input_counter:       bool  = false

# ── Internal state ────────────────────────────────────────────────────────────
var is_facing_right := true
var _kb_moved       := false
var _kb_vert_moved  := false
var coyote_timer    := 0.0
var jump_buf_timer  := 0.0

var is_dodging     := false
var dash_dir       := Vector2.ZERO
var dodge_timer    := 0.0
var dodge_cooldown := 0.0
var is_invincible  := false

var _was_on_floor  := true
var _walk_time     := 0.0
var _walk_pose_idx := 0
var _current_pose: PixelRenderer.BodyPose = PixelRenderer.BodyPose.IDLE
var _is_countering := false

# Previous-frame key state for edge detection
var _last_attack_key  := false
var _last_dodge_key   := false
var _last_counter_key := false

# Pre-generated pose textures
var _poses: Dictionary = {}  # Maps BodyPose enum to ImageTexture

func _ready() -> void:
	_poses = PixelRenderer.generate_body_textures()
	body_sprite.texture = _poses[PixelRenderer.BodyPose.IDLE]
	body_sprite.scale   = Vector2(1.25, 1.25)
	body_sprite.centered = true

	collision_layer = 4  # Layer 3 (player)
	collision_mask  = LAYER_GEOMETRY | LAYER_ENEMY

	GameManager.player_died.connect(_on_player_died)
	GameManager.player_reconstituted.connect(_on_reconstituted)

	add_to_group("player")
	camera.add_to_group("camera")

func _physics_process(delta: float) -> void:
	if not GameManager.is_playing():
		return

	_read_keyboard_input()
	_handle_dodge(delta)

	if not is_dodging:
		_handle_gravity(delta)
		_handle_movement()
		_handle_attack(delta)
		_handle_counter(delta)

	move_and_slide()

	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer -= delta

	_handle_body_animation(delta)

	if input_move > 0.01:
		is_facing_right    = true
		body_sprite.flip_h = false
	elif input_move < -0.01:
		is_facing_right    = false
		body_sprite.flip_h = true

func _handle_body_animation(delta: float) -> void:
	var on_floor := is_on_floor()
	var moving: bool = abs(input_move) > 0.1
	var blade_attacking: bool = (blade.get("current_state") as int) != 0  # 0 = IDLE

	if blade_attacking:
		_set_pose(_attack_pose())
	elif is_dodging:
		_set_pose(PixelRenderer.BodyPose.DODGE)
	elif _is_countering:
		_set_pose(PixelRenderer.BodyPose.COUNTER)
	elif not on_floor:
		_set_pose(PixelRenderer.BodyPose.JUMP)
	elif not _was_on_floor and on_floor:
		_set_pose(PixelRenderer.BodyPose.LAND)
		_was_on_floor = true
	elif moving and on_floor:
		_walk_time += delta
		if _walk_time >= WALK_POSE_INTERVAL:
			_walk_time = 0.0
			_walk_pose_idx = (_walk_pose_idx + 1) % 2
			_set_pose(
				PixelRenderer.BodyPose.WALK_A if _walk_pose_idx == 0
				else PixelRenderer.BodyPose.WALK_B
			)
	else:
		_set_pose(PixelRenderer.BodyPose.IDLE)
		_walk_time = 0.0

	_was_on_floor = on_floor

func _attack_pose() -> PixelRenderer.BodyPose:
	var combo: int = blade.get("current_combo") as int
	match combo:
		0: return PixelRenderer.BodyPose.ATTACK_1
		1: return PixelRenderer.BodyPose.ATTACK_2
		_: return PixelRenderer.BodyPose.ATTACK_3

func _set_pose(pose: PixelRenderer.BodyPose) -> void:
	if _current_pose == pose:
		return
	_current_pose = pose
	body_sprite.texture = _poses[pose]

func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	if input_jump:
		jump_buf_timer = JUMP_BUFFER
		input_jump = false

	jump_buf_timer -= delta

	if jump_buf_timer > 0.0 and coyote_timer > 0.0:
		velocity.y    = JUMP_FORCE
		coyote_timer  = 0.0
		jump_buf_timer = 0.0

func _handle_movement() -> void:
	if input_move != 0.0:
		velocity.x = input_move * MOVE_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 0.25)

# Brief speed burst toward enemy — called by blade.perform_attack()
func lunge(dir: float) -> void:
	velocity.x = dir * MOVE_SPEED * 2.0

# Reads keyboard + touch direction at moment of dodge press.
# No direction → dash forward. Any direction → normalized vector.
func _get_dash_direction() -> Vector2:
	var dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x = 1.0
	elif Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x = -1.0
	elif input_move != 0.0:
		dir.x = input_move

	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y = -1.0
	elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y = 1.0
	elif input_move_vertical != 0.0:
		dir.y = input_move_vertical

	if dir == Vector2.ZERO:
		dir = Vector2(1.0 if is_facing_right else -1.0, 0.0)

	return dir.normalized()

func _handle_dodge(delta: float) -> void:
	dodge_cooldown -= delta

	if input_dodge and not is_dodging and dodge_cooldown <= 0.0:
		dash_dir = _get_dash_direction()
		velocity = dash_dir * DODGE_SPEED
		is_dodging = true
		is_invincible = true
		dodge_timer = DODGE_TIME
		dodge_cooldown = DODGE_COOLDOWN
		input_dodge = false

		# Attack cancel: abort blade recovery/windup
		if blade.has_method("try_dodge_cancel"):
			blade.try_dodge_cancel()

		# Disable enemy collision — pass through enemies
		collision_mask = LAYER_GEOMETRY

	if is_dodging:
		velocity = dash_dir * DODGE_SPEED
		dodge_timer -= delta
		if dodge_timer <= 0.0:
			is_dodging = false
			is_invincible = false
			collision_mask = LAYER_GEOMETRY | LAYER_ENEMY

func _handle_attack(_delta: float) -> void:
	if input_attack:
		input_attack = false
		if blade.has_method("perform_attack"):
			blade.perform_attack()

func _handle_counter(_delta: float) -> void:
	if _is_countering:
		return
	if input_counter:
		input_counter = false
		_is_countering = true
		if blade.has_method("perform_counter"):
			blade.perform_counter()
		_set_pose(PixelRenderer.BodyPose.COUNTER)
		await get_tree().create_timer(0.2).timeout
		_is_countering = false

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_invincible:
		return

	var stack := get_stack()
	var caller := "unknown"
	if stack.size() >= 2:
		caller = stack[1].source + ":" + str(stack[1].line) + " (" + stack[1].function + ")"
	print("[DAMAGE] Player took ", amount, " damage from: ", caller)

	blade.take_damage(amount)

	if knockback != Vector2.ZERO:
		velocity = knockback

	emit_signal("player_hurt")
	_start_iframes(0.5)

func heal() -> void:
	if blade.has_method("restore_full"):
		blade.restore_full()
	_set_pose(PixelRenderer.BodyPose.IDLE)

func _start_iframes(duration: float) -> void:
	is_invincible = true
	await get_tree().create_timer(duration).timeout
	is_invincible = false

func _on_player_died(_pos: Vector2) -> void:
	set_physics_process(false)

func _on_reconstituted() -> void:
	global_position = GameManager.get_respawn_position()
	velocity        = Vector2.ZERO
	set_physics_process(true)

func _read_keyboard_input() -> void:
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		input_move = 1.0
		_kb_moved  = true
	elif Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		input_move = -1.0
		_kb_moved  = true
	elif _kb_moved:
		input_move = 0.0
		_kb_moved  = false

	# Jump
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		input_jump = true

	# Vertical direction for omnidirectional dodge (held state, separate from jump)
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		input_move_vertical = -1.0
		_kb_vert_moved = true
	elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		input_move_vertical = 1.0
		_kb_vert_moved = true
	elif _kb_vert_moved:
		input_move_vertical = 0.0
		_kb_vert_moved = false

	# Edge-triggered: only fire on the frame the key goes down
	var attack_down := Input.is_key_pressed(KEY_Z)
	if attack_down and not _last_attack_key:
		input_attack = true
	_last_attack_key = attack_down

	var dodge_down := Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_SHIFT)
	if dodge_down and not _last_dodge_key:
		input_dodge = true
	_last_dodge_key = dodge_down

	var counter_down := Input.is_key_pressed(KEY_C)
	if counter_down and not _last_counter_key:
		input_counter = true
	_last_counter_key = counter_down

func set_move_input(dir: float)           -> void: input_move   = dir
func set_move_vertical_input(dir: float)  -> void: input_move_vertical = dir
func set_jump_input(pressed: bool)        -> void: input_jump   = pressed
func set_attack_input(pressed: bool)      -> void: input_attack = pressed
func set_dodge_input(pressed: bool)       -> void: input_dodge  = pressed
func set_counter_input(pressed: bool)     -> void: input_counter = pressed
