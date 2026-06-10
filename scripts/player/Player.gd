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
@onready var _lock_on:    Node     = get_node("/root/LockOn")
var _reticle:      Sprite2D = null

# ── Input state (set by TouchInput.gd signals) ────────────────────────────────
var input_move:          float = 0.0
var input_move_vertical: float = 0.0
var input_jump:          bool  = false
var input_attack:        bool  = false
var input_dodge:         bool  = false
var input_counter:       bool  = false
var input_lock_on:       bool  = false

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
var _prev_position := Vector2.ZERO  # For per-frame teleport detection
var _diag_frames   := 0             # When > 0, dump state every frame unconditionally
var _room_w_px     := 704.0         # Set by Game.gd on room load (default 44*16)
var _room_h_px     := 352.0         # Set by Game.gd on room load (default 22*16)

# Previous-frame key state for edge detection
var _last_attack_key  := false
var _last_dodge_key   := false
var _last_counter_key := false
var _last_jump_key    := false
var _last_lock_key    := false

# Pre-generated pose textures
var _poses: Dictionary = {}  # Maps BodyPose enum to ImageTexture

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		print("[PLAYER] PREDELETE — pos=%s vel=%s" % [global_position.round(), velocity.round()])
	elif what == NOTIFICATION_EXIT_TREE:
		print("[PLAYER] EXIT_TREE — pos=%s" % [global_position.round()])

func _ready() -> void:
	_poses = PixelRenderer.generate_body_textures()
	body_sprite.texture = _poses[PixelRenderer.BodyPose.IDLE]
	body_sprite.scale   = Vector2(1.25, 1.25)
	body_sprite.centered = true

	collision_layer = 4  # Layer 3 (player)
	collision_mask  = LAYER_GEOMETRY | LAYER_ENEMY
	# Increase from 0.08 default — prevents degenerate overlap when standing on
	# enemy CharacterBody2Ds. At 1px on 16px tiles, visually imperceptible.
	safe_margin = 1.0

	GameManager.player_died.connect(_on_player_died)
	GameManager.player_reconstituted.connect(_on_reconstituted)

	add_to_group("player")
	camera.add_to_group("camera")

	_lock_on.target_locked.connect(_on_target_locked)
	_lock_on.target_unlocked.connect(_on_target_unlocked)

func set_room_bounds(w_tiles: int, h_tiles: int) -> void:
	_room_w_px = float(w_tiles * 16)
	_room_h_px = float(h_tiles * 16)
	print("[PLAYER] room bounds set: %dx%d tiles → %.0fx%.0f px" % [w_tiles, h_tiles, _room_w_px, _room_h_px])

func _record_hex_holds(timestamp: float) -> void:
	if not blade.has_method("get_input_buffer"):
		return
	var buf: InputBuffer = blade.get_input_buffer()
	if buf == null:
		return
	buf.record_hold("atk", Input.is_key_pressed(KEY_Z), timestamp)
	buf.record_hold("counter", Input.is_key_pressed(KEY_C), timestamp)
	buf.record_hold("jump", Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W), timestamp)
	buf.record_hold("dodge", Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_SHIFT), timestamp)


func _blade_record_action(action: String) -> void:
	if not blade.has_method("record_action"):
		return
	blade.record_action(action, Time.get_ticks_usec() / 1000000.0)


