extends StaticBody2D
class_name HexBreakableTile
# HexBreakableTile.gd — pixel-erosion wall tile.
#
# Each instance owns a 16×16 pixel mask and a live Image. Hex attacks carve
# pixel-shaped holes; a 4×4 sub-cell collision grid opens walkable gaps as
# pixels are destroyed; destroyed pixels launch as tiny coloured particles.
#
# Public API:
#   setup(source_image: Image) -> void
#       Call immediately after creation (before adding to scene or after).
#   take_hex_damage(global_impact: Vector2, pattern: Dictionary) -> void
#       pattern examples:
#           { "type": "circle", "radius": 5.0 }
#           { "type": "line", "direction": Vector2.RIGHT, "half_width": 2.0 }

const TILE_SIZE := 16
const CELL_COLS := 4
const CELL_ROWS := 4
const CELL_PX_W := TILE_SIZE / CELL_COLS   # 4 pixels wide per cell
const CELL_PX_H := TILE_SIZE / CELL_ROWS   # 4 pixels tall per cell

# Hex energy tint colour for particle blending
const HEX_TINT := Color(0.35, 0.05, 0.60, 1.0)

var linked_sprite: Sprite2D

var _pixel_alive:  Array   # [TILE_SIZE][TILE_SIZE] bool
var _pixel_colors: Array   # [TILE_SIZE][TILE_SIZE] Color — sampled at setup
var _image:        Image   # live copy, alpha zeroed as pixels die
var _texture:      ImageTexture
var _cells:        Array   # [CELL_ROWS][CELL_COLS] CollisionShape2D
var _cell_alive:   Array   # [CELL_ROWS][CELL_COLS] int — alive pixel count


# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(source_image: Image) -> void:
	# Own a duplicate of the source image so we can modify it independently
	_image = source_image.duplicate()

	# Sample pixel data
	_pixel_alive  = []
	_pixel_colors = []
	_pixel_alive.resize(TILE_SIZE)
	_pixel_colors.resize(TILE_SIZE)
	for y in range(TILE_SIZE):
		var alive_row: Array = []
		var color_row: Array = []
		alive_row.resize(TILE_SIZE)
		color_row.resize(TILE_SIZE)
		for x in range(TILE_SIZE):
			alive_row[x]  = true
			color_row[x]  = _image.get_pixel(x, y)
		_pixel_alive[y]  = alive_row
		_pixel_colors[y] = color_row

	# Create a unique ImageTexture for this tile and give it to the sprite
	_texture = ImageTexture.create_from_image(_image)
	if linked_sprite and is_instance_valid(linked_sprite):
		linked_sprite.texture = _texture

	# Build sub-cell collision grid
	_cell_alive = []
	_cell_alive.resize(CELL_ROWS)
	_cells      = []
	_cells.resize(CELL_ROWS)
	for cy in range(CELL_ROWS):
		var alive_row: Array = []
		var cell_row:  Array = []
		alive_row.resize(CELL_COLS)
		cell_row.resize(CELL_COLS)
		for cx in range(CELL_COLS):
			alive_row[cx] = CELL_PX_W * CELL_PX_H   # all pixels alive

			var shape_node := CollisionShape2D.new()
			var rect       := RectangleShape2D.new()
			rect.size      = Vector2(CELL_PX_W, CELL_PX_H)
			shape_node.shape = rect
			# Centre of cell relative to tile centre
			var ox := (cx * CELL_PX_W + CELL_PX_W * 0.5) - TILE_SIZE * 0.5
			var oy := (cy * CELL_PX_H + CELL_PX_H * 0.5) - TILE_SIZE * 0.5
			shape_node.position = Vector2(ox, oy)
			add_child(shape_node)
			cell_row[cx] = shape_node

		_cell_alive[cy] = alive_row
		_cells[cy]      = cell_row

	# Register in group so hex abilities can query nearby tiles
	add_to_group("hex_breakable")


