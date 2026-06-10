extends RefCounted
class_name BossBlueprint
# BossBlueprint.gd — Axis 4/5/8: deterministic boss generation.
#
# generate(seed, hex_theme, difficulty) → fully-specified blueprint that
# BossEnemy.spawn_for_dungeon() consumes. Same seed = same boss.

var seed_val: int
var body_type: int
var hex_theme: int
var difficulty: float

# Derived body stats
var hitbox_size: Vector2
var max_hp: int
var move_speed: float
var vertical_tracking: float
var stagger_resistance: float
var slot_count: int

# Abilities, keyed by unlock phase: {1: [ids], 2: [ids], 3: [ids]}
var phase_abilities: Dictionary = {}
var universal_abilities: Array = []

# Phases
var phase_count: int
var phase2_threshold: float   # fraction of max HP
var phase3_threshold: float

# Tuning
var cd_mult: float
var counter_window_mult: float
var minion_count: int

# Arena
var arena_hazards: Array = []      # hazard id strings
var hazard_phases: Array = []      # phase each hazard activates in

# Visual
var camera_zoom: float
var texture_size: Vector2i
var sprite_scale: float

const BASE_HP := 200

static func generate(p_seed: int, p_hex_theme: int, p_difficulty: float) -> BossBlueprint:
	var bp := BossBlueprint.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	bp.seed_val = p_seed
	bp.hex_theme = p_hex_theme
	bp.difficulty = clampf(p_difficulty, 0.0, 1.0)

	# 1. Body type from difficulty-weighted distribution
	bp.body_type = BossBodyTypes.roll_body_type(bp.difficulty, rng)
	var body := BossBodyTypes.get_data(bp.body_type)

	# 2. Derived body stats with difficulty scaling (Axis 8)
	var hp_scale := lerpf(0.7, 1.4, bp.difficulty)
	var speed_scale := lerpf(0.85, 1.2, bp.difficulty)
	bp.hitbox_size = body["hitbox"]
	bp.max_hp = int(BASE_HP * body["hp_mult"] * hp_scale)
	bp.move_speed = body["speed"] * speed_scale
	bp.vertical_tracking = body["vertical"]
	bp.stagger_resistance = body["stagger_resist"]
	bp.cd_mult = lerpf(1.3, 0.8, bp.difficulty)
	bp.counter_window_mult = lerpf(1.3, 0.8, bp.difficulty)
	bp.minion_count = 0 if bp.difficulty < 0.3 else (1 if bp.difficulty < 0.7 else 2)

	# Slots: base + difficulty bonus, capped by body max
	var bonus := 0 if bp.difficulty < 0.3 else (1 if bp.difficulty < 0.7 else 2)
	bp.slot_count = mini(int(body["min_slots"]) + bonus, int(body["max_slots"]))

	# 3. Phases (Axis 5 + Axis 8 thresholds)
	bp.phase_count = 2 if bp.difficulty < 0.4 else 3
	bp.phase2_threshold = lerpf(0.4, 0.6, bp.difficulty)
	bp.phase3_threshold = 0.3 if bp.phase_count >= 3 else 0.0

	# 4. Ability selection (Axis 4 step 3)
	var pool: Array = BossAbilities.get_pool(bp.body_type).duplicate()
	if bp.difficulty > 0.5 and bp.body_type != BossBodyTypes.BodyType.SENTINEL:
		if not pool.has(BossAbilities.U_SUMMON_MINION):
			pool.append(BossAbilities.U_SUMMON_MINION)

	var selected: Array = []
	bp.phase_abilities = {1: [], 2: [], 3: []}

	# Phase 1 guarantee: 1-2 phase-1 abilities
	var p1_pool := pool.filter(func(id): return int(BossAbilities.get_def(id)["phase"]) == 1 and not selected.has(id))
	var p1_count := maxi(1, bp.slot_count - 1)
	for i in range(mini(p1_count, p1_pool.size())):
		var pick: String = p1_pool[rng.randi_range(0, p1_pool.size() - 1)]
		p1_pool.erase(pick)
		selected.append(pick)
		bp.phase_abilities[1].append(pick)

	# Phase 2 ability
	if bp.slot_count > selected.size():
		var p2_pool := pool.filter(func(id): return int(BossAbilities.get_def(id)["phase"]) <= 2 and not selected.has(id))
		if not p2_pool.is_empty():
			var pick: String = p2_pool[rng.randi_range(0, p2_pool.size() - 1)]
			selected.append(pick)
			bp.phase_abilities[2].append(pick)

	# Phase 3 ability (hard dungeons)
	if bp.slot_count > selected.size() and bp.phase_count >= 3:
		var p3_pool := pool.filter(func(id): return int(BossAbilities.get_def(id)["phase"]) <= 3 and not selected.has(id))
		if not p3_pool.is_empty():
			var pick: String = p3_pool[rng.randi_range(0, p3_pool.size() - 1)]
			selected.append(pick)
			bp.phase_abilities[3].append(pick)

	# 5. Universal abilities
	bp.universal_abilities = []
	if bp.body_type != BossBodyTypes.BodyType.SENTINEL:
		bp.universal_abilities.append(BossAbilities.U_DODGE_DASH)
	bp.universal_abilities.append(BossAbilities.U_PHASE_SHIFT)

	# 6. Arena hazards (Axis 6): activate in phase 2+ per design
	bp.arena_hazards = BossHexThemes.roll_hazards(bp.hex_theme, bp.difficulty, rng)
	bp.hazard_phases = []
	for i in range(bp.arena_hazards.size()):
		bp.hazard_phases.append(2 if i == 0 else 3)

	# 7. Visuals
	bp.camera_zoom = body["camera_zoom"]
	bp.texture_size = body["texture_size"]
	bp.sprite_scale = body["sprite_scale"]

	return bp

func describe() -> String:
	return "%s %s (diff %.2f) hp=%d phases=%d abilities=%s hazards=%s" % [
		BossHexThemes.get_theme_name(hex_theme), BossBodyTypes.get_type_name(body_type),
		difficulty, max_hp, phase_count, str(phase_abilities), str(arena_hazards),
	]
