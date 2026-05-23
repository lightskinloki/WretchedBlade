extends CharacterBody2D
# RivalBlade.gd — enemy sword construct.
#
# Dual-wielding blade construct with a 3-hit combo chain.
# Patrols → chases → attacks in combos when close.

signal enemy_died(position: Vector2, essence_value: int)

const MOVE_SPEED   := 100.0
const CHASE_RANGE  := 200.0
const ATTACK_CD    := 1.8
const PATROL_DIST  := 140.0

var _body:        Sprite2D
var _blade_right:  Sprite2D
var _blade_left:   Sprite2D
var _right_hitbox:      Area2D
var _left_hitbox:       Area2D
var _right_hitbox_shape: CollisionShape2D
var _left_hitbox_shape: CollisionShape2D
var _right_dbg: ColorRect
var _left_dbg: ColorRect
const _BLADE_HITBOX_SIZE := Vector2(18, 60)

var _move_dir    := 1.0
var _start_pos:  Vector2
var _is_alive   := true
var _attack_cd   := 0.0
var _state       := "patrol"  # "patrol" | "chase" | "attack"
var _player_ref: Node2D
var _is_stunned := false
var _stun_timer := 0.0
var current_health := 120
var _stagger_timer := 0.0
const MAX_HEALTH := 120

# Combo system
var _combo_stage     := 0
var _attack_phase     := "windup"  # "windup" | "active" | "recovery"
var _attack_phase_timer := 0.0
var _rest_right_x := -14.0  # Right blade rest x
var _rest_left_x  :=  14.0  # Left blade rest x
const _REST_Y     := -20.0

const RIVAL_COMBO := [
	# Hit 0 — Right Slash (right blade sweeps across, left stays)
	{"windup": 0.20, "active": 0.18, "recovery": 0.15, "damage": 8,
	 "r_start": 150.0, "r_end": 25.0, "r_radius": 22.0, "r_wfrac": 0.15,
	 "l_start": 180.0, "l_end": 180.0, "l_radius": 14.0, "l_wfrac": 0.0},
	# Hit 1 — Left Slash (left blade sweeps across, right stays)
	{"windup": 0.18, "active": 0.16, "recovery": 0.12, "damage": 8,
	 "r_start": 0.0, "r_end": 0.0, "r_radius": 14.0, "r_wfrac": 0.0,
	 "l_start": -150.0, "l_end": -25.0, "l_radius": 22.0, "l_wfrac": 0.15},
	# Hit 2 — Cross Slash (both sweep inward from opposite sides)
	{"windup": 0.30, "active": 0.25, "recovery": 0.22, "damage": 14,
	 "r_start": 155.0, "r_end": -35.0, "r_radius": 24.0, "r_wfrac": 0.20,
	 "l_start": -155.0, "l_end": 35.0, "l_radius": 24.0, "l_wfrac": 0.20},
]

const ESSENCE_DROP := 25

# Stores the current interpolated angle for each blade during attack
var _r_angle := 0.0
var _l_angle := 0.0

func _ready() -> void:
	_start_pos = global_position
	_move_dir = 1.0 if randf() > 0.5 else -1.0

	_body = Sprite2D.new()
	_body.name = "BodySprite"
	var poses: Dictionary = PixelRenderer.generate_body_textures()
	_body.texture = poses[PixelRenderer.BodyPose.IDLE]
	_body.scale = Vector2(1.25, 1.25)
	_body.centered = true
	add_child(_body)

	var tex := PixelRenderer.generate_enemy_texture(PixelRenderer.EnemyType.RIVAL)

	_blade_right = Sprite2D.new()
	_blade_right.name = "BladeRight"
	_blade_right.texture = tex
	_blade_right.scale = Vector2(1.25, 1.25)
	_blade_right.position = Vector2(_rest_right_x, _REST_Y)
	_blade_right.centered = true
	add_child(_blade_right)

	_blade_left = Sprite2D.new()
	_blade_left.name = "BladeLeft"
	_blade_left.texture = tex
	_blade_left.scale = Vector2(1.25, 1.25)
	_blade_left.position = Vector2(_rest_left_x, _REST_Y)
	_blade_left.centered = true
	add_child(_blade_left)

	_hitbox_setup_for_blade(_blade_right, "_right_hitbox", "_right_hitbox_shape", "_right_dbg")
	_hitbox_setup_for_blade(_blade_left, "_left_hitbox", "_left_hitbox_shape", "_left_dbg")

	add_to_group("enemy")
	add_to_group("rival")

func _hitbox_setup_for_blade(blade: Sprite2D, hitbox_name: String, shape_name: String, dbg_name: String) -> void:
	var hitbox := Area2D.new()
	hitbox.name = blade.name + "Hitbox"
	hitbox.collision_mask = 4
	hitbox.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _BLADE_HITBOX_SIZE
	shape.shape = rect
	shape.position = Vector2(0, -2)
	hitbox.add_child(shape)
	var dbg := ColorRect.new()
	dbg.size = _BLADE_HITBOX_SIZE
	dbg.color = Color(1, 0, 0, 0.35)
	dbg.position = Vector2(-_BLADE_HITBOX_SIZE.x * 0.5, -_BLADE_HITBOX_SIZE.y * 0.5 - 2)
	hitbox.add_child(dbg)
	blade.add_child(hitbox)
	hitbox.body_entered.connect(_on_hitbox_entered)
	set(hitbox_name, hitbox)
	set(shape_name, shape)
	set(dbg_name, dbg)

