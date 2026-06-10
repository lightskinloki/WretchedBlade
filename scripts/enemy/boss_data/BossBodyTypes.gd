extends RefCounted
class_name BossBodyTypes
# BossBodyTypes.gd — Axis 1 data: the seven Nullman body frameworks.
# Each entry defines the physical chassis a generated boss is built on.
# See BOSS_DESIGN.md Axis 1.

enum BodyType { BRUISER, SKIRMISHER, SKITTERER, SENTINEL, STALKER, COLOSSUS, WRAITH }

# Movement AI archetypes interpreted by BossEnemy._movement_ai
enum MoveAI { WALKER, PACER, ERRATIC, ROOTED, TELEPORTER, ADVANCER, DRIFTER }

const DATA := {
	BodyType.BRUISER: {
		"name": "Bruiser",
		"hitbox": Vector2(48, 64),
		"hp_mult": 1.8,
		"speed": 60.0,
		"vertical": 0.2,
		"min_slots": 2, "max_slots": 3,
		"stagger_resist": 0.8,
		"move_ai": MoveAI.WALKER,
		"texture_size": Vector2i(32, 48),
		"sprite_scale": 1.5,
		"camera_zoom": 1.8,
	},
	BodyType.SKIRMISHER: {
		"name": "Skirmisher",
		"hitbox": Vector2(32, 48),
		"hp_mult": 1.0,
		"speed": 100.0,
		"vertical": 0.5,
		"min_slots": 2, "max_slots": 3,
		"stagger_resist": 0.5,
		"move_ai": MoveAI.PACER,
		"texture_size": Vector2i(24, 36),
		"sprite_scale": 1.25,
		"camera_zoom": 1.8,
	},
	BodyType.SKITTERER: {
		"name": "Skitterer",
		"hitbox": Vector2(20, 28),
		"hp_mult": 0.6,
		"speed": 160.0,
		"vertical": 0.8,
		"min_slots": 1, "max_slots": 2,
		"stagger_resist": 0.2,
		"move_ai": MoveAI.ERRATIC,
		"texture_size": Vector2i(16, 20),
		"sprite_scale": 1.0,
		"camera_zoom": 2.0,
	},
	BodyType.SENTINEL: {
		"name": "Sentinel",
		"hitbox": Vector2(36, 52),
		"hp_mult": 2.0,
		"speed": 0.0,
		"vertical": 0.0,
		"min_slots": 2, "max_slots": 4,
		"stagger_resist": 0.9,
		"move_ai": MoveAI.ROOTED,
		"texture_size": Vector2i(28, 40),
		"sprite_scale": 1.3,
		"camera_zoom": 1.8,
	},
	BodyType.STALKER: {
		"name": "Stalker",
		"hitbox": Vector2(28, 44),
		"hp_mult": 0.8,
		"speed": 120.0,
		"vertical": 0.8,
		"min_slots": 2, "max_slots": 2,
		"stagger_resist": 0.2,
		"move_ai": MoveAI.TELEPORTER,
		"texture_size": Vector2i(22, 36),
		"sprite_scale": 1.2,
		"camera_zoom": 1.8,
	},
	BodyType.COLOSSUS: {
		"name": "Colossus",
		"hitbox": Vector2(80, 96),
		"hp_mult": 3.0,
		"speed": 30.0,
		"vertical": 0.0,
		"min_slots": 3, "max_slots": 4,
		"stagger_resist": 1.0,
		"move_ai": MoveAI.ADVANCER,
		"texture_size": Vector2i(60, 72),
		"sprite_scale": 1.5,
		"camera_zoom": 1.4,
	},
	BodyType.WRAITH: {
		"name": "Wraith",
		"hitbox": Vector2(24, 40),
		"hp_mult": 0.7,
		"speed": 110.0,
		"vertical": 1.0,
		"min_slots": 1, "max_slots": 2,
		"stagger_resist": 1.0,  # "None" stagger = never staggers
		"move_ai": MoveAI.DRIFTER,
		"texture_size": Vector2i(20, 32),
		"sprite_scale": 1.1,
		"camera_zoom": 1.8,
	},
}

static func get_data(body_type: int) -> Dictionary:
	return DATA.get(body_type, DATA[BodyType.SKIRMISHER])

static func get_type_name(body_type: int) -> String:
	return get_data(body_type)["name"]

# Difficulty-weighted body type roll (Axis 4 step 1).
static func roll_body_type(difficulty: float, rng: RandomNumberGenerator) -> int:
	var weights: Dictionary
	if difficulty < 0.3:
		weights = {
			BodyType.SKITTERER: 35, BodyType.SKIRMISHER: 35,
			BodyType.BRUISER: 20, BodyType.SENTINEL: 10,
		}
	elif difficulty <= 0.7:
		weights = {
			BodyType.SKIRMISHER: 30, BodyType.BRUISER: 25,
			BodyType.SENTINEL: 20, BodyType.STALKER: 15,
			BodyType.SKITTERER: 10,
		}
	else:
		weights = {
			BodyType.COLOSSUS: 25, BodyType.STALKER: 20,
			BodyType.SKIRMISHER: 20, BodyType.WRAITH: 15,
			BodyType.SENTINEL: 10, BodyType.BRUISER: 10,
		}
	var total := 0
	for w in weights.values():
		total += w
	var roll := rng.randi_range(1, total)
	var acc := 0
	for bt in weights:
		acc += weights[bt]
		if roll <= acc:
			return bt
	return BodyType.SKIRMISHER
