extends Node
# EssenceManager — the souls-like currency system.
# Essence is gained by killing enemies. Lost on death. Recoverable at death spot.

# ── Signals ───────────────────────────────────────────────────────────────────
signal essence_changed(new_amount: int)         # Fires whenever essence total changes
signal lost_essence_spawned(position: Vector2)  # Fires when a death drops essence
signal lost_essence_recovered                    # Fires when player picks up lost essence

# ── State ─────────────────────────────────────────────────────────────────────
var current_essence: int = 0
var lost_essence: int = 0
var lost_essence_position: Vector2 = Vector2.ZERO
var _essence_gained_since_death := 0  # Reset on death, incremented on gain

# ── Public API ────────────────────────────────────────────────────────────────

func gain_essence(amount: int) -> void:
	current_essence += amount
	_essence_gained_since_death += amount
	emit_signal("essence_changed", current_essence)

# Returns false if player can't afford it
func spend_essence(amount: int) -> bool:
	if current_essence < amount:
		return false
	current_essence -= amount
	emit_signal("essence_changed", current_essence)
	return true

func can_afford(amount: int) -> bool:
	return current_essence >= amount

# Called by GameManager when the player dies
func on_player_death(death_position: Vector2) -> void:
	# Safe recovery: if no essence gained since last death and there's
	# already a pending orb, keep the old orb instead of replacing it.
	if _essence_gained_since_death == 0 and lost_essence > 0:
		_essence_gained_since_death = 0
		return

	if current_essence <= 0:
		_essence_gained_since_death = 0
		return

	lost_essence = current_essence
	lost_essence_position = death_position
	current_essence = 0
	_essence_gained_since_death = 0
	emit_signal("essence_changed", 0)
	emit_signal("lost_essence_spawned", death_position)

# Called when player walks over their previous death location
func recover_lost_essence() -> void:
	if lost_essence <= 0:
		return
	gain_essence(lost_essence)
	lost_essence = 0
	_essence_gained_since_death = 0
	emit_signal("lost_essence_recovered")

func has_lost_essence() -> bool:
	return lost_essence > 0
