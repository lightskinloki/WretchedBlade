extends RefCounted
class_name RoomArchetype
# RoomArchetype.gd — archetype definitions for procedural room generation.
#
# Each archetype defines:
#   - Structural skeleton rules (how floor segments are arranged)
#   - Valid portal slots (where doorways can be placed)
#   - Dimension ranges (min/max width and height)
#   - A display name
#
# Skeleton functions are called by RoomTerrainGenerator during Pass 2.
# They produce the raw structural layout (floor, platforms, air) without
# doorways — those are carved later by the portal system.

# ── Tile type constants (shared with WorldGenerator) ──────────────────────────
const TILE_EMPTY    := 0
const TILE_FLOOR    := 1
const TILE_WALL     := 2
const TILE_PLATFORM := 3

# ── Archetype enum ────────────────────────────────────────────────────────────
enum Archetype {
	GUARD_POST,      # Combat — raised sentry, choke at entrance, collapsed rear
	BRIDGE_SPAN,     # Combat/Transition — narrow, spanning gap, variable height
	STORAGE_VAULT,   # Exploration — wide, pillars, alcoves, hidden pockets
	RITUAL_CHAMBER,  # Puzzle/Boss — central focal point, structured geometry
	COLLAPSED_HALL,  # Combat — rubble heaps as platforms, blocked sightlines
	WATCHTOWER,      # Transition — vertical climb, windows to void
	QUARRY,          # Combat — open horizontal, waist-high cover, edge pits
	SANCTUARY,       # Safe — small, minimal, clear sightlines, calm geometry
	BOSS_ARENA,      # Boss — wide open floor, perimeter ledges, pillar clusters
}

# ── PortalSlot — static doorway definition per archetype ──────────────────────
class PortalSlot:
	var slot_id: String
	var side: String        # "left", "right", "top", "bottom"
	var height_band: String # "ground", "mid", "high"
	var tile_w: int         # doorway width in tiles (typically 2)
	var tile_h: int         # doorway height in tiles (typically 5)

	func _init(id: String, sd: String, hb: String, tw: int, th: int) -> void:
		slot_id = id
		side = sd
		height_band = hb
		tile_w = tw
		tile_h = th

	# Returns the top-left tile position of this slot within a room.
	func get_tile_position(room_w: int, room_h: int) -> Vector2i:
		var y: int
		match height_band:
			"ground": y = room_h - 4 - tile_h + 2
			"mid":    y = room_h / 2 - tile_h / 2
			"high":   y = 2
		match side:
			"left":   return Vector2i(0, y)
			"right":  return Vector2i(room_w - tile_w, y)
			_:
				push_error("PortalSlot: unsupported side '%s'" % side)
				return Vector2i(0, y)

	# Returns the tile position of the walkable floor inside the room
	# (the tile just past the doorway, at floor height).
	func get_floor_anchor(room_w: int, room_h: int) -> Vector2i:
		var pos := get_tile_position(room_w, room_h)
		var fy := pos.y + tile_h - 2
		var fx: int
		if side == "left":
			fx = pos.x + tile_w
		else:
			fx = pos.x - 1
		return Vector2i(fx, fy)

# ── PortalData — runtime portal instance connecting two rooms ─────────────────
class PortalData:
	var slot_id: String
	var connected_node: int
	var is_open: bool
	var locked_by_room: int

	func _init(sid: String, node: int, open: bool = true, locked: int = -1) -> void:
		slot_id = sid
		connected_node = node
		is_open = open
		locked_by_room = locked

# ── Static queries ────────────────────────────────────────────────────────────
static func get_archetype_name(archetype: int) -> String:
	match archetype:
		Archetype.GUARD_POST:      return "Guard Post"
		Archetype.BRIDGE_SPAN:     return "Bridge Span"
		Archetype.STORAGE_VAULT:   return "Storage Vault"
		Archetype.RITUAL_CHAMBER:  return "Ritual Chamber"
		Archetype.COLLAPSED_HALL:  return "Collapsed Hall"
		Archetype.WATCHTOWER:      return "Watchtower"
		Archetype.QUARRY:          return "Quarry"
		Archetype.SANCTUARY:       return "Sanctuary"
		Archetype.BOSS_ARENA:      return "Boss Arena"
		_:                         return "Unknown"

