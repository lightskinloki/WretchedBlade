extends CharacterBody2D
# RivalBlade.gd — enemy sword construct.
#
# Two-layer AI:
#   Layer 1 — Priority-based decision engine reads WretchedBlade.current_state every frame.
#             Reacts to player attack state with dodge / counter / punish / pressure / pace.
#   Layer 2 — Per-fight memory tracks 4 player behaviors and adapts personality mid-fight.
#             Resets on Rival death. Thresholds trigger logged [RIVAL] ADAPTED: events.

signal enemy_died(position: Vector2, essence_value: int)

# ── Movement ──────────────────────────────────────────────────────────────────
const MOVE_SPEED    := 100.0
const VERTICAL_SPEED := 75.0   # Vertical tracking speed — slower than horizontal for floaty feel
const PATROL_DIST   := 140.0
const CHASE_RANGE   := 200.0

# ── AI decision ranges ────────────────────────────────────────────────────────
const DODGE_TRIGGER_RANGE := 80.0    # Dodge if player WINDUP and closer than this
const COUNTER_RANGE       := 90.0    # Counter if player ACTIVE and closer than this
const PUNISH_RANGE        := 65.0    # Punish if player RECOVERY and closer than this
const PACE_MIN            := 80.0
const PACE_MAX            := 145.0

# ── Timing ────────────────────────────────────────────────────────────────────
const ATTACK_CD_BASE    := 1.8
const DODGE_SPEED       := 320.0
const DODGE_DURATION    := 0.15
const DODGE_CD          := 0.8
const COUNTER_DURATION  := 0.28
const COUNTER_CD        := 1.2

# ── Combat ────────────────────────────────────────────────────────────────────
const COUNTER_RIPOSTE_DAMAGE := 10
const ESSENCE_DROP           := 25

# ── Player blade state constants (mirrors WretchedBlade.AttackState enum) ────
const WB_IDLE     := 0
const WB_WINDUP   := 1
const WB_ACTIVE   := 2
const WB_RECOVERY := 3

# ── Node refs ─────────────────────────────────────────────────────────────────
var _body:               Sprite2D
var _blade_right:        Sprite2D
var _blade_left:         Sprite2D
var _right_hitbox:       Area2D
var _left_hitbox:        Area2D
var _right_hitbox_shape: CollisionShape2D
var _left_hitbox_shape:  CollisionShape2D
var _right_dbg:          ColorRect
var _left_dbg:           ColorRect
const _BLADE_HITBOX_SIZE := Vector2(18, 60)

# ── Core state ────────────────────────────────────────────────────────────────
var _state      := "patrol"
# States: "patrol" | "chase" | "pace" | "attack" | "dodge" | "counter" | "stun"

var _move_dir    := 1.0
var _start_pos:  Vector2
var _is_alive    := true
var _player_ref: Node2D
var current_health  := 120
var _stagger_timer  := 0.0
const MAX_HEALTH    := 120

# ── Cooldowns / timers ────────────────────────────────────────────────────────
var _attack_cd    := 0.0
var _dodge_cd     := 0.0
var _dodge_timer  := 0.0
var _counter_cd   := 0.0
var _counter_timer := 0.0
var _stun_timer   := 0.0

# ── Flags ─────────────────────────────────────────────────────────────────────
var _is_dodging    := false
var _is_countering := false

# ── Decision tracking ─────────────────────────────────────────────────────────
var _player_last_blade_state  := WB_IDLE
var _dodge_roll_done          := false
var _counter_roll_done        := false
var _player_was_dodging       := false

# ── Personality (randomized in _ready, modified by Layer 2) ──────────────────
var _aggression:      float   # 0.3 – 0.9   dodge probability
var _preferred_range: float   # 55 – 85px   pressure attack distance
var _counter_chance:  float   # 0.3 – 0.8   counter attempt probability

# ── Pacing ────────────────────────────────────────────────────────────────────
var _pace_timer  := 0.0
var _pace_action := "idle"   # "strafe_left"|"strafe_right"|"idle"|"feint"

# ── Combo ─────────────────────────────────────────────────────────────────────
var _combo_stage        := 0
var _attack_phase       := "windup"   # "windup"|"active"|"recovery"
var _attack_phase_timer := 0.0
var _feint_window_open  := false      # True while feint can still fire this windup
var _rec_prev_blade_state := WB_IDLE  # For recovery-trap detection
var _recovery_punish_checked := false # Only record one punish per recovery phase

