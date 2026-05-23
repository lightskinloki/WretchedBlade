extends Node2D
# WretchedBlade.gd — the player's TRUE SELF.
#
# This is not just a weapon. This IS the player's consciousness.
# Key design rule: the blade's visual state = the player's health.
# As health falls, the sprite becomes chipped, rusted, cracked, and glowing.
# At 0 health the blade shatters — that is "death".

# ── Signals ───────────────────────────────────────────────────────────────────
signal blade_shattered
signal health_changed(new_pct: float)
signal form_changed(new_form: int)
signal hit_connected

# ── Node references ───────────────────────────────────────────────────────────
@onready var blade_sprite:  Sprite2D    = $BladeSprite
@onready var attack_hitbox: Area2D      = $AttackHitbox

# ── Attack State Machine ──────────────────────────────────────────────────────
enum AttackState { IDLE, WINDUP, ACTIVE, RECOVERY }

var current_state := AttackState.IDLE
var state_timer   := 0.0

# Each attack: windup, active (hitbox on), recovery durations in seconds.
# arc_start/end in degrees (0=right, 90=down, 180=left, -90/270=up).
# windup_frac = fraction of arc covered during windup (0=static, 0.15=slight, 0.4=big pull-back).
# motion = "ARC" (orbital sweep) or "THRUST" (linear extension).
const ATTACK_DATA := [
	# Hit 1 — Horizontal Slash
	{
		"windup":       0.08,
		"active":       0.10,
		"recovery":     0.14,
		"damage":       15,
		"kb":           Vector2(220, -80),
		"arc_start":    150.0,
		"arc_end":       20.0,
		"radius":       28.0,
		"windup_frac":  0.15,
		"motion":       "ARC",
	},
	# Hit 2 — Rising Uppercut
	{
		"windup":       0.10,
		"active":       0.12,
		"recovery":     0.16,
		"damage":       18,
		"kb":           Vector2(160, -220),
		"arc_start":     30.0,
		"arc_end":     -110.0,
		"radius":       30.0,
		"windup_frac":  0.00,
		"motion":       "ARC",
	},
	# Hit 3 — Thrust
	{
		"windup":       0.16,
		"active":       0.14,
		"recovery":     0.20,
		"damage":       28,
		"kb":           Vector2(400, 0),
		"motion":       "THRUST",
		"thrust_range": 48.0,
	},
]

# ── Configuration ─────────────────────────────────────────────────────────────
@export var current_form: PixelRenderer.WeaponForm = PixelRenderer.WeaponForm.EXECUTIONER
const MAX_HEALTH := 100

# ── State ─────────────────────────────────────────────────────────────────────
var current_health := MAX_HEALTH
var health_pct     := 1.0
var current_combo  := 0       # Next combo stage to fire
var _playing_combo := 0      # Combo stage currently being animated
var combo_timer    := 0.0
var _attack_buffered := false

# Orbital blade tracking
var _arc_current   := 0.0

# Rest position offsets (x depends on facing, y is constant)
const REST_X_RIGHT := -16.0
const REST_X_LEFT  :=  16.0
const REST_Y       := -20.0

func _ready() -> void:
	_refresh_blade_sprite()
	attack_hitbox.monitoring = false
	attack_hitbox.collision_mask = 2 | 1  # Detect enemies (layer 2) + destructible geometry (layer 1)
	attack_hitbox.body_entered.connect(_on_hit_body)

	# Temp: red overlay to visualise hitbox position/orientation
	var dbg := ColorRect.new()
	dbg.size = Vector2(8, 28)
	dbg.color = Color(1, 0, 0, 0.4)
	dbg.position = Vector2(-4, -14)  # Centre on AttackHitbox origin
	attack_hitbox.add_child(dbg)

	_set_rest_position()

func _physics_process(delta: float) -> void:
	if current_state != AttackState.IDLE:
		_update_attack_state(delta)
	else:
		_set_rest_position()

	# Combo reset timer
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			current_combo = 0

