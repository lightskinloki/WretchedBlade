extends RefCounted
class_name RoomTerrainGenerator
# RoomTerrainGenerator.gd — full Pass 2 room rendering pipeline.
#
# Takes a DungeonGraph node and produces a tile grid ready for WorldGenerator
# to build into physical geometry.
#
# Pipeline phases:
#   A — Initialize grid (all WALL)
#   B — Apply archetype skeleton (floor segments, platforms, air)
#   C — Apply region shape modifier (theme-specific structural variation)
#   D — Carve portal doorways (from PortalData on the node)
#   E — Apply decorations (rubble, wall detail, ambient tiles)
#   F — Return grid for WorldGenerator

# ── Tile constants ────────────────────────────────────────────────────────────
const TILE_EMPTY    := 0
const TILE_FLOOR    := 1
const TILE_WALL     := 2
const TILE_PLATFORM := 3

# ── Public API ────────────────────────────────────────────────────────────────
# Renders a single room from a DungeonGraph node.
# Returns a 2D int array [y][x] of tile types.
#
# Parameters:
#   graph:   DungeonGraph — owning graph (for node data + portal info)
#   node_id: int — the node to render
#   rng:     RandomNumberGenerator — seeded per-room rng
#   theme:   int — RegionTheme.HexTheme enum value
#   archetype_override: int — optional override (for fallback)
static func render_room(
	graph: DungeonGraph,
	node_id: int,
	rng: RandomNumberGenerator,
	theme: int
) -> Array:
	var node := graph.get_node(node_id)
	if node == null:
		push_error("RoomTerrainGenerator: node %d not found" % node_id)
		return _init_grid(20, 16)

	var w := node.room_w
	var h := node.room_h

	# Phase A — Init
	var grid := _init_grid(w, h)

	# Phase B — Skeleton (portal-anchored generation)
	var available_slots := RoomArchetype.get_available_portal_slots(node.archetype)
	var max_b_retries := 5
	var b_attempt := 0
	print("  [DIAG] Phase B: node=%d arch=%s w=%d h=%d portals=%d" % [node_id, RoomArchetype.get_archetype_name(node.archetype), w, h, node.portals.size()])
	for p in node.portals:
		print("    portal slot=%s connected=%d" % [p.slot_id, p.connected_node])
	var anchors := _get_floor_anchors(node, w, h)
	print("    floor anchors: ", anchors)
	while b_attempt < max_b_retries:
		RoomArchetype.apply_skeleton(grid, node.archetype, rng, w, h, node.portals, available_slots)
		if _portals_are_connected(grid, node, w, h):
			break
		push_warning("RoomTerrainGenerator: skeleton connectivity failed for node %d (archetype %s), retry %d" % [node_id, RoomArchetype.get_archetype_name(node.archetype), b_attempt + 1])
		b_attempt += 1
		if b_attempt < max_b_retries:
			grid = _init_grid(w, h)
			rng.randi()
	if b_attempt >= max_b_retries:
		push_error("RoomTerrainGenerator: skeleton connectivity failed for node %d after %d attempts" % [node_id, max_b_retries])
	# Count floor tiles after Phase B
	var floor_count := 0
	for yy in range(h):
		for xx in range(w):
			if grid[yy][xx] == 1:
				floor_count += 1
	print("  [DIAG] Phase B result: floor_tiles=%d" % floor_count)

	# Phase C — Shape modifier
	RegionTheme.apply_shape_modifier(grid, theme, rng, w, h)
	var floor_c := 0
	for yy in range(h):
		for xx in range(w):
			if grid[yy][xx] == 1:
				floor_c += 1
	print("  [DIAG] Phase C: floor_tiles=%d" % floor_c)

	# Phase D — Portal carving
	for portal in node.portals:
		_carve_portal(grid, node.archetype, portal, w, h)

	var floor_d := 0
	for yy in range(h):
		for xx in range(w):
			if grid[yy][xx] == 1:
				floor_d += 1
	print("  [DIAG] Phase D: floor_tiles=%d" % floor_d)

	# Debug: verify connectivity still holds after carving
	if OS.is_debug_build():
		if not _portals_are_connected(grid, node, w, h):
			push_warning("RoomTerrainGenerator: portal connectivity lost after carving in node %d" % node_id)

	# Phase D backstop — guarantee portal openings are clear of TILE_WALL
	_sanitize_portal_rects(grid, node, w, h)

	# Phase E — Decoration
	_apply_decor(grid, rng, w, h, theme)
	var floor_e := 0
	for yy in range(h):
		for xx in range(w):
			if grid[yy][xx] == 1:
				floor_e += 1
	print("  [DIAG] Phase E final: floor_tiles=%d" % floor_e)

	# Phase E backstop — decoration can add ceiling spikes; re-sanitize portals
	# so no decoration tile sits inside or directly above a portal opening.
	_sanitize_portal_rects(grid, node, w, h)

	return grid

