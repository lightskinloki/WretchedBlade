extends Area2D
# LostEssenceOrb.gd — floating essence dropped at death location.
# Player picks it up to recover lost essence.

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	collision_mask = 4  # Detect player on layer 3
	body_entered.connect(_on_body_entered)
	sprite.texture = PixelRenderer.generate_tile_texture(PixelRenderer.TileType.CHECKPOINT, 0)
	sprite.scale = Vector2(1.5, 1.5)
	sprite.centered = true
	sprite.modulate = Color.CYAN

func _process(_delta: float) -> void:
	sprite.position.y = sin(Time.get_ticks_msec() * 0.008) * 6.0
	sprite.rotation_degrees = sin(Time.get_ticks_msec() * 0.004) * 15.0

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		EssenceManager.recover_lost_essence()
		queue_free()
