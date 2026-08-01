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
		Archetype.GUARD_POST:     base_range = {"min_w": 52, "max_w": 76, "min_h": 36, "max_h": 52}
		Archetype.BRIDGE_SPAN:    base_range = {"min_w": 64, "max_w": 88, "min_h": 36, "max_h": 48}
		Archetype.STORAGE_VAULT:  base_range = {"min_w": 56, "max_w": 76, "min_h": 38, "max_h": 52}
		Archetype.RITUAL_CHAMBER: base_range = {"min_w": 48, "max_w": 68, "min_h": 36, "max_h": 48}
		Archetype.COLLAPSED_HALL: base_range = {"min_w": 52, "max_w": 72, "min_h": 36, "max_h": 48}
		Archetype.WATCHTOWER:     base_range = {"min_w": 28, "max_w": 42, "min_h": 44, "max_h": 64}
		Archetype.QUARRY:         base_range = {"min_w": 56, "max_w": 76, "min_h": 36, "max_h": 48}
		Archetype.SANCTUARY:      base_range = {"min_w": 28, "max_w": 38, "min_h": 20, "max_h": 28}
		Archetype.BOSS_ARENA:     base_range = {"min_w": 64, "max_w": 92, "min_h": 40, "max_h": 56}
		_:                        base_range = {"min_w": 52, "max_w": 76, "min_h": 36, "max_h": 52}

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