func _physics_process(delta: float) -> void:
	if not _is_alive or not GameManager.is_playing():
		return

	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		return

	if _is_stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_is_stunned = false
			_set_blades_modulate(Color.WHITE)
			if _body:
				_body.modulate = Color.WHITE
		return

	_attack_cd = maxf(_attack_cd - delta, 0.0)

	if not _player_ref:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player_ref = players[0]

	match _state:
		"patrol":
			_patrol(delta)
			_check_chase()
		"chase":
			_chase(delta)
			_check_attack()
		"attack":
			_attack_process(delta)

	if _body and is_instance_valid(_body):
		_body.position.y = sin(Time.get_ticks_msec() * 0.015) * 2.0

func _set_blades_modulate(c: Color) -> void:
	if _blade_right:
		_blade_right.modulate = c
	if _blade_left:
		_blade_left.modulate = c

func _set_blade_rest_positions() -> void:
	var fdir := _facing_dir()
	var is_right := fdir > 0.0
	_rest_right_x = -14.0 if is_right else 14.0
	_rest_left_x  =  14.0 if is_right else -14.0
	if _blade_right:
		_blade_right.scale.x = 1.25 if is_right else -1.25
		_blade_right.position.x = _rest_right_x
		_blade_right.position.y = _REST_Y
		_blade_right.rotation_degrees = 0.0
	if _blade_left:
		_blade_left.scale.x = 1.25 if is_right else -1.25
		_blade_left.position.x = _rest_left_x
		_blade_left.position.y = _REST_Y
		_blade_left.rotation_degrees = 0.0

func _facing_dir() -> float:
	if _player_ref and is_instance_valid(_player_ref):
		return signf(_player_ref.global_position.x - global_position.x)
	return _move_dir

func _patrol(delta: float) -> void:
	velocity.x = _move_dir * MOVE_SPEED
	move_and_slide()

	var dist: float = absf(global_position.x - _start_pos.x)
	if dist >= PATROL_DIST:
		_move_dir = -_move_dir
		_start_pos = global_position

	var fdir := _facing_dir()
	if _body:
		_body.flip_h = fdir < 0.0
	_set_blade_rest_positions()

func _check_chase() -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	var dist := global_position.distance_to(_player_ref.global_position)
	if dist < CHASE_RANGE:
		_state = "chase"

func _chase(delta: float) -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		_state = "patrol"
		return

	var dir: float = signf(_player_ref.global_position.x - global_position.x)
	velocity.x = dir * MOVE_SPEED
	move_and_slide()

	_move_dir = dir
	var fdir := _facing_dir()
	if _body:
		_body.flip_h = fdir < 0.0
	_set_blade_rest_positions()

func _check_attack() -> void:
	if _attack_cd > 0.0:
		return
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	if global_position.distance_to(_player_ref.global_position) < 50.0:
		_state = "attack"
		_attack_phase = "windup"
		var data: Dictionary = RIVAL_COMBO[_combo_stage]
		_attack_phase_timer = data["windup"]
		_set_blades_modulate(Color(2.0, 2.0, 3.0, 1.0))

func _attack_process(delta: float) -> void:
	_attack_phase_timer -= delta
	var data: Dictionary = RIVAL_COMBO[_combo_stage]

	var total: float
	match _attack_phase:
		"windup":   total = data["windup"]
		"active":   total = data["active"]
		"recovery": total = data["recovery"]
		_:          return
	var t := clampf(1.0 - _attack_phase_timer / total, 0.0, 1.0)
	var et := _ease(t)

	match _attack_phase:
		"windup":
			if _attack_phase_timer <= 0.0:
				var r_wfrac: float = data.get("r_wfrac", 0.15)
				var l_wfrac: float = data.get("l_wfrac", 0.15)
				_r_angle = data["r_start"] + (data["r_end"] - data["r_start"]) * r_wfrac
				_l_angle = data["l_start"] + (data["l_end"] - data["l_start"]) * l_wfrac
				_attack_enter_active()
		"active":
			var r_wfrac: float = data.get("r_wfrac", 0.15)
			var l_wfrac: float = data.get("l_wfrac", 0.15)
			_r_angle = lerpf(data["r_start"] + (data["r_end"] - data["r_start"]) * r_wfrac, data["r_end"], et)
			_l_angle = lerpf(data["l_start"] + (data["l_end"] - data["l_start"]) * l_wfrac, data["l_end"], et)
			_position_blades()
			if _attack_phase_timer <= 0.0:
				_attack_enter_recovery()
		"recovery":
			if _attack_phase_timer <= 0.0:
				_attack_finish()

