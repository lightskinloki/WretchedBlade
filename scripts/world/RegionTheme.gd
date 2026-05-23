extends RefCounted
class_name RegionTheme

enum HexTheme { GEOCRASH, VOIDREND, ECHOSCREAM, MEMOREAVE, NULLPULSE, TECHNOMANTIC }

const TILE_EMPTY := 0
const TILE_FLOOR := 1
const TILE_WALL := 2
const TILE_PLATFORM := 3

static func get_theme_name(theme: int) -> String:
	match theme:
		HexTheme.GEOCRASH: return "Geocrash"
		HexTheme.VOIDREND: return "Voidrend"
		HexTheme.ECHOSCREAM: return "Echoscream"
		HexTheme.MEMOREAVE: return "Memoreave"
		HexTheme.NULLPULSE: return "Nullpulse"
		HexTheme.TECHNOMANTIC: return "Technomantic"
	return "Unknown"

static func get_theme_data(theme: int) -> Dictionary:
	match theme:
		HexTheme.GEOCRASH:
			return {
				"name": "Geocrash",
				"tile_colors": {
					"floor": Color(0.35, 0.29, 0.23),
					"wall": Color(0.23, 0.16, 0.10),
					"platform": Color(0.41, 0.35, 0.29),
					"bg": Color(0.10, 0.07, 0.06),
				},
				"decor_chance": 0.3,
				"decor_types": ["spike", "rubble", "crack"],
			}
		HexTheme.VOIDREND:
			return {
				"name": "Voidrend",
				"tile_colors": {
					"floor": Color(0.23, 0.16, 0.29),
					"wall": Color(0.10, 0.04, 0.16),
					"platform": Color(0.29, 0.23, 0.35),
					"bg": Color(0.04, 0.00, 0.07),
				},
				"decor_chance": 0.4,
				"decor_types": ["tear", "debris", "drift"],
			}
		HexTheme.ECHOSCREAM:
			return {
				"name": "Echoscream",
				"tile_colors": {
					"floor": Color(0.29, 0.16, 0.16),
					"wall": Color(0.16, 0.10, 0.10),
					"platform": Color(0.35, 0.23, 0.23),
					"bg": Color(0.09, 0.04, 0.04),
				},
				"decor_chance": 0.5,
				"decor_types": ["pulse", "vein", "membrane"],
			}
		HexTheme.MEMOREAVE:
			return {
				"name": "Memoreave",
				"tile_colors": {
					"floor": Color(0.16, 0.29, 0.23),
					"wall": Color(0.10, 0.16, 0.16),
					"platform": Color(0.23, 0.35, 0.29),
					"bg": Color(0.04, 0.08, 0.07),
				},
				"decor_chance": 0.35,
				"decor_types": ["glitch", "overlap", "flicker"],
			}
		HexTheme.NULLPULSE:
			return {
				"name": "Nullpulse",
				"tile_colors": {
					"floor": Color(0.16, 0.16, 0.16),
					"wall": Color(0.10, 0.10, 0.10),
					"platform": Color(0.23, 0.23, 0.23),
					"bg": Color(0.04, 0.04, 0.04),
				},
				"decor_chance": 0.2,
				"decor_types": ["void", "absence", "edge"],
			}
		HexTheme.TECHNOMANTIC:
			return {
				"name": "Technomantic",
				"tile_colors": {
					"floor": Color(0.29, 0.29, 0.35),
					"wall": Color(0.16, 0.16, 0.23),
					"platform": Color(0.35, 0.35, 0.41),
					"bg": Color(0.07, 0.06, 0.10),
				},
				"decor_chance": 0.4,
				"decor_types": ["panel", "conduit", "glyph"],
			}
	return get_theme_data(HexTheme.GEOCRASH)

static func apply_shape_modifier(grid: Array, theme: int, rng: RandomNumberGenerator, w: int, h: int) -> void:
	match theme:
		HexTheme.GEOCRASH: _mod_geocrash(grid, rng, w, h)
		HexTheme.VOIDREND: _mod_voidrend(grid, rng, w, h)
		HexTheme.ECHOSCREAM: _mod_echoscream(grid, rng, w, h)
		HexTheme.MEMOREAVE: _mod_memoreave(grid, rng, w, h)
		HexTheme.NULLPULSE: _mod_nullpulse(grid, rng, w, h)
		HexTheme.TECHNOMANTIC: _mod_technomantic(grid, rng, w, h)

static func _tile_at(grid: Array, x: int, y: int) -> int:
	if y < 0 or y >= grid.size() or x < 0 or x >= grid[0].size():
		return -1
	return grid[y][x]