# ── Phase A: Grid initialization ────────────────────────────────────────────
static func _init_grid(w: int, h: int) -> Array:
	var grid: Array = []
	grid.resize(h)
	for y in range(h):
		var row: Array = []
		row.resize(w)
		for x in range(w):
			row[x] = TILE_WALL
		grid[y] = row
	return grid

# ── Phase D: Portal carving ─────────────────────────────────────────────────
# Carves a doorway at the position defined by the portal's slot.
# Clears tile_h rows at the slot position, then places floor on the
# bottom 2 rows so the player can walk through.
static func _carve_portal(grid: Array, archetype: int, portal: RoomArchetype.PortalData, w: int, h: int) -> void:
	if portal == null or portal.slot_id.is_empty():
		push_warning("RoomTerrainGenerator: null or empty portal slot")
		return

	var slots := RoomArchetype.get_available_portal_slots(archetype)
	var slot_def: RoomArchetype.PortalSlot
	for s in slots:
		if s.slot_id == portal.slot_id:
			slot_def = s
			break

	if slot_def == null:
		push_error("RoomTerrainGenerator: slot '%s' not found for archetype %d" % [portal.slot_id, archetype])
		return

	var pos: Vector2i = slot_def.get_tile_position(w, h)

	# Clear the doorway area
	for dx in range(slot_def.tile_w):
		for dy in range(slot_def.tile_h):
			var tx := pos.x + dx
			var ty := pos.y + dy
			if ty >= 0 and ty < h and tx >= 0 and tx < w:
				grid[ty][tx] = TILE_EMPTY

	# Floor at doorway bottom (2 rows)
	var floor_y := pos.y + slot_def.tile_h - 2
	for dx in range(slot_def.tile_w):
		var tx := pos.x + dx
		if floor_y >= 0 and floor_y < h and tx >= 0 and tx < w:
			grid[floor_y][tx] = TILE_FLOOR
		var floor_y2 := floor_y + 1
		if floor_y2 >= 0 and floor_y2 < h and tx >= 0 and tx < w:
			grid[floor_y2][tx] = TILE_FLOOR

	# Bridge: connect portal floor to room's main floor (ground portals only)
	if slot_def.height_band == "ground":
		var scan_dir: int
		var scan_start: int
		if slot_def.side == "right":
			scan_dir = -1
			scan_start = pos.x - 1
		elif slot_def.side == "left":
			scan_dir = 1
			scan_start = pos.x + slot_def.tile_w
		else:
			return

		var bridge_floor := pos.y + slot_def.tile_h - 2

		for step in range(5):
			var bx := scan_start + step * scan_dir
			if bx < 0 or bx >= w:
				break

			if bridge_floor >= 0 and bridge_floor < h and grid[bridge_floor][bx] == TILE_FLOOR:
				break

			if bridge_floor >= 0 and bridge_floor < h:
				grid[bridge_floor][bx] = TILE_FLOOR
			if bridge_floor + 1 >= 0 and bridge_floor + 1 < h:
				grid[bridge_floor + 1][bx] = TILE_FLOOR

			# Clear 5 tiles above the bridge floor so the player has headroom to
			# jump up to the room floor if it sits 1-2 tiles higher than the bridge.
			var air_top := maxi(1, bridge_floor - 5)
			for ay in range(air_top, bridge_floor):
				if ay >= 0 and ay < h and grid[ay][bx] == TILE_WALL:
					grid[ay][bx] = TILE_EMPTY