func _position_blades() -> void:
	var fdir := _facing_dir()

	var rad := deg_to_rad(_r_angle)
	var ox := cos(rad) * absf(data_r("r_radius", 20.0))
	var oy := sin(rad) * absf(data_r("r_radius", 20.0))
	if fdir < 0.0:
		ox = -ox
	if _blade_right:
		_blade_right.position = Vector2(ox, _REST_Y + oy)
		_blade_right.rotation_degrees = 0.0

	rad = deg_to_rad(_l_angle)
	ox = cos(rad) * absf(data_r("l_radius", 20.0))
	oy = sin(rad) * absf(data_r("l_radius", 20.0))
	if fdir < 0.0:
		ox = -ox
	if _blade_left:
		_blade_left.position = Vector2(ox, _REST_Y + oy)
		_blade_left.rotation_degrees = 0.0

# Helper: read a float from current combo data with fallback
func data_r(key: String, default: float) -> float:
	var d: Dictionary = RIVAL_COMBO[_combo_stage]
	return d.get(key, default)

func _ease(t: float) -> float:
	if t < 0.5:
		return 2.0 * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0

func _attack_enter_active() -> void:
	_attack_phase = "active"
	var data: Dictionary = RIVAL_COMBO[_combo_stage]
	_attack_phase_timer = data["active"]
	_set_blades_modulate(Color.WHITE)
	_enable_active_hitboxes()

func _enable_active_hitboxes() -> void:
	var data: Dictionary = RIVAL_COMBO[_combo_stage]
	if _right_hitbox:
		_right_hitbox.monitoring = data.get("r_start", 0.0) != data.get("r_end", 0.0)
	if _left_hitbox:
		_left_hitbox.monitoring = data.get("l_start", 0.0) != data.get("l_end", 0.0)

func _disable_all_hitboxes() -> void:
	if _right_hitbox:
		_right_hitbox.monitoring = false
	if _left_hitbox:
		_left_hitbox.monitoring = false

func _attack_enter_recovery() -> void:
	_attack_phase = "recovery"
	var data: Dictionary = RIVAL_COMBO[_combo_stage]
	_attack_phase_timer = data["recovery"]
	_disable_all_hitboxes()
	# Smooth tween back to rest positions
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_blade_right, "position", Vector2(_rest_right_x, _REST_Y), data["recovery"])
	t.tween_property(_blade_left,  "position", Vector2(_rest_left_x, _REST_Y), data["recovery"])
	t.tween_property(_blade_right, "rotation_degrees", 0.0, data["recovery"])
	t.tween_property(_blade_left,  "rotation_degrees", 0.0, data["recovery"])

func _attack_finish() -> void:
	_combo_stage = (_combo_stage + 1) % RIVAL_COMBO.size()
	_attack_cd = ATTACK_CD

	if _should_chain():
		_state = "attack"
		_attack_phase = "windup"
		var data: Dictionary = RIVAL_COMBO[_combo_stage]
		_attack_phase_timer = data["windup"]
		_set_blades_modulate(Color(2.0, 2.0, 3.0, 1.0))
	else:
		_combo_stage = 0
		_state = "chase"

func _should_chain() -> bool:
	if not _player_ref or not is_instance_valid(_player_ref):
		return false
	return global_position.distance_to(_player_ref.global_position) < 65.0

func is_counterable() -> bool:
	return _is_alive and _state == "attack" and _attack_phase == "windup"

func countered() -> void:
	if not _is_alive:
		return
	_state = "chase"
	_combo_stage = 0
	_disable_all_hitboxes()
	_is_stunned = true
	_stun_timer = 1.0
	_set_blades_modulate(Color(1.0, 0.8, 1.0, 1.0))
	if _body:
		_body.modulate = Color(1.0, 0.8, 1.0, 1.0)

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not _is_alive:
		return

	current_health -= amount
	if _state == "attack":
		_state = "chase"
		_combo_stage = 0
		_disable_all_hitboxes()

	if current_health > 0:
		_stagger_timer = 0.10
		_set_blades_modulate(Color(1.0, 0.6, 0.7, 1.0))
		var t := create_tween()
		t.tween_callback(_set_blades_modulate.bind(Color.WHITE)).set_delay(0.15)
		if knockback != Vector2.ZERO:
			velocity = Vector2(knockback.x, 0.0)
			move_and_slide()
		return

	_is_alive = false
	set_physics_process(false)

	if knockback != Vector2.ZERO:
		velocity = Vector2(knockback.x, 0.0)
		move_and_slide()

	if _body:
		var t := create_tween()
		t.tween_property(_body, "modulate:a", 0.0, 0.3)
		t.parallel().tween_property(_blade_right, "modulate:a", 0.0, 0.3)
		t.parallel().tween_property(_blade_left,  "modulate:a", 0.0, 0.3)
		t.tween_callback(queue_free)

	emit_signal("enemy_died", global_position, ESSENCE_DROP)
	EssenceManager.gain_essence(ESSENCE_DROP)

func _on_hitbox_entered(body: Node) -> void:
	if body.is_in_group("player") and _is_alive:
		body.take_damage(15)
