extends Node
# GameManager — loaded automatically, available everywhere as GameManager.something
# Tracks death, checkpoints, and overall game state.

# ── Signals ──────────────────────────────────────────────────────────────────
# Other nodes can listen to these events with:  GameManager.player_died.connect(my_function)
signal player_died(position: Vector2)
signal player_reconstituted
signal checkpoint_set(position: Vector2)

# ── State ─────────────────────────────────────────────────────────────────────
enum GameState { PLAYING, DEAD, RECONSTITUTING, PAUSED }
var state: GameState = GameState.PLAYING

var checkpoint_position: Vector2 = Vector2(200, 600)  # Default spawn
var _hitstop_end_time := 0  # Real-time ms when hitstop ends

# ── Public API ────────────────────────────────────────────────────────────────

# ── Public API ────────────────────────────────────────────────────────────────

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
	emit_signal("checkpoint_set", position)
	# Heal player on checkpoint touch
	if get_tree().current_scene.has_node("Player"):
		var player = get_tree().current_scene.get_node("Player")
		if player.has_method("heal"):
			player.heal()

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