var _rest_right_x := -14.0
var _rest_left_x  :=  14.0
const _REST_Y     := -20.0

const RIVAL_COMBO := [
	# Hit 0 — Right Slash (right blade sweeps right-to-left; catches player going right)
	{"windup": 0.20, "active": 0.18, "recovery": 0.15, "damage": 8,
	 "r_start": 150.0, "r_end": 25.0,  "r_radius": 22.0, "r_wfrac": 0.15,
	 "l_start": 180.0, "l_end": 180.0, "l_radius": 14.0, "l_wfrac": 0.0},
	# Hit 1 — Left Slash (left blade sweeps left-to-right; catches player going left)
	{"windup": 0.18, "active": 0.16, "recovery": 0.12, "damage": 8,
	 "r_start": 0.0,    "r_end": 0.0,   "r_radius": 14.0, "r_wfrac": 0.0,
	 "l_start": -150.0, "l_end": -25.0, "l_radius": 22.0, "l_wfrac": 0.15},
	# Hit 2 — Cross Slash (both blades; no dodge direction bias)
	{"windup": 0.30, "active": 0.25, "recovery": 0.22, "damage": 14,
	 "r_start": 155.0,  "r_end": -35.0, "r_radius": 24.0, "r_wfrac": 0.20,
	 "l_start": -155.0, "l_end": 35.0,  "l_radius": 24.0, "l_wfrac": 0.20},
]

var _r_angle := 0.0
var _l_angle := 0.0

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 2 — Per-fight memory
# All vars reset when Rival dies (_is_alive = false path in take_damage).
# ─────────────────────────────────────────────────────────────────────────────
var _mem_times_countered:   int   = 0   # Rival's windup was player-countered
var _mem_dodge_left:        int   = 0   # Player dodged left
var _mem_dodge_right:       int   = 0   # Player dodged right
var _mem_punished_recovery: int   = 0   # Player attacked during Rival's recovery
var _mem_player_attacks:    int   = 0   # Player WINDUP initiations observed
var _mem_fight_elapsed:     float = 0.0 # Seconds spent active (for aggression rate)
var _mem_pressure_timer:    float = 0.0 # Countdown to next aggression recalculation

# Derived adaptation variables — fed back into Layer 1 decisions
var _feint_chance:         float = 0.0   # Probability of aborting windup mid-swing
var _recovery_trap_chance: float = 0.0   # Probability of snapping recovery into counter
var _attack_dir_bias:      int   = 0     # -1=prefer Hit1(left), 0=neutral, 1=prefer Hit0(right)
var _pressure_mod:         float = 1.0   # Multiplier on ATTACK_CD (< 1.0 = more pressure)

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_start_pos = global_position
	_move_dir = 1.0 if randf() > 0.5 else -1.0

	# Personality — varies per Rival instance
	_aggression      = randf_range(0.3, 0.9)
	_preferred_range = randf_range(55.0, 85.0)
	_counter_chance  = randf_range(0.3, 0.8)

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
	_hitbox_setup_for_blade(_blade_left,  "_left_hitbox",  "_left_hitbox_shape",  "_left_dbg")

	add_to_group("enemy")
	add_to_group("rival")

func _hitbox_setup_for_blade(blade: Sprite2D, hitbox_name: String, shape_name: String, dbg_name: String) -> void:
	var hitbox := Area2D.new()
	hitbox.name = blade.name + "Hitbox"
	hitbox.collision_mask = 4
	hitbox.monitoring = false
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size = _BLADE_HITBOX_SIZE
	shape.shape = rect
	shape.position = Vector2(0, -2)
	hitbox.add_child(shape)
	var dbg := ColorRect.new()
	dbg.size  = _BLADE_HITBOX_SIZE
	dbg.color = Color(1, 0, 0, 0.35)
	dbg.position = Vector2(-_BLADE_HITBOX_SIZE.x * 0.5, -_BLADE_HITBOX_SIZE.y * 0.5 - 2)
	hitbox.add_child(dbg)
	blade.add_child(hitbox)
	hitbox.body_entered.connect(_on_hitbox_entered)
	set(hitbox_name, hitbox)
	set(shape_name, shape)
	set(dbg_name, dbg)

