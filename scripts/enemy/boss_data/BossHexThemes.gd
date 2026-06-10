extends RefCounted
class_name BossHexThemes
# BossHexThemes.gd — Axis 2 data: hex theme visual palettes and hazard pools.
# Themes map 1:1 to RegionTheme.HexTheme. Composite is final-boss only and is
# intentionally absent — dungeon bosses never roll it.

const DATA := {
	RegionTheme.HexTheme.GEOCRASH: {
		"name": "Geocrash",
		"primary": Color(0.55, 0.40, 0.22, 1.0),   # earthen brown
		"secondary": Color(0.85, 0.65, 0.25, 1.0), # amber
		"accent": Color(0.45, 0.45, 0.45, 1.0),    # gray
		"glow": Color(0.95, 0.75, 0.30, 1.0),
		"texture": "cracks",
		"hazards": ["collapsing_floor", "rising_pillars", "rubble_piles"],
	},
	RegionTheme.HexTheme.VOIDREND: {
		"name": "Voidrend",
		"primary": Color(0.22, 0.05, 0.35, 1.0),   # deep purple
		"secondary": Color(0.05, 0.05, 0.08, 1.0), # black
		"accent": Color(0.25, 0.85, 0.30, 1.0),    # toxic green
		"glow": Color(0.60, 0.20, 0.95, 1.0),
		"texture": "voronoi",
		"hazards": ["void_pool", "darkness_zone", "teleport_pad"],
	},
	RegionTheme.HexTheme.ECHOSCREAM: {
		"name": "Echoscream",
		"primary": Color(0.85, 0.90, 0.95, 1.0),   # white
		"secondary": Color(0.30, 0.80, 0.90, 1.0), # cyan
		"accent": Color(0.20, 0.40, 0.90, 1.0),    # blue
		"glow": Color(0.55, 0.90, 1.00, 1.0),
		"texture": "rings",
		"hazards": ["resonance_crystal", "echo_field"],
	},
	RegionTheme.HexTheme.MEMOREAVE: {
		"name": "Memoreave",
		"primary": Color(0.90, 0.55, 0.75, 1.0),   # pink
		"secondary": Color(0.55, 0.30, 0.80, 1.0), # violet
		"accent": Color(0.95, 0.92, 0.98, 0.8),    # translucent white
		"glow": Color(0.95, 0.60, 0.95, 1.0),
		"texture": "fractal",
		"hazards": ["confusion_field", "illusion_wall", "memory_fragment"],
	},
	RegionTheme.HexTheme.NULLPULSE: {
		"name": "Nullpulse",
		"primary": Color(0.95, 0.95, 0.95, 1.0),   # white-void
		"secondary": Color(0.80, 0.10, 0.15, 1.0), # crimson
		"accent": Color(0.50, 0.05, 0.10, 1.0),
		"glow": Color(1.00, 0.30, 0.35, 1.0),
		"texture": "radial",
		"hazards": ["corruption_cyst", "null_zone", "pulse_node"],
	},
	RegionTheme.HexTheme.TECHNOMANTIC: {
		"name": "Technomantic",
		"primary": Color(0.45, 0.48, 0.52, 1.0),   # steel gray
		"secondary": Color(0.95, 0.55, 0.15, 1.0), # orange glow
		"accent": Color(0.25, 0.65, 0.95, 1.0),    # electric blue
		"glow": Color(1.00, 0.65, 0.20, 1.0),
		"texture": "grid",
		"hazards": ["wall_turret", "tesla_coil", "conveyor"],
	},
}

static func get_data(theme: int) -> Dictionary:
	return DATA.get(theme, DATA[RegionTheme.HexTheme.GEOCRASH])

static func get_theme_name(theme: int) -> String:
	return get_data(theme)["name"]

# Picks 0-2 hazards from the theme pool based on difficulty (Axis 8).
static func roll_hazards(theme: int, difficulty: float, rng: RandomNumberGenerator) -> Array:
	var pool: Array = get_data(theme)["hazards"].duplicate()
	var count := 0
	if difficulty >= 0.7:
		count = 2
	elif difficulty >= 0.35:
		count = 1
	var picked: Array = []
	for i in range(mini(count, pool.size())):
		var idx := rng.randi_range(0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked
