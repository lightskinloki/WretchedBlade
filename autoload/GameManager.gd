extends Node
# GameManager — loaded automatically, available everywhere as GameManager.something
# Tracks death, checkpoints, and overall game state.

# ── Signals ──────────────────────────────────────────────────────────────────
# Other nodes can listen to these events with:  GameManager.player_died.connect(my_function)
signal player_died(position: Vector2)
signal player_reconstituted
signal checkpoint_set(position: Vector2)
signal whetstone_used(remaining: int)
signal whetstone_refilled(count: int)
signal god_mode_toggled(active: bool)

# ── State ─────────────────────────────────────────────────────────────────────
enum GameState { PLAYING, DEAD, RECONSTITUTING, PAUSED }
var state: GameState = GameState.PLAYING

# ── CRITICAL LAUNCH CHECKLIST ITEM ───────────────────────────────────────────
# TODO: REMOVE / DISABLE GOD MODE BEFORE RELEASE!
# God mode allows infinite stats / dev toggles. Ensure `is_god_mode` and `toggle_god_mode()`
# are completely removed or guarded behind debug builds (OS.is_debug_build()) prior to production launch.
var is_god_mode: bool = false

# ── Blade & Lineage Progression State ─────────────────────────────────────────
var max_whetstone_capacity: int = 3
const MAX_WHETSTONES := 3  # Legacy fallback
var whetstone_charges := 3

var checkpoint_position: Vector2 = Vector2(200, 600)  # Default spawn
var _hitstop_end_time := 0  # Real-time ms when hitstop ends

var blade_edge_level: int = 1
var poise_level: int = 1
var current_lineage: String = "cinder"
var hex_affinity_score: float = 0.0
var equipped_resonance_art: String = ""

# ── Campaign / Overworld State ────────────────────────────────────────────────
var is_first_run: bool = true  # True until the tutorial dungeon exit is reached
var overworld_graph: OverworldGraph = null
var active_region_data: Dictionary = {
	"node_id": 0,
	"hex_theme": "geocrash",
	"difficulty": 0.3,
	"is_boss": false,
	"seed": 0,
}

func _ready() -> void:
	overworld_graph = OverworldGraph.build_campaign()

# ── Upgrade & Lineage Helpers ────────────────────────────────────────────────
func get_edge_upgrade_cost() -> int:
	return blade_edge_level * 150

func upgrade_blade_edge() -> bool:
	var cost := get_edge_upgrade_cost()
	if EssenceManager.spend_essence(cost):
		blade_edge_level += 1
		return true
	return false

func get_poise_upgrade_cost() -> int:
	return poise_level * 120

func upgrade_poise() -> bool:
	var cost := get_poise_upgrade_cost()
	if EssenceManager.spend_essence(cost):
		poise_level += 1
		return true
	return false

func get_whetstone_upgrade_cost() -> int:
	return max_whetstone_capacity * 250

func upgrade_whetstone_capacity() -> bool:
	if max_whetstone_capacity >= 5:
		return false
	var cost := get_whetstone_upgrade_cost()
	if EssenceManager.spend_essence(cost):
		max_whetstone_capacity += 1
		whetstone_charges = max_whetstone_capacity
		emit_signal("whetstone_refilled", whetstone_charges)
		return true
	return false

func set_lineage(lineage: String) -> void:
	current_lineage = lineage

func enter_campsite_hub() -> void:
	state = GameState.PLAYING
	whetstone_charges = max_whetstone_capacity
	emit_signal("whetstone_refilled", whetstone_charges)
	get_tree().change_scene_to_file("res://scenes/world/CampsiteHub.tscn")

# ── Public API ────────────────────────────────────────────────────────────────

func toggle_god_mode() -> bool:
	is_god_mode = not is_god_mode
	emit_signal("god_mode_toggled", is_god_mode)
	print("[DEV] God Mode: ", "ENABLED" if is_god_mode else "DISABLED")
	return is_god_mode

# Call this when the blade shatters (player "dies")
func on_player_died(death_position: Vector2) -> void:
	if state == GameState.DEAD:
		return  # Already dead, ignore
	state = GameState.DEAD
	EssenceManager.on_player_death(death_position)
	emit_signal("player_died", death_position)

# Call this after the reconstitution animation completes
func on_reconstitution_complete() -> void:
	state = GameState.PLAYING
	emit_signal("player_reconstituted")

# Save a checkpoint (Tuning Fork location in lore)
func set_checkpoint(position: Vector2) -> void:
	checkpoint_position = position
	whetstone_charges = MAX_WHETSTONES
	emit_signal("checkpoint_set", position)
	emit_signal("whetstone_refilled", whetstone_charges)
	# Heal player on checkpoint touch
	if get_tree().current_scene.has_node("Player"):
		var player = get_tree().current_scene.get_node("Player")
		if player.has_method("heal"):
			player.heal()

func use_whetstone() -> bool:
	if is_god_mode:
		emit_signal("whetstone_used", whetstone_charges)
		return true
	if whetstone_charges <= 0:
		return false
	whetstone_charges -= 1
	emit_signal("whetstone_used", whetstone_charges)
	return true

func get_respawn_position() -> Vector2:
	return checkpoint_position

# Use this check before processing gameplay logic
func is_playing() -> bool:
	return state == GameState.PLAYING

# Trigger hitstop — freezes gameplay for duration_ms real-time milliseconds
func trigger_hitstop(duration_ms: int) -> void:
	Engine.time_scale = 0.0
	_hitstop_end_time = Time.get_ticks_msec() + duration_ms

# Check hitstop each frame (uses real-time clock, unaffected by time_scale)
func _process(_delta: float) -> void:
	if _hitstop_end_time > 0 and Time.get_ticks_msec() >= _hitstop_end_time:
		Engine.time_scale = 1.0
		_hitstop_end_time = 0

# ── Campaign Transitions ─────────────────────────────────────────────────────

# Called when the player reaches a dungeon exit
func complete_current_region() -> void:
	var nid: int = active_region_data.get("node_id", 0)
	if overworld_graph != null:
		overworld_graph.mark_cleared(nid)
	if is_first_run:
		is_first_run = false

# Set up region data and transition into a dungeon
func start_dungeon(node_id: int) -> void:
	if overworld_graph == null:
		return
	var ow_node: OverworldGraph.OverworldNode = overworld_graph.get_node(node_id)
	if ow_node == null:
		return

	active_region_data = {
		"node_id": node_id,
		"hex_theme": ow_node.hex_theme,
		"difficulty": ow_node.difficulty,
		"is_boss": ow_node.node_type == OverworldGraph.NodeType.BOSS_GATE,
		"seed": randi(),
	}

	# Reset gameplay state for the new dungeon
	state = GameState.PLAYING
	checkpoint_position = Vector2(200, 600)
	whetstone_charges = MAX_WHETSTONES

	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")

# Return to the overworld map
func return_to_overworld() -> void:
	state = GameState.PLAYING
	get_tree().change_scene_to_file("res://scenes/ui/OverworldMap.tscn")