static func get_dimension_range(archetype: int, complexity: float = -1.0) -> Dictionary:
	var base_range: Dictionary
	match archetype:
		Archetype.GUARD_POST:     base_range = {"min_w": 120, "max_w": 170, "min_h": 80, "max_h": 120}
		Archetype.BRIDGE_SPAN:    base_range = {"min_w": 140, "max_w": 200, "min_h": 70, "max_h": 110}
		Archetype.STORAGE_VAULT:  base_range = {"min_w": 130, "max_w": 180, "min_h": 85, "max_h": 130}
		Archetype.RITUAL_CHAMBER: base_range = {"min_w": 120, "max_w": 160, "min_h": 80, "max_h": 120}
		Archetype.COLLAPSED_HALL: base_range = {"min_w": 130, "max_w": 180, "min_h": 80, "max_h": 120}
		Archetype.WATCHTOWER:     base_range = {"min_w": 60, "max_w": 90, "min_h": 120, "max_h": 180}
		Archetype.QUARRY:         base_range = {"min_w": 140, "max_w": 190, "min_h": 80, "max_h": 120}
		Archetype.SANCTUARY:      base_range = {"min_w": 36, "max_w": 48, "min_h": 22, "max_h": 30}
		Archetype.BOSS_ARENA:     base_range = {"min_w": 150, "max_w": 220, "min_h": 90, "max_h": 140}
		_:                        base_range = {"min_w": 120, "max_w": 170, "min_h": 80, "max_h": 120}

	if complexity >= 0.0:
		var cx := clampf(complexity, 0.0, 1.0)
		base_range["target_w"] = int(lerpf(float(base_range.min_w), float(base_range.max_w), cx))
		base_range["target_h"] = int(lerpf(float(base_range.min_h), float(base_range.max_h), cx))
	return base_range

static func get_available_portal_slots(archetype: int) -> Array[PortalSlot]:
	match archetype:
		Archetype.GUARD_POST:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		Archetype.BRIDGE_SPAN:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		Archetype.STORAGE_VAULT:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		Archetype.RITUAL_CHAMBER:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		Archetype.COLLAPSED_HALL:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		Archetype.WATCHTOWER:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("left-high", "left", "high", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		Archetype.QUARRY:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		Archetype.SANCTUARY:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
			]
		Archetype.BOSS_ARENA:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("left-high", "left", "high", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]
		_:
			return [
				PortalSlot.new("left-ground", "left", "ground", 2, 5),
				PortalSlot.new("left-mid", "left", "mid", 2, 5),
				PortalSlot.new("right-ground", "right", "ground", 2, 5),
				PortalSlot.new("right-mid", "right", "mid", 2, 5),
				PortalSlot.new("right-high", "right", "high", 2, 5),
			]

