extends Node
# LockOn.gd — singleton for target lock-on.
#
# Both the player and AI use this to track their duel target.
# When locked, characters always face their target instead of their movement
# direction. This makes distance management and footsies readable.

signal target_locked(target: Node2D)
signal target_unlocked

var current_target: Node2D = null

func lock_on(target: Node2D) -> void:
	if current_target == target:
		return
	if is_instance_valid(current_target):
		current_target.tree_exited.disconnect(_on_target_freed)
	current_target = target
	target.tree_exited.connect(_on_target_freed)
	emit_signal("target_locked", target)

func unlock() -> void:
	if is_instance_valid(current_target):
		current_target.tree_exited.disconnect(_on_target_freed)
	current_target = null
	emit_signal("target_unlocked")

func is_locked() -> bool:
	return current_target != null and is_instance_valid(current_target)

func get_target_position() -> Vector2:
	if is_locked():
		return current_target.global_position
	return Vector2.ZERO

# Returns 1 if target is to the right, -1 if left, 0 if no target.
func facing_dir(from_position: Vector2) -> float:
	if not is_locked():
		return 0.0
	return signf(current_target.global_position.x - from_position.x)

# Returns distance to target, INF if no target.
func distance_to_target(from_position: Vector2) -> float:
	if not is_locked():
		return INF
	return from_position.distance_to(current_target.global_position)

# Returns the target node itself (null if not locked).
func get_target_node() -> Node2D:
	return current_target if is_locked() else null

func _on_target_freed() -> void:
	current_target = null
	emit_signal("target_unlocked")