# ── Main loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not _is_alive or not GameManager.is_playing():
		return

	# Tick cooldowns
	_attack_cd  = maxf(_attack_cd  - delta, 0.0)
	_dodge_cd   = maxf(_dodge_cd   - delta, 0.0)
	_counter_cd = maxf(_counter_cd - delta, 0.0)

	# Find player ref
	if not _player_ref:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player_ref = players[0]

	# Stagger blocks all action
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		return

	match _state:
		"patrol":
			_patrol(delta)
			_tick_decision(delta)
		"chase":
			_chase(delta)
			_tick_decision(delta)
		"pace":
			_pace(delta)
			_tick_decision(delta)
		"attack":
			_attack_process(delta)
		"dodge":
			_process_dodge(delta)
		"counter":
			_process_counter(delta)
		"stun":
			_process_stun(delta)

	# Float body
	if _body and is_instance_valid(_body):
		_body.position.y = sin(Time.get_ticks_msec() * 0.015) * 2.0

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 1 — Decision engine
# ─────────────────────────────────────────────────────────────────────────────
func _tick_decision(delta: float) -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		if _state != "patrol":
			_state = "patrol"
		return

	# Advance fight clock
	_mem_fight_elapsed += delta
	_mem_pressure_timer -= delta
	if _mem_pressure_timer <= 0.0:
		_mem_pressure_timer = 5.0
		_recalculate_pressure()

	var dist        := _player_dist()
	var blade_state := _read_blade_state()
	var player_inv  := _read_player_invincible()

	# ── Track player events ──────────────────────────────────────────────────

	# Player attack initiation
	if blade_state == WB_WINDUP and _player_last_blade_state == WB_IDLE:
		_mem_player_attacks += 1

	# Player dodge direction
	var is_dodging_now := _read_player_dodging()
	if is_dodging_now and not _player_was_dodging:
		_observe_dodge_direction()
	_player_was_dodging = is_dodging_now

	# Reset per-attack rolls on blade state change
	if blade_state != _player_last_blade_state:
		_player_last_blade_state = blade_state
		_dodge_roll_done  = false
		_counter_roll_done = false

	# ── Priority waterfall ───────────────────────────────────────────────────

	# 1. Dodge — player winding up and we're in range
	if blade_state == WB_WINDUP \
			and dist < DODGE_TRIGGER_RANGE \
			and _dodge_cd <= 0.0 \
			and not _dodge_roll_done:
		_dodge_roll_done = true
		if randf() < _aggression:
			_start_dodge()
			return

	# 2. Counter — player active (mid-swing) and we're in window
	if blade_state == WB_ACTIVE \
			and dist < COUNTER_RANGE \
			and _counter_cd <= 0.0 \
			and not _counter_roll_done:
		_counter_roll_done = true
		if randf() < _counter_chance:
			_start_counter()
			return

	# 3. Punish — player in recovery, we're close
	if blade_state == WB_RECOVERY \
			and dist < PUNISH_RANGE \
			and _attack_cd <= 0.0:
		_start_attack("punish")
		return

	# 4. Pressure — player idle/passive, attack ready, in preferred range
	if _attack_cd <= 0.0 and dist < _preferred_range and not player_inv:
		_start_attack("pressure")
		return

	# 5. Pace — mid-range
	if dist >= PACE_MIN and dist <= PACE_MAX:
		if _state != "pace":
			_state = "pace"
			_pace_timer = 0.0
		return

	# 6. Approach — far range
	if dist > PACE_MAX:
		if _state != "chase":
			_state = "chase"
		return

	# Too close, attack not ready — back off (handled inside _chase)
	if dist < PACE_MIN and _attack_cd > 0.3:
		if _state != "chase":
			_state = "chase"

# ── Patrol ────────────────────────────────────────────────────────────────────
func _patrol(delta: float) -> void:
	velocity.x = _move_dir * MOVE_SPEED
	# Float back toward spawn height while patrolling
	var ydiff := _start_pos.y - global_position.y
	velocity.y = signf(ydiff) * VERTICAL_SPEED if absf(ydiff) > 4.0 else 0.0
	move_and_slide()

	var dist_from_start := absf(global_position.x - _start_pos.x)
	if dist_from_start >= PATROL_DIST:
		_move_dir  = -_move_dir
		_start_pos = global_position

	var fdir := _facing_dir()
	if _body:
		_body.flip_h = fdir < 0.0
	_set_blade_rest_positions()

	if _player_ref and is_instance_valid(_player_ref):
		if global_position.distance_to(_player_ref.global_position) < CHASE_RANGE:
			_state = "chase"

