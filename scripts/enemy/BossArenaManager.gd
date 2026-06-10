extends Node2D
class_name BossArenaManager
# BossArenaManager.gd — boss arena door lock + theme hazards (Axis 6).
#
# Game.gd creates one when a boss room activates, passing the boss, the room
# bounds, and the portal openings to seal. Hazards activate per phase via the
# boss's phase_changed signal and run as lightweight data-driven zones.

const TILE_SIZE := 16
const LAYER_GEOMETRY := 1

var _boss: BossEnemy
var _room_px: Vector2
var _door_blocks: Array = []
var _zones: Array = []   # {style, pos, radius, timer, tick, node, phase}
var _rng := RandomNumberGenerator.new()
var _active_phase := 1

func setup(boss: BossEnemy, room_w_tiles: int, room_h_tiles: int, door_rects: Array) -> void:
	_boss = boss
	_room_px = Vector2(room_w_tiles * TILE_SIZE, room_h_tiles * TILE_SIZE)
	_rng.seed = boss.blueprint.seed_val + 31

	boss.phase_changed.connect(_on_phase_changed)
	boss.boss_defeated.connect(_on_boss_defeated)

	_lock_doors(door_rects)
	_prepare_hazards()
	# Phase-1 hazards activate immediately
	_activate_hazards_for_phase(1)

# ── Door lock ─────────────────────────────────────────────────────────────────
func _lock_doors(door_rects: Array) -> void:
	for rect in door_rects:
		var block := StaticBody2D.new()
		block.collision_layer = LAYER_GEOMETRY
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		cs.shape = shape
		block.position = rect.position + rect.size * 0.5
		block.add_child(cs)

		# Visual: energy wall tinted by theme
		var visual := Sprite2D.new()
		visual.texture = PixelRenderer.generate_glow_texture(int(maxf(rect.size.x, rect.size.y) * 0.5))
		visual.modulate = BossHexThemes.get_data(_boss.blueprint.hex_theme)["glow"]
		visual.modulate.a = 0.5
		visual.scale = Vector2(rect.size.x / maxf(rect.size.y, 1.0), 1.0)
		block.add_child(visual)

		add_child(block)
		_door_blocks.append(block)

func _unlock_doors() -> void:
	for block in _door_blocks:
		if is_instance_valid(block):
			block.queue_free()
	_door_blocks.clear()

# ── Hazards ───────────────────────────────────────────────────────────────────
func _prepare_hazards() -> void:
	var bp := _boss.blueprint
	for i in range(bp.arena_hazards.size()):
		var hz_id: String = bp.arena_hazards[i]
		var hz_phase: int = bp.hazard_phases[i] if i < bp.hazard_phases.size() else 2
		_zones.append(_make_zone(hz_id, hz_phase))

# Builds the data record for one hazard. Position rolled inside the arena.
func _make_zone(hz_id: String, hz_phase: int) -> Dictionary:
	var floor_y := _room_px.y - 4.0 * TILE_SIZE
	var x := _rng.randf_range(_room_px.x * 0.2, _room_px.x * 0.8)
	var zone := {
		"style": hz_id, "phase": hz_phase, "active": false,
		"pos": Vector2(x, floor_y), "radius": 50.0,
		"timer": 0.0, "tick": 0.0, "node": null,
	}
	match hz_id:
		"void_pool", "null_zone":
			zone["radius"] = 55.0
		"darkness_zone", "confusion_field", "echo_field":
			zone["radius"] = 80.0
		"pulse_node", "tesla_coil":
			zone["pos"] = Vector2(x, floor_y - 30.0)
			zone["radius"] = 70.0
		"wall_turret":
			zone["pos"] = Vector2(TILE_SIZE * 2.0 if _rng.randf() < 0.5 else _room_px.x - TILE_SIZE * 2.0, _room_px.y * 0.4)
		"corruption_cyst", "resonance_crystal":
			zone["pos"] = Vector2(x, _room_px.y * 0.35)
			zone["hp"] = 15
		"collapsing_floor", "memory_fragment":
			zone["radius"] = 45.0
		"rising_pillars", "rubble_piles", "illusion_wall", "teleport_pad", "conveyor":
			zone["radius"] = 60.0
	return zone

func _on_phase_changed(new_phase: int) -> void:
	_active_phase = new_phase
	_activate_hazards_for_phase(new_phase)

func _activate_hazards_for_phase(phase: int) -> void:
	for zone in _zones:
		if zone["active"] or int(zone["phase"]) > phase:
			continue
		zone["active"] = true
		# Visual marker for the hazard zone
		var marker := Sprite2D.new()
		marker.texture = PixelRenderer.generate_glow_texture(int(zone["radius"]))
		var theme: Dictionary = BossHexThemes.get_data(_boss.blueprint.hex_theme)
		marker.modulate = theme["accent"]
		marker.modulate.a = 0.35
		marker.global_position = zone["pos"]
		add_child(marker)
		zone["node"] = marker