func _physics_process(delta: float) -> void:
	# Log BEFORE the GameManager gate so we know if processing stops
	if not GameManager.is_playing():
		if _diag_frames > 0:
			print("[DIAG] physics BLOCKED by GameManager — pos=", global_position.round(),
				" vel=", velocity.round())
			_diag_frames -= 1
		return

	# ── Unconditional combat dump ─────────────────────────────────────────────
	# After any combat event, dump every frame for 30 frames to catch the launch
	if _diag_frames > 0:
		_diag_frames -= 1
		print("[DIAG %d] pos=%s vel=%s spd=%.0f floor=%s dodge=%s inv=%s vis=%s body_vis=%s mod=%s intree=%s" % [
			_diag_frames, global_position.round(), velocity.round(),
			velocity.length(), is_on_floor(), is_dodging, is_invincible,
			visible, body_sprite.visible if body_sprite else "NULL",
			body_sprite.modulate if body_sprite else "NULL",
			is_inside_tree()])

	# ── Threshold-based checks ────────────────────────────────────────────────
	var _spd := velocity.length()

	if _spd > 520.0 and not is_dodging:
		print("[PHYSICS] EXCESS SPEED: vel=", velocity.round(),
			" speed=", snapped(_spd, 0.1), " pos=", global_position.round())

	# Position teleport: moved more than 64px in one frame without dodging
	var _pos_delta := global_position.distance_to(_prev_position)
	if _pos_delta > 64.0 and _prev_position != Vector2.ZERO and not is_dodging:
		print("[PHYSICS] POSITION JUMP: delta=", snapped(_pos_delta, 0.1),
			" from=", _prev_position.round(), " to=", global_position.round(),
			" vel=", velocity.round())

	# Out of room bounds (dynamic — set by Game.gd per room)
	if global_position.x < -20.0 or global_position.x > _room_w_px + 20.0:
		print("[PHYSICS] OUT OF X BOUNDS: pos=", global_position.round(),
			" vel=", velocity.round(), " room_w=", _room_w_px)
	if global_position.y > _room_h_px - 40.0:
		print("[PHYSICS] BELOW FLOOR: pos=", global_position.round(),
			" vel=", velocity.round(), " room_h=", _room_h_px)

	_read_keyboard_input()
	_tick_status(delta)
	_handle_dodge(delta)

	var timestamp := Time.get_ticks_usec() / 1000000.0
	_record_hex_holds(timestamp)

	if not is_dodging:
		_handle_gravity(delta)
		_handle_movement()
		_handle_attack(delta)
		_handle_counter(delta)

	if input_lock_on:
		input_lock_on = false
		if _lock_on.is_locked():
			_lock_on.unlock()
		else:
			_lock_nearest()

	var pre_slide_vel := velocity
	move_and_slide()

	# ── NaN guard ─────────────────────────────────────────────────────────────
	# move_and_slide() can return NaN when two CharacterBody2Ds overlap and the
	# physics engine can't resolve the collision normal. Reset to checkpoint.
	if is_nan(global_position.x) or is_nan(global_position.y):
		print("[PHYSICS] NaN DETECTED after move_and_slide — pre_vel=", pre_slide_vel,
			" restoring prev_pos=", _prev_position.round())
		global_position = _prev_position
		velocity = Vector2.ZERO
		return

	# ── Velocity spike detector ───────────────────────────────────────────────
	# Prints when move_and_slide imparts a large unexpected velocity change,
	# which is the signature of a physics stacking launch off enemy bodies.
	var vel_delta := (velocity - pre_slide_vel).length()
	if vel_delta > 400.0:
		print("[PHYSICS] Velocity spike after move_and_slide: pre=", pre_slide_vel.round(),
			" post=", velocity.round(), " delta=", snapped(vel_delta, 0.1),
			" pos=", global_position.round(),
			" slide_count=", get_slide_collision_count())
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			print("  collider[%d]: %s layer=%d" % [i, col.get_collider(), col.get_collider().collision_layer if col.get_collider() is PhysicsBody2D else -1])

	_prev_position = global_position

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

	if _lock_on.is_locked():
		var dir: float = _lock_on.facing_dir(global_position)
		if dir != 0.0:
			is_facing_right = dir > 0.0
			body_sprite.flip_h = not is_facing_right
		if _reticle and _lock_on.get_target_node():
			_reticle.global_position = _lock_on.get_target_node().global_position + Vector2(0, -40)

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
	# Boss status effects (BOSS_DESIGN.md): root/stun freeze, invert flips, slow scales
	if _status_timer > 0.0 and (_status == "root" or _status == "stun"):
		velocity.x = 0.0
		return
	var move := input_move
	if _status_timer > 0.0 and _status == "invert":
		move = -move
	var speed := MOVE_SPEED
	if _status_timer > 0.0 and _status == "slow":
		speed *= 0.6
	if move != 0.0:
		velocity.x = move * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 0.25)

# ── Boss status effects ──────────────────────────────────────────────────────
# Applied by BossEnemy / BossArenaManager. One status at a time, last wins.
var _status := ""
var _status_timer := 0.0
var _pull_target := Vector2.ZERO