# ── Chase / Approach ──────────────────────────────────────────────────────────
func _chase(delta: float) -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		_state = "patrol"
		return

	var diff := _player_ref.global_position - global_position
	var hdist := absf(diff.x)

	# Horizontal: approach or back off
	var hdir: float
	if hdist < 42.0:
		hdir = -signf(diff.x)
		if hdir == 0.0:
			hdir = -_move_dir
	else:
		hdir = signf(diff.x)

	# Vertical: track player height
	velocity.x = hdir * MOVE_SPEED
	velocity.y = signf(diff.y) * VERTICAL_SPEED if absf(diff.y) > 4.0 else 0.0
	move_and_slide()
	_move_dir = hdir

	var fdir := _facing_dir()
	if _body:
		_body.flip_h = fdir < 0.0
	_set_blade_rest_positions()

# ── Pacing ────────────────────────────────────────────────────────────────────
func _pace(delta: float) -> void:
	_pace_timer -= delta
	if _pace_timer <= 0.0:
		_choose_pace_action()

	# Vertical drift — gently track player height during pacing
	if _player_ref and is_instance_valid(_player_ref):
		var ydiff := _player_ref.global_position.y - global_position.y
		velocity.y = signf(ydiff) * VERTICAL_SPEED * 0.5 if absf(ydiff) > 6.0 else 0.0
	else:
		velocity.y = 0.0

	match _pace_action:
		"strafe_left":
			velocity.x = -MOVE_SPEED * 0.65
			move_and_slide()
		"strafe_right":
			velocity.x = MOVE_SPEED * 0.65
			move_and_slide()
		"feint":
			move_and_slide()
			velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 8.0 * delta)
		_:  # "idle"
			velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 8.0 * delta)
			move_and_slide()

	var fdir := _facing_dir()
	if _body:
		_body.flip_h = fdir < 0.0
	_set_blade_rest_positions()

func _choose_pace_action() -> void:
	var r := randf()
	if r < 0.30:
		_pace_action = "strafe_left"
		_pace_timer  = randf_range(0.3, 0.65)
	elif r < 0.60:
		_pace_action = "strafe_right"
		_pace_timer  = randf_range(0.3, 0.65)
	elif r < 0.78:
		_pace_action = "feint"
		_pace_timer  = randf_range(0.18, 0.35)
		var fdir := _facing_dir()
		velocity.x = fdir * MOVE_SPEED * 1.8
	else:
		_pace_action = "idle"
		_pace_timer  = randf_range(0.4, 0.85)

# ── Dodge ─────────────────────────────────────────────────────────────────────
func _start_dodge() -> void:
	_state      = "dodge"
	_is_dodging = true
	_dodge_timer = DODGE_DURATION
	_dodge_cd    = DODGE_CD

	# Dash in 2D — away from player
	var away := (global_position - _player_ref.global_position).normalized()
	if away.length_squared() < 0.01:
		away = Vector2(-_move_dir, -1.0).normalized()
	velocity = away * DODGE_SPEED

	_set_blades_modulate(Color(0.4, 0.9, 2.2, 1.0))
	print("[RIVAL] DODGE START — dist=%.0f dir=%s aggr=%.2f" % [
		_player_dist(), away.round(), _aggression])

func _process_dodge(delta: float) -> void:
	_dodge_timer -= delta
	move_and_slide()

	if _dodge_timer <= 0.0:
		_is_dodging = false
		_state      = "chase"
		velocity.x  = 0.0
		_set_blades_modulate(Color.WHITE)

# ── Counter ───────────────────────────────────────────────────────────────────
func _start_counter() -> void:
	_state         = "counter"
	_is_countering = true
	_counter_timer = COUNTER_DURATION
	_counter_cd    = COUNTER_CD
	velocity       = Vector2.ZERO

	_set_blades_modulate(Color(0.1, 1.0, 1.8, 1.0))
	print("[RIVAL] COUNTER START — dist=%.0f chance=%.2f" % [
		_player_dist(), _counter_chance])

