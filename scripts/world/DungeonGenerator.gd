extends RefCounted
class_name DungeonGenerator
# DungeonGenerator.gd — two-pass dungeon generation.
#
# Pass 1: generate_graph() → DungeonGraph
#   Produces a node-web dungeon graph with critical path, branches,
#   portal slot matching, checkpoint placement, and puzzle wiring.
#
# Pass 2: Called externally (RoomTerrainGenerator) to render rooms
#   from the graph on-demand.
#
# Backward compat: generate_plan() still available for legacy DungeonPlan use.

# ── Defaults ──────────────────────────────────────────────────────────────────
const MIN_ROOMS_PER_SECTION := 1
const MAX_ROOMS_PER_SECTION := 6
const CHECKPOINT_INTERVAL   := 5
const BRANCH_CHANCE_BASE    := 0.3

# Branch topology constants
const BRANCH_RECONNECT   := 0
const BRANCH_CHAIN       := 1
const BRANCH_SUB_DUNGEON := 2

# ── Public API: Graph-based generation ────────────────────────────────────────
# Produces a DungeonGraph from the given parameters.
# params:
#   seed:       int   — random seed (required)
#   is_boss:    bool  — true for boss dungeons
#   hex_theme:  str   — theme identifier, stored as metadata
#   difficulty: float — 0.0–1.0, affects room count and enemy density
func generate_graph(params: Dictionary) -> DungeonGraph:
	var seed_val: int = params.get("seed", randi())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var is_boss: bool = params.get("is_boss", false)
	var difficulty: float = clampf(params.get("difficulty", 0.5), 0.0, 1.0)
	var theme: String = params.get("hex_theme", "geocrash")

	var graph := DungeonGraph.new()

	# ── 1. Section specs ────────────────────────────────────────────────────────
	var section_specs := _generate_section_counts(rng, is_boss, difficulty)

	# ── 2. Critical path nodes ──────────────────────────────────────────────────
	var path_nodes: Array[int] = []
	var prev_id := -1
	var trigger_node := -1

	for spec in section_specs:
		var section_name: String = spec[0]
		var room_count: int = spec[1]
		var sec_rng := RandomNumberGenerator.new()
		sec_rng.seed = seed_val + path_nodes.size()

		for i in range(room_count):
			var arch := _archetype_for_section(section_name, i, room_count, sec_rng)
			var dims := RoomArchetype.get_dimension_range(arch)
			var w := sec_rng.randi_range(dims.min_w, dims.max_w)
			var h := sec_rng.randi_range(dims.min_h, dims.max_h)

			var nid := graph.create_node(arch, w, h, path_nodes.size())
			path_nodes.append(nid)

			# Wire edge from previous node on critical path
			if prev_id >= 0:
				var exit_slot := _pick_exit_slot(graph.get_node(prev_id).archetype, sec_rng)
				var entry_slot := _pick_entry_slot(arch, sec_rng)
				graph.connect_nodes(prev_id, nid, exit_slot, entry_slot)

			prev_id = nid

			# Puzzle trigger — placed in the last room of the puzzle section
			if section_name == "puzzle" and i == room_count - 1:
				trigger_node = nid

	# ── 3. Start / end / critical path ──────────────────────────────────────────
	var start_id := path_nodes[0]
	var end_id := path_nodes[path_nodes.size() - 1]
	graph.set_start_node(start_id)
	graph.set_end_node(end_id)
	graph.set_critical_path(path_nodes)

	# ── 4. Branches ─────────────────────────────────────────────────────────────

	for i in range(path_nodes.size()):
		var nid := path_nodes[i]
		# Skip first 2 and last 2 nodes; they're structural
		if i < 2 or i >= path_nodes.size() - 2:
			continue
		# 30% chance per node for a branch
		if rng.randf() >= BRANCH_CHANCE_BASE:
			continue

		# Pick branch topology: 35% reconnect, 40% chain, 25% sub-dungeon
		var roll := rng.randf()
		var btype := BRANCH_RECONNECT if roll < 0.35 else (BRANCH_CHAIN if roll < 0.75 else BRANCH_SUB_DUNGEON)

		# Need a spare slot on the origin node for the branch exit
		var origin_slot := _pick_spare_slot(graph.get_node(nid).archetype, nid, graph, rng)
		if origin_slot.is_empty():
			continue

		match btype:
			BRANCH_RECONNECT:
				_build_reconnect_branch(graph, nid, i, path_nodes, origin_slot, rng)
			BRANCH_CHAIN:
				var depth := rng.randi_range(2, 3)
				_build_linear_branch(graph, nid, origin_slot, depth, rng)
			BRANCH_SUB_DUNGEON:
				var depth := rng.randi_range(3, 5)
				_build_linear_branch(graph, nid, origin_slot, depth, rng, true)

	# ── 5. Checkpoints ──────────────────────────────────────────────────────────
	for i in range(CHECKPOINT_INTERVAL, path_nodes.size(), CHECKPOINT_INTERVAL):
		var n := graph.get_node(path_nodes[i])
		if n != null:
			n.is_dead_end = false  # ensure no accidental flag
			# store checkpoint flag via metadata — we add a flag property
			# DungeonGraph doesn't have checkpoint property on nodes, so we'll
			# track it via a separate dictionary in DungeonGraph.
			_checkpoint_nodes.append(path_nodes[i])

	# ── 6. Puzzle wiring ────────────────────────────────────────────────────────
	if trigger_node >= 0:
		_wire_puzzle_graph(graph, trigger_node, path_nodes)

	# ── 7. Validation ───────────────────────────────────────────────────────────
	var vresult := graph.validate()
	if not vresult.valid:
		push_warning("DungeonGenerator: graph validation failed:\n  %s" % "\n  ".join(vresult.errors))

	# ── 8. Store metadata ───────────────────────────────────────────────────────
	graph.meta["seed"] = seed_val
	graph.meta["is_boss"] = is_boss
	graph.meta["hex_theme"] = theme
	graph.meta["difficulty"] = difficulty
	graph.meta["checkpoint_nodes"] = _checkpoint_nodes.duplicate()
	if trigger_node >= 0:
		graph.meta["trigger_node"] = trigger_node

	return graph

