extends CharacterBody2D
# Minimal player stand-in for boss smoke tests.

var damage_taken := 0
var statuses: Array = []

func _ready() -> void:
	add_to_group("player")
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 30)
	cs.shape = rect
	add_child(cs)

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	damage_taken += amount

func apply_status(status: String, _duration: float, _origin: Vector2 = Vector2.ZERO) -> void:
	statuses.append(status)