func _process_counter(delta: float) -> void:
	_counter_timer -= delta

	var fdir := _facing_dir()
	if _body:
		_body.flip_h = fdir < 0.0
	_set_blade_rest_positions()

	if _counter_timer <= 0.0:
		_is_countering = false
		_state = "chase"
		_set_blades_modulate(Color.WHITE)
		print("[RIVAL] COUNTER EXPIRED — no hit caught")

# ── Stun ──────────────────────────────────────────────────────────────────────
func _process_stun(delta: float) -> void:
	_stun_timer -= delta
	if _stun_timer <= 0.0:
		_state = "chase"
		_set_blades_modulate(Color.WHITE)
		if _body:
			_body.modulate = Color.WHITE

# ── Attack — entry ────────────────────────────────────────────────────────────
func _start_attack(reason: String = "") -> void:
	_state        = "attack"
	_attack_phase = "windup"
	_feint_window_open = true
	velocity = Vector2.ZERO  # Hold position during attack execution
	var data: Dictionary = RIVAL_COMBO[_combo_stage]
	_attack_phase_timer = data["windup"]
	_set_blades_modulate(Color(2.0, 2.0, 3.0, 1.0))
	if reason != "":
		print("[RIVAL] ATTACK START (%s) — combo=%d dist=%.0f feint_chance=%.2f" % [
			reason, _combo_stage, _player_dist(), _feint_chance])

# ── Attack — process ──────────────────────────────────────────────────────────
func _attack_process(delta: float) -> void:
	_attack_phase_timer -= delta
	var data: Dictionary = RIVAL_COMBO[_combo_stage]

	var total: float
	match _attack_phase:
		"windup":   total = data["windup"]
		"active":   total = data["active"]
		"recovery": total = data["recovery"]
		_:          return

	var t  := clampf(1.0 - _attack_phase_timer / total, 0.0, 1.0)
	var et := _ease(t)

	match _attack_phase:
		"windup":
			# ── Per-frame pull-back animation ─────────────────────────────────
			var t_raw := clampf(1.0 - _attack_phase_timer / data["windup"], 0.0, 1.0)
			_update_windup_blades(data, _ease(t_raw))

			# ── Feint check — fires once, at 45% of windup remaining ─────────
			if _feint_window_open \
					and _feint_chance > 0.0 \
					and _attack_phase_timer <= data["windup"] * 0.45:
				_feint_window_open = false
				if randf() < _feint_chance:
					_do_feint()
					return

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
			_position_blades(data)
			if _attack_phase_timer <= 0.0:
				_attack_enter_recovery()

		"recovery":
			# ── Recovery trap — snap to counter if player starts attacking ───
			var blade_state_now := _read_blade_state()
			if not _recovery_punish_checked \
					and _rec_prev_blade_state != WB_WINDUP \
					and blade_state_now == WB_WINDUP:
				_recovery_punish_checked = true
				_mem_punished_recovery += 1
				_adapt_recovery_punish()
				if _recovery_trap_chance > 0.0 and randf() < _recovery_trap_chance:
					_do_recovery_trap()
					return
			_rec_prev_blade_state = blade_state_now

			if _attack_phase_timer <= 0.0:
				_attack_finish()

func _attack_enter_active() -> void:
	_attack_phase = "active"
	var data: Dictionary = RIVAL_COMBO[_combo_stage]
	_attack_phase_timer = data["active"]
	_set_blades_modulate(Color.WHITE)
	_enable_active_hitboxes()

func _attack_enter_recovery() -> void:
	_attack_phase = "recovery"
	var data: Dictionary = RIVAL_COMBO[_combo_stage]
	_attack_phase_timer = data["recovery"]
	_disable_all_hitboxes()
	_rec_prev_blade_state    = _read_blade_state()
	_recovery_punish_checked = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_blade_right, "position", Vector2(_rest_right_x, _REST_Y), data["recovery"])
	tw.tween_property(_blade_left,  "position", Vector2(_rest_left_x,  _REST_Y), data["recovery"])
	tw.tween_property(_blade_right, "rotation_degrees", 0.0, data["recovery"])
	tw.tween_property(_blade_left,  "rotation_degrees", 0.0, data["recovery"])

