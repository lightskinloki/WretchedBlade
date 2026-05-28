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

static func get_dimension_range(archetype: int) -> Dictionary:
	match archetype:
		Archetype.GUARD_POST:     return {"min_w": 40, "max_w": 64, "min_h": 20, "max_h": 30}
		Archetype.BRIDGE_SPAN:    return {"min_w": 55, "max_w": 80, "min_h": 16, "max_h": 24}
		Archetype.STORAGE_VAULT:  return {"min_w": 44, "max_w": 64, "min_h": 22, "max_h": 32}
		Archetype.RITUAL_CHAMBER: return {"min_w": 36, "max_w": 52, "min_h": 22, "max_h": 30}
		Archetype.COLLAPSED_HALL: return {"min_w": 42, "max_w": 58, "min_h": 20, "max_h": 26}
		Archetype.WATCHTOWER:     return {"min_w": 24, "max_w": 36, "min_h": 32, "max_h": 50}
		Archetype.QUARRY:         return {"min_w": 48, "max_w": 64, "min_h": 18, "max_h": 26}
		Archetype.SANCTUARY:      return {"min_w": 24, "max_w": 34, "min_h": 18, "max_h": 24}
		Archetype.BOSS_ARENA:     return {"min_w": 50, "max_w": 80, "min_h": 28, "max_h": 44}
		_:                        return {"min_w": 40, "max_w": 64, "min_h": 20, "max_h": 30}

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
static func apply_skeleton(grid: Array, archetype: int, rng: RandomNumberGenerator, w: int, h: int, portals: Array = [], available_slots: Array[PortalSlot] = []) -> void:
	_connect_portal_floors(grid, _get_portal_anchors(portals, available_slots, w, h), w, h)
	match archetype:
		Archetype.GUARD_POST:     _skeleton_guard_post(grid, rng, w, h, portals, available_slots)
		Archetype.BRIDGE_SPAN:    _skeleton_bridge_span(grid, rng, w, h, portals, available_slots)
		Archetype.SANCTUARY:      _skeleton_sanctuary(grid, rng, w, h, portals, available_slots)
		Archetype.STORAGE_VAULT:  _skeleton_storage_vault(grid, rng, w, h, portals, available_slots)
		Archetype.COLLAPSED_HALL: _skeleton_collapsed_hall(grid, rng, w, h, portals, available_slots)
		Archetype.RITUAL_CHAMBER: _skeleton_ritual_chamber(grid, rng, w, h, portals, available_slots)
		Archetype.WATCHTOWER:     _skeleton_watchtower(grid, rng, w, h, portals, available_slots)
		Archetype.QUARRY:         _skeleton_quarry(grid, rng, w, h, portals, available_slots)
		Archetype.BOSS_ARENA:     _skeleton_boss_arena(grid, rng, w, h, portals, available_slots)
		_:                        _skeleton_guard_post(grid, rng, w, h, portals, available_slots)

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
# Character: raised sentry platform above the path, rubble pile at base.
static func _skeleton_guard_post(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Raised sentry platform at random x in right third of room
	var sentry_w := clampi(w / 12, 3, 6)
	var sentry_x := rng.randi_range(w / 3, w - sentry_w - 3)
	var sentry_y := floor_lo - rng.randi_range(3, maxi(5, h / 6))
	for dx in range(sentry_w):
		for dy in range(2):
			var tx := sentry_x + dx
			var ty := sentry_y + dy
			_place_off_path(grid, tx, ty, TILE_WALL if dy == 0 else TILE_PLATFORM, w, h)
	for dx in range(sentry_w):
		_place_off_path(grid, sentry_x + dx, sentry_y, TILE_PLATFORM, w, h)

	# Rubble pile at random x near left or right wall — scale with room
	var rubble_w := clampi(w / 14, 2, 5)
	var rubble_side := rng.randi() % 2
	var rubble_x := rng.randi_range(2, 5) if rubble_side == 0 else rng.randi_range(w - rubble_w - 3, w - 3)
	var rubble_y_base := h - 2
	for dx in range(rubble_w):
		var rx := rubble_x + dx
		if rx >= w: break
		for dy in range(rng.randi_range(1, 2)):
			var ry := rubble_y_base - dy
			_place_off_path(grid, rx, ry, TILE_PLATFORM, w, h)

# ── Bridge Span ───────────────────────────────────────────────────────────────
# Character: support pillars below the path, railing segments above, cable anchors.
static func _skeleton_bridge_span(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var anchors := _get_portal_anchors(portals, available_slots, w, h)
	if anchors.is_empty():
		return
	# Pillars below the path at random x positions — scale with room width
	var num_pillars := clampi(w / 8, 1, 5)
	var pillar_positions: Array[int] = []
	for _i in range(num_pillars):
		var px := rng.randi_range(w / 6, w * 5 / 6)
		pillar_positions.append(px)
		for dy in range(h - 3, h):
			_place_off_path(grid, px, dy, TILE_WALL, w, h)

	# Railing segments above the path at random x spans
	var rail_y := (anchors[0].y if anchors.size() > 0 else h - 4) - rng.randi_range(1, 2)
	var num_rails := clampi(w / 15, 1, 4)
	for _i in range(num_rails):
		var rx := rng.randi_range(w / 6, w * 5 / 6 - 4)
		var rw := rng.randi_range(3, maxi(5, w / 12))
		for dx in range(rw):
			var tx := rx + dx
			if tx >= w: break
			_place_off_path(grid, tx, rail_y, TILE_WALL, w, h)

	# Cable anchors on side walls at varying heights
	var cable_y := rng.randi_range(4, h - 8)
	_place_off_path(grid, 1, cable_y, TILE_PLATFORM, w, h)
	_place_off_path(grid, w - 2, cable_y, TILE_PLATFORM, w, h)

# ── Sanctuary ─────────────────────────────────────────────────────────────────
# Character: minimal — single raised meditation spot offset from the path.
static func _skeleton_sanctuary(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2

	# Single 2x2 meditation platform near center, above the path
	var plat_x := cx - 1 + rng.randi_range(-2, 2)
	var plat_y := floor_lo - rng.randi_range(2, 4)
	for dx in range(2):
		for dy in range(2):
			_place_off_path(grid, plat_x + dx, plat_y + dy, TILE_PLATFORM, w, h)

# ── Storage Vault ─────────────────────────────────────────────────────────────
# Character: ceiling pillars descending toward path, wall alcoves with shelves,
# one hidden pocket.
static func _skeleton_storage_vault(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Ceiling pillars: columns from y=2 down to above the path — scale with room
	var num_pillars := clampi(w / 7, 2, 6)
	var pillar_positions: Array[int] = []
	for _i in range(num_pillars):
		var px := rng.randi_range(w / 6, w * 5 / 6)
		var pillar_bottom := floor_lo - rng.randi_range(4, maxi(6, h / 5))
		for y in range(2, pillar_bottom):
			_place_off_path(grid, px, y, TILE_WALL, w, h)
		pillar_positions.append(px)

	# Wall alcoves with shelves between pillars (at y above path) — scale with room
	var num_alcoves := clampi(w / 15, 1, 4)
	for _i in range(num_alcoves):
		var ax := rng.randi_range(w / 4, w * 3 / 4)
		var aw := rng.randi_range(3, 4)
		var ay := floor_lo - rng.randi_range(4, 6)
		for dx in range(aw):
			for dy in range(2):
				_place_off_path(grid, ax + dx, ay + dy, TILE_PLATFORM, w, h)

	# Hidden pocket behind a random pillar
	if pillar_positions.size() > 0:
		var hp := pillar_positions[rng.randi() % pillar_positions.size()]
		var hy := floor_lo - rng.randi_range(5, 7)
		# Clear the pillar tile at this position, add platform behind
		_place_off_path(grid, hp, hy, TILE_EMPTY, w, h)
		_place_off_path(grid, hp, hy + 1, TILE_PLATFORM, w, h)

# ── Collapsed Hall ────────────────────────────────────────────────────────────
# Character: rubble heap below the path, fallen ceiling debris, a fallen pillar.
static func _skeleton_collapsed_hall(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_hi := y_range.y

	# Rubble heap below the path at a random X — scale with room
	var rubble_w := clampi(w / 10, 3, 6)
	var rubble_x := rng.randi_range(w / 6, w * 5 / 6 - rubble_w)
	var rubble_base := floor_hi + 2
	for dx in range(rubble_w):
		var rx := rubble_x + dx
		if rx >= w: break
		var local := float(dx) / float(rubble_w - 1)
		var pile_h := int(local * 3.0) + 1
		for dy in range(pile_h):
			var ry := rubble_base + dy
			if ry < h:
				_place_off_path(grid, rx, ry, TILE_PLATFORM, w, h)

	# Fallen ceiling debris above the path — scale with room
	var debris_count := clampi(w / 10, 2, 6)
	for _i in range(debris_count):
		var dx := rng.randi_range(w / 6, w * 5 / 6)
		var dy := rng.randi_range(2, 5)
		_place_off_path(grid, dx, dy, TILE_PLATFORM, w, h)

	# Fallen pillar — diagonal trace from wall to ground
	var fall_x := rng.randi_range(w / 3, w * 2 / 3)
	var fall_top := rng.randi_range(4, 7)
	for step in range(4):
		var fx := fall_x + step
		var fy := fall_top + step
		if fx < w and fy < h:
			_place_off_path(grid, fx, fy, TILE_PLATFORM, w, h)

# ── Ritual Chamber ────────────────────────────────────────────────────────────
# Character: central raised platform (off the path), steps, corner platforms.
static func _skeleton_ritual_chamber(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2

	# Central raised platform above the path, at random size — scale with room
	var plat_w := clampi(w / 8, 3, 8)
	var plat_h := clampi(h / 6, 3, 6)
	var plat_x1 := cx - plat_w / 2 + rng.randi_range(-2, 2)
	var plat_y := floor_lo - plat_h - rng.randi_range(1, 2)

	for dx in range(plat_w):
		for dy in range(plat_h):
			var tx := plat_x1 + dx
			var ty := plat_y + dy
			if dy >= plat_h - 2:
				_place_off_path(grid, tx, ty, TILE_FLOOR, w, h)
			else:
				_place_off_path(grid, tx, ty, TILE_WALL, w, h)

	# Steps on one or both sides
	var step_w := rng.randi_range(2, 3)
	for side_idx in range(2 if rng.randf() < 0.5 else 1):
		var side_sign := -1 if side_idx == 0 else 1
		var step_x := plat_x1 + (plat_w / 2) + step_w if side_sign == 1 else plat_x1 - step_w - 1
		for dx in range(step_w):
			var sx := step_x + dx * (-side_sign)
			if sx < 0 or sx >= w:
				continue
			for dy in range(2):
				var sy := plat_y + plat_h - 2 + dy
				_place_off_path(grid, sx, sy, TILE_FLOOR, w, h)

	# Corner platforms at random corners (choose 1-3 of 4)
	var possible_corners: Array[Vector2i] = [
		Vector2i(rng.randi_range(1, 3), floor_lo - rng.randi_range(2, 3)),
		Vector2i(w - rng.randi_range(2, 4), floor_lo - rng.randi_range(2, 3)),
		Vector2i(rng.randi_range(1, 3), rng.randi_range(3, 5)),
		Vector2i(w - rng.randi_range(2, 4), rng.randi_range(3, 5)),
	]
	var num_corners := rng.randi_range(1, 3)
	for i in range(num_corners):
		var c := possible_corners[i]
		for dx in range(2):
			for dy in range(2):
				_place_off_path(grid, c.x + dx, c.y + dy, TILE_PLATFORM, w, h)

# ── Watchtower ────────────────────────────────────────────────────────────────
# Character: staggered side platforms going up, window gaps in side walls.
static func _skeleton_watchtower(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Staggered platforms alternating left/right, going up from the path
	var plat_level := floor_lo - 3
	var plat_side := 0

	while plat_level > 5:
		var pw := rng.randi_range(maxi(3, w / 4), maxi(4, w / 3))
		if plat_side == 0:
			# Left side
			for x in range(1, mini(pw + 1, w - 1)):
				_place_off_path(grid, x, plat_level, TILE_PLATFORM, w, h)
				_place_off_path(grid, x, plat_level - 1, TILE_EMPTY, w, h)
		else:
			# Right side
			for x in range(maxi(1, w - pw - 1), w - 1):
				_place_off_path(grid, x, plat_level, TILE_PLATFORM, w, h)
				_place_off_path(grid, x, plat_level - 1, TILE_EMPTY, w, h)

		plat_side = 1 - plat_side
		plat_level -= rng.randi_range(2, 4)

	# Top platform near ceiling
	var top_y := rng.randi_range(2, 5)
	for x in range(1, w - 1):
		_place_off_path(grid, x, top_y, TILE_FLOOR, w, h)
		_place_off_path(grid, x, top_y + 1, TILE_FLOOR, w, h)
		for ay in range(2, top_y):
			_place_off_path(grid, x, ay, TILE_EMPTY, w, h)

	# Window gaps in side walls at random heights — scale with room
	var num_windows := clampi(h / 6, 2, 6)
	for _i in range(num_windows):
		var wy := rng.randi_range(3, floor_lo - 6)
		var w_side := rng.randi() % 2
		var wx := 0 if w_side == 0 else w - 1
		_place_off_path(grid, wx, wy, TILE_EMPTY, w, h)
		if wy + 1 < h:
			_place_off_path(grid, wx, wy + 1, TILE_EMPTY, w, h)

# ── Quarry ────────────────────────────────────────────────────────────────────
# Character: waist-high cover walls in the air above path, visual edge pits.
static func _skeleton_quarry(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x

	# Waist-high cover walls at random x positions — scale with room
	var num_covers := clampi(w / 12, 2, 6)
	for _i in range(num_covers):
		var cx := rng.randi_range(w / 8, w * 7 / 8 - 4)
		var cw := rng.randi_range(3, maxi(4, w / 15))
		var ch := rng.randi_range(2, 3)
		for dx in range(cw):
			for dy in range(ch):
				var tx := cx + dx
				var ty := floor_lo - 1 - dy
				if ty < 2 or ty >= h:
					continue
				_place_off_path(grid, tx, ty, TILE_WALL, w, h)

	# Visual edge pits: empty tiles at floor level near edges
	var pit_side := rng.randi() % 2
	var pit_x := 1 if pit_side == 0 else w - 3
	for dy in range(3):
		_place_off_path(grid, pit_x, floor_lo + dy, TILE_EMPTY, w, h)
		_place_off_path(grid, pit_x + 1, floor_lo + dy, TILE_EMPTY, w, h)

	# Quarry vein — diagonal platform detail on empty wall space
	var vein_x := rng.randi_range(w / 4, w * 3 / 4)
	var vein_y := rng.randi_range(3, floor_lo - 4)
	for step in range(3):
		_place_off_path(grid, vein_x + step, vein_y + step, TILE_PLATFORM, w, h)

# ── Boss Arena ─────────────────────────────────────────────────────────────────
# Character: wide open floor with perimeter ledges, pillar clusters, and
# elevated boss spawn platform — scaled to room dimensions.
static func _skeleton_boss_arena(grid: Array, rng: RandomNumberGenerator, w: int, h: int, portals: Array, available_slots: Array[PortalSlot]) -> void:
	var y_range := _get_anchor_y_range(portals, available_slots, w, h)
	var floor_lo := y_range.x
	var cx := w / 2

	# Open floor — clear a wide central zone above the path
	var clear_left := clampi(w / 5, 3, 8)
	var clear_right := w - clear_left
	for y in range(2, floor_lo + 2):
		for x in range(clear_left, clear_right):
			if y >= 0 and y < h and x >= 0 and x < w:
				if grid[y][x] != TILE_FLOOR:
					grid[y][x] = TILE_EMPTY

	# Perimeter ledges on left and right walls — scaled by room height
	var ledge_count := clampi(h / 8, 1, 4)
	for i in range(ledge_count):
		var ly := 2 + i * ((floor_lo - 2) / (ledge_count + 1))
		var lw := clampi(w / 12, 2, 4)
		# Left ledge
		for dx in range(lw):
			_place_off_path(grid, dx + 1, ly, TILE_PLATFORM, w, h)
		# Right ledge
		for dx in range(lw):
			_place_off_path(grid, w - lw + dx - 1, ly, TILE_PLATFORM, w, h)

	# Pillar clusters — 2-4 groups of pillars
	var num_clusters := clampi(w / 15, 2, 4)
	for _i in range(num_clusters):
		var pcx := rng.randi_range(clear_left + 2, clear_right - 4)
		var pcy := rng.randi_range(3, floor_lo - 3)
		var pw := rng.randi_range(2, 3)
		for dx in range(pw):
			for dy in range(2):
				var tx := pcx + dx
				var ty := pcy + dy
				_place_off_path(grid, tx, ty, TILE_WALL, w, h)

	# Boss spawn platform near ceiling center
	var spawn_y := clampi(2, 2, h - 6)
	var spawn_w := clampi(w / 10, 3, 6)
	var spawn_x1 := cx - spawn_w / 2
	for x in range(spawn_x1, spawn_x1 + spawn_w):
		for y in range(spawn_y, spawn_y + 2):
			_place_off_path(grid, x, y, TILE_FLOOR, w, h)
		for ay in range(2, spawn_y):
			_place_off_path(grid, x, ay, TILE_EMPTY, w, h)
