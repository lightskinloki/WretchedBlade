extends StaticBody2D
class_name DestructibleTile

var linked_sprite: Sprite2D

func take_damage(_amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	_spawn_debris()
	if linked_sprite and is_instance_valid(linked_sprite):
		linked_sprite.queue_free()
	queue_free()

func _spawn_debris() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if not world:
		return
	for i in range(6):
		var shard := ColorRect.new()
		shard.size = Vector2(randf_range(2, 5), randf_range(2, 5))
		shard.rotation = randf() * TAU
		shard.color = Color(0.35, 0.25, 0.40, 1.0) if randf() > 0.4 else Color(0.50, 0.40, 0.55, 1.0)
		shard.global_position = global_position
		world.add_child(shard)

		var vel := Vector2(randf_range(-120, 120), randf_range(-200, -40))
		var tween := create_tween()
		tween.tween_property(shard, "global_position", shard.global_position + vel * 0.4, 0.4)
		tween.parallel().tween_property(shard, "modulate:a", 0.0, 0.4)
		tween.tween_callback(shard.queue_free)