func _attack_finish() -> void:
	_attack_cd = ATTACK_CD_BASE * _pressure_mod

	if _should_chain():
		_combo_stage = (_combo_stage + 1) % RIVAL_COMBO.size()
		_start_attack("chain")
	else:
		_combo_stage = _choose_combo_start()
		_state = "chase"

func _should_chain() -> bool:
	if not _player_ref or not is_instance_valid(_player_ref):
		return false
	return global_position.distance_to(_player_ref.global_position) < 65.0

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

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 2 — Adaptation behaviors
# ─────────────────────────────────────────────────────────────────────────────

# Called from countered() — player successfully parried our windup
func _adapt_counter_response() -> void:
	_mem_times_countered += 1
	match _mem_times_countered:
		2:
			_feint_chance = 0.35
			print("[RIVAL] ADAPTED: feint unlocked (countered x2) feint_chance=0.35")
		4:
			_feint_chance = 0.65
			print("[RIVAL] ADAPTED: feint aggressive (countered x4) feint_chance=0.65")

# Called from _tick_decision when dodge start is detected
func _observe_dodge_direction() -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	# Read velocity; CharacterBody2D always has this
	var vel = _player_ref.get("velocity")
	var vx: float = 0.0
	if vel != null:
		vx = (vel as Vector2).x
	# Fallback: player facing direction if velocity is near zero at sample time
	if absf(vx) < 10.0:
		var facing = _player_ref.get("is_facing_right")
		vx = 1.0 if facing else -1.0

	if vx > 0:
		_mem_dodge_right += 1
	else:
		_mem_dodge_left += 1

	_adapt_dodge_pattern()

func _adapt_dodge_pattern() -> void:
	var total := _mem_dodge_left + _mem_dodge_right
	if total < 5:
		return
	var right_pct := float(_mem_dodge_right) / float(total)
	var prev_bias := _attack_dir_bias
	if right_pct >= 0.70:
		_attack_dir_bias = 1
	elif right_pct <= 0.30:
		_attack_dir_bias = -1
	else:
		_attack_dir_bias = 0
	if _attack_dir_bias != prev_bias:
		print("[RIVAL] ADAPTED: attack bias=%d (dodge R=%d L=%d)" % [
			_attack_dir_bias, _mem_dodge_right, _mem_dodge_left])

# Called from _attack_process when player attacks during our recovery
func _adapt_recovery_punish() -> void:
	match _mem_punished_recovery:
		2:
			_recovery_trap_chance = 0.30
			print("[RIVAL] ADAPTED: recovery trap armed (punished x2) trap_chance=0.30")
		4:
			_recovery_trap_chance = 0.55
			print("[RIVAL] ADAPTED: recovery trap aggressive (punished x4) trap_chance=0.55")

# Recalculated every 5 seconds — adjusts pressure based on player aggression rate
func _recalculate_pressure() -> void:
	if _mem_fight_elapsed < 5.0:
		return
	var rate := float(_mem_player_attacks) / _mem_fight_elapsed
	var prev_mod := _pressure_mod
	if rate < 0.5:
		# Passive player — press harder
		_pressure_mod = 0.60
	elif rate > 2.0:
		# Aggressive player — increase counter chance
		_counter_chance = minf(_counter_chance + 0.25, 0.95)
		_pressure_mod = 1.0
	else:
		_pressure_mod = 1.0
	if _pressure_mod != prev_mod:
		print("[RIVAL] ADAPTED: pressure_mod=%.2f (atk_rate=%.2f/s)" % [
			_pressure_mod, rate])
	if rate > 2.0:
		print("[RIVAL] ADAPTED: high aggression response — counter_chance=%.2f" % _counter_chance)

# Choose which combo hit starts a fresh (non-chained) sequence
func _choose_combo_start() -> int:
	var total := _mem_dodge_left + _mem_dodge_right
	if total >= 5 and _attack_dir_bias != 0:
		# Bias toward the hit that catches the player's preferred dodge direction
		# Bias +1 (player goes right) → Hit 0 (right slash, sweeps right-to-left)
		# Bias -1 (player goes left) → Hit 1 (left slash, sweeps left-to-right)
		var preferred := 0 if _attack_dir_bias > 0 else 1
		if randf() < 0.70:
			return preferred
	return 0   # Default: start from Hit 0