# ── Checkpoint tracking (bridge for DungeonGraph) ─────────────────────────────
var _checkpoint_nodes: Array[int] = []

func get_checkpoint_nodes() -> Array[int]:
	return _checkpoint_nodes.duplicate()

# ── Archetype selection ───────────────────────────────────────────────────────
static func _archetype_for_section(section: String, room_idx: int, total: int, rng: RandomNumberGenerator) -> int:
	match section:
		"approach":
			if room_idx == 0:
				return RoomArchetype.Archetype.SANCTUARY
			return RoomArchetype.Archetype.GUARD_POST
		"puzzle":
			return RoomArchetype.Archetype.RITUAL_CHAMBER
		"exploration":
			if rng.randf() < 0.4:
				return RoomArchetype.Archetype.STORAGE_VAULT
			return RoomArchetype.Archetype.QUARRY
		"setback":
			if room_idx == total - 1:
				return RoomArchetype.Archetype.COLLAPSED_HALL
			return RoomArchetype.Archetype.BRIDGE_SPAN
		"climax":
			if room_idx == total - 1:
				return RoomArchetype.Archetype.RITUAL_CHAMBER
			if rng.randf() < 0.5:
				return RoomArchetype.Archetype.GUARD_POST
			return RoomArchetype.Archetype.BRIDGE_SPAN
		"reward":
			return RoomArchetype.Archetype.SANCTUARY
	return RoomArchetype.Archetype.GUARD_POST

static func _branch_archetype(rng: RandomNumberGenerator) -> int:
	var options := [
		RoomArchetype.Archetype.WATCHTOWER,
		RoomArchetype.Archetype.COLLAPSED_HALL,
		RoomArchetype.Archetype.SANCTUARY,
		RoomArchetype.Archetype.STORAGE_VAULT,
	]
	return options[rng.randi_range(0, options.size() - 1)]

# ── Portal slot matching ──────────────────────────────────────────────────────
# Returns a right-side slot ID for use as an exit from this archetype.
static func _pick_exit_slot(archetype: int, rng: RandomNumberGenerator) -> String:
	var slots := RoomArchetype.get_available_portal_slots(archetype)
	var rights: Array[RoomArchetype.PortalSlot] = []
	for s in slots:
		if s.side == "right":
			rights.append(s)
	if rights.is_empty():
		return slots[0].slot_id if not slots.is_empty() else "right-ground"
	return rights[rng.randi_range(0, rights.size() - 1)].slot_id

static func _pick_entry_slot(archetype: int, rng: RandomNumberGenerator) -> String:
	var slots := RoomArchetype.get_available_portal_slots(archetype)
	var lefts: Array[RoomArchetype.PortalSlot] = []
	for s in slots:
		if s.side == "left":
			lefts.append(s)
	if lefts.is_empty():
		return slots[0].slot_id if not slots.is_empty() else "left-ground"
	return lefts[rng.randi_range(0, lefts.size() - 1)].slot_id

