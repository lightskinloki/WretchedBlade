extends Node
# HexManager — autoload.  Tracks known hexes, cooldowns, and input matching.
#
# WretchedBlade calls poll_input() each frame; when a valid hex input is
# detected, essence is spent and hex_triggered is emitted for the blade
# to fire the visual/hitbox effect.

signal hex_triggered(hex_id: String)
signal hex_unlocked(hex_id: String)  # Fires once when a hex is first obtained

var known_hexes: Dictionary = {}  # hex_id (String) -> HexAbility
var _cooldowns: Dictionary  = {}  # hex_id (String) -> remaining seconds
var _newly_unlocked: Array[String] = []


func _process(delta: float) -> void:
	for hex_id in _cooldowns.keys():
		_cooldowns[hex_id] -= delta
		if _cooldowns[hex_id] <= 0.0:
			_cooldowns.erase(hex_id)


# ── Hex management ─────────────────────────────────────────────────────────────

func unlock_hex(hex: HexAbility) -> void:
	known_hexes[hex.id] = hex
	if hex.id not in _newly_unlocked:
		_newly_unlocked.append(hex.id)
	hex_unlocked.emit(hex.id)


func has_unseen_unlock() -> bool:
	return not _newly_unlocked.is_empty()


func pop_new_unlocks() -> Array[String]:
	var result: Array[String] = _newly_unlocked.duplicate()
	_newly_unlocked.clear()
	return result


# ── Input polling ──────────────────────────────────────────────────────────────

func poll_input(buffer: InputBuffer, current_time: float) -> void:
	for hex_id in known_hexes:
		if _cooldowns.has(hex_id):
			continue
		var hex: HexAbility = known_hexes[hex_id]
		if buffer.match_hex(hex.input_definition, current_time):
			if EssenceManager.spend_essence(hex.essence_cost):
				_cooldowns[hex_id] = hex.cooldown
				hex_triggered.emit(hex_id)
				return  # Only one hex per frame


# ── Queries ────────────────────────────────────────────────────────────────────

func get_hex(hex_id: String) -> HexAbility:
	return known_hexes.get(hex_id, null)


func is_on_cooldown(hex_id: String) -> bool:
	return _cooldowns.has(hex_id)


func get_cooldown_remaining(hex_id: String) -> float:
	return _cooldowns.get(hex_id, 0.0)


func get_all_hexes() -> Array[HexAbility]:
	var result: Array[HexAbility] = []
	for hex_id in known_hexes:
		result.append(known_hexes[hex_id])
	return result