# ── Feint — abort windup mid-swing ───────────────────────────────────────────
func _do_feint() -> void:
	_disable_all_hitboxes()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_blade_right, "position", Vector2(_rest_right_x, _REST_Y), 0.12)
	tw.tween_property(_blade_left,  "position", Vector2(_rest_left_x,  _REST_Y), 0.12)
	tw.tween_property(_blade_right, "rotation_degrees", 0.0, 0.12)
	tw.tween_property(_blade_left,  "rotation_degrees", 0.0, 0.12)
	print("[RIVAL] FEINT — combo=%d feint_chance=%.2f" % [_combo_stage, _feint_chance])
	# Transition to dodge if possible; dodge sets its own color so don't fight it
	if _dodge_cd <= 0.0:
		_start_dodge()
	else:
		# Yellow flash only when staying in place (pace) — no dodge to clobber it
		_set_blades_modulate(Color(2.2, 2.2, 0.3, 1.0))
		tw.tween_callback(_set_blades_modulate.bind(Color.WHITE)).set_delay(0.18)
		_state = "pace"
		_pace_timer = 0.0

# ── Recovery trap — snap from recovery into counter ───────────────────────────
func _do_recovery_trap() -> void:
	_disable_all_hitboxes()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_blade_right, "position", Vector2(_rest_right_x, _REST_Y), 0.08)
	tw.tween_property(_blade_left,  "position", Vector2(_rest_left_x,  _REST_Y), 0.08)
	_start_counter()
	print("[RIVAL] RECOVERY TRAP — snapped to counter (trap_chance=%.2f)" % _recovery_trap_chance)

# ── Blade visual helpers ──────────────────────────────────────────────────────
func _set_blades_modulate(c: Color) -> void:
	if _blade_right:
		_blade_right.modulate = c
	if _blade_left:
		_blade_left.modulate = c

func _set_blade_rest_positions() -> void:
	var fdir     := _facing_dir()
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

func _position_blades(data: Dictionary) -> void:
	var fdir := _facing_dir()

	if data["r_start"] != data["r_end"]:
		var rad := deg_to_rad(_r_angle)
		var ox  := cos(rad) * absf(data.get("r_radius", 20.0))
		var oy  := sin(rad) * absf(data.get("r_radius", 20.0))
		if fdir < 0.0: ox = -ox
		if _blade_right:
			_blade_right.position = Vector2(ox, _REST_Y + oy)
			_blade_right.rotation_degrees = (90.0 + _r_angle) * fdir
	else:
		if _blade_right:
			_blade_right.position = Vector2(_rest_right_x, _REST_Y)
			_blade_right.rotation_degrees = 0.0

	if data["l_start"] != data["l_end"]:
		var rad := deg_to_rad(_l_angle)
		var ox  := cos(rad) * absf(data.get("l_radius", 20.0))
		var oy  := sin(rad) * absf(data.get("l_radius", 20.0))
		if fdir < 0.0: ox = -ox
		if _blade_left:
			_blade_left.position = Vector2(ox, _REST_Y + oy)
			_blade_left.rotation_degrees = (90.0 + _l_angle) * fdir
	else:
		if _blade_left:
			_blade_left.position = Vector2(_rest_left_x, _REST_Y)
			_blade_left.rotation_degrees = 0.0

func _update_windup_blades(data: Dictionary, t: float) -> void:
	var fdir := _facing_dir()

	if data.get("r_wfrac", 0.0) > 0.0:
		var r_rad: float = float(data["r_start"])
		var rad := deg_to_rad(r_rad)
		var r_radius: float = float(data.get("r_radius", 20.0))
		var ox: float = cos(rad) * r_radius
		var oy: float = sin(rad) * r_radius
		if fdir < 0.0: ox = -ox
		if _blade_right:
			_blade_right.position = Vector2(_rest_right_x, _REST_Y).lerp(
				Vector2(ox, _REST_Y + oy), t)
			_blade_right.rotation_degrees = lerpf(0.0, (90.0 + r_rad) * fdir, t)
	else:
		if _blade_right:
			_blade_right.position = Vector2(_rest_right_x, _REST_Y)
			_blade_right.rotation_degrees = 0.0

	if data.get("l_wfrac", 0.0) > 0.0:
		var l_rad: float = float(data["l_start"])
		var rad := deg_to_rad(l_rad)
		var l_radius: float = float(data.get("l_radius", 20.0))
		var ox: float = cos(rad) * l_radius
		var oy: float = sin(rad) * l_radius
		if fdir < 0.0: ox = -ox
		if _blade_left:
			_blade_left.position = Vector2(_rest_left_x, _REST_Y).lerp(
				Vector2(ox, _REST_Y + oy), t)
			_blade_left.rotation_degrees = lerpf(0.0, (90.0 + l_rad) * fdir, t)
	else:
		if _blade_left:
			_blade_left.position = Vector2(_rest_left_x, _REST_Y)
			_blade_left.rotation_degrees = 0.0