# ── Public damage API ─────────────────────────────────────────────────────────
func take_hex_damage(global_impact: Vector2, pattern: Dictionary) -> void:
	if _image == null:
		return

	# Convert global impact to pixel-space coordinates (0–15)
	var lp         := to_local(global_impact)
	var px_center  := Vector2i(
		clampi(int(lp.x + TILE_SIZE * 0.5), 0, TILE_SIZE - 1),
		clampi(int(lp.y + TILE_SIZE * 0.5), 0, TILE_SIZE - 1)
	)

	var destroyed: Array[Vector2i] = []
	match pattern.get("type", "circle"):
		"circle":
			destroyed = _apply_circle(px_center, float(pattern.get("radius", 4.0)))
		"line":
			var dir: Vector2 = pattern.get("direction", Vector2.RIGHT)
			destroyed = _apply_line(px_center, dir.normalized(), float(pattern.get("half_width", 1.5)))

	if not destroyed.is_empty():
		_destroy_pixels(destroyed, global_impact)


# ── Pattern calculators ───────────────────────────────────────────────────────
func _apply_circle(center: Vector2i, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for py in range(TILE_SIZE):
		for px in range(TILE_SIZE):
			if not _pixel_alive[py][px]:
				continue
			var dx := float(px - center.x)
			var dy := float(py - center.y)
			if dx * dx + dy * dy <= radius * radius:
				result.append(Vector2i(px, py))
	return result


func _apply_line(origin: Vector2i, dir: Vector2, half_w: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for py in range(TILE_SIZE):
		for px in range(TILE_SIZE):
			if not _pixel_alive[py][px]:
				continue
			# Perpendicular distance from pixel to the line through origin along dir
			var offset := Vector2(px - origin.x, py - origin.y)
			var perp   := absf(offset.x * dir.y - offset.y * dir.x)
			if perp <= half_w:
				result.append(Vector2i(px, py))
	return result


# ── Pixel destruction ─────────────────────────────────────────────────────────
func _destroy_pixels(pixels: Array[Vector2i], global_impact: Vector2) -> void:
	for p in pixels:
		var px: int = p.x
		var py: int = p.y
		_pixel_alive[py][px] = false
		_image.set_pixel(px, py, Color(0.0, 0.0, 0.0, 0.0))

		# Update cell alive count; disable collision when cell is empty
		var cx: int = px / CELL_PX_W
		var cy: int = py / CELL_PX_H
		_cell_alive[cy][cx] -= 1
		if _cell_alive[cy][cx] <= 0:
			_cell_alive[cy][cx] = 0
			(_cells[cy][cx] as CollisionShape2D).disabled = true

	# One GPU push for the entire batch
	_texture.update(_image)

	_spawn_particles(pixels, global_impact)
	_check_fully_destroyed()


# ── Particles ─────────────────────────────────────────────────────────────────
func _spawn_particles(pixels: Array[Vector2i], global_impact: Vector2) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if not world:
		return

	for p in pixels:
		var px: int = p.x
		var py: int = p.y

		# Blend tile pixel colour toward hex violet
		var base_col: Color = _pixel_colors[py][px]
		var tint_amt := randf_range(0.2, 0.6)
		var final_col := base_col.lerp(HEX_TINT, tint_amt)
		final_col.a = 1.0

		# World position of this pixel
		var pixel_world := global_position + Vector2(
			float(px) - TILE_SIZE * 0.5 + 0.5,
			float(py) - TILE_SIZE * 0.5 + 0.5
		)

		var shard := ColorRect.new()
		shard.size   = Vector2(1.0, 1.0)
		shard.color  = final_col
		shard.global_position = pixel_world
		world.add_child(shard)

		# Velocity: outward from impact + upward bias
		var outward := (pixel_world - global_impact).normalized()
		if outward == Vector2.ZERO:
			outward = Vector2(randf_range(-1.0, 1.0), -1.0).normalized()
		var speed   := randf_range(30.0, 90.0)
		var vel     := outward * speed + Vector2(randf_range(-20.0, 20.0), randf_range(-60.0, -10.0))

		var tween := create_tween()
		tween.tween_property(shard, "global_position", pixel_world + vel * 0.35, 0.35)
		tween.parallel().tween_property(shard, "color:a", 0.0, 0.35)
		tween.tween_callback(shard.queue_free)


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _check_fully_destroyed() -> void:
	for cy in range(CELL_ROWS):
		for cx in range(CELL_COLS):
			if _cell_alive[cy][cx] > 0:
				return
	# All cells empty — free the tile
	if linked_sprite and is_instance_valid(linked_sprite):
		linked_sprite.queue_free()
	queue_free()
