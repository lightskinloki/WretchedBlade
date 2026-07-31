extends CharacterBody2D
class_name BossEnemy
# BossEnemy.gd — generated dungeon boss (a Nullman warped by a Hexocaust).
#
# Consumes a BossBlueprint and runs:
#   _phase_controller   — HP thresholds → phase transitions
#   _pattern_controller — picks/executes abilities from the current phase set
#   _movement_ai        — per-body-type locomotion between attacks
#   projectiles/hazards — data-driven, updated in _physics_process
#
# Integration contract (matches Nullman/RivalBlade):
#   take_damage(amount, knockback) / is_counterable() / countered()
#   emits enemy_died(position, essence) — and boss-specific signals below.

signal enemy_died(position: Vector2, essence_value: int)
signal boss_defeated
signal phase_changed(phase: int)
signal health_changed(hp: int, max_hp: int)

const LAYER_GEOMETRY := 1
const LAYER_ENEMY := 2
const LAYER_PLAYER := 4

const GRAVITY := 980.0
const COUNTER_STUN := 1.5
const PHASE_SPEED_BONUS := 0.10
const CONTACT_NONE := 0  # bosses deal damage only through abilities

var blueprint: BossBlueprint
var current_hp: int
var phase := 1
var is_boss_defeated := false

var sprite: Sprite2D

# Ability state machine
enum AState { IDLE, WINDUP, ACTIVE, RECOVERY, STUNNED, PHASE_SHIFT }
var _astate: int = AState.IDLE
var _current_ability: String = ""
var _state_timer := 0.0
var _cooldowns: Dictionary = {}        # ability_id → seconds remaining
var _stun_timer := 0.0
var _invuln_timer := 0.0
var _hit_index := 0                    # multi-hit melee progress
var _hit_timer := 0.0
var _pending_hits := 0

# Buffs
var _speed_mult := 1.0
var _damage_mult := 1.0
var _buff_timer := 0.0
var _active_buff := ""
var _next_attack_mult := 1.0
var _shielded := false
var _intangible := false

# Posture (Poise) & Hex Barrier Systems
var max_posture: float = 100.0
var current_posture: float = 100.0
var posture_regen_timer: float = 0.0
var hex_barrier_active: bool = false
var _barrier_sprite: Sprite2D = null

# Charge/leap motion
var _charge_dir := 1.0
var _leap_target := Vector2.ZERO
var _leap_start := Vector2.ZERO
var _leap_t := 0.0

# Tracked transient objects (data-driven, no per-object scripts)
var _projectiles: Array = []   # {node, vel, style, damage, lifetime, aoe}
var _hazards: Array = []       # {node, style, pos, damage, timer, radius}
var _delayed_aoes: Array = []  # {node, pos, timer, damage, radius}
var _beam: Dictionary = {}     # {node, timer, damage, dir}

var _rng := RandomNumberGenerator.new()
var _move_ai: int
var _think_timer := 0.0
var _facing := 1.0

# ── Spawning ──────────────────────────────────────────────────────────────────
static func spawn_for_dungeon(bp: BossBlueprint, spawn_position: Vector2) -> BossEnemy:
	var boss := BossEnemy.new()
	boss.blueprint = bp
	boss.position = spawn_position
	boss.collision_layer = LAYER_ENEMY
	boss.collision_mask = LAYER_GEOMETRY | LAYER_PLAYER
	return boss

func _ready() -> void:
	if blueprint == null:
		push_error("BossEnemy: no blueprint — freeing")
		queue_free()
		return

	current_hp = blueprint.max_hp
	_damage_mult = lerpf(0.8, 1.4, blueprint.difficulty)

	# Posture threshold derived from body stagger resistance + difficulty scaling
	var stagger_res := blueprint.stagger_resistance
	max_posture = (60.0 + stagger_res * 100.0) * lerpf(0.8, 1.5, blueprint.difficulty)
	current_posture = max_posture

	_rng.seed = blueprint.seed_val
	_move_ai = BossBodyTypes.get_data(blueprint.body_type)["move_ai"]

	# Wraiths ignore terrain entirely
	if blueprint.body_type == BossBodyTypes.BodyType.WRAITH:
		collision_mask = LAYER_PLAYER

	# Hitbox
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = blueprint.hitbox_size
	cs.shape = rect
	add_child(cs)

	# Sprite
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = PixelRenderer.generate_boss_texture(blueprint, 1)
	sprite.scale = Vector2.ONE * blueprint.sprite_scale
	sprite.centered = true
	add_child(sprite)

	add_to_group("enemy")
	add_to_group("boss")
	emit_signal("health_changed", current_hp, blueprint.max_hp)

# ── Main loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if is_boss_defeated or not GameManager.is_playing():
		return

	_update_timers(delta)
	_update_projectiles(delta)
	_update_hazards(delta)
	_update_delayed_aoes(delta)
	_update_beam(delta)

	if _stun_timer > 0.0:
		_stun_timer -= delta
		if sprite:
			sprite.modulate = Color(1.4, 1.4, 0.6, 1.0)
		if _stun_timer <= 0.0 and sprite:
			sprite.modulate = Color.WHITE
		_apply_gravity(delta)
		move_and_slide()
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		_apply_gravity(delta)
		move_and_slide()
		return

	_facing = 1.0 if player.global_position.x > global_position.x else -1.0
	if sprite:
		sprite.flip_h = _facing < 0

	match _astate:
		AState.IDLE:
			_movement_ai(player, delta)
			_pattern_controller(player, delta)
		AState.WINDUP:
			_tick_windup(player, delta)
		AState.ACTIVE:
			_tick_active(player, delta)
		AState.RECOVERY:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_astate = AState.IDLE
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		AState.PHASE_SHIFT:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_finish_phase_shift()

	_apply_gravity(delta)
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if _move_ai == BossBodyTypes.MoveAI.DRIFTER:
		return  # wraiths float
	if _astate == AState.ACTIVE and _current_ability != "" :
		var def := BossAbilities.get_def(_current_ability)
		if not def.is_empty() and int(def["cat"]) == BossAbilities.Cat.LEAP:
			return  # leap manages its own arc
	if not is_on_floor():
		velocity.y += GRAVITY * delta

func _update_timers(delta: float) -> void:
	for id in _cooldowns:
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_end_buff()

	if posture_regen_timer > 0.0:
		posture_regen_timer -= delta
	else:
		current_posture = minf(max_posture, current_posture + max_posture * 0.25 * delta)