func _set_rest_position() -> void:
	var parent := get_parent()
	if parent:
		var right: bool = parent.get("is_facing_right")
		position = Vector2(REST_X_RIGHT if right else REST_X_LEFT, REST_Y)
		rotation_degrees = 0.0
		blade_sprite.rotation_degrees = 0.0
		blade_sprite.flip_h = not right

func _update_attack_state(delta: float) -> void:
	state_timer -= delta
	if state_timer > 0.0:
		_update_orbital_blade(delta)
		return

	match current_state:
		AttackState.WINDUP:
			_enter_active()
		AttackState.ACTIVE:
			_enter_recovery()
		AttackState.RECOVERY:
			_enter_idle()

func _enter_active() -> void:
	current_state = AttackState.ACTIVE
	var data: Dictionary = ATTACK_DATA[_playing_combo % ATTACK_DATA.size()]
	state_timer = data["active"]
	attack_hitbox.monitoring = true

	# Blade flash
	var flash := create_tween()
	flash.tween_property(blade_sprite, "modulate", Color(2.2, 2.2, 2.2, 1.0), 0.03)
	flash.tween_property(blade_sprite, "modulate", Color.WHITE, 0.10)

	# Camera shake
	var cam: Camera2D = get_tree().get_first_node_in_group("camera")
	if cam:
		_shake(cam, 2.5, 0.10)

func _enter_recovery() -> void:
	current_state = AttackState.RECOVERY
	var data: Dictionary = ATTACK_DATA[_playing_combo % ATTACK_DATA.size()]
	state_timer = data["recovery"]
	attack_hitbox.monitoring = false

func _enter_idle() -> void:
	current_state = AttackState.IDLE
	if _attack_buffered:
		_attack_buffered = false
		_fire_attack(current_combo)
		current_combo = (current_combo + 1) % ATTACK_DATA.size()
		return
	rotation_degrees = 0.0

# Called by Player.gd when dodge starts.
# Returns true if the attack was canceled, false if too late.
func try_dodge_cancel() -> bool:
	match current_state:
		AttackState.WINDUP, AttackState.RECOVERY:
			current_state = AttackState.IDLE
			state_timer = 0.0
			attack_hitbox.monitoring = false
			rotation_degrees = 0.0
			_attack_buffered = false
			current_combo = 0
			return true
		AttackState.ACTIVE:
			return false
	return false

func _update_orbital_blade(delta: float) -> void:
	var data: Dictionary = ATTACK_DATA[_playing_combo % ATTACK_DATA.size()]
	var motion: String = data.get("motion", "ARC")
	if motion == "THRUST":
		_update_thrust(delta, data)
	else:
		_update_arc(delta, data)

func _update_arc(delta: float, data: Dictionary) -> void:
	var start_angle: float = data["arc_start"]
	var end_angle: float   = data["arc_end"]
	var radius: float      = data["radius"]
	var windup_frac: float = data.get("windup_frac", 0.15)

	var total_phase_time: float
	match current_state:
		AttackState.WINDUP:   total_phase_time = data["windup"]
		AttackState.ACTIVE:   total_phase_time = data["active"]
		AttackState.RECOVERY: total_phase_time = data["recovery"]
		_: return

	var elapsed = total_phase_time - state_timer
	var t = clampf(elapsed / total_phase_time, 0.0, 1.0)
	t = _ease_out_in(t)

	if current_state == AttackState.WINDUP:
		_arc_current = lerp(start_angle, start_angle + (end_angle - start_angle) * windup_frac, t)
	elif current_state == AttackState.ACTIVE:
		_arc_current = lerp(start_angle + (end_angle - start_angle) * windup_frac, end_angle, t)
	else:
		_arc_current = lerp(end_angle, 0.0, t)

	var parent := get_parent()
	var facing_right: bool = parent.get("is_facing_right")
	var rest_x: float = REST_X_RIGHT if facing_right else REST_X_LEFT
	var rest_y: float = REST_Y

	var rad = deg_to_rad(_arc_current)
	var offset_x := cos(rad) * radius
	var offset_y := sin(rad) * radius

	if not facing_right:
		offset_x = -offset_x

	position.x = rest_x + offset_x
	position.y = rest_y + offset_y
	blade_sprite.rotation_degrees = 0.0

	# Rotate blade so its tip always points outward along the arc radius.
	# The blade edge faces the direction of motion — a natural cutting swing.
	var facing_sign := 1.0 if facing_right else -1.0
	if current_state == AttackState.WINDUP or current_state == AttackState.ACTIVE:
		rotation_degrees = (90.0 + _arc_current) * facing_sign
	else:  # RECOVERY — smoothly return blade to rest orientation
		rotation_degrees = lerpf((90.0 + end_angle) * facing_sign, 0.0, t)

