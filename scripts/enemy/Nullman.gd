extends CharacterBody2D
# Nullman.gd — nullstone shard enemy.
#
# A jagged fragment of corrupted terrain possessed by an echo of the Cataclysm.
# Patrols aimlessly until the Wretched (player) enters detection range (~80px).
# Winds up with a visible telegraph (glow + growth) then pulses radial damage.
# Counterable during the windup. Damage only from the pulse — no contact damage.

signal enemy_died(position: Vector2, essence_value: int)

const MOVE_SPEED := 80.0
const PATROL_RANGE := 120.0
const IDLE_TIME := 0.8
const WINDUP_DURATION := 0.6
const WINDUP_RANGE := 80.0
const PULSE_RADIUS := 60.0
const PULSE_DAMAGE := 10
const MAX_HEALTH := 60
const ESSENCE_DROP := 10
const TELEGRAPH_SCALE := 1.15
const PULSE_VISUAL_DURATION := 0.35

var _start_pos: Vector2
var _direction := 1.0
var _idle_timer := 0.0
var _is_idle := false
var _is_alive := true
var _is_winding_up := false
var _windup_timer := 0.0
var _is_stunned := false
var _stun_timer := 0.0
var current_health := MAX_HEALTH
var _stagger_timer := 0.0
var _base_scale := Vector2.ONE

var sprite: Sprite2D  # Set by WorldGenerator after creation

func _ready() -> void:
	_start_pos = global_position
	_direction = 1.0 if randf() > 0.5 else -1.0
	if sprite:
		_base_scale = sprite.scale
	add_to_group("enemy")
	add_to_group("nullman")

func _physics_process(delta: float) -> void:
	if not _is_alive or not GameManager.is_playing():
		return

	# ── Stagger ────────────────────────────────────────────────────────────────
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if sprite:
			sprite.position = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		if _stagger_timer <= 0.0 and _is_alive and sprite:
			sprite.position = Vector2.ZERO
			sprite.modulate = Color.WHITE
		return

	# ── Stun (countered) ──────────────────────────────────────────────────────
	if _is_stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_is_stunned = false
			if sprite:
				sprite.modulate = Color.WHITE
		return

	# ── Windup telegraph ──────────────────────────────────────────────────────
	if _is_winding_up:
		_windup_timer -= delta
		var wp := 1.0 - (_windup_timer / WINDUP_DURATION)  # 0→1
		if sprite:
			sprite.modulate = Color.WHITE.lerp(Color(1.5, 1.5, 2.0, 1.0), wp)
			sprite.scale = _base_scale.lerp(_base_scale * TELEGRAPH_SCALE, wp)
		if _windup_timer <= 0.0:
			_is_winding_up = false
			if sprite:
				sprite.modulate = Color.WHITE
				sprite.scale = _base_scale
			_emit_pulse_visual()
			# Pulse damage
			for p in get_tree().get_nodes_in_group("player"):
				if global_position.distance_to(p.global_position) <= PULSE_RADIUS:
					if p.has_method("take_damage"):
						print("[DAMAGE] Nullman pulse hitting player at distance ", global_position.distance_to(p.global_position))
						p.take_damage(PULSE_DAMAGE)
		return

	# ── Proximity detection ───────────────────────────────────────────────────
	var player := get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) <= WINDUP_RANGE:
		_is_winding_up = true
		_windup_timer = WINDUP_DURATION
		return

	# ── Idle ──────────────────────────────────────────────────────────────────
	if _is_idle:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_is_idle = false
			_direction = 1.0 if randf() > 0.5 else -1.0
		return

	# ── Patrol ────────────────────────────────────────────────────────────────
	velocity.x = _direction * MOVE_SPEED

	var dist_from_start := global_position.x - _start_pos.x
	if abs(dist_from_start) >= PATROL_RANGE:
		_direction = -_direction
		_start_pos = global_position

	move_and_slide()

	if sprite:
		sprite.position.y = sin(Time.get_ticks_msec() * 0.01) * 2.0
		sprite.flip_h = _direction < 0

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not _is_alive:
		print("[NULLMAN] take_damage(%d) ignored — already dead. pos=%s" % [amount, global_position.round()])
		return
	current_health -= amount
	_is_winding_up = false
	print("[NULLMAN] take_damage(%d) hp=%d pos=%s" % [amount, current_health, global_position.round()])

	if current_health > 0:
		_stagger_timer = 0.15
		if sprite:
			sprite.modulate = Color(0.3, 0.3, 0.3, 1.0)
		if knockback != Vector2.ZERO:
			velocity = knockback
			move_and_slide()
		return

	# Death
	print("[NULLMAN] DEATH — sprite_valid=%s pos=%s" % [sprite != null, global_position.round()])
	_is_alive = false
	set_physics_process(false)

	if knockback != Vector2.ZERO:
		velocity = knockback
		move_and_slide()

	if sprite:
		var t := create_tween()
		t.tween_property(sprite, "modulate:a", 0.0, 0.3)
		t.tween_callback(queue_free)
	else:
		print("[NULLMAN] sprite is null at death — freeing immediately")
		queue_free()

	emit_signal("enemy_died", global_position, ESSENCE_DROP)
	EssenceManager.gain_essence(ESSENCE_DROP)
	print("[NULLMAN] essence gained (%d)" % ESSENCE_DROP)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		print("[NULLMAN] PREDELETE — was_alive=%s hp=%d pos=%s" % [_is_alive, current_health, global_position.round()])

func is_counterable() -> bool:
	return _is_alive and _is_winding_up

func countered() -> void:
	if not _is_alive:
		return
	_is_winding_up = false
	_is_stunned = true
	_stun_timer = 1.0
	if sprite:
		sprite.modulate = Color(1.0, 0.8, 1.0, 1.0)
		sprite.scale = _base_scale

func _emit_pulse_visual() -> void:
	var tex_radius := 24
	var tex := PixelRenderer.generate_glow_texture(tex_radius)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.modulate = Color(0.9, 0.2, 1.0, 0.8)
	spr.centered = true
	spr.z_index = 10
	add_child(spr)
	spr.scale = Vector2.ZERO
	var final_scale := PULSE_RADIUS / float(tex_radius)
	var t := create_tween()
	# tween_property and parallel().tween_property run simultaneously.
	# The callback is chained AFTER both finish — not set_parallel, which would
	# fire queue_free at t=0 and destroy the sprite before it ever displayed.
	t.tween_property(spr, "scale", Vector2(final_scale, final_scale), PULSE_VISUAL_DURATION)
	t.parallel().tween_property(spr, "modulate:a", 0.0, PULSE_VISUAL_DURATION)
	t.tween_callback(spr.queue_free)