func apply_status(status: String, duration: float, origin: Vector2 = Vector2.ZERO) -> void:
	if is_dodging and (status == "root" or status == "stun" or status == "pull_to"):
		return  # dodge i-frames also evade control effects
	_status = status
	_status_timer = duration
	_pull_target = origin
	if body_sprite:
		body_sprite.modulate = Color(0.7, 0.7, 1.2, 1.0)

func _tick_status(delta: float) -> void:
	if _status_timer <= 0.0:
		return
	_status_timer -= delta
	if _status == "pull_to" and _pull_target != Vector2.ZERO:
		var dir := (_pull_target - global_position).normalized()
		velocity = dir * 260.0
	if _status_timer <= 0.0:
		_status = ""
		if body_sprite:
			body_sprite.modulate = Color.WHITE

# Brief speed burst toward enemy — called by blade.perform_attack()
func lunge(dir: float) -> void:
	print("[LUNGE] dir=", dir, " vel_before=", velocity.round(), " pos=", global_position.round())
	velocity.x = dir * MOVE_SPEED * 2.0
	_diag_frames = 30

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
		print("[DODGE] start: dir=", dash_dir, " vel_before=", velocity.round(), " pos=", global_position.round())
		velocity = dash_dir * DODGE_SPEED
		is_dodging = true
		_diag_frames = 30
		is_invincible = true
		dodge_timer = DODGE_TIME
		dodge_cooldown = DODGE_COOLDOWN
		input_dodge = false

		# Attack cancel: abort blade recovery/windup
		if blade.has_method("try_dodge_cancel"):
			blade.try_dodge_cancel()

		# Disable enemy collision during dodge — pass through enemies
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
	_diag_frames = 30

	if knockback != Vector2.ZERO:
		print("[DAMAGE] knockback applied: ", knockback.round(), " vel_before=", velocity.round())
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

	# Jump (edge-triggered for hex buffer)
	var jump_down := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
	if jump_down:
		input_jump = true
		if not _last_jump_key:
			_blade_record_action("jump")
	_last_jump_key = jump_down

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
		_blade_record_action("atk")
	_last_attack_key = attack_down

	var dodge_down := Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_SHIFT)
	if dodge_down and not _last_dodge_key:
		input_dodge = true
		_blade_record_action("dodge")
	_last_dodge_key = dodge_down

	var counter_down := Input.is_key_pressed(KEY_C)
	if counter_down and not _last_counter_key:
		input_counter = true
		_blade_record_action("counter")
	_last_counter_key = counter_down

	var lock_down := Input.is_key_pressed(KEY_TAB)
	if lock_down and not _last_lock_key:
		input_lock_on = true
	_last_lock_key = lock_down

func _on_target_locked(_target: Node2D) -> void:
	_reticle = Sprite2D.new()
	_reticle.texture = PixelRenderer.generate_lockon_reticle()
	_reticle.centered = true
	_reticle.z_index = 100
	add_child(_reticle)
	var t := create_tween()
	t.set_loops()
	t.tween_property(_reticle, "scale", Vector2(1.3, 1.3), 0.6)
	t.tween_property(_reticle, "scale", Vector2(0.9, 0.9), 0.6)

func _on_target_unlocked() -> void:
	if _reticle:
		_reticle.queue_free()
		_reticle = null

func _lock_nearest() -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_squared_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	if nearest != null:
		_lock_on.lock_on(nearest)

func set_move_input(dir: float)           -> void: input_move   = dir
func set_move_vertical_input(dir: float)  -> void: input_move_vertical = dir
func set_jump_input(pressed: bool)        -> void:
	input_jump = pressed
	if pressed:
		_blade_record_action("jump")
func set_attack_input(pressed: bool)      -> void:
	input_attack = pressed
	if pressed:
		_blade_record_action("atk")
func set_dodge_input(pressed: bool)       -> void:
	input_dodge = pressed
	if pressed:
		_blade_record_action("dodge")
func set_counter_input(pressed: bool)     -> void:
	input_counter = pressed
	if pressed:
		_blade_record_action("counter")