# ── Guard Post ────────────────────────────────────────────────────────────────
static func _skeleton_guard_post(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2

	# Upper lookout platform (y ~ 30% height)
	var lookout_y := clampi(int(float(h) * 0.3), 3, h - 5)
	var lookout_w := clampi(int(float(w) / 6.0 * (0.5 + complexity)), 4, 10)
	var lookout_x := cx - lookout_w / 2
	for dx in range(lookout_w):
		_place_off_path(grid, lookout_x + dx, lookout_y, TILE_FLOOR, w, h)
		_place_off_path(grid, lookout_x + dx, lookout_y + 1, TILE_FLOOR, w, h)
		# Support columns under the platform
		if dx == 0 or dx == lookout_w - 1:
			for ty in range(lookout_y + 2, floor_lo):
				_place_off_path(grid, lookout_x + dx, ty, TILE_WALL, w, h)
	
	# Mid-level patrol bridge connecting left/right walls
	var bridge_y := lookout_y + clampi(int(float(floor_lo - lookout_y) / 2.0), 3, 6)
	var gap_x := rng.randi_range(w / 3, w * 2 / 3)
	for tx in range(1, w - 1):
		if abs(tx - gap_x) > 2: # 4-5 tile gap
			_place_off_path(grid, tx, bridge_y, TILE_PLATFORM, w, h)

	# 2-tile wide access shaft below lookout
	var shaft_x := lookout_x + lookout_w / 2 - 1
	for ty in range(lookout_y + 2, bridge_y):
		_place_off_path(grid, shaft_x, ty, TILE_EMPTY, w, h)
		_place_off_path(grid, shaft_x + 1, ty, TILE_EMPTY, w, h)
		if ty % 3 == 0:
			_place_off_path(grid, shaft_x, ty, TILE_PLATFORM, w, h)

	# Lower rubble basement (bottom 25% of room)
	var basement_y := clampi(int(float(h) * 0.75), floor_lo + 1, h - 2)
	var num_rubble := clampi(int(float(w) / 8.0 * (0.5 + complexity)), 2, 8)
	for _i in range(num_rubble):
		var rx := rng.randi_range(2, w - 4)
		var rw := rng.randi_range(2, 4)
		for dx in range(rw):
			for dy in range(rng.randi_range(1, 2)):
				if basement_y - dy > floor_lo:
					_place_off_path(grid, rx + dx, basement_y - dy, TILE_PLATFORM, w, h)

# ── Bridge Span ───────────────────────────────────────────────────────────────
static func _skeleton_bridge_span(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Upper cable bridge
	var upper_y := clampi(int(float(h) * 0.25), 3, h - 8)
	var dash_gap_start := rng.randi_range(w / 3, w / 2)
	var dash_gap_end := dash_gap_start + rng.randi_range(6, 7)
	
	for tx in range(1, w - 1):
		# Optional dash-gap
		if rng.randf() < complexity and tx >= dash_gap_start and tx <= dash_gap_end:
			continue
		_place_off_path(grid, tx, upper_y, TILE_PLATFORM, w, h)
		# Railing segments
		if tx % 4 != 0:
			_place_off_path(grid, tx, upper_y - 1, TILE_WALL, w, h)

	# Mid-level secondary bridge (shorter, offset)
	var mid_y := upper_y + rng.randi_range(5, 7)
	var mid_start := rng.randi_range(w / 5, w / 3)
	var mid_w := rng.randi_range(w / 3, w / 2)
	for tx in range(mid_start, mid_start + mid_w):
		_place_off_path(grid, tx, mid_y, TILE_PLATFORM, w, h)

	# Deep support pillars extending from mid-bridges down to the floor
	var num_pillars := clampi(int(float(w) / 10.0 * (0.5 + complexity)), 1, 4)
	for _i in range(num_pillars):
		var px := rng.randi_range(mid_start + 1, mid_start + mid_w - 2)
		for ty in range(mid_y + 1, floor_lo):
			_place_off_path(grid, px, ty, TILE_WALL, w, h)
			_place_off_path(grid, px + 1, ty, TILE_WALL, w, h)

	# Lower cavern basin
	var basin_y := h - 2
	var num_rubble := clampi(int(float(w) / 6.0 * (0.5 + complexity)), 3, 10)
	for _i in range(num_rubble):
		var rx := rng.randi_range(1, w - 3)
		var ry := basin_y - rng.randi_range(0, 2)
		if ry > floor_lo:
			_place_off_path(grid, rx, ry, TILE_PLATFORM, w, h)

# ── Sanctuary ─────────────────────────────────────────────────────────────────
static func _skeleton_sanctuary(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2

	# Central meditation platform (3x3) slightly raised
	var plat_x := cx - 1
	var plat_y := floor_lo - 2
	for dx in range(3):
		for dy in range(3):
			var ty := plat_y + dy
			if ty < h:
				_place_off_path(grid, plat_x + dx, ty, TILE_PLATFORM if dy == 0 else TILE_WALL, w, h)

	# Background pillar column behind the meditation spot
	for ty in range(2, plat_y):
		_place_off_path(grid, cx, ty, TILE_WALL, w, h)

	# Two small flanking alcove shelves at different heights
	var shelf_y1 := plat_y - rng.randi_range(3, 4)
	var shelf_y2 := plat_y - rng.randi_range(5, 6)
	for dx in range(2):
		_place_off_path(grid, plat_x - 4 + dx, shelf_y1, TILE_PLATFORM, w, h)
		_place_off_path(grid, plat_x + 5 + dx, shelf_y2, TILE_PLATFORM, w, h)

# ── Storage Vault ─────────────────────────────────────────────────────────────
static func _skeleton_storage_vault(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# 3-tier archive vault
	var top_y := clampi(int(float(h) * 0.25), 3, h - 8)
	var mid_y := clampi(int(float(h) * 0.5), top_y + 4, h - 4)
	
	# Top tier: high shelf/ledge row
	for tx in range(2, w - 2):
		if tx % 5 != 0:
			_place_off_path(grid, tx, top_y, TILE_PLATFORM, w, h)

	# Top tier: ceiling-mounted pillars descending to high shelf
	var num_pillars := clampi(int(float(w) / 6.0 * (0.5 + complexity)), 3, 8)
	for _i in range(num_pillars):
		var px := rng.randi_range(3, w - 4)
		for ty in range(2, top_y):
			_place_off_path(grid, px, ty, TILE_WALL, w, h)

	# Mid tier: main walkway with wall alcoves and hidden pockets between pillars
	for tx in range(1, w - 1):
		if tx % 7 != 0:
			_place_off_path(grid, tx, mid_y, TILE_PLATFORM, w, h)
			# Wall alcoves
			if tx % 3 == 0:
				_place_off_path(grid, tx, mid_y - 1, TILE_WALL, w, h)

	# Vertical connecting shaft between tiers (2-3 tiles wide)
	var shaft_w := rng.randi_range(2, 3)
	var shaft_x := rng.randi_range(w / 4, w * 3 / 4)
	for ty in range(top_y, floor_lo):
		for dx in range(shaft_w):
			_place_off_path(grid, shaft_x + dx, ty, TILE_EMPTY, w, h)
		# Step platforms every 3-4 tiles
		if ty % 4 == 0:
			_place_off_path(grid, shaft_x, ty, TILE_PLATFORM, w, h)

	# Lower tier: deep storage basement accessed via shaft
	var base_y := h - 2
	for tx in range(shaft_x - 4, shaft_x + shaft_w + 4):
		if tx > 0 and tx < w and base_y > floor_lo:
			_place_off_path(grid, tx, base_y, TILE_PLATFORM, w, h)

# ── Collapsed Hall ────────────────────────────────────────────────────────────
static func _skeleton_collapsed_hall(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Multiple broken concrete slabs at staggered heights creating a zig-zag climbing path
	var num_slabs := clampi(int(float(h) / 5.0 * (0.5 + complexity)), 3, 6)
	var current_y := floor_lo - 2
	var current_x := w / 4
	var zig := 1
	for _i in range(num_slabs):
		var slab_w := rng.randi_range(4, 7)
		for dx in range(slab_w):
			var tx := current_x + dx
			if tx > 0 and tx < w:
				_place_off_path(grid, tx, current_y, TILE_PLATFORM, w, h)
		current_y -= rng.randi_range(3, 4)
		current_x += zig * rng.randi_range(3, 5)
		zig *= -1
		current_x = clampi(current_x, 2, w - 8)

	# Large rubble pile blocking direct path
	var pile_x := w / 2 - 3
	var pile_w := 6
	for dx in range(pile_w):
		for dy in range(rng.randi_range(2, 4)):
			_place_off_path(grid, pile_x + dx, floor_lo - dy, TILE_WALL, w, h)

	# Fallen pillars creating diagonal bridge segments
	var fall_x := w / 3
	var fall_y := floor_lo - 5
	for step in range(5):
		var tx := fall_x + step
		var ty := fall_y + step
		if tx < w and ty < h:
			_place_off_path(grid, tx, ty, TILE_PLATFORM, w, h)

	# Upper ledge with debris
	var ledge_y := current_y + 4
	var ledge_w := 5
	for dx in range(ledge_w):
		var tx := 1 + dx if zig == 1 else w - 2 - dx
		_place_off_path(grid, tx, ledge_y, TILE_FLOOR, w, h)
		_place_off_path(grid, tx, ledge_y - 1, TILE_PLATFORM, w, h)

	# Lower pit area beneath the slabs
	var pit_y := floor_lo + 2
	if pit_y < h:
		for tx in range(w / 3, w * 2 / 3):
			_place_off_path(grid, tx, pit_y, TILE_EMPTY, w, h)

# ── Ritual Chamber ────────────────────────────────────────────────────────────
static func _skeleton_ritual_chamber(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2

	# Massive central raised dais
	var dais_w := clampi(int(float(w) / 4.0 * (0.5 + complexity)), 6, 12)
	var dais_h := clampi(int(float(h) / 5.0 * (0.5 + complexity)), 3, 6)
	var dais_x := cx - dais_w / 2
	var dais_y := floor_lo - dais_h
	for dx in range(dais_w):
		for dy in range(dais_h):
			var tx := dais_x + dx
			var ty := dais_y + dy
			if ty < h:
				_place_off_path(grid, tx, ty, TILE_FLOOR if dy < 2 else TILE_WALL, w, h)

	# Flanking staircases leading up to the dais
	var stair_w := 3
	for step in range(dais_h):
		var ty := dais_y + step
		# Left stair
		for dx in range(stair_w):
			var tx_l := dais_x - 1 - step - dx
			if tx_l > 0:
				_place_off_path(grid, tx_l, ty, TILE_PLATFORM, w, h)
		# Right stair
		for dx in range(stair_w):
			var tx_r := dais_x + dais_w + step + dx
			if tx_r < w - 1:
				_place_off_path(grid, tx_r, ty, TILE_PLATFORM, w, h)

	# Upper observation balconies on left/right walls
	var balc_y := dais_y - rng.randi_range(4, 5)
	var balc_w := clampi(w / 8, 3, 6)
	for dx in range(balc_w):
		_place_off_path(grid, 1 + dx, balc_y, TILE_FLOOR, w, h)
		_place_off_path(grid, w - 2 - dx, balc_y, TILE_FLOOR, w, h)

	# Lower ritual pit beneath the dais (accessed by drop shaft)
	var pit_y := floor_lo + 2
	if pit_y < h - 1:
		for tx in range(dais_x + 2, dais_x + dais_w - 2):
			_place_off_path(grid, tx, pit_y, TILE_EMPTY, w, h)
			_place_off_path(grid, tx, pit_y + 1, TILE_WALL, w, h)
		# Drop shaft on one side
		var shaft_x := dais_x - 3
		for ty in range(floor_lo, pit_y + 1):
			_place_off_path(grid, shaft_x, ty, TILE_EMPTY, w, h)
			_place_off_path(grid, shaft_x + 1, ty, TILE_EMPTY, w, h)

	# Corner platforms at multiple heights
	for i in range(2):
		var cy := rng.randi_range(3, floor_lo - 2)
		_place_off_path(grid, 2, cy, TILE_PLATFORM, w, h)
		_place_off_path(grid, w - 3, cy, TILE_PLATFORM, w, h)

# ── Watchtower ────────────────────────────────────────────────────────────────
static func _skeleton_watchtower(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# 4 distinct floor tiers with alternating left/right platforms
	var tier_spacing := rng.randi_range(3, 4)
	var tier_y := floor_lo - tier_spacing
	var side := 0

	for i in range(4):
		var tier_w := rng.randi_range(w / 3, w * 2 / 3)
		# Optional dash-gap between non-adjacent tiers
		var gap_x := -1
		if i % 2 == 1 and rng.randf() < complexity:
			gap_x := rng.randi_range(tier_w / 3, tier_w * 2 / 3)
		
		for dx in range(tier_w):
			if dx == gap_x or dx == gap_x + 1:
				continue
			var tx := 1 + dx if side == 0 else w - 2 - dx
			if tx > 0 and tx < w - 1:
				_place_off_path(grid, tx, tier_y, TILE_PLATFORM, w, h)
		
		# Window gaps in walls at each tier
		var wx := 0 if side == 0 else w - 1
		for wy in range(tier_y - 2, tier_y):
			if wy > 0 and wy < h:
				_place_off_path(grid, wx, wy, TILE_EMPTY, w, h)

		side = 1 - side
		tier_y -= tier_spacing
		if tier_y < 4:
			break

	# Top observation platform spanning the full width
	var top_y := maxi(3, tier_y)
	for tx in range(1, w - 1):
		_place_off_path(grid, tx, top_y, TILE_FLOOR, w, h)
		_place_off_path(grid, tx, top_y + 1, TILE_FLOOR, w, h)

# ── Quarry ────────────────────────────────────────────────────────────────────
static func _skeleton_quarry(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Stepped descent: 3-4 step-down platforms to a deep pit floor
	var num_steps := rng.randi_range(3, 4)
	var step_w := clampi(w / num_steps, 4, 10)
	var pit_y := floor_lo
	var step_x := 1
	for i in range(num_steps):
		for dx in range(step_w):
			var tx := step_x + dx
			if tx < w - 1:
				_place_off_path(grid, tx, pit_y, TILE_PLATFORM, w, h)
				# Waist-high cover walls
				if rng.randf() < 0.3:
					_place_off_path(grid, tx, pit_y - 1, TILE_WALL, w, h)
		step_x += step_w
		pit_y += rng.randi_range(2, 3)

	# Excavation walls: thick wall segments at the bottom creating a pit basin
	if pit_y < h:
		for tx in range(1, w - 1):
			for ty in range(pit_y, h - 1):
				_place_off_path(grid, tx, ty, TILE_WALL, w, h)

	# Upper crane beams (thin horizontal wall segments near ceiling)
	var crane_y := clampi(4, 3, h - 6)
	var crane_w := clampi(int(float(w) * 0.6 * (0.5 + complexity)), 5, w - 2)
	var crane_x := rng.randi_range(1, w - crane_w - 1)
	for dx in range(crane_w):
		_place_off_path(grid, crane_x + dx, crane_y, TILE_PLATFORM, w, h)

	# Vein detail platforms on walls
	var vein_x := rng.randi_range(w / 4, w * 3 / 4)
	var vein_y := rng.randi_range(crane_y + 2, floor_lo - 4)
	for step in range(4):
		_place_off_path(grid, vein_x + step, vein_y + step, TILE_PLATFORM, w, h)

# ── Boss Arena ─────────────────────────────────────────────────────────────────
static func _skeleton_boss_arena(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot], complexity: float = 0.5) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2

	# Wide open central combat floor (clear zone)
	var clear_w := clampi(int(float(w) * 0.8), 10, w - 4)
	var clear_x := cx - clear_w / 2
	for ty in range(3, floor_lo):
		for tx in range(clear_x, clear_x + clear_w):
			if ty > 0 and ty < h and tx > 0 and tx < w:
				if grid[ty][tx] != TILE_FLOOR:
					grid[ty][tx] = TILE_EMPTY

	# Upper spectator balconies on left and right walls at 2 height levels
	var balc_w := clampi(clear_x, 2, 6)
	for i in range(2):
		var balc_y := floor_lo - 4 - (i * 4)
		if balc_y > 2:
			for dx in range(balc_w):
				_place_off_path(grid, 1 + dx, balc_y, TILE_PLATFORM, w, h)
				_place_off_path(grid, w - 2 - dx, balc_y, TILE_PLATFORM, w, h)

	# Pillar clusters in the arena that break sightlines
	var num_clusters := clampi(int(float(w) / 10.0 * (0.5 + complexity)), 2, 4)
	for _i in range(num_clusters):
		var px := rng.randi_range(clear_x + 2, clear_x + clear_w - 4)
		var py := floor_lo - rng.randi_range(1, 3)
		for dy in range(rng.randi_range(2, 4)):
			if py - dy > 2:
				_place_off_path(grid, px, py - dy, TILE_WALL, w, h)
				_place_off_path(grid, px + 1, py - dy, TILE_WALL, w, h)

	# Boss spawn platform at the top center
	var spawn_y := 4
	var spawn_w := clampi(w / 6, 4, 8)
	var spawn_x := cx - spawn_w / 2
	for dx in range(spawn_w):
		_place_off_path(grid, spawn_x + dx, spawn_y, TILE_FLOOR, w, h)
		_place_off_path(grid, spawn_x + dx, spawn_y + 1, TILE_FLOOR, w, h)

	# Lower pit traps (empty tiles at floor level near edges)
	var pit_w := 3
	for dx in range(pit_w):
		_place_off_path(grid, clear_x + dx, floor_lo, TILE_EMPTY, w, h)
		_place_off_path(grid, clear_x + clear_w - 1 - dx, floor_lo, TILE_EMPTY, w, h)

	# Perimeter ledges scaled by room height
	var ledge_y := floor_lo + 2
	if ledge_y < h - 1:
		for dx in range(balc_w + 2):
			_place_off_path(grid, 1 + dx, ledge_y, TILE_PLATFORM, w, h)
			_place_off_path(grid, w - 2 - dx, ledge_y, TILE_PLATFORM, w, h)