static func _pick_spare_slot(archetype: int, node_id: int, graph: DungeonGraph, rng: RandomNumberGenerator) -> String:
	var slots := RoomArchetype.get_available_portal_slots(archetype)
	var node := graph.get_node(node_id)
	if node == null:
		return ""
	var used: Dictionary = {}
	var used_sides: Dictionary = {}
	for p in node.portals:
		used[p.slot_id] = true
	# Determine which sides are already in use on this node
	for s in slots:
		if used.has(s.slot_id):
			used_sides[s.side] = true

	var all_free: Array[RoomArchetype.PortalSlot] = []
	var preferred: Array[RoomArchetype.PortalSlot] = []
	for s in slots:
		if not used.has(s.slot_id):
			all_free.append(s)
			# Prefer a side not yet used — ensures entry+exit on opposite sides
			if not used_sides.has(s.side):
				preferred.append(s)

	if not preferred.is_empty():
		return preferred[rng.randi_range(0, preferred.size() - 1)].slot_id
	if not all_free.is_empty():
		return all_free[rng.randi_range(0, all_free.size() - 1)].slot_id
	return ""

# Returns "left" or "right" for a given slot_id on an archetype.
static func _get_slot_side(archetype: int, slot_id: String) -> String:
	var slots := RoomArchetype.get_available_portal_slots(archetype)
	for s in slots:
		if s.slot_id == slot_id:
			return s.side
	return "right"

# Picks a free slot on the given side of a node. Falls back to any free slot if
# the preferred side has no free slots, and finally to any free slot at all.
static func _pick_slot_on_side(archetype: int, side: String, node_id: int, graph: DungeonGraph, rng: RandomNumberGenerator) -> String:
	var slots := RoomArchetype.get_available_portal_slots(archetype)
	var node := graph.get_node(node_id)
	var used: Dictionary = {}
	if node != null:
		for p in node.portals:
			used[p.slot_id] = true

	var on_side: Array[RoomArchetype.PortalSlot] = []
	var any_free: Array[RoomArchetype.PortalSlot] = []
	for s in slots:
		if not used.has(s.slot_id):
			any_free.append(s)
			if s.side == side:
				on_side.append(s)

	if not on_side.is_empty():
		return on_side[rng.randi_range(0, on_side.size() - 1)].slot_id
	if not any_free.is_empty():
		return any_free[rng.randi_range(0, any_free.size() - 1)].slot_id
	return ""

# ── Branch generation helpers ─────────────────────────────────────────────────
# Builds a linear chain of branch rooms. Last room is a dead-end with a secret.
#   always_boss=true → terminal secret is always SECRET_BOSS (sub-dungeon)
static func _build_linear_branch(graph: DungeonGraph, origin_id: int, origin_slot: String, depth: int, rng: RandomNumberGenerator, always_boss: bool = false) -> void:
	var prev_id := origin_id
	var prev_slot := origin_slot

	for b in range(depth):
		var branch_arch := _branch_archetype(rng)
		var bdims := RoomArchetype.get_dimension_range(branch_arch)
		var bw := rng.randi_range(bdims.min_w, bdims.max_w)
		var bh := rng.randi_range(bdims.min_h, bdims.max_h)
		var bid := graph.create_node(branch_arch, bw, bh, -1)

		# Entry side is opposite of the source slot's side so the player
		# always exits from the opposite side of the room they entered from.
		var src_side := _get_slot_side(graph.get_node(prev_id).archetype, prev_slot)
		var entry_side := "left" if src_side == "right" else "right"
		var entry_slot := _pick_slot_on_side(branch_arch, entry_side, bid, graph, rng)
		graph.connect_nodes(prev_id, bid, prev_slot, entry_slot)

		prev_id = bid
		prev_slot = _pick_spare_slot(branch_arch, bid, graph, rng)
		if prev_slot.is_empty() and b + 1 < depth:
			push_warning("DungeonGenerator: no spare slot on branch node %d, terminating early" % bid)
			break

		if b == depth - 1:
			var secret_type := DungeonGraph.SecretType.SECRET_BOSS if (always_boss or rng.randf() < 0.5) else DungeonGraph.SecretType.SECRET_REWARD
			graph.mark_dead_end(bid, secret_type)