static func _mod_geocrash(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	for y in range(2, h - 2):
		for x in [0, w - 1]:
			if _tile_at(grid, x, y) == TILE_WALL and rng.randf() < 0.3:
				var dir := 1 if x == 0 else -1
				var spike_len := rng.randi_range(1, 3)
				for s in range(1, spike_len + 1):
					var sx: int = x + dir * s
					if _tile_at(grid, sx, y) == TILE_EMPTY:
						grid[y][sx] = TILE_PLATFORM
					else:
						break

static func _mod_voidrend(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	for _i in range(rng.randi_range(1, 3)):
		var dx := rng.randi_range(3, w - 4)
		var dy := rng.randi_range(3, h - 6)
		if _tile_at(grid, dx, dy) == TILE_EMPTY:
			grid[dy][dx] = TILE_PLATFORM
			if rng.randf() < 0.4:
				grid[dy + 1][dx] = TILE_PLATFORM
	for _i in range(rng.randi_range(1, 4)):
		var tx := rng.randi_range(0, 2) if rng.randf() < 0.5 else w - 1 - rng.randi_range(0, 2)
		var ty := rng.randi_range(3, h - 4)
		if _tile_at(grid, tx, ty) == TILE_WALL:
			grid[ty][tx] = TILE_EMPTY

static func _mod_echoscream(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	for y in range(2, h - 2):
		for x in [0, w - 1]:
			if _tile_at(grid, x, y) == TILE_WALL and rng.randf() < 0.2:
				var dir := 1 if x == 0 else -1
				grid[y][x + dir] = TILE_FLOOR
				if rng.randf() < 0.3:
					grid[y + 1][x + dir] = TILE_FLOOR
	for y in range(3, h - 3):
		if rng.randf() < 0.1:
			for x in range(1, w - 1):
				if _tile_at(grid, y, x) == TILE_EMPTY and _tile_at(grid, y, x - 1) == TILE_WALL:
					var vlen := 0
					while x + vlen < w - 1 and _tile_at(grid, y, x + vlen) == TILE_EMPTY and vlen < 6:
						grid[y][x + vlen] = TILE_PLATFORM
						vlen += 1
					if vlen > 0:
						break

static func _mod_memoreave(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	for _i in range(rng.randi_range(1, 3)):
		var gx := rng.randi_range(2, w - 3)
		var gy := rng.randi_range(2, h - 3)
		if _tile_at(grid, gx, gy) == TILE_FLOOR:
			var dx := gx + (1 if rng.randf() < 0.5 else -1)
			var dy := gy + (1 if rng.randf() < 0.5 else -1)
			if _tile_at(grid, dx, dy) == TILE_EMPTY:
				grid[dy][dx] = TILE_FLOOR
	for _i in range(rng.randi_range(1, 2)):
		var ox := rng.randi_range(3, w - 5)
		var oy := rng.randi_range(3, h - 5)
		if _tile_at(grid, ox, oy) == TILE_PLATFORM:
			var gx := ox + rng.randi_range(-2, 2)
			var gy := oy + rng.randi_range(-1, 1)
			if _tile_at(grid, gx, gy) == TILE_EMPTY:
				grid[gy][gx] = TILE_PLATFORM

static func _mod_nullpulse(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	var cx := w / 2
	var cy := h - 5
	for _i in range(rng.randi_range(1, 2)):
		var ax := cx + rng.randi_range(-3, 3)
		var ay := cy + rng.randi_range(-1, 1)
		if _tile_at(grid, ax, ay) == TILE_PLATFORM:
			grid[ay][ax] = TILE_EMPTY
			if rng.randf() < 0.5 and _tile_at(grid, ax + 1, ay) == TILE_PLATFORM:
				grid[ay][ax + 1] = TILE_EMPTY
	for y in range(2, h - 2):
		for x in [0, w - 1]:
			if _tile_at(grid, x, y) == TILE_WALL and rng.randf() < 0.25:
				grid[y][x] = TILE_EMPTY

static func _mod_technomantic(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	for y in range(3, h - 3):
		for x in [2, w - 3]:
			if _tile_at(grid, x, y) == TILE_WALL and rng.randf() < 0.15:
				var dir := 1 if x < w / 2 else -1
				grid[y][x + dir] = TILE_PLATFORM
	for _i in range(rng.randi_range(1, 3)):
		var gx := rng.randi_range(4, w - 5)
		var gy := rng.randi_range(4, h - 5)
		if _tile_at(grid, gx, gy) == TILE_EMPTY and _tile_at(grid, gx + 1, gy) == TILE_EMPTY:
			grid[gy][gx] = TILE_PLATFORM
			grid[gy][gx + 1] = TILE_PLATFORM
			if rng.randf() < 0.5:
				grid[gy + 1][gx] = TILE_PLATFORM
				grid[gy + 1][gx + 1] = TILE_PLATFORM
