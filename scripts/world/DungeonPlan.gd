extends RefCounted
class_name DungeonPlan
# DungeonPlan.gd — read-only dungeon description.
#
# Legacy: flat `rooms: Array[Dictionary]` of room specs (used by old Game.gd).
# New: stores a DungeonGraph directly (used by new generate_graph() pipeline).
#
# The new flow: DungeonGenerator.generate_graph() → DungeonGraph
# Game.gd traverses the graph directly, making DungeonPlan mostly a metadata
# wrapper. The `rooms` array is kept for backward compat until Step 9.

# ── Legacy ─────────────────────────────────────────────────────────────────────
var rooms: Array  # Array[Dictionary] — only populated by legacy generate_plan()
var seed: int
var is_boss_dungeon: bool
var hex_theme: String
var _section_starts: Dictionary  # String → int room_index (legacy)

# ── New ───────────────────────────────────────────────────────────────────────
var graph: DungeonGraph  # null unless created via from_graph()

func _init(sd: int, boss: bool, theme: String) -> void:
	seed = sd
	is_boss_dungeon = boss
	hex_theme = theme
	rooms = []
	_section_starts = {}
	graph = null

# ── Factory: create from a DungeonGraph ──────────────────────────────────────
static func from_graph(g: DungeonGraph, sd: int, boss: bool, theme: String) -> DungeonPlan:
	var plan := DungeonPlan.new(sd, boss, theme)
	plan.graph = g
	plan.rooms = []  # leave empty — graph is the source of truth
	return plan

# ── Legacy methods ─────────────────────────────────────────────────────────────
func add_room(spec: Dictionary) -> void:
	spec["index"] = rooms.size()
	rooms.append(spec)

func mark_section_start(section: String, room_index: int) -> void:
	_section_starts[section] = room_index

func get_section_start(section: String) -> int:
	return _section_starts.get(section, -1)

func get_section_of_room(room_index: int) -> String:
	for section in ["approach", "puzzle", "exploration", "setback", "climax", "reward"]:
		var start: int = _section_starts.get(section, -1)
		var next_start: int = _get_next_section_start(section)
		if start >= 0 and room_index >= start and (next_start < 0 or room_index < next_start):
			return section
	return ""

func _get_next_section_start(section: String) -> int:
	var sections := ["approach", "puzzle", "exploration", "setback", "climax", "reward"]
	var found := false
	for s in sections:
		if found:
			var idx: int = _section_starts.get(s, -1)
			if idx >= 0:
				return idx
		if s == section:
			found = true
	return -1

static func make_room_spec() -> Dictionary:
	return {
		"index": -1,
		"section": "",
		"room_type": "combat",
		"has_checkpoint": false,
		"has_trigger": false,
		"trigger_type": "",
		"door_locked": false,
		"locked_by_room": -1,
		"enemies": {},
		"has_champion": false,
		"is_boss_room": false,
		"is_last_room": false,
	}

static func room_count_estimate(plan: DungeonPlan) -> int:
	if plan.graph != null:
		return plan.graph.get_node_count()
	return plan.rooms.size()
