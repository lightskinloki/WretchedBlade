extends RefCounted
class_name RoomAnchorHelper

const TILE_EMPTY    := 0
const TILE_FLOOR    := 1
const TILE_WALL     := 2
const TILE_PLATFORM := 3

static func get_walkable_floor_y(grid: Array, x_col: int) -> int:
	if grid.is_empty() or x_col < 0 or x_col >= grid[0].size():
		return -1
	var h := grid.size()
	for y in range(h - 1, -1, -1):
		if grid[y][x_col] == TILE_FLOOR:
			return y
	return -1

static func get_ceiling_y(grid: Array, x_col: int) -> int:
	if grid.is_empty() or x_col < 0 or x_col >= grid[0].size():
		return -1
	var h := grid.size()
	for y in range(h):
		if grid[y][x_col] != TILE_EMPTY:
			return y
	return -1

static func get_room_floor_ceiling(grid: Array) -> Dictionary:
	var result := {floor_lo = 9999, floor_hi = -1, ceil_lo = 9999, ceil_hi = -1}
	if grid.is_empty():
		return result
	var w: int = grid[0].size()
	for x in range(w):
		var fy := get_walkable_floor_y(grid, x)
		if fy >= 0:
			if fy < result.floor_lo: result.floor_lo = fy
			if fy > result.floor_hi: result.floor_hi = fy
		var cy := get_ceiling_y(grid, x)
		if cy >= 0:
			if cy < result.ceil_lo: result.ceil_lo = cy
			if cy > result.ceil_hi: result.ceil_hi = cy
	return result

static func clamp_to_room(x: int, y: int, w: int, h: int, margin: int = 1) -> Vector2i:
	return Vector2i(
		clampi(x, margin, w - 1 - margin),
		clampi(y, margin, h - 1 - margin)
	)
