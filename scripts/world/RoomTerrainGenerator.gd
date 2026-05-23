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
	RoomArchetype.apply_skeleton(grid, node.archetype, rng, w, h, node.portals, available_slots)

	# Phase C — Shape modifier
	RegionTheme.apply_shape_modifier(grid, theme, rng, w, h)

	# Phase D — Portal carving
	for portal in node.portals:
		_carve_portal(grid, node.archetype, portal, w, h)

	# Debug: verify all portal floors are reachable from each other
	if OS.is_debug_build():
		_validate_portal_connectivity(grid, node, w, h)

	# Phase E — Decoration
	_apply_decor(grid, rng, w, h, theme)

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

			var air_top := maxi(1, bridge_floor - 3)
			for ay in range(air_top, bridge_floor):
				if ay >= 0 and ay < h and grid[ay][bx] == TILE_WALL:
					grid[ay][bx] = TILE_EMPTY

# ── Debug: Portal connectivity validation (BFS flood-fill) ─────────────────
static func _validate_portal_connectivity(grid: Array, node: DungeonGraph.RoomNode, w: int, h: int) -> void:
	var portal_floors: Array[Vector2i] = []
	for portal in node.portals:
		if portal == null or portal.slot_id.is_empty():
			continue
		var slots := RoomArchetype.get_available_portal_slots(node.archetype)
		for s in slots:
			if s.slot_id == portal.slot_id:
				var pos := s.get_tile_position(w, h)
				var fy := pos.y + s.tile_h - 2
				var fx := pos.x
				if fy >= 0 and fy < h and fx >= 0 and fx < w:
					portal_floors.append(Vector2i(fx, fy))
				break

	if portal_floors.size() < 2:
		return

	var start := portal_floors[0]
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		for dir: Vector2i in dirs:
			var nx: Vector2i = cur + dir
			if nx.x < 0 or nx.x >= w or nx.y < 0 or nx.y >= h:
				continue
			if visited.has(nx):
				continue
			if grid[nx.y][nx.x] != TILE_EMPTY and grid[nx.y][nx.x] != TILE_FLOOR:
				continue
			visited[nx] = true
			queue.append(nx)

	for i in range(1, portal_floors.size()):
		if not visited.has(portal_floors[i]):
			push_warning("RoomTerrainGenerator: portal %d is NOT reachable from portal 0 in node %d (archetype %d)" % [i, node.node_id, node.archetype])

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
