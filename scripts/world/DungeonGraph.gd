extends RefCounted
class_name DungeonGraph

# Ã¢â€â‚¬Ã¢â€â‚¬ Secret content type Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
enum SecretType {
	NONE,
	SECRET_BOSS,
	SECRET_REWARD,
}

# Ã¢â€â‚¬Ã¢â€â‚¬ Graph node Ã¢â‚¬â€ one room Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
class RoomNode:
	var node_id: int
	var archetype: int
	var room_w: int
	var room_h: int
	var section_id: int
	var on_critical_path: bool
	var is_dead_end: bool
	var secret_type: int
	var complexity: float
	var portals: Array

	func _init(
		nid: int,
		arch: int,
		w: int,
		hh: int,
		sec: int
	) -> void:
		node_id = nid
		archetype = arch
		room_w = w
		room_h = hh
		section_id = sec
		on_critical_path = false
		is_dead_end = false
		secret_type = SecretType.NONE
		complexity = 0.5
		portals = []

# Ã¢â€â‚¬Ã¢â€â‚¬ Edge descriptor for errors and validation Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
class GraphEdge:
	var from_node: int
	var to_node: int
	var from_slot: String
	var to_slot: String

	func _init(f: int, t: int, fs: String, ts: String) -> void:
		from_node = f
		to_node = t
		from_slot = fs
		to_slot = ts

# Ã¢â€â‚¬Ã¢â€â‚¬ DungeonGraph Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
var _node_map: Dictionary  # int -> RoomNode
var _next_id: int = 0
var _start_node: int = -1
var _end_node: int = -1
var _critical_path: Array[int] = []
var meta: Dictionary = {}

# Ã¢â€â‚¬Ã¢â€â‚¬ Node lifecycle Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

# Creates a new node and returns its node_id.
func create_node(archetype: int, w: int, h: int, section: int) -> int:
	var nid := _next_id
	_next_id += 1
	var node := RoomNode.new(nid, archetype, w, h, section)
	_node_map[nid] = node
	return nid

func has_node(nid: int) -> bool:
	return _node_map.has(nid)

func get_node(nid: int) -> RoomNode:
	return _node_map.get(nid)

func get_all_nodes() -> Array:
	var result: Array[RoomNode] = []
	for nid in _node_map:
		result.append(_node_map[nid])
	return result

func get_node_count() -> int:
	return _node_map.size()

# Ã¢â€â‚¬Ã¢â€â‚¬ Start / end Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
func set_start_node(nid: int) -> void:
	assert(has_node(nid), "start node %d not in graph" % nid)
	_start_node = nid

func get_start_node() -> int:
	return _start_node

func set_end_node(nid: int) -> void:
	assert(has_node(nid), "end node %d not in graph" % nid)
	_end_node = nid

func get_end_node() -> int:
	return _end_node

# Ã¢â€â‚¬Ã¢â€â‚¬ Critical path Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
func set_critical_path(path: Array[int]) -> void:
	_critical_path = path
	for nid in path:
		var n := get_node(nid)
		if n != null:
			n.on_critical_path = true

func get_critical_path() -> Array[int]:
	return _critical_path.duplicate()

func is_on_critical_path(nid: int) -> bool:
	var n := get_node(nid)
	return n != null and n.on_critical_path

# Ã¢â€â‚¬Ã¢â€â‚¬ Edge management Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
# Connects two nodes bidirectionally with PortalData on each.
# slot_a: the slot_id on node_a used for this connection.
# slot_b: the slot_id on node_b used for this connection.
func connect_nodes(node_a: int, node_b: int, slot_a: String, slot_b: String) -> void:
	assert(has_node(node_a), "node_a %d not found" % node_a)
	assert(has_node(node_b), "node_b %d not found" % node_b)

	var na: RoomNode = _node_map[node_a]
	var nb: RoomNode = _node_map[node_b]

	# Prevent duplicate direct connections
	for p in na.portals:
		if p.connected_node == node_b:
			push_warning("DungeonGraph: duplicate edge %d<->%d skipped" % [node_a, node_b])
			return

	# Bidirectional portal data
	na.portals.append(RoomArchetype.PortalData.new(slot_a, node_b, true, -1))
	nb.portals.append(RoomArchetype.PortalData.new(slot_b, node_a, true, -1))

func get_neighbors(nid: int) -> Array[int]:
	var result: Array[int] = []
	var n := get_node(nid)
	if n == null:
		return result
	for p in n.portals:
		result.append(p.connected_node)
	return result

func get_edges_from(nid: int) -> Array:
	var n := get_node(nid)
	if n == null:
		return []
	var result: Array = []
	for p in n.portals:
		result.append(GraphEdge.new(nid, p.connected_node, p.slot_id, ""))
	return result