# ── Movement AI ───────────────────────────────────────────────────────────────
func _movement_ai(player: Node2D, delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	var dx := player.global_position.x - global_position.x
	var spd := blueprint.move_speed * _speed_mult * (1.0 + PHASE_SPEED_BONUS * (phase - 1))

	match _move_ai:
		BossBodyTypes.MoveAI.WALKER, BossBodyTypes.MoveAI.ADVANCER:
			if dist > 60.0:
				velocity.x = signf(dx) * spd
			else:
				velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		BossBodyTypes.MoveAI.PACER:
			_think_timer -= delta
			if _think_timer <= 0.0:
				_think_timer = _rng.randf_range(0.6, 1.4)
			if dist > 120.0:
				velocity.x = signf(dx) * spd
			elif dist < 50.0:
				velocity.x = -signf(dx) * spd * 0.7
			else:
				velocity.x = signf(dx) * spd * 0.3 * (1.0 if fmod(_think_timer, 0.8) > 0.4 else -1.0)
		BossBodyTypes.MoveAI.ERRATIC:
			_think_timer -= delta
			if _think_timer <= 0.0:
				_think_timer = _rng.randf_range(0.3, 0.8)
				_charge_dir = signf(dx) if _rng.randf() < 0.7 else -signf(dx)
			velocity.x = _charge_dir * spd
		BossBodyTypes.MoveAI.ROOTED:
			velocity.x = 0.0
		BossBodyTypes.MoveAI.TELEPORTER:
			if dist > 90.0:
				velocity.x = signf(dx) * spd * 0.6
			else:
				velocity.x = 0.0
		BossBodyTypes.MoveAI.DRIFTER:
			var dir := (player.global_position - global_position).normalized()
			velocity = dir * spd if dist > 50.0 else velocity.move_toward(Vector2.ZERO, 300.0 * delta)

# ── Pattern controller ────────────────────────────────────────────────────────
func _pattern_controller(player: Node2D, _delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	var player_spd: float = player.velocity.length() if player is CharacterBody2D else 0.0
	var player_healing_or_charging: bool = (player_spd < 15.0 and dist > 120.0)

	var available: Array = []
	var priority_available: Array = []

	for ability_id in _unlocked_abilities():
		if _cooldowns.get(ability_id, 0.0) > 0.0:
			continue
		var def := BossAbilities.get_def(ability_id)
		if def.is_empty():
			continue
		if int(def["cat"]) == BossAbilities.Cat.REPOSITION:
			continue  # dodge is reactive, not pattern-driven
		if dist <= float(def["range_px"]):
			available.append(ability_id)
	if available.is_empty():
		return
	_start_ability(available[_rng.randi_range(0, available.size() - 1)])

func _unlocked_abilities() -> Array:
	var ids: Array = []
	for p in range(1, phase + 1):
		ids.append_array(blueprint.phase_abilities.get(p, []))
	return ids

func _start_ability(ability_id: String) -> void:
	var def := BossAbilities.get_def(ability_id)
	_current_ability = ability_id
	_astate = AState.WINDUP
	_state_timer = float(def["windup"])
	_cooldowns[ability_id] = float(def["cd"]) * blueprint.cd_mult
	velocity.x = 0.0
	if sprite:
		sprite.modulate = Color(1.3, 1.2, 1.5, 1.0)  # telegraph tint

func _tick_windup(player: Node2D, delta: float) -> void:
	_state_timer -= delta
	var def := BossAbilities.get_def(_current_ability)
	# Telegraph grows brighter toward release
	if sprite and float(def["windup"]) > 0.0:
		var t := 1.0 - _state_timer / float(def["windup"])
		sprite.modulate = Color.WHITE.lerp(Color(1.6, 1.4, 1.9, 1.0), t)
	if _state_timer <= 0.0:
		if sprite:
			sprite.modulate = Color.WHITE
		_execute_ability(player, def)

func _execute_ability(player: Node2D, def: Dictionary) -> void:
	_astate = AState.ACTIVE
	_state_timer = float(def["active"])
	var params: Dictionary = def.get("params", {})
	var dmg := int(round(float(def["damage"]) * _damage_mult * _next_attack_mult))
	_next_attack_mult = 1.0

	match int(def["cat"]):
		BossAbilities.Cat.MELEE:
			_pending_hits = int(params.get("hits", 1))
			_hit_index = 0
			_hit_timer = 0.0
			_do_melee_hit(player, def, dmg)
		BossAbilities.Cat.AOE_PULSE:
			_do_aoe_pulse(player, def, dmg)
		BossAbilities.Cat.CHARGE:
			_charge_dir = _facing
			velocity.x = _charge_dir * float(params.get("speed", 320.0))
		BossAbilities.Cat.LEAP:
			_leap_start = global_position
			_leap_target = player.global_position
			_leap_t = 0.0
		BossAbilities.Cat.PROJECTILE:
			_fire_projectile(player, def, dmg)
		BossAbilities.Cat.DELAYED_AOE:
			_place_delayed_aoe(player, def, dmg)
		BossAbilities.Cat.BEAM:
			_fire_beam(player, def, dmg)
		BossAbilities.Cat.SUMMON:
			_do_summon(params)
		BossAbilities.Cat.BUFF:
			_apply_buff(def, params)
		BossAbilities.Cat.TELEPORT_STRIKE:
			var side := -1.0 if player.global_position.x > global_position.x else 1.0
			global_position = player.global_position + Vector2(side * -30.0, -4.0)
			_do_melee_hit(player, def, dmg)
		BossAbilities.Cat.REPOSITION:
			if params.get("behind_player", false):
				global_position = player.global_position + Vector2(_facing * 40.0, -4.0)
			else:
				global_position += Vector2(-_facing * float(params.get("distance", 60.0)), 0.0)
		BossAbilities.Cat.ROOT:
			_do_root(player, def, dmg)
		BossAbilities.Cat.HAZARD_DROP:
			_drop_hazard(player, def, dmg)

func _tick_active(player: Node2D, delta: float) -> void:
	_state_timer -= delta
	var def := BossAbilities.get_def(_current_ability)
	var params: Dictionary = def.get("params", {})
	var cat := int(def["cat"])

	match cat:
		BossAbilities.Cat.MELEE:
			# Multi-hit sequencing
			if _hit_index < _pending_hits:
				_hit_timer -= delta
				if _hit_timer <= 0.0:
					_do_melee_hit(player, def, int(round(float(def["damage"]) * _damage_mult)))
		BossAbilities.Cat.CHARGE:
			velocity.x = _charge_dir * float(params.get("speed", 320.0))
			if is_on_wall():
				_state_timer = 0.0
			if params.get("stop_at_player", false) and global_position.distance_to(player.global_position) < 40.0:
				_hit_player(player, int(round(float(def["damage"]) * _damage_mult)), Vector2(_charge_dir * 200.0, -100.0))
				_state_timer = 0.0
			elif global_position.distance_to(player.global_position) < 36.0:
				_hit_player(player, int(round(float(def["damage"]) * _damage_mult)), Vector2(_charge_dir * 200.0, -100.0))
		BossAbilities.Cat.LEAP:
			var dur := float(def["active"])
			_leap_t = clampf(_leap_t + delta / maxf(dur, 0.01), 0.0, 1.0)
			var flat := _leap_start.lerp(_leap_target, _leap_t)
			var arc := -80.0 * sin(_leap_t * PI)
			global_position = Vector2(flat.x, flat.y + arc)
			velocity = Vector2.ZERO
			if _leap_t >= 1.0:
				var radius := float(params.get("land_radius", 40.0))
				if global_position.distance_to(player.global_position) <= radius:
					_hit_player(player, int(round(float(def["damage"]) * _damage_mult)), Vector2(0, -150))
				_spawn_burst_visual(global_position, radius)

	if _state_timer <= 0.0:
		_astate = AState.RECOVERY
		_state_timer = float(def["recovery"])
		velocity.x = 0.0

# ── Ability effects ───────────────────────────────────────────────────────────
func _do_melee_hit(player: Node2D, def: Dictionary, dmg: int) -> void:
	var params: Dictionary = def.get("params", {})
	_hit_index += 1
	_hit_timer = float(params.get("hit_gap", 0.2))
	if params.get("requires_behind", false):
		var player_facing: float = 1.0
		if player.has_method("get_facing"):
			player_facing = player.get_facing()
		elif "facing" in player:
			player_facing = float(player.facing)
		var behind: bool = signf(global_position.x - player.global_position.x) != signf(player_facing)
		if not behind:
			return
	var reach := float(params.get("arc_px", 40.0))
	if global_position.distance_to(player.global_position) <= reach + blueprint.hitbox_size.x * 0.5:
		var kb := Vector2(_facing * float(params.get("knockback", 120.0)), 0.0)
		if params.has("launch"):
			kb = Vector2(_facing * 60.0, -float(params["launch"]))
		_hit_player(player, dmg, kb)
	_spawn_slash_visual(reach)

func _do_aoe_pulse(player: Node2D, def: Dictionary, dmg: int) -> void:
	var params: Dictionary = def.get("params", {})
	var radius := float(params.get("radius", 60.0))
	var hits_player := global_position.distance_to(player.global_position) <= radius
	if params.get("ground_only", false):
		# Full-arena shockwave dodged by being airborne
		hits_player = hits_player and player.is_on_floor() if player is CharacterBody2D else hits_player
	if params.get("cone", false):
		var to_player := player.global_position - global_position
		hits_player = hits_player and signf(to_player.x) == _facing
		if hits_player:
			var kb := Vector2.ZERO
			if params.has("knockback"):
				kb = (player.global_position - global_position).normalized() * float(params["knockback"])
			_hit_player(player, dmg, kb)
			if params.has("slow_mult") and player.has_method("apply_status"):
				player.apply_status("slow", float(params["slow_duration"]), Vector2.ZERO, float(params["slow_mult"]))
	_spawn_burst_visual(global_position, minf(radius, 140.0))
	if params.get("screen_shake", false):
		_shake_camera()
	# Multi-hit pulses (Whirlwind)
	if int(params.get("hits", 1)) > 1 and _hit_index == 0:
		_hit_index = 1
		var gap := float(params.get("hit_gap", 0.2))
		var t := get_tree().create_timer(gap)
		t.timeout.connect(func():
			if _astate == AState.ACTIVE and is_instance_valid(player):
				_do_aoe_pulse(player, def, dmg))

func _fire_projectile(player: Node2D, def: Dictionary, dmg: int) -> void:
	var params: Dictionary = def.get("params", {})
	var style: String = params.get("style", "straight")
	var speed := float(params.get("speed", 200.0))
	var to_player := (player.global_position - global_position).normalized()

	var count := int(params.get("count", 1))
	for i in range(count):
		var dir := to_player
		if style == "spread" and count > 1:
			var spread := deg_to_rad(float(params.get("spread_deg", 24.0)))
			dir = to_player.rotated(spread * (float(i) / float(count - 1) - 0.5))
		elif style == "lob":
			dir = (to_player + Vector2(0, -0.7)).normalized()

		var node := _make_orb_node(6, BossHexThemes.get_data(blueprint.hex_theme)["glow"])
		node.global_position = global_position
		_projectiles.append({
			"node": node, "vel": dir * speed, "style": style, "damage": dmg,
			"lifetime": float(params.get("lifetime", 4.0)),
			"aoe": float(params.get("aoe_radius", 0.0)),
			"origin": global_position, "returning": false,
		})

func _update_projectiles(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var i := _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var node: Node2D = p["node"]
		if not is_instance_valid(node):
			_projectiles.remove_at(i)
			i -= 1
			continue

		p["lifetime"] -= delta
		match p["style"]:
			"homing":
				if player:
					var want: Vector2 = (player.global_position - node.global_position).normalized() * p["vel"].length()
					p["vel"] = p["vel"].lerp(want, 0.06)
			"lob":
				p["vel"] += Vector2(0, GRAVITY * 0.6) * delta
			"boomerang":
				if not p["returning"] and node.global_position.distance_to(p["origin"]) > 140.0:
					p["returning"] = true
				if p["returning"]:
					var back: Vector2 = (global_position - node.global_position).normalized() * p["vel"].length()
					p["vel"] = p["vel"].lerp(back, 0.15)
					if node.global_position.distance_to(global_position) < 16.0:
						p["lifetime"] = 0.0

		node.global_position += p["vel"] * delta

		var hit := false
		if player and node.global_position.distance_to(player.global_position) < 14.0:
			_hit_player(player, p["damage"], p["vel"].normalized() * 120.0)
			hit = true
		if p["aoe"] > 0.0 and (hit or p["lifetime"] <= 0.0):
			if player and node.global_position.distance_to(player.global_position) <= p["aoe"] and not hit:
				_hit_player(player, p["damage"], Vector2.ZERO)
			_spawn_burst_visual(node.global_position, p["aoe"])

		if hit or p["lifetime"] <= 0.0:
			node.queue_free()
			_projectiles.remove_at(i)
		i -= 1

func _place_delayed_aoe(player: Node2D, def: Dictionary, dmg: int) -> void:
	var params: Dictionary = def.get("params", {})
	var radius := float(params.get("radius", 60.0))
	var marker := _make_ring_node(radius, Color(1.0, 0.3, 0.2, 0.5))
	marker.global_position = player.global_position
	_delayed_aoes.append({
		"node": marker, "pos": player.global_position,
		"timer": float(params.get("delay", 1.0)), "damage": dmg, "radius": radius,
	})

func _update_delayed_aoes(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var i := _delayed_aoes.size() - 1
	while i >= 0:
		var a: Dictionary = _delayed_aoes[i]
		a["timer"] -= delta
		if a["timer"] <= 0.0:
			if player and a["pos"].distance_to(player.global_position) <= a["radius"]:
				_hit_player(player, a["damage"], Vector2(0, -120))
			_spawn_burst_visual(a["pos"], a["radius"])
			if is_instance_valid(a["node"]):
				a["node"].queue_free()
			_delayed_aoes.remove_at(i)
		i -= 1

func _fire_beam(player: Node2D, def: Dictionary, dmg: int) -> void:
	var params: Dictionary = def.get("params", {})
	var dir := (player.global_position - global_position).normalized()
	var line := Line2D.new()
	line.width = float(params.get("width_px", 10.0))
	line.default_color = BossHexThemes.get_data(blueprint.hex_theme)["glow"]
	line.add_point(Vector2.ZERO)
	line.add_point(dir * 600.0)
	add_child(line)
	_beam = {"node": line, "timer": float(def["active"]), "damage": dmg, "dir": dir,
		"width": float(params.get("width_px", 10.0)), "hit_done": false,
		"sweep": params.get("sweep", false), "tracks": params.get("tracks_player", false)}

func _update_beam(delta: float) -> void:
	if _beam.is_empty():
		return
	var node: Line2D = _beam["node"]
	if not is_instance_valid(node):
		_beam = {}
		return
	_beam["timer"] -= delta
	var player := get_tree().get_first_node_in_group("player")
	var dir: Vector2 = _beam["dir"]
	if player:
		if _beam["tracks"]:
			var want: Vector2 = (player.global_position - global_position).normalized()
			dir = dir.lerp(want, 0.04).normalized()
		elif _beam["sweep"]:
			dir = dir.rotated(0.9 * delta * -signf(dir.x))
		_beam["dir"] = dir
		node.set_point_position(1, dir * 600.0)
		# Perpendicular distance from player to beam line
		var rel: Vector2 = player.global_position - global_position
		var along := rel.dot(dir)
		if along > 0.0:
			var perp: float = absf(rel.x * dir.y - rel.y * dir.x)
			if perp <= float(_beam["width"]) and not _beam["hit_done"]:
				_hit_player(player, _beam["damage"], dir * 140.0)
				_beam["hit_done"] = true
	if _beam["timer"] <= 0.0:
		node.queue_free()
		_beam = {}

func _do_summon(params: Dictionary) -> void:
	var style: String = params.get("style", "minion")
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_parent()
	var count := int(params.get("count", 1))
	if blueprint.difficulty > 0.7:
		count = int(params.get("count_hard", count))
	count = mini(count, blueprint.minion_count if blueprint.minion_count > 0 else 1)

	if style == "decoy":
		# Translucent 1-HP visual decoy: a sprite that fades on any approach
		var decoy := Sprite2D.new()
		decoy.texture = sprite.texture
		decoy.scale = sprite.scale
		decoy.modulate = Color(1, 1, 1, 0.55)
		decoy.global_position = global_position + Vector2(-_facing * 50.0, 0)
		world.add_child(decoy)
		var t := decoy.create_tween()
		t.tween_interval(4.0)
		t.tween_property(decoy, "modulate:a", 0.0, 0.5)
		t.tween_callback(decoy.queue_free)
		return

	for i in range(maxi(count, 1)):
		var minion := CharacterBody2D.new()
		minion.set_script(load("res://scripts/enemy/Nullman.gd"))
		minion.collision_layer = LAYER_ENEMY
		minion.collision_mask = LAYER_GEOMETRY | LAYER_PLAYER
		minion.position = global_position + Vector2((i * 2 - 1) * 40.0, -8.0)
		var ms := Sprite2D.new()
		ms.name = "Sprite"
		ms.texture = PixelRenderer.generate_enemy_texture(PixelRenderer.EnemyType.NULLMAN, blueprint.seed_val + i)
		ms.scale = Vector2(1.2, 1.2)
		minion.add_child(ms)
		minion.set("sprite", ms)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(16, 20)
		cs.shape = shape
		minion.add_child(cs)
		world.add_child(minion)

func _apply_buff(def: Dictionary, params: Dictionary) -> void:
	var style: String = params.get("style", "")
	_active_buff = style
	_buff_timer = float(def["active"])
	match style:
		"enrage":
			_speed_mult = float(params.get("speed_mult", 1.3))
			_damage_mult = float(params.get("damage_mult", 1.25))
			if sprite:
				sprite.modulate = Color(1.5, 0.7, 0.7, 1.0)
		"shield":
			_shielded = true
			if sprite:
				sprite.modulate = Color(0.7, 0.9, 1.5, 1.0)
		"invis":
			if sprite:
				sprite.modulate = Color(1, 1, 1, 0.12)
			_next_attack_mult = float(params.get("next_attack_mult", 2.0))
		"intangible":
			_intangible = true
			if sprite:
				sprite.modulate = Color(1, 1, 1, 0.35)
		"parry":
			_shielded = true  # absorbs hits during stance; riposte on take_damage
			if sprite:
				sprite.modulate = Color(1.2, 1.2, 0.8, 1.0)

func _end_buff() -> void:
	_speed_mult = 1.0
	_damage_mult = 1.0
	_shielded = false
	_intangible = false
	_active_buff = ""
	if sprite:
		sprite.modulate = Color.WHITE

func _do_root(player: Node2D, def: Dictionary, dmg: int) -> void:
	var params: Dictionary = def.get("params", {})
	var style: String = params.get("style", "root")
	if player.has_method("apply_status"):
		match style:
			"root":
				player.apply_status("root", float(params.get("duration", 1.2)))
			"stun":
				player.apply_status("stun", float(params.get("duration", 1.0)))
			"invert":
				player.apply_status("invert", float(params.get("duration", 1.2)))
			"pull":
				player.apply_status("pull_to", float(params.get("pull_time", 0.5)), global_position)
	if dmg > 0:
		_hit_player(player, dmg, Vector2.ZERO)
	_spawn_burst_visual(player.global_position, 30.0)

func _drop_hazard(player: Node2D, def: Dictionary, dmg: int) -> void:
	var params: Dictionary = def.get("params", {})
	var style: String = params.get("style", "pool")
	var theme: Dictionary = BossHexThemes.get_data(blueprint.hex_theme)
	if style == "pool":
		# Spit a projectile that leaves a pool where it lands
		var node := _make_orb_node(5, theme["accent"])
		node.global_position = global_position
		var dir := ((player.global_position - global_position).normalized() + Vector2(0, -0.5)).normalized()
		_projectiles.append({
			"node": node, "vel": dir * float(params.get("speed", 240.0)), "style": "lob",
			"damage": int(def["damage"]), "lifetime": 2.0, "aoe": 0.0,
			"origin": global_position, "returning": false, "leaves_pool": true,
			"pool_dps": int(params.get("pool_dps", 1)),
			"pool_duration": float(params.get("pool_duration", 2.0)),
		})
	elif style == "mine":
		var node := _make_orb_node(4, theme["secondary"])
		node.global_position = player.global_position + Vector2(_rng.randf_range(-50, 50), -4)
		_hazards.append({
			"node": node, "style": "mine", "pos": node.global_position,
			"damage": dmg, "timer": 20.0,
			"radius": float(params.get("trigger_radius", 40.0)),
		})

func _update_hazards(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var i := _hazards.size() - 1
	while i >= 0:
		var hz: Dictionary = _hazards[i]
		hz["timer"] -= delta
		var done: bool = hz["timer"] <= 0.0
		if player:
			var dist: float = hz["pos"].distance_to(player.global_position)
			match hz["style"]:
				"mine":
					if dist <= hz["radius"]:
						_hit_player(player, hz["damage"], Vector2(0, -140))
						_spawn_burst_visual(hz["pos"], hz["radius"])
						done = true
				"pool":
					hz["tick"] = hz.get("tick", 0.0) - delta
					if dist <= hz["radius"] and hz["tick"] <= 0.0:
						_hit_player(player, hz["damage"], Vector2.ZERO)
						hz["tick"] = 1.0
		if done:
			if is_instance_valid(hz["node"]):
				hz["node"].queue_free()
			_hazards.remove_at(i)
		i -= 1

# ── Damage / counters / phases ───────────────────────────────────────────────
func take_hex_damage(impact_pos: Vector2, _pattern: Dictionary) -> void:
	if hex_barrier_active:
		_break_hex_barrier()
	var dmg := int(round(14.0 * _damage_mult))
	take_damage(dmg, (global_position - impact_pos).normalized() * 120.0)

func _break_hex_barrier() -> void:
	hex_barrier_active = false
	if _barrier_sprite and is_instance_valid(_barrier_sprite):
		var t := create_tween()
		t.tween_property(_barrier_sprite, "modulate:a", 0.0, 0.25)
		t.tween_callback(_barrier_sprite.queue_free)
		_barrier_sprite = null

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_boss_defeated or _invuln_timer > 0.0 or _intangible:
		return
	if _shielded:
		if _active_buff == "parry":
			# Riposte: punish the player for striking the stance
			var player := get_tree().get_first_node_in_group("player")
			if player:
				_hit_player(player, 10, Vector2(_facing * 200.0, -80.0))
			_end_buff()
			_buff_timer = 0.0
		return

	if hex_barrier_active:
		amount = int(ceil(amount * 0.2))

	posture_regen_timer = 2.5
	current_posture -= float(amount)
	if current_posture <= 0.0 and _stun_timer <= 0.0:
		_stun_timer = COUNTER_STUN * (1.0 - blueprint.stagger_resistance * 0.4)
		current_posture = max_posture
		if sprite:
			sprite.modulate = Color(2.0, 2.0, 0.4, 1.0)

	current_hp = maxi(0, current_hp - amount)
	emit_signal("health_changed", current_hp, blueprint.max_hp)

	# Stagger response scales inversely with resistance
	if _rng.randf() > blueprint.stagger_resistance:
		velocity += knockback * 0.4
	if sprite and _stun_timer <= 0.0:
		sprite.modulate = Color(2.0, 0.6, 0.6, 1.0)
		var t := sprite.create_tween()
		t.tween_property(sprite, "modulate", Color.WHITE, 0.15)

	_phase_controller()

	if current_hp <= 0:
		_die()

func _phase_controller() -> void:
	if is_boss_defeated:
		return
	var frac := float(current_hp) / float(blueprint.max_hp)
	var target_phase := 1
	if blueprint.phase_count >= 3 and frac <= blueprint.phase3_threshold:
		target_phase = 3
	elif frac <= blueprint.phase2_threshold:
		target_phase = 2
	if target_phase > phase:
		_begin_phase_shift(target_phase)

func _begin_phase_shift(new_phase: int) -> void:
	phase = new_phase
	_astate = AState.PHASE_SHIFT
	_state_timer = 1.0
	_invuln_timer = 1.5
	velocity = Vector2.ZERO
	# Activate Hex Barrier on phase shift
	hex_barrier_active = true
	if _barrier_sprite == null or not is_instance_valid(_barrier_sprite):
		_barrier_sprite = Sprite2D.new()
		_barrier_sprite.texture = PixelRenderer.generate_glow_texture(int(blueprint.hitbox_size.x * 0.9))
		_barrier_sprite.modulate = Color(0.8, 0.2, 1.0, 0.7)
		_barrier_sprite.centered = true
		add_child(_barrier_sprite)

	# Cooldown reset (Axis 5)
	for id in _cooldowns:
		_cooldowns[id] = 0.0
	if sprite:
		sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)

func _finish_phase_shift() -> void:
	_astate = AState.IDLE
	# Shockwave burst (u_phase_shift behavior)
	var player := get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) <= 60.0:
		var kb: Vector2 = (player.global_position - global_position).normalized() * 220.0
		_hit_player(player, 8, kb)
	_spawn_burst_visual(global_position, 60.0)
	_shake_camera()
	if sprite:
		sprite.texture = PixelRenderer.generate_boss_texture(blueprint, phase)
		sprite.modulate = Color.WHITE
	emit_signal("phase_changed", phase)

func is_counterable() -> bool:
	if is_boss_defeated or _astate != AState.WINDUP or _current_ability.is_empty():
		return false
	var def := BossAbilities.get_def(_current_ability)
	var c: String = def.get("counterable", "no")
	if c == "no":
		return false
	var window := float(def.get("counter_window", 0.3)) * blueprint.counter_window_mult
	var windup := float(def["windup"])
	# Counterable during the final `window` fraction of the windup
	return _state_timer <= windup * minf(window, 1.0)

func countered() -> void:
	if is_boss_defeated:
		return
	_astate = AState.IDLE
	_current_ability = ""
	current_posture = maxf(0.0, current_posture - 80.0)
	_stun_timer = COUNTER_STUN * (1.0 - blueprint.stagger_resistance * 0.4)
	velocity = Vector2.ZERO
	print("[BOSS] COUNTERED — stunned %.2fs" % _stun_timer)

func _die() -> void:
	is_boss_defeated = true
	_astate = AState.IDLE
	velocity = Vector2.ZERO
	set_physics_process(false)

	# Clean up transient objects
	for p in _projectiles:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	for hz in _hazards:
		if is_instance_valid(hz["node"]):
			hz["node"].queue_free()
	for a in _delayed_aoes:
		if is_instance_valid(a["node"]):
			a["node"].queue_free()
	if not _beam.is_empty() and is_instance_valid(_beam["node"]):
		_beam["node"].queue_free()

	var essence := int(50 + 100 * blueprint.difficulty)
	emit_signal("enemy_died", global_position, essence)
	emit_signal("boss_defeated")
	EssenceManager.gain_essence(essence)

	# Death visual: flash → dissolve
	if sprite:
		var t := create_tween()
		t.tween_property(sprite, "modulate", Color(3, 3, 3, 1), 0.2)
		t.tween_property(sprite, "modulate:a", 0.0, 0.8)
		t.tween_callback(queue_free)
	else:
		queue_free()

# ── Helpers ───────────────────────────────────────────────────────────────────
func _hit_player(player: Node2D, dmg: int, knockback: Vector2) -> void:
	if dmg <= 0:
		return
	if player.has_method("take_damage"):
		player.take_damage(dmg, knockback)

func _make_orb_node(radius_px: int, color: Color) -> Node2D:
	var orb := Sprite2D.new()
	orb.texture = PixelRenderer.generate_glow_texture(radius_px)
	orb.modulate = color
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_parent()
	world.add_child(orb)
	return orb

func _make_ring_node(radius: float, color: Color) -> Node2D:
	var ring := Sprite2D.new()
	ring.texture = PixelRenderer.generate_glow_texture(int(radius))
	ring.modulate = color
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_parent()
	world.add_child(ring)
	return ring

func _spawn_burst_visual(pos: Vector2, radius: float) -> void:
	var theme: Dictionary = BossHexThemes.get_data(blueprint.hex_theme)
	var burst := Sprite2D.new()
	burst.texture = PixelRenderer.generate_glow_texture(int(clampf(radius, 8.0, 120.0)))
	burst.modulate = theme["glow"]
	burst.global_position = pos
	burst.scale = Vector2(0.3, 0.3)
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_parent()
	world.add_child(burst)
	var t := burst.create_tween()
	t.tween_property(burst, "scale", Vector2.ONE, 0.25)
	t.parallel().tween_property(burst, "modulate:a", 0.0, 0.3)
	t.tween_callback(burst.queue_free)

func _spawn_slash_visual(reach: float) -> void:
	var slash := Sprite2D.new()
	slash.texture = PixelRenderer.generate_glow_texture(int(clampf(reach * 0.5, 6.0, 40.0)))
	slash.modulate = BossHexThemes.get_data(blueprint.hex_theme)["glow"]
	slash.global_position = global_position + Vector2(_facing * reach * 0.6, 0)
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_parent()
	world.add_child(slash)
	var t := slash.create_tween()
	t.tween_property(slash, "modulate:a", 0.0, 0.2)
	t.tween_callback(slash.queue_free)

func _shake_camera() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(0.3, 6.0)