func _update_thrust(delta: float, data: Dictionary) -> void:
	var parent := get_parent()
	var facing_right: bool = parent.get("is_facing_right")
	var rest_x: float = REST_X_RIGHT if facing_right else REST_X_LEFT
	var rest_y: float = REST_Y
	var dir := 1.0 if facing_right else -1.0
	var thrust_range: float = data.get("thrust_range", 40.0)

	var total_phase: float
	match current_state:
		AttackState.WINDUP:   total_phase = data["windup"]
		AttackState.ACTIVE:   total_phase = data["active"]
		AttackState.RECOVERY: total_phase = data["recovery"]
		_: return

	var elapsed = total_phase - state_timer
	var t = clampf(elapsed / total_phase, 0.0, 1.0)

	# Rotate the whole node so the hitbox follows the blade orientation
	blade_sprite.flip_h = false

	match current_state:
		AttackState.WINDUP:
			rotation_degrees = lerpf(0.0, 90.0, _ease_out_in(t)) * dir
			position = Vector2(rest_x, rest_y)
		AttackState.ACTIVE:
			rotation_degrees = 90.0 * dir
			position.x = rest_x + dir * _ease_out_in(t) * thrust_range
			position.y = rest_y
		AttackState.RECOVERY:
			rotation_degrees = lerpf(90.0, 0.0, _ease_out_in(t)) * dir
			position.x = rest_x + dir * (1.0 - _ease_out_in(t)) * thrust_range
			position.y = rest_y

func _ease_out_in(t: float) -> float:
	if t < 0.5:
		return 2.0 * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0

# ── Attacking ─────────────────────────────────────────────────────────────────
func perform_attack() -> void:
	combo_timer = 0.55
	if current_state != AttackState.IDLE:
		_attack_buffered = true
		return
	_fire_attack(current_combo)
	current_combo = (current_combo + 1) % ATTACK_DATA.size()

func _fire_attack(combo_idx: int) -> void:
	_playing_combo = combo_idx
	current_state = AttackState.WINDUP
	var data: Dictionary = ATTACK_DATA[combo_idx]
	state_timer = data["windup"]
	if data.get("motion", "ARC") == "ARC":
		_arc_current = data["arc_start"]

	# Auto-lunge toward nearest enemy
	_lunge_to_enemy()