# ── Skeleton application — called by RoomTerrainGenerator during Pass 2 ──────
# Phase B: builds walkable path between all portals, then adds archetype character.
# Portals array elements are PortalData objects; available_slots are PortalSlot defs.
static func apply_skeleton(grid: Array, archetype: int, rng: RandomNumberGenerator, w: int, h: int, portals: Array = [], available_slots: Array[PortalSlot] = [], complexity: float = 0.5) -> void:
	_connect_portal_floors(grid, _get_portal_anchors(portals, available_slots, w, h), w, h)
	match archetype:
		Archetype.GUARD_POST:     _skeleton_guard_post(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.BRIDGE_SPAN:    _skeleton_bridge_span(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.SANCTUARY:      _skeleton_sanctuary(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.STORAGE_VAULT:  _skeleton_storage_vault(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.COLLAPSED_HALL: _skeleton_collapsed_hall(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.RITUAL_CHAMBER: _skeleton_ritual_chamber(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.WATCHTOWER:     _skeleton_watchtower(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.QUARRY:         _skeleton_quarry(grid, rng, w, h, portals, available_slots, complexity)
		Archetype.BOSS_ARENA:     _skeleton_boss_arena(grid, rng, w, h, portals, available_slots, complexity)
		_:                        _skeleton_guard_post(grid, rng, w, h, portals, available_slots, complexity)

# ── Portal anchor extraction ───────────────────────────────────────────────────
static func _get_portal_anchors(portals: Array, available_slots: Array[PortalSlot], w: int, h: int) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	for portal in portals:
		if portal == null or portal.slot_id.is_empty():
			continue
		var slot := _find_slot(portal.slot_id, available_slots)
		if slot != null:
			anchors.append(slot.get_floor_anchor(w, h))
	return anchors

static func _find_slot(slot_id: String, slots: Array[PortalSlot]) -> PortalSlot:
	for s in slots:
		if s.slot_id == slot_id:
			return s
	return null

# ── Portal floor connection ───────────────────────────────────────────────────
# Builds a walkable 2-tile-thick floor path connecting all portal anchors.
# Sorts anchors by X and connects adjacent pairs with linear interpolation.
# For a single portal (dead end), places a small platform at the anchor.
static func _connect_portal_floors(grid: Array, anchors: Array[Vector2i], w: int, h: int) -> void:
	if anchors.is_empty():
		return
	if anchors.size() == 1:
		var a := anchors[0]
		var sx := 2
		var ex := w - 3
		for x in range(sx, ex + 1):
			if a.y >= 0 and a.y < h:
				grid[a.y][x] = TILE_FLOOR
			if a.y + 1 < h:
				grid[a.y + 1][x] = TILE_FLOOR
			if x > 0 and x < w - 1:
				var air_top := maxi(2, a.y - 6)
				for ay in range(air_top, a.y):
					grid[ay][x] = TILE_EMPTY
		return

	anchors.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x)
	for i in range(anchors.size() - 1):
		_connect_two_floors(grid, anchors[i], anchors[i + 1], w, h)

static func _connect_two_floors(grid: Array, a: Vector2i, b: Vector2i, w: int, h: int) -> void:
	var x1 := a.x
	var x2 := b.x
	var y1 := a.y
	var y2 := b.y

	if x1 > x2:
		var tmp := x1; x1 = x2; x2 = tmp
		tmp = y1; y1 = y2; y2 = tmp

	if x1 >= w or x2 < 0:
		return

	x1 = maxi(0, x1)
	x2 = mini(w - 1, x2)

	var dx := x2 - x1
	if dx <= 0:
		# Same column — build a staircase to the right (x increasing) so the
		# player can walk between heights without a solid vertical wall.
		# Limited to sy >= 7 (min_step_y) so steps have enough headroom
		# (5 rows ceiling clearance). Extends a flat walkway from the top
		# of the staircase back to the portal anchor column.
		var y_top := mini(y1, y2)
		var y_bot := maxi(y1, y2)
		var steps := y_bot - y_top
		if steps <= 1:
			# Identical or adjacent anchors: place a small platform so the
			# anchor tile always has walkable floor.
			var fy := y1
			for fx in range(maxi(0, x1 - 2), mini(w, x2 + 3)):
				if fy >= 0 and fy < h:
					grid[fy][fx] = TILE_FLOOR
				if fy + 1 < h:
					grid[fy + 1][fx] = TILE_FLOOR
			return
		var min_step_y := 7
		var safe_top := maxi(y_top, min_step_y)
		var safe_steps := maxi(0, y_bot - safe_top)
		var sx := x1
		for step in range(safe_steps + 1):
			var sy := y_bot - step
			if sx >= 0 and sx < w:
				if sy >= 0 and sy < h:
					grid[sy][sx] = TILE_FLOOR
				if sy + 1 >= 0 and sy + 1 < h:
					grid[sy + 1][sx] = TILE_FLOOR
				if sx > 0 and sx < w - 1:
					for ay in range(2, sy):
						grid[ay][sx] = TILE_EMPTY
			sx += 1
			if sx >= w:
				break
		# Flat walkway at safe_top from x1 to staircase end
		var walkway_end := maxi(x1, x1 + safe_steps)
		for wx in range(x1, walkway_end + 1):
			if wx >= 0 and wx < w:
				if safe_top >= 0 and safe_top < h:
					grid[safe_top][wx] = TILE_FLOOR
				if safe_top + 1 >= 0 and safe_top + 1 < h:
					grid[safe_top + 1][wx] = TILE_FLOOR
				if wx > 0 and wx < w - 1:
					for ay in range(2, safe_top):
						grid[ay][wx] = TILE_EMPTY
		return

	for x in range(x1, x2 + 1):
		var t := float(x - x1) / float(dx)
		var y := int(roundf(lerpf(float(y1), float(y2), t)))
		y = clampi(y, 2, h - 3)

		grid[y][x] = TILE_FLOOR
		if y + 1 < h:
			grid[y + 1][x] = TILE_FLOOR

		if x > 0 and x < w - 1:
			for ay in range(2, y):
				grid[ay][x] = TILE_EMPTY

# ── Path-safe placement helpers ───────────────────────────────────────────────
# Returns true if the tile at (x, y) is part of the walkable path floor.
static func _is_on_path(grid: Array, x: int, y: int, w: int, h: int) -> bool:
	if x < 0 or x >= w or y < 0 or y >= h:
		return false
	return grid[y][x] == TILE_FLOOR

# Places a tile only if it will not overwrite path floor.
static func _place_off_path(grid: Array, x: int, y: int, tile: int, w: int, h: int) -> void:
	if x < 0 or x >= w or y < 0 or y >= h:
		return
	if grid[y][x] == TILE_FLOOR:
		return
	grid[y][x] = tile

# Returns the lowest (smallest y) and highest (largest y) portal floor anchors.
static func _get_anchor_y_range(portals: Array, available_slots: Array[PortalSlot], w: int, h: int) -> Vector2i:
	var anchors := _get_portal_anchors(portals, available_slots, w, h)
	if anchors.is_empty():
		return Vector2i(maxi(2, h - 2), maxi(2, h - 2))
	var lo := h
	var hi := 0
	for a in anchors:
		if a.y < lo: lo = a.y
		if a.y > hi: hi = a.y
	return Vector2i(lo, hi)

# ── Macro-Section Carving Primitives ──────────────────────────────────────────
# Carves a full-sized chamber (rw x rh) into solid bedrock.
# Hollows interior with TILE_EMPTY and puts solid TILE_FLOOR on the bottom 2 rows.
static func _carve_chamber(grid: Array, rx: int, ry: int, rw: int, rh: int, w: int, h: int) -> void:
	rx = clampi(rx, 2, w - rw - 2)
	ry = clampi(ry, 2, h - rh - 2)
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			if y >= 0 and y < h and x >= 0 and x < w:
				if y >= ry + rh - 2:
					grid[y][x] = TILE_FLOOR
				else:
					grid[y][x] = TILE_EMPTY

# Carves a horizontal corridor through bedrock connecting two X positions at height y.
static func _carve_tunnel_h(grid: Array, x1: int, x2: int, y: int, tunnel_h: int, w: int, h: int) -> void:
	var min_x := mini(x1, x2)
	var max_x := maxi(x1, x2)
	for x in range(maxi(1, min_x), mini(w - 1, max_x + 1)):
		for dy in range(tunnel_h):
			var ty := y + dy
			if ty >= 0 and ty < h:
				if dy >= tunnel_h - 2:
					grid[ty][x] = TILE_FLOOR
				else:
					grid[ty][x] = TILE_EMPTY

# Carves a vertical shaft through bedrock connecting two Y positions at column x.
# Includes step platforms every 3 tiles so the player can jump/ascend vertically.
static func _carve_tunnel_v(grid: Array, x: int, y1: int, y2: int, tunnel_w: int, w: int, h: int) -> void:
	var min_y := mini(y1, y2)
	var max_y := maxi(y1, y2)
	var step_side := 0
	for y in range(maxi(1, min_y), mini(h - 1, max_y + 1)):
		for dx in range(tunnel_w):
			var tx := x + dx
			if tx >= 0 and tx < w:
				grid[y][tx] = TILE_EMPTY
		if y % 3 == 0 and y < max_y - 2:
			var px := x if step_side == 0 else x + tunnel_w - 2
			px = clampi(px, 1, w - 2)
			grid[y][px] = TILE_PLATFORM
			if px + 1 < w:
				grid[y][px + 1] = TILE_PLATFORM
			step_side = 1 - step_side

# Carves a diagonal stairwell corridor connecting (x1, y1) to (x2, y2).
static func _carve_stairwell(grid: Array, x1: int, y1: int, x2: int, y2: int, w: int, h: int) -> void:
	var steps: int = absi(x2 - x1)
	if steps == 0:
		return
	var dx_sign: int = 1 if x2 > x1 else -1
	var dy_sign: int = 1 if y2 > y1 else -1
	var y_step: float = float(absi(y2 - y1)) / float(steps)
	
	for i in range(steps + 1):
		var cx := x1 + i * dx_sign
		var cy := int(float(y1) + float(i) * y_step * float(dy_sign))
		for dy in range(-3, 2):
			var ty := cy + dy
			if cx >= 0 and cx < w and ty >= 0 and ty < h:
				if dy >= 0:
					grid[ty][cx] = TILE_FLOOR
				else:
					grid[ty][cx] = TILE_EMPTY

# ── Guard Post ────────────────────────────────────────────────────────────────
# Macro-Section: 4 full-sized chambers (40-48 x 22-26 tiles) carved from bedrock.
static func _skeleton_guard_post(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	
	# Chamber 1: Entry Guardhouse (44x24 tiles) at portal anchor height
	var c1_w := mini(44, w / 3); var c1_h := mini(24, h / 3)
	var c1_x := 4; var c1_y := clampi(floor_lo - 20, 4, h - 28)
	_carve_chamber(grid, c1_x, c1_y, c1_w, c1_h, w, h)

	# Chamber 2: Central Patrol Hall (48x26 tiles) in upper-middle height
	var c2_w := mini(48, w / 3); var c2_h := mini(26, h / 3)
	var c2_x := clampi(w / 3, c1_x + c1_w + 4, w - c2_w - 4)
	var c2_y := clampi(h / 3, 4, h - c2_h - 4)
	_carve_chamber(grid, c2_x, c2_y, c2_w, c2_h, w, h)

	# Chamber 3: Upper Lookout Tower (40x22 tiles) at top right
	var c3_w := mini(40, w / 3); var c3_h := mini(22, h / 3)
	var c3_x := clampi(w * 2 / 3, c2_x + c2_w + 4, w - c3_w - 4)
	var c3_y := clampi(4, 4, c2_y)
	_carve_chamber(grid, c3_x, c3_y, c3_w, c3_h, w, h)

	# Chamber 4: Lower Armory Basement (44x20 tiles) at bottom
	var c4_w := mini(44, w / 3); var c4_h := mini(20, h / 4)
	var c4_x := clampi(w / 2 - 20, c1_x + 10, w - c4_w - 4)
	var c4_y := clampi(h - c4_h - 4, c2_y + 10, h - c4_h - 2)
	_carve_chamber(grid, c4_x, c4_y, c4_w, c4_h, w, h)

	# Carve connecting tunnels through bedrock
	_carve_tunnel_h(grid, c1_x + c1_w - 2, c2_x + 4, c1_y + c1_h - 4, 4, w, h)
	_carve_stairwell(grid, c2_x + c2_w - 4, c2_y + 4, c3_x + 4, c3_y + c3_h - 2, w, h)
	_carve_tunnel_v(grid, c2_x + 10, c2_y + c2_h - 2, c4_y + 2, 3, w, h)
	_carve_tunnel_h(grid, c3_x + c3_w - 2, w - 4, c3_y + c3_h - 4, 4, w, h)

# ── Bridge Span ───────────────────────────────────────────────────────────────
# Macro-Section: Multi-level chasm complex with 4 full-sized chambers.
static func _skeleton_bridge_span(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Chamber 1: West Bridge Anchor (44x24 tiles)
	var c1_w := mini(44, w / 3); var c1_h := mini(24, h / 3)
	var c1_x := 4; var c1_y := clampi(floor_lo - 20, 4, h - 28)
	_carve_chamber(grid, c1_x, c1_y, c1_w, c1_h, w, h)

	# Chamber 2: Upper Suspension Bridge Hall (60x24 tiles) spanning top center
	var c2_w := mini(60, w / 2); var c2_h := mini(24, h / 3)
	var c2_x := clampi(w / 3, c1_x + c1_w + 4, w - c2_w - 4)
	var c2_y := clampi(6, 4, h - c2_h - 4)
	_carve_chamber(grid, c2_x, c2_y, c2_w, c2_h, w, h)

	# Chamber 3: Secondary Bridge Vault (44x22 tiles)
	var c3_w := mini(44, w / 3); var c3_h := mini(22, h / 3)
	var c3_x := clampi(w * 2 / 3, c2_x + c2_w + 4, w - c3_w - 4)
	var c3_y := clampi(c2_y + 12, c2_y + 6, h - c3_h - 4)
	_carve_chamber(grid, c3_x, c3_y, c3_w, c3_h, w, h)

	# Chamber 4: Abyssal Cavern Basin (50x22 tiles) at bottom
	var c4_w := mini(50, w / 2); var c4_h := mini(22, h / 4)
	var c4_x := clampi(w / 3, 10, w - c4_w - 4)
	var c4_y := clampi(h - c4_h - 4, c3_y + 6, h - c4_h - 2)
	_carve_chamber(grid, c4_x, c4_y, c4_w, c4_h, w, h)

	# Carve connecting tunnels, shafts, and abyssal drops
	_carve_stairwell(grid, c1_x + c1_w - 4, c1_y + c1_h - 2, c2_x + 4, c2_y + c2_h - 2, w, h)
	_carve_tunnel_h(grid, c2_x + c2_w - 2, c3_x + 4, c2_y + c2_h - 4, 4, w, h)
	_carve_tunnel_v(grid, c2_x + c2_w / 2, c2_y + c2_h - 2, c4_y + 2, 3, w, h)
	_carve_tunnel_h(grid, c3_x + c3_w - 2, w - 4, c3_y + c3_h - 4, 4, w, h)

# ── Sanctuary ─────────────────────────────────────────────────────────────────
# Macro-Section: Peaceful sanctuary complex with full-sized meditation hall.
static func _skeleton_sanctuary(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Main Meditation Hall (36x22 tiles)
	var c1_w := mini(36, w - 6); var c1_h := mini(22, h - 6)
	var c1_x := 4; var c1_y := clampi(floor_lo - c1_h + 2, 3, h - c1_h - 3)
	_carve_chamber(grid, c1_x, c1_y, c1_w, c1_h, w, h)

	# Flanking Reflection Alcove (30x18 tiles)
	var c2_w := mini(30, w - c1_w - 10); var c2_h := mini(18, h - 6)
	if c2_w >= 10:
		var c2_x := clampi(c1_x + c1_w + 4, c1_x + c1_w + 4, w - c2_w - 4)
		var c2_y := clampi(floor_lo - c2_h + 2, 3, h - c2_h - 3)
		_carve_chamber(grid, c2_x, c2_y, c2_w, c2_h, w, h)
		_carve_tunnel_h(grid, c1_x + c1_w - 2, c2_x + 4, c1_y + c1_h - 4, 4, w, h)
		_carve_tunnel_h(grid, c2_x + c2_w - 2, w - 4, c2_y + c2_h - 4, 4, w, h)
	else:
		_carve_tunnel_h(grid, c1_x + c1_w - 2, w - 4, c1_y + c1_h - 4, 4, w, h)

# ── Storage Vault ─────────────────────────────────────────────────────────────
static func _skeleton_storage_vault(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2
	var cy := h / 2
	
	var c1_x := clampi(cx - 44 - 6, 2, w - 46)
	var c1_y := clampi(cy - 24 - 4, 2, h - 26)
	_carve_chamber(grid, c1_x, c1_y, 44, 24, w, h)
	
	var c2_x := clampi(cx + 6, 2, w - 46)
	var c2_y := c1_y
	_carve_chamber(grid, c2_x, c2_y, 44, 24, w, h)
	
	var c3_x := c1_x
	var c3_y := clampi(cy + 4, 2, h - 26)
	_carve_chamber(grid, c3_x, c3_y, 44, 24, w, h)
	
	var c4_x := c2_x
	var c4_y := c3_y
	_carve_chamber(grid, c4_x, c4_y, 44, 24, w, h)
	
	_carve_tunnel_h(grid, c1_x + 44, c2_x, c1_y + 12, 4, w, h)
	_carve_tunnel_h(grid, c3_x + 44, c4_x, c3_y + 12, 4, w, h)
	
	_carve_tunnel_v(grid, c1_x + 22, c1_y + 24, c3_y, 3, w, h)
	_carve_tunnel_v(grid, c2_x + 22, c2_y + 24, c4_y, 3, w, h)
	
	var s_x := clampi(c4_x + 44 + 2, 2, w - 12)
	var s_y := clampi(c4_y + 4, 2, h - 12)
	_carve_chamber(grid, s_x, s_y, 10, 10, w, h)

# ── Collapsed Hall ────────────────────────────────────────────────────────────
static func _skeleton_collapsed_hall(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	
	var c1_x := clampi(w / 4 - 24, 2, w - 50)
	var c1_y := clampi(h / 6, 2, h - 28)
	_carve_chamber(grid, c1_x, c1_y, 48, 26, w, h)
	
	var c2_x := clampi(w * 3 / 4 - 24, 2, w - 50)
	var c2_y := clampi(h / 2 - 13, 2, h - 28)
	_carve_chamber(grid, c2_x, c2_y, 48, 26, w, h)
	
	var c3_x := clampi(w / 4 - 24, 2, w - 50)
	var c3_y := clampi(h * 5 / 6 - 26, 2, h - 28)
	_carve_chamber(grid, c3_x, c3_y, 48, 26, w, h)
	
	_carve_stairwell(grid, c1_x + 48, c1_y + 13, c2_x, c2_y + 13, w, h)
	_carve_stairwell(grid, c2_x, c2_y + 13, c3_x + 48, c3_y + 13, w, h)

# ── Ritual Chamber ────────────────────────────────────────────────────────────
static func _skeleton_ritual_chamber(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	
	var c1_x := 4
	var c1_y := clampi(floor_lo - 24, 2, h - 26)
	_carve_chamber(grid, c1_x, c1_y, 40, 24, w, h)
	
	var c2_x := clampi(w / 2 - 30, 2, w - 62)
	var c2_y := clampi(h / 2 - 16, 2, h - 34)
	_carve_chamber(grid, c2_x, c2_y, 60, 32, w, h)
	
	var c3_x := clampi(w / 2 - 22, 2, w - 46)
	var c3_y := clampi(h / 4 - 10, 2, h - 22)
	_carve_chamber(grid, c3_x, c3_y, 44, 20, w, h)
	
	var c4_x := clampi(w / 2 - 24, 2, w - 50)
	var c4_y := clampi(h * 3 / 4, 2, h - 24)
	_carve_chamber(grid, c4_x, c4_y, 48, 22, w, h)
	
	_carve_tunnel_h(grid, c1_x + 40, c2_x, c1_y + 12, 4, w, h)
	_carve_tunnel_v(grid, c3_x + 22, c3_y + 20, c2_y, 3, w, h)
	_carve_tunnel_v(grid, c2_x + 30, c2_y + 32, c4_y, 3, w, h)

# ── Watchtower ────────────────────────────────────────────────────────────────
static func _skeleton_watchtower(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2
	var tier_h := 22
	var gap := clampi((h - 4 * tier_h) / 5, 2, 20)
	for i in range(4):
		var cy := gap + i * (tier_h + gap)
		_carve_chamber(grid, cx - 22, cy, 44, tier_h, w, h)
		if i < 3:
			_carve_tunnel_v(grid, cx - 2, cy + tier_h, cy + tier_h + gap, 4, w, h)

# ── Quarry ────────────────────────────────────────────────────────────────────
static func _skeleton_quarry(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	
	var step_w := 48
	var step_h := 24
	var start_x := clampi(w / 6, 2, w - 150)
	var start_y := clampi(h / 6, 2, h - 100)
	for i in range(3):
		var cx := start_x + i * 20
		var cy := start_y + i * 20
		_carve_chamber(grid, cx, cy, step_w, step_h, w, h)
		if i < 2:
			_carve_stairwell(grid, cx + step_w, cy + step_h - 4, cx + step_w + 10, cy + 20 + step_h / 2, w, h)

# ── Boss Arena ─────────────────────────────────────────────────────────────────
static func _skeleton_boss_arena(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	
	var c1_x := 4
	var c1_y := clampi(floor_lo - 24, 2, h - 26)
	_carve_chamber(grid, c1_x, c1_y, 44, 24, w, h)
	
	var c2_x := clampi(w / 2 - 35, 2, w - 72)
	var c2_y := clampi(h / 2 - 20, 2, h - 42)
	_carve_chamber(grid, c2_x, c2_y, 70, 40, w, h)
	
	var c3_x := clampi(w - 44, 2, w - 42)
	var c3_y := clampi(h / 2 - 9, 2, h - 20)
	_carve_chamber(grid, c3_x, c3_y, 40, 18, w, h)
	
	_carve_tunnel_h(grid, c1_x + 44, c2_x, c1_y + 12, 4, w, h)
	_carve_tunnel_h(grid, c2_x + 70, c3_x, c3_y + 9, 4, w, h)
