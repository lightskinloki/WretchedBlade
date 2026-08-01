extends RefCounted
class_name CampsiteEnvironmentGenerator

const TILE_SIZE := 16
const WORLD_WIDTH := 76
const GROUND_Y := 23

static func build(parent: Node2D, seed_val: int = 77777) -> Dictionary:
	var width := WORLD_WIDTH * TILE_SIZE
	var height := 520
	var far_world := Sprite2D.new()
	far_world.name = "SeveredLandsHorizon"
	far_world.texture = PixelRenderer.generate_far_environment_texture(width + 512, height + 240, Color(0.055, 0.072, 0.085), Color(0.52, 0.22, 0.10), seed_val, "campsite")
	far_world.centered = false
	far_world.position = Vector2(-256, -160)
	far_world.z_index = -20
	parent.add_child(far_world)

	var structures := Sprite2D.new()
	structures.name = "CampsiteRuinSilhouettes"
	structures.texture = PixelRenderer.generate_atmosphere_texture(width + 512, height + 240, Color.TRANSPARENT, Color(0.30, 0.34, 0.36), seed_val + 61, 5, 0.85)
	structures.centered = false
	structures.position = Vector2(-256, -160)
	structures.z_index = -12
	parent.add_child(structures)

	var ambient := CanvasModulate.new()
	ambient.name = "OverworldDuskAmbient"
	ambient.color = Color(0.74, 0.70, 0.63)
	parent.add_child(ambient)

	_build_ground(parent, seed_val)
	_add_landmark(parent, Vector2(width * 0.50, GROUND_Y * TILE_SIZE - 58))
	_add_fire(parent, Vector2(width * 0.55, GROUND_Y * TILE_SIZE - 12), Color(1.0, 0.45, 0.16), 112, 0.85)
	_add_fire(parent, Vector2(width * 0.20, GROUND_Y * TILE_SIZE - 24), Color(1.0, 0.67, 0.34), 78, 0.48)
	_add_fire(parent, Vector2(width * 0.80, GROUND_Y * TILE_SIZE - 24), Color(1.0, 0.67, 0.34), 78, 0.48)

	var spots: Array[Vector2] = []
	for x in range(6, WORLD_WIDTH - 5, 2):
		spots.append(Vector2(x * TILE_SIZE + 8, GROUND_Y * TILE_SIZE - 8))
	return {"spawn": Vector2(width * 0.46, GROUND_Y * TILE_SIZE - 8), "floor_spots": spots, "room_w": WORLD_WIDTH}

static func _build_ground(parent: Node2D, seed_val: int) -> void:
	for x in range(WORLD_WIDTH):
		var sprite := Sprite2D.new()
		sprite.name = "AshenGround_%d" % x
		sprite.texture = PixelRenderer.generate_tile_texture(PixelRenderer.TileType.FLOOR, (seed_val + x * 31) % 4)
		sprite.position = Vector2(x * TILE_SIZE + 8, GROUND_Y * TILE_SIZE + 8)
		sprite.z_index = 0
		parent.add_child(sprite)
		var body := StaticBody2D.new()
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE, TILE_SIZE)
		collision.shape = shape
		body.position = sprite.position
		body.add_child(collision)
		parent.add_child(body)
		if x % 7 == 0:
			var rubble := Sprite2D.new()
			rubble.texture = PixelRenderer.generate_tile_texture(PixelRenderer.TileType.NULLSTONE, (seed_val + x) % 4)
			rubble.position = Vector2(x * TILE_SIZE + 8, GROUND_Y * TILE_SIZE - 8)
			rubble.z_index = 1
			parent.add_child(rubble)

static func _add_landmark(parent: Node2D, pos: Vector2) -> void:
	var landmark := Sprite2D.new()
	landmark.name = "MasterTuningFork"
	landmark.texture = PixelRenderer.generate_campsite_landmark_texture()
	landmark.position = pos
	landmark.z_index = -2
	parent.add_child(landmark)
	_add_fire(parent, pos + Vector2(0, 18), Color(1.0, 0.72, 0.36), 138, 0.70)

static func _add_fire(parent: Node2D, pos: Vector2, color: Color, radius: int, energy: float) -> void:
	var light := PointLight2D.new()
	light.texture = PixelRenderer.generate_light_mask(radius, 0.48, "harmonic")
	light.color = color
	light.energy = energy
	light.position = pos
	light.z_index = -10
	light.range_z_min = -20
	light.range_z_max = 10
	parent.add_child(light)
	var source := Sprite2D.new()
	source.texture = PixelRenderer.generate_light_mask(8, 0.70, "harmonic")
	source.modulate = color
	source.position = pos
	source.z_index = 1
	parent.add_child(source)