func _lunge_to_enemy() -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")
	if enemies.is_empty():
		return
	var nearest: Node2D
	var nearest_dist := 9999.0
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var d := global_position.distance_to(enemy.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = enemy
	if nearest and nearest_dist < 180.0:
		var parent := get_parent()
		if parent and parent.has_method("lunge"):
			var dir := 1.0 if nearest.global_position.x > global_position.x else -1.0
			parent.lunge(dir)

func _on_hit_body(body: Node) -> void:
	if body == get_parent():
		return
	if body.has_method("take_damage"):
		var data: Dictionary = ATTACK_DATA[_playing_combo]
		var dir := 1.0 if get_parent().is_facing_right else -1.0
		body.take_damage(data["damage"], data["kb"] * Vector2(dir, 1.0))
		# Hitstop — freeze frame on impact (60ms real-time)
		GameManager.trigger_hitstop(60)
		hit_connected.emit()

# ── Counter attack ────────────────────────────────────────────────────────────
func perform_counter() -> void:
	if current_state != AttackState.IDLE:
		return
	# Scan enemies in range for one in windup state
	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_counterable") and enemy.is_counterable():
			var dist := global_position.distance_to(enemy.global_position)
			if dist > 150.0:
				continue  # Too far
			# Successful counter — interrupt and stun
			if enemy.has_method("countered"):
				enemy.countered()
			# Deal counter damage
			if enemy.has_method("take_damage"):
				enemy.take_damage(12)
			# Visual feedback
			var flash := create_tween()
			flash.tween_property(blade_sprite, "modulate", Color(1.5, 1.5, 2.5, 1.0), 0.03)
			flash.tween_property(blade_sprite, "modulate", Color.WHITE, 0.12)
			# Hitstop
			GameManager.trigger_hitstop(60)
			return

# ── Weapon transmutation ──────────────────────────────────────────────────────
func transmute(new_form: PixelRenderer.WeaponForm) -> void:
	current_form = new_form
	emit_signal("form_changed", new_form)
	_refresh_blade_sprite()
	_play_transmutation_flash()

# ── Visual updates ────────────────────────────────────────────────────────────
func _refresh_blade_sprite() -> void:
	blade_sprite.texture = PixelRenderer.generate_blade_texture(current_form, health_pct)
	blade_sprite.scale   = Vector2(1.25, 1.25)

func _play_transmutation_flash() -> void:
	var t := create_tween()
	t.tween_property(blade_sprite, "scale", Vector2(5.0, 5.0), 0.12)
	t.tween_property(blade_sprite, "scale", Vector2(3.5, 3.5), 0.20)

# ── Damage & healing ──────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)
	health_pct     = float(current_health) / float(MAX_HEALTH)
	emit_signal("health_changed", health_pct)
	_refresh_blade_sprite()

	var cam: Camera2D = get_tree().get_first_node_in_group("camera")
	if cam:
		_shake(cam, 6.0, 0.18)

	if current_health <= 0:
		_shatter()

func heal(amount: int) -> void:
	current_health = min(MAX_HEALTH, current_health + amount)
	health_pct     = float(current_health) / float(MAX_HEALTH)
	emit_signal("health_changed", health_pct)
	_refresh_blade_sprite()

func restore_full() -> void:
	current_health = MAX_HEALTH
	health_pct     = 1.0
	emit_signal("health_changed", 1.0)
	_refresh_blade_sprite()

# ── Death — the blade shatters ────────────────────────────────────────────────
const C_BLADE_BODY := Color(0.70, 0.80, 0.90, 1.0)
const C_CRACK_GLOW := Color(0.80, 0.20, 1.00, 1.0)

func _shatter() -> void:
	blade_sprite.visible = false
	_spawn_shard_particles()
	emit_signal("blade_shattered")
	GameManager.on_player_died(global_position)

func _spawn_shard_particles() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if not world:
		return

	for i in range(24):
		var shard := ColorRect.new()
		shard.size          = Vector2(randf_range(2, 4), randf_range(4, 12))
		shard.rotation      = randf() * TAU
		shard.color         = C_BLADE_BODY if randf() > 0.35 else C_CRACK_GLOW
		shard.global_position = global_position
		world.add_child(shard)

		var vel := Vector2(randf_range(-260, 260), randf_range(-480, -60))
		var tween := create_tween()
		tween.tween_property(shard, "global_position", shard.global_position + vel * 0.6, 0.55)
		tween.parallel().tween_property(shard, "modulate:a", 0.0, 0.55)
		tween.tween_callback(shard.queue_free)

# ── Screen shake helper ───────────────────────────────────────────────────────
func _shake(cam: Camera2D, strength: float, duration: float) -> void:
	var orig := cam.offset
	var t    := create_tween()
	for _i in range(8):
		t.tween_property(cam, "offset",
			orig + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
			duration / 8.0)
	t.tween_property(cam, "offset", orig, 0.06)