func _facing_dir() -> float:
	if _player_ref and is_instance_valid(_player_ref):
		return signf(_player_ref.global_position.x - global_position.x)
	return _move_dir

func _ease(t: float) -> float:
	if t < 0.5:
		return 2.0 * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0

# ── Player state readers ──────────────────────────────────────────────────────
func _player_dist() -> float:
	if not _player_ref or not is_instance_valid(_player_ref):
		return INF
	return global_position.distance_to(_player_ref.global_position)

func _get_wretched_blade() -> Node:
	if not _player_ref or not is_instance_valid(_player_ref):
		return null
	return _player_ref.get_node_or_null("WretchedBlade")

func _read_blade_state() -> int:
	var wb := _get_wretched_blade()
	if not wb:
		return WB_IDLE
	var s = wb.get("current_state")
	return s if s != null else WB_IDLE

func _read_player_dodging() -> bool:
	if not _player_ref or not is_instance_valid(_player_ref):
		return false
	return _player_ref.get("is_dodging") == true

func _read_player_invincible() -> bool:
	if not _player_ref or not is_instance_valid(_player_ref):
		return false
	return (_player_ref.get("is_dodging") == true) or (_player_ref.get("is_invincible") == true)

# ── Combat interface ──────────────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		print("[RIVAL] PREDELETE — was_alive=%s hp=%d pos=%s state=%s" % [
			_is_alive, current_health, global_position.round(), _state])

func is_counterable() -> bool:
	return _is_alive and _state == "attack" and _attack_phase == "windup"

func countered() -> void:
	if not _is_alive:
		return
	_state = "stun"
	_combo_stage = 0
	_disable_all_hitboxes()
	_is_dodging    = false
	_is_countering = false
	_stun_timer = 1.0
	_set_blades_modulate(Color(1.0, 0.8, 1.0, 1.0))
	if _body:
		_body.modulate = Color(1.0, 0.8, 1.0, 1.0)
	# Layer 2 — record counter event, adapt
	_adapt_counter_response()

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not _is_alive:
		return

	# Counter deflect — we're in parry pose, absorb the hit and riposte
	if _is_countering:
		_is_countering = false
		_counter_timer = 0.0
		_state = "chase"
		_set_blades_modulate(Color(0.0, 1.6, 3.0, 1.0))
		var flash := create_tween()
		flash.tween_callback(_set_blades_modulate.bind(Color.WHITE)).set_delay(0.22)
		if _player_ref and is_instance_valid(_player_ref) and _player_ref.has_method("take_damage"):
			_player_ref.take_damage(COUNTER_RIPOSTE_DAMAGE)
		print("[RIVAL] COUNTER DEFLECT — riposted %d to player" % COUNTER_RIPOSTE_DAMAGE)
		return

	# Normal damage
	current_health -= amount
	if _state == "attack":
		_state = "chase"
		_combo_stage = 0
		_disable_all_hitboxes()
	elif _state == "counter":
		_is_countering = false

	if current_health > 0:
		_stagger_timer = 0.10
		_set_blades_modulate(Color(1.0, 0.6, 0.7, 1.0))
		var t := create_tween()
		t.tween_callback(_set_blades_modulate.bind(Color.WHITE)).set_delay(0.15)
		if knockback != Vector2.ZERO:
			velocity = Vector2(knockback.x, 0.0)
			move_and_slide()
		return

	# Death
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
	# I-frames during dodge — Rival is untouchable mid-dash
	if _is_dodging:
		return
	if body.is_in_group("player") and _is_alive:
		# Use the current combo hit's damage value — cross slash hits harder than singles
		var dmg: int = RIVAL_COMBO[_combo_stage]["damage"]
		body.take_damage(dmg)