# Locks a portal (for puzzle wiring). Both directions are locked.
func lock_portal(from_node: int, to_node: int) -> void:
	var na := get_node(from_node)
	var nb := get_node(to_node)
	if na == null or nb == null:
		return
	for p in na.portals:
		if p.connected_node == to_node:
			p.is_open = false
			p.locked_by_room = -1
	for p in nb.portals:
		if p.connected_node == from_node:
			p.is_open = false
			p.locked_by_room = -1

func unlock_portal(from_node: int, to_node: int) -> void:
	var na := get_node(from_node)
	var nb := get_node(to_node)
	if na == null or nb == null:
		return
	for p in na.portals:
		if p.connected_node == to_node:
			p.is_open = true
			p.locked_by_room = -1
	for p in nb.portals:
		if p.connected_node == from_node:
			p.is_open = true
			p.locked_by_room = -1

# Ã¢â€â‚¬Ã¢â€â‚¬ Dead-end marking Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
func mark_dead_end(nid: int, secret: int) -> void:
	assert(has_node(nid), "dead end node %d not in graph" % nid)
	var n := get_node(nid)
	n.is_dead_end = true
	n.secret_type = secret

# Ã¢â€â‚¬Ã¢â€â‚¬ Validation Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
# Returns a Dictionary with keys:
#   valid: bool
#   errors: Array[String]
func validate() -> Dictionary:
	var errors: Array[String] = []

	# Empty graph check
	if _node_map.is_empty():
		return {"valid": false, "errors": ["graph is empty"]}

	# Start / end
	if _start_node == -1 or not has_node(_start_node):
		errors.append("invalid start node: %d" % _start_node)
	if _end_node == -1 or not has_node(_end_node):
		errors.append("invalid end node: %d" % _end_node)

	# Check each node
	for nid in _node_map:
		var n: RoomNode = _node_map[nid]

		# Self-loops
		for p in n.portals:
			if p.connected_node == nid:
				errors.append("self-loop at node %d" % nid)

		# Dead-end invariants
		if n.is_dead_end:
			if n.portals.size() != 1:
				errors.append("dead end node %d has %d portals (expected 1)" % [nid, n.portals.size()])
			if n.secret_type == SecretType.NONE:
				errors.append("dead end node %d has secret_type NONE" % nid)

		# Duplicate portal slot_ids on same node
		var used_slots: Dictionary = {}
		for p in n.portals:
			if used_slots.has(p.slot_id):
				errors.append("node %d has duplicate portal slot_id '%s'" % [nid, p.slot_id])
			used_slots[p.slot_id] = true

		# Duplicate connected_nodes on same node (two doors → same room)
		var used_connections: Dictionary = {}
		for p in n.portals:
			if used_connections.has(p.connected_node):
				errors.append("node %d has two portals leading to same node %d" % [nid, p.connected_node])
			used_connections[p.connected_node] = true

	# Bidirectional consistency (check A->B implies B->A)
	for nid in _node_map:
		var n: RoomNode = _node_map[nid]
		for p in n.portals:
			var target := get_node(p.connected_node)
			if target == null:
				errors.append("node %d references missing node %d" % [nid, p.connected_node])
				continue
			var found := false
			for tp in target.portals:
				if tp.connected_node == nid:
					found = true
					break
			if not found:
				errors.append("node %d has edge to %d but no reverse edge" % [nid, p.connected_node])

	# Critical path validity
	if _critical_path.is_empty() and _node_map.size() > 1:
		errors.append("critical path is empty but graph has %d nodes" % _node_map.size())

	# BFS reachability: every node must be reachable from start node
	if _start_node != -1 and has_node(_start_node):
		var visited: Dictionary = {}
		var queue: Array[int] = [_start_node]
		visited[_start_node] = true
		while not queue.is_empty():
			var cur := queue.pop_front() as int
			for p in _node_map[cur].portals:
				var nb: int = p.connected_node
				if not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
		for nid in _node_map:
			if not visited.has(nid):
				errors.append("node %d is not reachable from start %d" % [nid, _start_node])

	return {
		"valid": errors.is_empty(),
		"errors": errors,
	}

# Ã¢â€â‚¬Ã¢â€â‚¬ Debug Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
func describe() -> String:
	var parts: Array[String] = []
	parts.append("DungeonGraph (%d nodes)" % _node_map.size())
	parts.append("  start: %d  end: %d" % [_start_node, _end_node])
	parts.append("  critical path: %s" % str(_critical_path))
	for nid in _node_map:
		var n: RoomNode = _node_map[nid]
		var neighbors := ", ".join(PackedStringArray(get_neighbors(nid)))
		var flag := ""
		if n.is_dead_end: flag += " DEAD_END"
		if n.on_critical_path: flag += " CP"
		parts.append("  %d[%s](%dx%d)%s -> %s" % [
			nid,
			RoomArchetype.get_archetype_name(n.archetype),
			n.room_w, n.room_h,
			flag,
			neighbors,
		])
	return "\n".join(parts)