# ── Phase D backstop: sanitize portal opening rects ────────────────────────
# Guaranteed last-resort pass that runs after all carving phases.
# If _carve_portal cleared correctly this is a no-op. If any edge case left
# TILE_WALL inside the opening rect, this removes it and re-stamps the floor rows.
static func _sanitize_portal_rects(grid: Array, node: DungeonGraph.RoomNode, w: int, h: int) -> void:
	var slots := RoomArchetype.get_available_portal_slots(node.archetype)
	for portal in node.portals:
		if portal == null or portal.slot_id.is_empty():
			continue
		var slot_def: RoomArchetype.PortalSlot = null
		for s in slots:
			if s.slot_id == portal.slot_id:
				slot_def = s
				break
		if slot_def == null:
			continue

		var pos: Vector2i = slot_def.get_tile_position(w, h)

		# Force-clear any TILE_WALL inside the opening rect
		for dx in range(slot_def.tile_w):
			for dy in range(slot_def.tile_h):
				var tx := pos.x + dx
				var ty := pos.y + dy
				if tx >= 0 and tx < w and ty >= 0 and ty < h:
					if grid[ty][tx] == TILE_WALL:
						grid[ty][tx] = TILE_EMPTY

		# Guarantee floor at the bottom two rows of the opening
		var floor_y := pos.y + slot_def.tile_h - 2
		for dx in range(slot_def.tile_w):
			var tx := pos.x + dx
			if tx >= 0 and tx < w:
				if floor_y >= 0 and floor_y < h:
					grid[floor_y][tx] = TILE_FLOOR
				if floor_y + 1 >= 0 and floor_y + 1 < h:
					grid[floor_y + 1][tx] = TILE_FLOOR

# ── Portal floor anchor extraction (uses same logic as RoomArchetype) ──────
static func _get_floor_anchors(node: DungeonGraph.RoomNode, w: int, h: int) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var slots := RoomArchetype.get_available_portal_slots(node.archetype)
	for portal in node.portals:
		if portal == null or portal.slot_id.is_empty():
			continue
		for s in slots:
			if s.slot_id == portal.slot_id:
				var anchor := s.get_floor_anchor(w, h)
				if anchor.y >= 0 and anchor.y < h and anchor.x >= 0 and anchor.x < w:
					anchors.append(anchor)
				break
	return anchors

# ── BFS flood-fill: returns true if all portal floor anchors are reachable ──
static func _portals_are_connected(grid: Array, node: DungeonGraph.RoomNode, w: int, h: int) -> bool:
	var anchors := _get_floor_anchors(node, w, h)
	if anchors.size() < 2:
		return true

	var start := anchors[0]
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dir: Vector2i in dirs:
			var nx: Vector2i = cur + dir
			if nx.x < 0 or nx.x >= w or nx.y < 0 or nx.y >= h:
				continue
			if visited.has(nx):
				continue
			if grid[nx.y][nx.x] != TILE_EMPTY and grid[nx.y][nx.x] != TILE_FLOOR:
				continue
			# Player-height clearance: the body is ~2 tiles tall, so a cell is
			# only traversable if the cell above is not an unbreakable WALL.
			# A 1-tile gap under a wall slab is impassable and must fail the
			# check so the skeleton retry loop regenerates the room.
			if nx.y - 1 >= 0 and grid[nx.y - 1][nx.x] == TILE_WALL:
				continue
			visited[nx] = true
			queue.append(nx)

	for i in range(1, anchors.size()):
		if not visited.has(anchors[i]):
			return false
	return true

# ── Phase E: Decoration ────────────────────────────────────────────────────
# Adds visual detail without affecting gameplay structure.
static func _apply_decor(grid: Array, rng: RandomNumberGenerator, w: int, h: int, theme: int) -> void:
	# Rubble above floor edges (decorative, never modifies TILE_FLOOR)
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			if grid[y][x] == TILE_FLOOR and grid[y - 1][x] == TILE_EMPTY:
				if rng.randf() < 0.08:
					grid[y - 1][x] = TILE_PLATFORM

	# Wall cracks (thin vertical lines in walls)
	for x in [1, w - 2]:
		if rng.randf() < 0.3:
			var crack_y := rng.randi_range(3, h - 4)
			var crack_h := rng.randi_range(2, 4)
			for dy in range(crack_h):
				if crack_y + dy < h and grid[crack_y + dy][x] == TILE_WALL:
					# Leave as wall (no visual distinction yet; future PixelRenderer pass)
					pass

	# Ceiling spikes theme-agnostic
	for x in range(2, w - 2):
		if rng.randf() < 0.05:
			for y in range(1, h - 2):
				if grid[y][x] == TILE_WALL and grid[y + 1][x] == TILE_EMPTY:
					var spike_h := rng.randi_range(1, 2)
					for dy in range(1, spike_h + 1):
						if y + dy < h and grid[y + dy][x] == TILE_EMPTY:
							grid[y + dy][x] = TILE_PLATFORM
					break