# Builds a reconnect branch: a chain from origin_id to a later critical-path node,
# creating a shortcut that skips intermediate rooms. Falls back to linear chain
# if no valid reconnection target is found.
static func _build_reconnect_branch(graph: DungeonGraph, origin_id: int, origin_idx: int, path_nodes: Array[int], origin_slot: String, rng: RandomNumberGenerator) -> void:
	var target_id := -1
	var target_slot := ""
	# Determine which side the target node must receive the reconnect portal on.
	# Branch travel direction is opposite of the origin slot's side:
	#   origin RIGHT → branch travels right → last exits RIGHT → target receives LEFT
	#   origin LEFT  → branch travels left  → last exits RIGHT → target receives RIGHT
	# In both cases, the player enters the target room continuing in the same
	# direction they were traveling through the branch.
	var origin_side := _get_slot_side(graph.get_node(origin_id).archetype, origin_slot)
	var target_side := "left" if origin_side == "right" else "right"
	for j in range(origin_idx + 2, path_nodes.size()):
		var candidate_id := path_nodes[j]
		var arch := graph.get_node(candidate_id).archetype
		var slot := _pick_slot_on_side(arch, target_side, candidate_id, graph, rng)
		if not slot.is_empty():
			target_id = candidate_id
			target_slot = slot
			break

	if target_id < 0:
		push_warning("DungeonGenerator: reconnect branch - no reconnection target found, falling back to chain")
		_build_linear_branch(graph, origin_id, origin_slot, rng.randi_range(2, 3), rng)
		return

	var branch_count := rng.randi_range(1, 3)
	var prev_id := origin_id
	var prev_slot := origin_slot

	for b in range(branch_count):
		var branch_arch := _branch_archetype(rng)
		var bdims := RoomArchetype.get_dimension_range(branch_arch)
		var bw := rng.randi_range(bdims.min_w, bdims.max_w)
		var bh := rng.randi_range(bdims.min_h, bdims.max_h)
		var bid := graph.create_node(branch_arch, bw, bh, -1)

		# Entry side is opposite of the source slot's side.
		var src_side := _get_slot_side(graph.get_node(prev_id).archetype, prev_slot)
		var entry_side := "left" if src_side == "right" else "right"
		var entry_slot := _pick_slot_on_side(branch_arch, entry_side, bid, graph, rng)
		graph.connect_nodes(prev_id, bid, prev_slot, entry_slot)

		prev_id = bid
		if b < branch_count - 1:
			prev_slot = _pick_spare_slot(branch_arch, bid, graph, rng)
			if prev_slot.is_empty():
				push_warning("DungeonGenerator: no spare slot on reconnect branch node %d, terminating" % bid)
				break
		else:
			# Last branch node — connect forward to the target CP node
			var exit_slot := _pick_exit_slot(branch_arch, rng)
			graph.connect_nodes(bid, target_id, exit_slot, target_slot)

# ── Puzzle wiring (graph version) ────────────────────────────────────────────
static func _wire_puzzle_graph(graph: DungeonGraph, trigger_node: int, path_nodes: Array[int]) -> void:
	var trigger_idx := -1
	for i in range(path_nodes.size()):
		if path_nodes[i] == trigger_node:
			trigger_idx = i
			break
	if trigger_idx < 0:
		return

	# Find the next combat node after trigger to lock
	var lock_from := -1
	var lock_to := -1
	for i in range(trigger_idx + 1, path_nodes.size()):
		var n := graph.get_node(path_nodes[i])
		if n != null and n.archetype != RoomArchetype.Archetype.SANCTUARY:
			# Lock the portal between trigger_node's successor and this node
			if i - 1 >= 0:
				lock_from = path_nodes[i - 1]
				lock_to = path_nodes[i]
			break

	if lock_from >= 0 and lock_to >= 0:
		graph.lock_portal(lock_from, lock_to)
		graph.meta["lock_from"] = lock_from
		graph.meta["lock_to"] = lock_to

# ═════════════════════════════════════════════════════════════════════════════
# LEGACY: generate_plan() — maintained for backward compat until Step 9
# ═════════════════════════════════════════════════════════════════════════════

