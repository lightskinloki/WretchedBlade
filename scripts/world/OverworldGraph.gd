extends RefCounted
class_name OverworldGraph
# OverworldGraph.gd — Campaign-level graph connecting the 7 Dominator regions.
# Each node represents a region on the overworld map. Clearing a region's boss
# unlocks adjacent region nodes.

# ── Node types ────────────────────────────────────────────────────────────────
enum NodeType {
	STARTER_VAULT,   # Tutorial dungeon ("The Shattered Vault")
	CAMPSITE,        # Safe rest area between regions
	DUNGEON,         # Standard multi-room procedural dungeon section
	HEX_RIFT,        # Unstable rift with heavy hex hazards
	BOSS_GATE,       # Region boss encounter gate
}

# ── Overworld node ────────────────────────────────────────────────────────────
class OverworldNode:
	var node_id: int
	var display_name: String
	var hex_theme: String          # "geocrash", "voidrend", etc.
	var difficulty: float          # 0.0 – 1.0
	var node_type: int             # NodeType enum
	var unlocked: bool
	var cleared: bool
	var connections: Array[int]    # Adjacent node IDs
	var map_position: Vector2      # Visual position on the overworld canvas
	var lore_blurb: String

	func _init(
		nid: int,
		name: String,
		theme: String,
		diff: float,
		ntype: int,
		pos: Vector2,
		lore: String = ""
	) -> void:
		node_id = nid
		display_name = name
		hex_theme = theme
		difficulty = diff
		node_type = ntype
		unlocked = false
		cleared = false
		connections = []
		map_position = pos
		lore_blurb = lore

# ── Graph data ────────────────────────────────────────────────────────────────
var nodes: Dictionary = {}  # int -> OverworldNode
var start_node_id: int = 0

# ── Build the campaign graph ──────────────────────────────────────────────────
# Layout:
#
#   [0: Shattered Vault] ──> [1: Campsite] ──> [2: Fractured Yards]
#                                  │                    │
#                                  ▼                    ▼
#                          [3: Hollow Expanse]   [4: Resonant Ruins]
#                                  │                    │
#                                  ▼                    ▼
#                          [5: Forgotten Archive] ──> [6: Unraveling Core]
#                                                       │
#                                                       ▼
#                                               [7: Corroded Expanse]
#                                                       │
#                                                       ▼
#                                               [8: Throne of Ashes]
#
static func build_campaign() -> OverworldGraph:
	var graph := OverworldGraph.new()

	# Node 0 — Tutorial / Starter Vault
	graph._add_node(OverworldNode.new(
		0, "The Shattered Vault", "geocrash", 0.3, NodeType.STARTER_VAULT,
		Vector2(80, 195),
		"An ancient vault where the Wretched Blade first awakens. The walls bear Geocrash fractures from the First Hexocaust."
	))

	# Node 1 — Campsite (safe hub after tutorial)
	graph._add_node(OverworldNode.new(
		1, "Ashen Campsite", "geocrash", 0.0, NodeType.CAMPSITE,
		Vector2(230, 195),
		"A sheltered alcove between the ruined yards. Rest here to attune the blade and refill Whetstones."
	))

	# Node 2 — Geocrash region: Fractured Yards
	graph._add_node(OverworldNode.new(
		2, "The Fractured Yards", "geocrash", 0.4, NodeType.BOSS_GATE,
		Vector2(420, 120),
		"Cubic, angular ruins at unnatural angles. The Shattered Sovereign's domain — grays, rust, and fractured earth."
	))

	# Node 3 — Voidrend region: Hollow Expanse
	graph._add_node(OverworldNode.new(
		3, "The Hollow Expanse", "voidrend", 0.5, NodeType.BOSS_GATE,
		Vector2(230, 80),
		"Scooped-out reality. Floating islands in empty space, void-edges, unreliable gravity. The Void Echo awaits."
	))

	# Node 4 — Echoscream region: Resonant Ruins
	graph._add_node(OverworldNode.new(
		4, "The Resonant Ruins", "echoscream", 0.55, NodeType.BOSS_GATE,
		Vector2(560, 195),
		"Impossibly tall sound-warping towers. Translucent walls, audiovisual distortion. The Screaming Spire reverberates."
	))

	# Node 5 — Memoreave region: Forgotten Archive
	graph._add_node(OverworldNode.new(
		5, "The Forgotten Archive", "memoreave", 0.65, NodeType.BOSS_GATE,
		Vector2(350, 280),
		"Memory-warped libraries and monuments. Perspective shifts, temporal echoes. The Memory Thief hoards lost minds."
	))

	# Node 6 — Nullpulse region: Unraveling Core
	graph._add_node(OverworldNode.new(
		6, "The Unraveling Core", "nullpulse", 0.75, NodeType.BOSS_GATE,
		Vector2(560, 310),
		"The world visibly unravels. Fragmenting ground, crackling energy, collapsing reality. The Nullpulse Heart beats."
	))

	# Node 7 — Technomantic region: Corroded Expanse
	graph._add_node(OverworldNode.new(
		7, "The Corroded Expanse", "technomantic", 0.85, NodeType.BOSS_GATE,
		Vector2(700, 250),
		"Rusted machinery and bio-mechanical corruption. Industrial decay fused with organic growth. The Rust Tyrant reigns."
	))

	# Node 8 — Final region: Throne of Ashes
	graph._add_node(OverworldNode.new(
		8, "The Throne of Ashes", "nullpulse", 1.0, NodeType.BOSS_GATE,
		Vector2(700, 120),
		"Ash, bone, and echoes of all prior Hexocausts. The Final Echo — the Wretched Blade's inverse — awaits the end."
	))

	# ── Connections ───────────────────────────────────────────────────────────
	graph._connect(0, 1)  # Vault -> Campsite
	graph._connect(1, 2)  # Campsite -> Fractured Yards
	graph._connect(1, 3)  # Campsite -> Hollow Expanse
	graph._connect(2, 4)  # Fractured Yards -> Resonant Ruins
	graph._connect(3, 5)  # Hollow Expanse -> Forgotten Archive
	graph._connect(4, 6)  # Resonant Ruins -> Unraveling Core
	graph._connect(5, 6)  # Forgotten Archive -> Unraveling Core
	graph._connect(6, 7)  # Unraveling Core -> Corroded Expanse
	graph._connect(7, 8)  # Corroded Expanse -> Throne of Ashes

	# Starter vault is always unlocked
	graph.nodes[0].unlocked = true
	graph.start_node_id = 0

	return graph

# ── Internal helpers ──────────────────────────────────────────────────────────
func _add_node(node: OverworldNode) -> void:
	nodes[node.node_id] = node

func _connect(a: int, b: int) -> void:
	if nodes.has(a) and nodes.has(b):
		if not nodes[a].connections.has(b):
			nodes[a].connections.append(b)
		if not nodes[b].connections.has(a):
			nodes[b].connections.append(a)

# ── Public API ────────────────────────────────────────────────────────────────
func get_node(nid: int) -> OverworldNode:
	return nodes.get(nid)

func mark_cleared(nid: int) -> void:
	if not nodes.has(nid):
		return
	nodes[nid].cleared = true
	# Unlock all adjacent nodes
	for adj_id in nodes[nid].connections:
		if nodes.has(adj_id):
			nodes[adj_id].unlocked = true

func get_unlocked_nodes() -> Array:
	var result: Array = []
	for nid in nodes:
		if nodes[nid].unlocked:
			result.append(nodes[nid])
	return result

func get_all_nodes() -> Array:
	var result: Array = []
	for nid in nodes:
		result.append(nodes[nid])
	return result
