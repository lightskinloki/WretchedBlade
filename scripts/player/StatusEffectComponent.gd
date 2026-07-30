extends RefCounted
class_name StatusEffectComponent
# StatusEffectComponent.gd — data-driven status effect engine.
#
# Attached to Player (and optionally enemies/bosses). Each status tracks
# its own timer and params. All statuses stack independently.
# Call _process(delta) every frame from the owning node.
#
# Usage:
#   var fx: StatusEffectComponent = StatusEffectComponent.new()
#   fx.apply(StatusEffectComponent.ROOT, 1.2, {}, self)
#   fx.apply(StatusEffectComponent.SLOW, 2.5, {"mult": 0.6}, self)
#   if fx.has(StatusEffectComponent.ROOT):
#       velocity.x = 0.0
#
# Signals:
#   status_added(status_id, duration, params)    — fired when first applied or refreshed
#   status_removed(status_id)                    — fired when timer expires
#   status_tick(status_id, params)               — fired every tick_interval for DOT
#   visual_tint_changed(tint, intensity)          — current blended tint for player sprite

# ── Status IDs ────────────────────────────────────────────────────────────────
enum ID {
	ROOT,       # Freeze horizontal movement
	STUN,       # Freeze movement + block attacks
	INVERT,     # Flip horizontal input
	SLOW,       # Reduce speed (stacking multiplier)
	PULL_TO,    # Drag toward origin
	DARKNESS,   # Vignette / reduced vision
	DOT,        # Damage over time
}

# ── Signals ───────────────────────────────────────────────────────────────────
signal status_added(status_id: int, duration: float, params: Dictionary)
signal status_removed(status_id: int)
signal status_tick(status_id: int, params: Dictionary)
signal visual_tint_changed(tint_color: Color, intensity: float)

# ── State ─────────────────────────────────────────────────────────────────────
# Active: { ID → { "timer": float, "params": dict, "source": Node|null } }
var _active: Dictionary = {}

# Dodge immunity — when true, ROOT/STUN/PULL_TO are rejected
var _dodge_immune: bool = false

# Combined slow multiplier (product of all active SLOW effects)
var _slow_mult: float = 1.0
var _dirty_slow: bool = true  # Recalculate when statuses change

# Combined tint (additive blend of active status tints)
var _tint_color := Color.WHITE
var _tint_intensity := 0.0
var _dirty_tint: bool = true

# ── Public API ────────────────────────────────────────────────────────────────

func apply(status_id: int, duration: float, params: Dictionary = {}, source: Node = null) -> void:
	if _dodge_immune:
		# Immune to control effects during dodge
		match status_id:
			ID.ROOT, ID.STUN, ID.PULL_TO:
				return

	# Refresh existing status or add new
	if _active.has(status_id):
		var entry: Dictionary = _active[status_id]
		# Extend timer (take the greater)
		entry["timer"] = maxf(entry["timer"], duration)
		# Merge params (new overrides old)
		entry["params"].merge(params)
	else:
		_active[status_id] = {
			"timer": duration,
			"params": params.duplicate(),
			"source": source,
		}

	_dirty_slow = true
	_dirty_tint = true
	status_added.emit(status_id, duration, _active[status_id]["params"])


func remove(status_id: int) -> void:
	if not _active.has(status_id):
		return
	_active.erase(status_id)
	_dirty_slow = true
	_dirty_tint = true
	status_removed.emit(status_id)


func clear_all() -> void:
	for id in _active.keys():
		status_removed.emit(id)
	_active.clear()
	_dirty_slow = true
	_dirty_tint = true
	_rebuild_tint()


func has(status_id: int) -> bool:
	return _active.has(status_id)


func get_remaining(status_id: int) -> float:
	if not _active.has(status_id):
		return 0.0
	return _active[status_id]["timer"]


func get_all_active() -> Array[int]:
	var ids: Array[int] = []
	for id in _active.keys():
		ids.append(int(id))
	return ids


func get_slow_multiplier() -> float:
	if _dirty_slow:
		_rebuild_slow()
	return _slow_mult


func get_tint() -> Color:
	if _dirty_tint:
		_rebuild_tint()
	return _tint_color


func get_tint_intensity() -> float:
	if _dirty_tint:
		_rebuild_tint()
	return _tint_intensity


func set_dodge_immune(value: bool) -> void:
	_dodge_immune = value


# ── Per-frame tick ────────────────────────────────────────────────────────────
# Call from Player._physics_process(delta)
func process(delta: float) -> void:
	var expired: Array[int] = []

	for status_id in _active.keys():
		var entry: Dictionary = _active[status_id]
		entry["timer"] -= delta

		# DOT tick
		if status_id == ID.DOT:
			var tick_interval: float = entry["params"].get("tick_interval", 1.0)
			entry["params"]["_tick_accum"] = entry["params"].get("_tick_accum", 0.0) + delta
			if entry["params"]["_tick_accum"] >= tick_interval:
				entry["params"]["_tick_accum"] -= tick_interval
				status_tick.emit(status_id, entry["params"])

		if entry["timer"] <= 0.0:
			expired.append(status_id)

	for status_id in expired:
		remove(status_id)


# ── Private ───────────────────────────────────────────────────────────────────

func _rebuild_slow() -> void:
	_slow_mult = 1.0
	for status_id in _active:
		if status_id == ID.SLOW:
			var entry: Dictionary = _active[status_id]
			_slow_mult *= entry["params"].get("mult", 0.6)
	_dirty_slow = false


func _rebuild_tint() -> void:
	var colors: Array = []
	var max_intensity := 0.0

	for status_id in _active:
		var c := _tint_for(status_id)
		if c.a > 0.0:
			colors.append(c)
			max_intensity = maxf(max_intensity, c.a)

	if colors.is_empty():
		_tint_color = Color.WHITE
		_tint_intensity = 0.0
	else:
		# Blend: average hue, max intensity
		var blended := Color.BLACK
		for c in colors:
			blended.r += c.r
			blended.g += c.g
			blended.b += c.b
		blended /= colors.size()
		_tint_color = blended
		_tint_intensity = max_intensity

	_dirty_tint = false
	visual_tint_changed.emit(_tint_color, _tint_intensity)


func _tint_for(status_id: int) -> Color:
	match status_id:
		ID.ROOT:
			return Color(0.5, 0.6, 1.0, 0.5)   # blue
		ID.STUN:
			return Color(1.0, 0.9, 0.3, 0.5)   # yellow
		ID.INVERT:
			return Color(0.7, 0.3, 0.9, 0.5)   # purple
		ID.SLOW:
			return Color(0.4, 0.8, 0.4, 0.3)   # green
		ID.PULL_TO:
			return Color(0.8, 0.5, 0.8, 0.3)   # magenta
		ID.DARKNESS:
			return Color(0.2, 0.2, 0.2, 0.6)   # dark
		ID.DOT:
			return Color(0.9, 0.2, 0.1, 0.4)   # red
		_:
			return Color.TRANSPARENT