func _physics_process(delta: float) -> void:
	if _boss == null or _boss.is_boss_defeated:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	for zone in _zones:
		if not zone["active"]:
			continue
		var dist: float = zone["pos"].distance_to(player.global_position)
		zone["tick"] = float(zone["tick"]) - delta
		match zone["style"]:
			"void_pool":
				# Standing in it: 2 dmg/sec
				if dist <= zone["radius"] and zone["tick"] <= 0.0:
					player.take_damage(2)
					zone["tick"] = 1.0
			"null_zone":
				# Drains essence instead of HP
				if dist <= zone["radius"] and zone["tick"] <= 0.0:
					EssenceManager.spend_essence(3)
					zone["tick"] = 1.0
			"pulse_node":
				# Radial pulse every 4s — jump to dodge handled by distance only
				zone["timer"] = float(zone["timer"]) - delta
				if zone["timer"] <= 0.0:
					zone["timer"] = 4.0
					if dist <= zone["radius"]:
						player.take_damage(6)
					_pulse_visual(zone)
			"wall_turret":
				# Fires at player every 3s
				zone["timer"] = float(zone["timer"]) - delta
				if zone["timer"] <= 0.0:
					zone["timer"] = 3.0
					_turret_shot(zone, player)
			"tesla_coil":
				if dist <= zone["radius"] * 0.5 and zone["tick"] <= 0.0:
					player.take_damage(4)
					zone["tick"] = 0.8
			"darkness_zone", "confusion_field", "memory_fragment":
				# Status zones — degrade gracefully if Player lacks apply_status
				if dist <= zone["radius"] and zone["tick"] <= 0.0 and player.has_method("apply_status"):
					match zone["style"]:
						"darkness_zone":
							player.apply_status("darkness", 1.0)
						"confusion_field":
							player.apply_status("invert", 1.0)
						"memory_fragment":
							player.take_damage(1)
					zone["tick"] = 1.0
			"corruption_cyst":
				# Heals boss if boss touches it; destroyable conceptually via proximity attack
				if _boss.global_position.distance_to(zone["pos"]) < 40.0 and zone["tick"] <= 0.0:
					_boss.current_hp = mini(_boss.blueprint.max_hp, _boss.current_hp + 5)
					_boss.emit_signal("health_changed", _boss.current_hp, _boss.blueprint.max_hp)
					zone["tick"] = 2.0
			"conveyor":
				# Push the player horizontally while inside
				if dist <= zone["radius"] and player is CharacterBody2D:
					player.velocity.x += 60.0 * delta * 10.0
			_:
				pass  # decorative-only hazards (rubble_piles, illusion_wall, etc.)

func _turret_shot(zone: Dictionary, player: Node2D) -> void:
	var orb := Sprite2D.new()
	orb.texture = PixelRenderer.generate_glow_texture(4)
	orb.modulate = BossHexThemes.get_data(_boss.blueprint.hex_theme)["secondary"]
	orb.global_position = zone["pos"]
	add_child(orb)
	var dir: Vector2 = (player.global_position - zone["pos"]).normalized()
	var t := orb.create_tween()
	var travel_time: float = zone["pos"].distance_to(player.global_position) / 220.0
	t.tween_property(orb, "global_position", player.global_position + dir * 30.0, travel_time)
	t.tween_callback(func():
		var p := get_tree().get_first_node_in_group("player")
		if p and orb.global_position.distance_to(p.global_position) < 16.0:
			p.take_damage(5)
		orb.queue_free())

func _pulse_visual(zone: Dictionary) -> void:
	var burst := Sprite2D.new()
	burst.texture = PixelRenderer.generate_glow_texture(int(zone["radius"]))
	burst.modulate = BossHexThemes.get_data(_boss.blueprint.hex_theme)["glow"]
	burst.global_position = zone["pos"]
	burst.scale = Vector2(0.2, 0.2)
	add_child(burst)
	var t := burst.create_tween()
	t.tween_property(burst, "scale", Vector2.ONE, 0.3)
	t.parallel().tween_property(burst, "modulate:a", 0.0, 0.35)
	t.tween_callback(burst.queue_free)

func _on_boss_defeated() -> void:
	_unlock_doors()
	for zone in _zones:
		if zone["node"] != null and is_instance_valid(zone["node"]):
			zone["node"].queue_free()
	_zones.clear()
	set_physics_process(false)
