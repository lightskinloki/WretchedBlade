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

# ── Status effect component ────────────────────────────────────────────────────
var status_fx: StatusEffectComponent = StatusEffectComponent.new()
var _status_icons: Control = null    # Container for status icon display
var _icon_textures: Dictionary = {}  # Cache of generated icon textures
var _pull_target := Vector2.ZERO     # For PULL_TO origin tracking

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

	# Status effect component
	status_fx.status_added.connect(_on_status_added)
	status_fx.status_removed.connect(_on_status_removed)
	status_fx.status_tick.connect(_on_status_tick)
	status_fx.visual_tint_changed.connect(_on_visual_tint_changed)
	_build_status_icon_container()

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
	status_fx.process(delta)
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
	# Pull status — override all movement
	if status_fx.has(StatusEffectComponent.ID.PULL_TO):
		var pull_to_status = status_fx._active.get(StatusEffectComponent.ID.PULL_TO)
		if pull_to_status:
			_pull_target = pull_to_status["params"].get("origin", Vector2.ZERO)
		if _pull_target != Vector2.ZERO:
			var dir := (_pull_target - global_position).normalized()
			velocity = dir * 260.0
			return

	# Root/STUN — freeze horizontal movement
	if status_fx.has(StatusEffectComponent.ID.ROOT) or status_fx.has(StatusEffectComponent.ID.STUN):
		velocity.x = 0.0
		return

	var move := input_move
	# Invert — flip horizontal input
	if status_fx.has(StatusEffectComponent.ID.INVERT):
		move = -move

	# Speed — apply combined slow multiplier
	var speed := MOVE_SPEED * status_fx.get_slow_multiplier()

	if move != 0.0:
		velocity.x = move * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 0.25)

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
		status_fx.set_dodge_immune(true)

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
			status_fx.set_dodge_immune(false)
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

var _last_whetstone_key := false
var _last_god_key := false

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_invincible or GameManager.is_god_mode:
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

func use_whetstone() -> void:
	if is_invincible or not GameManager.is_playing():
		return
	if GameManager.use_whetstone():
		if blade.has_method("repair"):
			blade.repair(40)

func _start_iframes(duration: float) -> void:
	is_invincible = true
	await get_tree().create_timer(duration).timeout
	is_invincible = false

func _on_player_died(_pos: Vector2) -> void:
	set_physics_process(false)

func _on_reconstituted() -> void:
	global_position = GameManager.get_respawn_position()
	velocity        = Vector2.ZERO
	heal()
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

	var whetstone_down := Input.is_key_pressed(KEY_H)
	if whetstone_down and not _last_whetstone_key:
		use_whetstone()
	_last_whetstone_key = whetstone_down

	var god_down := Input.is_key_pressed(KEY_F1) or Input.is_key_pressed(KEY_G)
	if god_down and not _last_god_key:
		GameManager.toggle_god_mode()
	_last_god_key = god_down

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


# ── Status effect integration ─────────────────────────────────────────────────

func apply_status(status: String, duration: float, origin: Vector2 = Vector2.ZERO, mult: float = 0.6) -> void:
	# String → ID mapping for backward compatibility
	var status_id := -1
	match status:
		"root":     status_id = StatusEffectComponent.ID.ROOT
		"stun":     status_id = StatusEffectComponent.ID.STUN
		"invert":   status_id = StatusEffectComponent.ID.INVERT
		"slow":     status_id = StatusEffectComponent.ID.SLOW
		"pull_to":  status_id = StatusEffectComponent.ID.PULL_TO
		"darkness": status_id = StatusEffectComponent.ID.DARKNESS
		"dot":      status_id = StatusEffectComponent.ID.DOT
	if status_id >= 0:
		var params := {}
		if status_id == StatusEffectComponent.ID.PULL_TO:
			params["origin"] = origin
		elif status_id == StatusEffectComponent.ID.SLOW:
			params["mult"] = mult
		status_fx.apply(status_id, duration, params, self)


func _on_status_added(_status_id: int, _duration: float, _params: Dictionary) -> void:
	_update_status_icons()


func _on_status_removed(_status_id: int) -> void:
	_update_status_icons()
	# Clear tint if no statuses remain
	if status_fx.get_all_active().is_empty():
		body_sprite.modulate = Color.WHITE


func _on_status_tick(status_id: int, params: Dictionary) -> void:
	if status_id == StatusEffectComponent.ID.DOT:
		var dmg: int = params.get("dmg_per_tick", 1)
		if blade.has_method("take_damage"):
			blade.take_damage(dmg)


func _on_visual_tint_changed(tint_color: Color, intensity: float) -> void:
	if status_fx.get_all_active().is_empty():
		body_sprite.modulate = Color.WHITE
	else:
		# Blend tint with white based on intensity
		body_sprite.modulate = Color.WHITE.lerp(tint_color, intensity)


func _build_status_icon_container() -> void:
	_status_icons = Control.new()
	_status_icons.name = "StatusIcons"
	_status_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Position above the body sprite
	_status_icons.position = Vector2(-20, -30)
	_status_icons.size = Vector2(40, 12)
	add_child(_status_icons)


func _update_status_icons() -> void:
	# Clear old icons
	for child in _status_icons.get_children():
		child.queue_free()

	var active_ids := status_fx.get_all_active()
	var offset := 0.0
	for status_id in active_ids:
		var icon := TextureRect.new()
		icon.name = "Icon_%d" % status_id
		if not _icon_textures.has(status_id):
			_icon_textures[status_id] = PixelRenderer.generate_status_icon(status_id)
		icon.texture = _icon_textures[status_id]
		icon.position = Vector2(offset, 0)
		icon.size = Vector2(8, 8)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_icons.add_child(icon)
		offset += 10.0
