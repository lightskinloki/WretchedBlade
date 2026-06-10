extends Resource
class_name HexAbility
# HexAbility.gd — data definition for a hex ability.
#
# Each hex has a unique input trigger, a damage pattern, resource costs,
# and lore text.  The input_definition field is a Dictionary whose structure
# varies by "type" — see InputBuffer.gd for the supported matchers.

enum HexTheme {
	GEOCRASH,     # 0 — geometry, stone, fracture
	VOIDREND,     # 1 — shadow, void, absence
	ECHOSCREAM,   # 2 — sound, sonics, resonance
	MEMOREAVE,    # 3 — memory, mind, psychic
	NULLPULSE,    # 4 — entropy, essence, raw null
	TECHNOMANTIC, # 5 — technology, metal, grid
	COMPOSITE,    # 6 — all themes resonating (reserved)
}

@export var id: String
@export var display_name: String
@export_multiline var lore_blurb: String

@export var theme: HexTheme = HexTheme.NULLPULSE

# Input trigger definition — structure depends on type:
#   "hold":     { "type": "hold",     "button": "attack", "duration": 0.4 }
#   "combo":    { "type": "combo",    "sequence": ["atk", "atk", "atk"] }
#   "sequence": { "type": "sequence", "sequence": ["atk", "counter"] }
@export var input_definition: Dictionary = {}

# Damage pattern passed to HexBreakableTile.take_hex_damage():
#   "circle": { "type": "circle", "radius": 48.0 }
#   "line":   { "type": "line",   "direction": Vector2.RIGHT, "half_width": 2.0 }
@export var pattern: Dictionary = {}

# Resource costs and limits
@export var essence_cost: int   = 10
@export var cooldown: float     = 12.0
@export var wall_damage: int    = 1   # Hits to destroy a HexBreakableTile
@export var enemy_damage: int   = 6
@export var range: float        = 48.0  # Effective radius or line length