func generate_plan(params: Dictionary) -> DungeonPlan:
	var seed_val: int = params.get("seed", randi())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var is_boss: bool = params.get("is_boss", false)
	var theme: String = params.get("hex_theme", "geocrash")
	var difficulty: float = clampf(params.get("difficulty", 0.5), 0.0, 1.0)

	var plan := DungeonPlan.new(seed_val, is_boss, theme)

	var section_specs := _generate_section_counts(rng, is_boss, difficulty)

	for spec in section_specs:
		var section_name: String = spec[0]
		var room_count: int = spec[1]
		var rng_for_section := RandomNumberGenerator.new()
		rng_for_section.seed = seed_val + plan.rooms.size()

		plan.mark_section_start(section_name, plan.rooms.size())

		for i in range(room_count):
			var room := DungeonPlan.make_room_spec()
			room["section"] = section_name
			room["room_type"] = _room_type_for_section(section_name, i, room_count, rng_for_section)

			if plan.rooms.size() > 0 and plan.rooms.size() % CHECKPOINT_INTERVAL == 0:
				room["has_checkpoint"] = true

			var enemy_data := _enemies_for_room(section_name, i, room_count, difficulty, rng_for_section, is_boss)
			room["enemies"] = enemy_data["enemies"]
			room["has_champion"] = enemy_data["has_champion"]

			if section_name == "puzzle" and i == room_count - 1:
				room["has_trigger"] = true
				room["trigger_type"] = "pressure_plate"

			if section_name == "climax" and i == room_count - 1:
				room["is_boss_room"] = is_boss
				room["room_type"] = "boss"

			if section_name == "reward" and i == room_count - 1:
				room["is_last_room"] = true
				room["room_type"] = "reward"

			plan.add_room(room)

	_wire_puzzles(plan)

	return plan

func _generate_section_counts(rng: RandomNumberGenerator, is_boss: bool, difficulty: float) -> Array:
	var per_section := int(1.0 + difficulty * 3.0)
	per_section = clampi(per_section, MIN_ROOMS_PER_SECTION, MAX_ROOMS_PER_SECTION)

	var sections := [
		["approach",    maxi(1, per_section - 1)],
		["puzzle",      1],
		["exploration", per_section],
		["setback",     maxi(1, per_section - 1)],
		["climax",      per_section if is_boss else per_section],
		["reward",      1],
	]

	if is_boss:
		sections[3][1] += 1
		sections[4][1] += 1

	return sections

func _room_type_for_section(section: String, room_idx: int, total: int, rng: RandomNumberGenerator) -> String:
	match section:
		"approach":
			if room_idx == 0:
				return "transition"
			return "combat"
		"puzzle":
			return "puzzle"
		"exploration":
			if rng.randf() < 0.3:
				return "exploration"
			return "combat"
		"setback":
			if room_idx == total - 1:
				return "combat"
			return "combat"
		"climax":
			if room_idx == total - 1:
				return "boss"
			return "combat"
		"reward":
			return "reward"
	return "combat"

func _enemies_for_room(section: String, room_idx: int, total: int, difficulty: float, rng: RandomNumberGenerator, is_boss: bool) -> Dictionary:
	var nullman := 0
	var rival := 0
	var champion := false

	match section:
		"approach":
			if room_idx == 0:
				nullman = 0
			else:
				nullman = 1 + int(difficulty * 2.0)
				if difficulty > 0.6:
					nullman = maxi(1, nullman - 1)
					rival = 1
				if room_idx == total - 1:
					champion = true
		"puzzle":
			nullman = 1 + int(difficulty * 1.0)
		"exploration":
			var scale := int(difficulty * 3.0 + float(room_idx) / float(total) * 2.0)
			if rng.randf() < 0.7:
				nullman = clampi(scale, 1, 4)
			else:
				nullman = clampi(scale - 1, 0, 3)
				rival = 1
		"setback":
			if room_idx == total - 1:
				nullman = 2 + int(difficulty * 2.0)
				rival = 1
			else:
				nullman = 1 + int(difficulty * 2.0)
		"climax":
			if room_idx == total - 1:
				champion = true
				nullman = 0
				rival = 0
			else:
				nullman = 2 + int(difficulty * 2.0)
				if rng.randf() < 0.4:
					rival = 1
		"reward":
			nullman = 0
			rival = 0

	return {
		"enemies": {"nullman": nullman, "rival": rival},
		"has_champion": champion,
	}

func _wire_puzzles(plan: DungeonPlan) -> void:
	var trigger_room_idx := -1
	var lock_target_idx := -1

	for i in range(plan.rooms.size()):
		var room: Dictionary = plan.rooms[i]
		if room["has_trigger"]:
			trigger_room_idx = i
		if trigger_room_idx >= 0 and room["section"] != "puzzle" and room["room_type"] == "combat":
			lock_target_idx = i
			break

	if trigger_room_idx >= 0 and lock_target_idx < 0:
		for i in range(plan.rooms.size()):
			var room: Dictionary = plan.rooms[i]
			if room["section"] == "exploration":
				lock_target_idx = i

	if trigger_room_idx >= 0 and lock_target_idx >= 0 and trigger_room_idx < lock_target_idx:
		plan.rooms[lock_target_idx]["door_locked"] = true
		plan.rooms[lock_target_idx]["locked_by_room"] = trigger_room_idx
