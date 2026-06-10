extends RefCounted
class_name InputBuffer

const MAX_AGE    := 3.0
const BUFFER_MAX := 64

var _buffer:       Array[Dictionary] = []
var _hold_states:  Dictionary        = {}  # button -> hold_start_time  (for "hold" matcher)
var _custom_matchers: Dictionary     = {}

# charge_release tracking
var _charge_start:  Dictionary = {}  # button -> start_time
var _charged_set:   Dictionary = {}  # button -> true (threshold met, waiting for release)
var _release_fired: Dictionary = {}  # button -> true (released while charged, pending match)

# ── Public API ─────────────────────────────────────────────────────────────────
func record_action(action: String, timestamp: float) -> void:
	_buffer.append({"action": action, "time": timestamp})
	if _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()

func record_hold(button: String, is_held: bool, timestamp: float) -> void:
	# Legacy hold tracking (used by "hold" matcher)
	if is_held and not _hold_states.has(button):
		_hold_states[button] = timestamp
	elif not is_held:
		_hold_states.erase(button)

	# charge_release tracking
	if is_held:
		if not _charge_start.has(button) and not _charged_set.has(button):
			_charge_start[button] = timestamp
		_release_fired.erase(button)
	else:
		if _charged_set.has(button):
			_release_fired[button] = true
		_charge_start.erase(button)
		_charged_set.erase(button)

func register_matcher(type_name: String, matcher: Callable) -> void:
	_custom_matchers[type_name] = matcher

func match_hex(definition: Dictionary, current_time: float) -> bool:
	_purge_old(current_time)
	var raw_type = definition.get("type", "hold")
	match raw_type:
		"hold":
			return _match_hold(definition, current_time)
		"charge_release":
			return _match_charge_release(definition, current_time)
		"combo":
			return _match_combo(definition, current_time)
		"sequence":
			return _match_sequence(definition, current_time)
		_:
			if _custom_matchers.has(raw_type):
				return _custom_matchers[raw_type].call(_buffer, definition, _hold_states, current_time)
	return false

# Returns 0.0–1.0 charge progress for a button.  Returns 0.0 if not charging.
func get_charge_progress(button: String, duration: float) -> float:
	if not _charge_start.has(button):
		return 0.0
	var held = Time.get_ticks_usec() / 1000000.0 - _charge_start[button]
	return clampf(held / duration, 0.0, 1.0)

# Returns true if button is currently in charge state (held but not yet released).
func is_charging(button: String) -> bool:
	return _charge_start.has(button) or _charged_set.has(button)

# Returns true if button has reached charge threshold (still held).
func is_charged(button: String) -> bool:
	return _charged_set.has(button)

# ── Hold matcher — fires repeatedly while held past threshold ──────────────────
func _match_hold(definition: Dictionary, current_time: float) -> bool:
	var raw_btn = definition.get("button", "attack")
	var raw_dur = definition.get("duration", 0.4)
	if _hold_states.has(raw_btn):
		return current_time - _hold_states[raw_btn] >= raw_dur
	return false

# ── Charge-release matcher — fires ONCE on release after hold threshold ────────
func _match_charge_release(definition: Dictionary, current_time: float) -> bool:
	var raw_btn = definition.get("button", "attack")
	var raw_dur = definition.get("duration", 1.0)

	if _charge_start.has(raw_btn) and not _charged_set.has(raw_btn):
		if current_time - _charge_start[raw_btn] >= raw_dur:
			_charged_set[raw_btn] = true

	if _release_fired.has(raw_btn):
		_release_fired.erase(raw_btn)
		return true

	return false

# ── Combo matcher ──────────────────────────────────────────────────────────────
func _match_combo(definition: Dictionary, current_time: float) -> bool:
	var sequence = definition.get("sequence", [])
	if sequence.is_empty() or _buffer.is_empty():
		return false

	var last_action = sequence.back()
	if typeof(last_action) != TYPE_STRING or _buffer.back().action != last_action:
		return false
	if current_time - _buffer.back().time > 0.3:
		return false

	var seq_len = sequence.size()
	if _buffer.size() < seq_len:
		return false

	for i in range(seq_len):
		var seq_action = sequence[seq_len - 1 - i]
		var buf_action = _buffer[_buffer.size() - 1 - i].action
		if typeof(seq_action) != TYPE_STRING or buf_action != seq_action:
			return false

	return true

# ── Sequence matcher ───────────────────────────────────────────────────────────
func _match_sequence(definition: Dictionary, _current_time: float) -> bool:
	var sequence = definition.get("sequence", [])
	if sequence.is_empty() or _buffer.is_empty():
		return false

	for start_idx in range(_buffer.size() - sequence.size() + 1):
		var match_all = true
		for i in range(sequence.size()):
			if typeof(sequence[i]) != TYPE_STRING:
				match_all = false
				break
			if _buffer[start_idx + i].action != sequence[i]:
				match_all = false
				break
		if match_all:
			return true

	return false

# ── Internal ───────────────────────────────────────────────────────────────────
func _purge_old(current_time: float) -> void:
	while _buffer.size() > 0 and current_time - _buffer[0].time > MAX_AGE:
		_buffer.pop_front()

func clear() -> void:
	_buffer.clear()
	_hold_states.clear()
	_charge_start.clear()
	_charged_set.clear()
	_release_fired.clear()
